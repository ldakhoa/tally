@testable import MCPKit
import TallyCore
import XCTest

final class MCPKitTests: XCTestCase {
    private let token = "secret-token"

    private var host: MCPToolHost {
        MCPToolHost(
            info: { MCPServerInfo(name: "tally", title: "Tally", version: "1.0", instructions: "Use the tools.") },
            tools: {
                [
                    MCPTool(name: "echo", description: "Echoes", inputSchema: .schemaObject([("text", .schemaString("Text"))]), readOnly: true),
                    MCPTool(name: "delete_thing", description: "Deletes", inputSchema: .schemaObject([]), readOnly: false, destructive: true),
                ]
            },
            call: { name, arguments in
                switch name {
                case "echo": return MCPToolResult(text: arguments["text"]?.stringValue ?? "(none)")
                case "delete_thing": return MCPToolResult(text: "Error: nothing to delete", isError: true)
                default: return nil
                }
            }
        )
    }

    private var core: MCPServerCore { MCPServerCore(host: host) }
    private var endpoint: MCPHTTPEndpoint { MCPHTTPEndpoint(token: token, core: core) }

    private func rpc(_ json: String) async throws -> [String: Any] {
        let reply = try await XCTUnwrapAsync(await core.handle(body: Data(json.utf8)))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    private func XCTUnwrapAsync<T>(_ value: T?) async throws -> T {
        try XCTUnwrap(value)
    }

    private func post(_ body: String, headers: [String: String] = [:]) -> HTTPRequest {
        var all = ["host": "127.0.0.1:47821", "authorization": "Bearer \(token)", "content-type": "application/json"]
        for (name, value) in headers { all[name] = value }
        return HTTPRequest(method: "POST", path: "/mcp", headers: all, body: Data(body.utf8))
    }

    // MARK: Protocol

    func testInitializeEchoesSupportedVersionAndSendsInstructions() async throws {
        let reply = try await rpc(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        XCTAssertEqual(reply["id"] as? Int, 1)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-03-26")
        XCTAssertEqual(result["instructions"] as? String, "Use the tools.")
        XCTAssertEqual((result["serverInfo"] as? [String: Any])?["name"] as? String, "tally")
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
    }

    func testInitializeWithUnknownVersionAnswersNewestSupported() async throws {
        let reply = try await rpc(#"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual(reply["id"] as? String, "a")
        XCTAssertEqual((reply["result"] as? [String: Any])?["protocolVersion"] as? String, MCPServerCore.supportedVersions[0])
    }

    func testToolsListCarriesSchemasAndAnnotations() async throws {
        let reply = try await rpc(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.map { $0["name"] as? String }, ["echo", "delete_thing"])
        XCTAssertEqual((tools[0]["inputSchema"] as? [String: Any])?["type"] as? String, "object")
        XCTAssertEqual((tools[0]["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, true)
        XCTAssertEqual((tools[1]["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool, false)
        XCTAssertEqual((tools[1]["annotations"] as? [String: Any])?["destructiveHint"] as? Bool, true)
    }

    func testToolCallReturnsTextContent() async throws {
        let reply = try await rpc(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#)
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "hi")
    }

    func testToolCallWithoutArgumentsAndToolErrors() async throws {
        let none = try await rpc(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"echo"}}"#)
        XCTAssertEqual((((none["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first)?["text"] as? String, "(none)")

        // A tool that fails is a result with isError, not a protocol error.
        let failed = try await rpc(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"delete_thing","arguments":{}}}"#)
        XCTAssertEqual((failed["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertNil(failed["error"])
    }

    func testUnknownToolAndUnknownMethodAreProtocolErrors() async throws {
        let tool = try await rpc(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope"}}"#)
        XCTAssertEqual((tool["error"] as? [String: Any])?["code"] as? Int, -32602)
        let method = try await rpc(#"{"jsonrpc":"2.0","id":7,"method":"resources/list"}"#)
        XCTAssertEqual((method["error"] as? [String: Any])?["code"] as? Int, -32601)
        let ping = try await rpc(#"{"jsonrpc":"2.0","id":8,"method":"ping"}"#)
        XCTAssertNotNil(ping["result"])
    }

    func testNotificationsAndClientResponsesGetNoReply() async {
        let notification = await core.handle(body: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        XCTAssertNil(notification)
        let response = await core.handle(body: Data(#"{"jsonrpc":"2.0","id":1,"result":{}}"#.utf8))
        XCTAssertNil(response)
    }

    func testMalformedJSONAndInvalidRequests() async throws {
        let parse = try await rpc("{not json")
        XCTAssertEqual((parse["error"] as? [String: Any])?["code"] as? Int, -32700)
        let invalid = try await rpc(#"{"id":1,"method":"ping"}"#)
        XCTAssertEqual((invalid["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testBatchAnswersOnlyRequests() async throws {
        let body = #"[{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":1,"method":"ping"}]"#
        let reply = try await XCTUnwrapAsync(await core.handle(body: Data(body.utf8)))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [[String: Any]])
        XCTAssertEqual(array.count, 1)
        XCTAssertEqual(array.first?["id"] as? Int, 1)
    }

    // MARK: HTTP endpoint

    func testPostReturnsJSONAndNotificationReturns202() async {
        let ok = await endpoint.respond(to: post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#))
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.headers["Content-Type"], "application/json")

        let accepted = await endpoint.respond(to: post(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertEqual(accepted.status, 202)
        XCTAssertTrue(accepted.body.isEmpty)
    }

    func testRejectsMissingOrWrongToken() async {
        for value in [nil, "Bearer wrong", "Bearer ", "Basic \(token)", token, "Bearer \(token)x"] as [String?] {
            var request = post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
            request.headers["authorization"] = value
            let response = await endpoint.respond(to: request)
            XCTAssertEqual(response.status, 401, value ?? "nil")
            XCTAssertEqual(response.headers["WWW-Authenticate"], "Bearer")
        }
        let lowercase = await endpoint.respond(to: post(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#, headers: ["authorization": "bearer \(token)"]))
        XCTAssertEqual(lowercase.status, 200)
    }

    func testAnEmptyTokenNeverAuthorizes() {
        XCTAssertFalse(MCPHTTPEndpoint.isAuthorized("Bearer ", token: ""))
        XCTAssertFalse(MCPHTTPEndpoint.isAuthorized("Bearer", token: ""))
    }

    func testRejectsForeignHostAndOrigin() async {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let rebinding = await endpoint.respond(to: post(body, headers: ["host": "evil.example:47821"]))
        XCTAssertEqual(rebinding.status, 403)
        let webPage = await endpoint.respond(to: post(body, headers: ["origin": "https://evil.example"]))
        XCTAssertEqual(webPage.status, 403)

        for host in ["localhost:47821", "127.0.0.1", "[::1]:47821"] {
            let response = await endpoint.respond(to: post(body, headers: ["host": host]))
            XCTAssertEqual(response.status, 200, host)
        }
        let localOrigin = await endpoint.respond(to: post(body, headers: ["origin": "http://localhost:6274"]))
        XCTAssertEqual(localOrigin.status, 200)
    }

    func testWrongPathMethodAndContentType() async {
        var request = post("{}")
        request.path = "/"
        let notFound = await endpoint.respond(to: request)
        XCTAssertEqual(notFound.status, 404)

        request = post("")
        request.method = "GET"
        let get = await endpoint.respond(to: request)
        XCTAssertEqual(get.status, 405)
        XCTAssertEqual(get.headers["Allow"], "POST")

        let text = await endpoint.respond(to: post("{}", headers: ["content-type": "text/plain"]))
        XCTAssertEqual(text.status, 415)
    }

    func testQuickTokenPathAuthorizesWithoutBearerHeaderAndRejectsBadTokens() async {
        let body = #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#
        let ok = await endpoint.respond(to: HTTPRequest(
            method: "POST",
            path: "/u/\(token)/mcp",
            headers: ["host": "127.0.0.1:47821", "content-type": "application/json"],
            body: Data(body.utf8)
        ))
        XCTAssertEqual(ok.status, 200)

        let wrong = await endpoint.respond(to: HTTPRequest(
            method: "POST",
            path: "/u/wrong-token/mcp",
            headers: ["host": "127.0.0.1:47821", "content-type": "application/json"],
            body: Data(body.utf8)
        ))
        XCTAssertEqual(wrong.status, 401)

        let badNest = await endpoint.respond(to: HTTPRequest(
            method: "POST",
            path: "/u/a/b/mcp",
            headers: ["host": "127.0.0.1:47821", "content-type": "application/json"],
            body: Data(body.utf8)
        ))
        XCTAssertEqual(badNest.status, 404)

        let emptyTok = await endpoint.respond(to: HTTPRequest(
            method: "POST",
            path: "/u//mcp",
            headers: ["host": "127.0.0.1:47821", "content-type": "application/json"],
            body: Data(body.utf8)
        ))
        XCTAssertEqual(emptyTok.status, 404)

        let rebinding = await endpoint.respond(to: HTTPRequest(
            method: "POST",
            path: "/u/\(token)/mcp",
            headers: ["host": "evil.example", "content-type": "application/json"],
            body: Data(body.utf8)
        ))
        XCTAssertEqual(rebinding.status, 403)
    }

    // MARK: HTTP parsing

    func testParsesRequestWithBodyAndReportsConsumedBytes() {
        let body = #"{"a":1}"#
        let raw = "POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let next = "POST /mcp HTTP/1.1\r\n"
        guard case .request(let request, let consumed) = HTTPRequestParser.parse(Data((raw + next).utf8)) else {
            return XCTFail("expected a request")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), body)
        XCTAssertEqual(consumed, raw.utf8.count)
        XCTAssertFalse(request.wantsClose)
    }

    func testIncompleteUntilHeadersAndBodyArrive() {
        XCTAssertEqual(HTTPRequestParser.parse(Data("POST /mcp HTTP/1.1\r\nHost: x\r\n".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(Data("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345".utf8)), .incomplete)
        XCTAssertEqual(HTTPRequestParser.parse(Data()), .incomplete)
    }

    func testParsesFromASliceWithNonZeroStartIndex() {
        let data = Data("XXXXGET /mcp HTTP/1.1\r\nConnection: close\r\n\r\n".utf8).dropFirst(4)
        guard case .request(let request, _) = HTTPRequestParser.parse(data) else { return XCTFail("expected a request") }
        XCTAssertEqual(request.method, "GET")
        XCTAssertTrue(request.wantsClose)
    }

    func testRefusesOversizedChunkedAndMalformedRequests() {
        func status(_ raw: String) -> Int? {
            if case .failure(let response) = HTTPRequestParser.parse(Data(raw.utf8)) { return response.status }
            return nil
        }
        XCTAssertEqual(status("POST /mcp HTTP/1.1\r\nContent-Length: \(HTTPRequestParser.maxBodyBytes + 1)\r\n\r\n"), 413)
        XCTAssertEqual(status("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), 411)
        XCTAssertEqual(status("POST /mcp HTTP/1.1\r\nContent-Length: abc\r\n\r\n"), 400)
        XCTAssertEqual(status("nonsense\r\n\r\n"), 400)
        XCTAssertEqual(status(String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes + 10)), 431)
    }

    func testResponseSerialization() {
        let text = String(decoding: HTTPResponse.json(200, Data("{}".utf8)).serialized(keepAlive: true), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"), text)
        XCTAssertTrue(text.contains("Content-Length: 2\r\n"), text)
        XCTAssertTrue(text.contains("Connection: keep-alive\r\n"), text)
        XCTAssertTrue(text.hasSuffix("\r\n\r\n{}"), text)
    }
}
