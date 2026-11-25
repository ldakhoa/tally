@testable import MCPKit
import XCTest

final class MCPClientConfigTests: XCTestCase {
    private let cloudEndpoint = MCPEndpointConfig(
        url: "https://tally-mcp-server.example.workers.dev/mcp",
        quickURL: "https://tally-mcp-server.example.workers.dev/u/tok123/mcp",
        token: "tok123"
    )

    private let localEndpoint = MCPEndpointConfig(
        url: "http://127.0.0.1:47821/mcp",
        quickURL: "http://127.0.0.1:47821/u/tok123/mcp",
        token: "tok123"
    )

    func testJSONUpsertAndRemovePreserveOtherKeysAndServers() throws {
        let initial = Data("""
        {
          "numStartups": 42,
          "mcpServers": {
            "atlassian": {
              "type": "http",
              "url": "https://mcp.atlassian.com/v1/mcp"
            }
          }
        }
        """.utf8)

        XCTAssertEqual(
            MCPClientConfig.inspectJSONConfig(initial, serverName: "tally", endpoint: cloudEndpoint, kind: .claudeCode),
            .notConfigured
        )

        let updated = try MCPClientConfig.upsertJSONConfig(initial, serverName: "tally", endpoint: cloudEndpoint, kind: .claudeCode)
        XCTAssertEqual(
            MCPClientConfig.inspectJSONConfig(updated, serverName: "tally", endpoint: cloudEndpoint, kind: .claudeCode),
            .connected
        )
        XCTAssertEqual(
            MCPClientConfig.inspectJSONConfig(updated, serverName: "tally", endpoint: localEndpoint, kind: .claudeCode),
            .needsUpdate
        )

        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        XCTAssertEqual(parsed["numStartups"] as? Int, 42)
        let servers = try XCTUnwrap(parsed["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["atlassian"])
        let tally = try XCTUnwrap(servers["tally"] as? [String: Any])
        XCTAssertEqual(tally["url"] as? String, cloudEndpoint.url)
        XCTAssertEqual((tally["headers"] as? [String: String])?["Authorization"], "Bearer tok123")

        let removed = try MCPClientConfig.removeJSONConfig(updated, serverName: "tally")
        let afterRemove = try XCTUnwrap(JSONSerialization.jsonObject(with: removed) as? [String: Any])
        let serversAfter = try XCTUnwrap(afterRemove["mcpServers"] as? [String: Any])
        XCTAssertNil(serversAfter["tally"])
        XCTAssertNotNil(serversAfter["atlassian"])
    }

    func testAntigravityAcceptsZeroByteFileAndUsesQuickURL() throws {
        let empty = Data()
        let updated = try MCPClientConfig.upsertJSONConfig(empty, serverName: "tally", endpoint: cloudEndpoint, kind: .antigravity)
        XCTAssertEqual(
            MCPClientConfig.inspectJSONConfig(updated, serverName: "tally", endpoint: cloudEndpoint, kind: .antigravity),
            .connected
        )
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        let tally = try XCTUnwrap((parsed["mcpServers"] as? [String: Any])?["tally"] as? [String: Any])
        XCTAssertEqual(tally["url"] as? String, cloudEndpoint.quickURL)
        XCTAssertNil(tally["headers"])
    }

    func testClaudeDesktopBridgeAddsAllowHttpOnlyForLocalHTTP() throws {
        let httpsData = try MCPClientConfig.upsertJSONConfig(nil, serverName: "tally", endpoint: cloudEndpoint, kind: .claudeDesktop)
        let httpsArgs = (((try XCTUnwrap(JSONSerialization.jsonObject(with: httpsData) as? [String: Any]))["mcpServers"] as? [String: Any])?["tally"] as? [String: Any])?["args"] as? [String]
        XCTAssertEqual(httpsArgs, ["-y", "mcp-remote", cloudEndpoint.quickURL])

        let httpData = try MCPClientConfig.upsertJSONConfig(nil, serverName: "tally", endpoint: localEndpoint, kind: .claudeDesktop)
        let httpArgs = (((try XCTUnwrap(JSONSerialization.jsonObject(with: httpData) as? [String: Any]))["mcpServers"] as? [String: Any])?["tally"] as? [String: Any])?["args"] as? [String]
        XCTAssertEqual(httpArgs, ["-y", "mcp-remote", localEndpoint.quickURL, "--allow-http"])
    }

    func testCursorUsesURLAndHeaders() throws {
        let updated = try MCPClientConfig.upsertJSONConfig(nil, serverName: "tally", endpoint: cloudEndpoint, kind: .cursor)
        XCTAssertEqual(
            MCPClientConfig.inspectJSONConfig(updated, serverName: "tally", endpoint: cloudEndpoint, kind: .cursor),
            .connected
        )
    }

    func testCodexTOMLUpsertUpdateAndRemovePreserveCommentsAndSiblingSections() {
        let initial = """
        # User settings
        model = "gpt-5"

        [mcp_servers.node_repl]
        command = "node"

        [mcp_servers.node_repl.env]
        FOO = "bar"
        """

        XCTAssertEqual(
            MCPClientConfig.inspectCodexTOML(initial, serverName: "tally", endpoint: cloudEndpoint),
            .notConfigured
        )

        let added = MCPClientConfig.upsertCodexTOML(initial, serverName: "tally", endpoint: cloudEndpoint)
        XCTAssertEqual(
            MCPClientConfig.inspectCodexTOML(added, serverName: "tally", endpoint: cloudEndpoint),
            .connected
        )
        XCTAssertTrue(added.contains("# User settings"))
        XCTAssertTrue(added.contains("[mcp_servers.node_repl.env]"))

        let updated = MCPClientConfig.upsertCodexTOML(added, serverName: "tally", endpoint: localEndpoint)
        XCTAssertEqual(
            MCPClientConfig.inspectCodexTOML(updated, serverName: "tally", endpoint: cloudEndpoint),
            .needsUpdate
        )
        XCTAssertEqual(
            MCPClientConfig.inspectCodexTOML(updated, serverName: "tally", endpoint: localEndpoint),
            .connected
        )

        let removed = MCPClientConfig.removeCodexTOML(updated, serverName: "tally")
        XCTAssertEqual(
            MCPClientConfig.inspectCodexTOML(removed, serverName: "tally", endpoint: localEndpoint),
            .notConfigured
        )
        XCTAssertTrue(removed.contains("[mcp_servers.node_repl]"))
        XCTAssertFalse(removed.contains("[mcp_servers.tally]"))
    }
}
