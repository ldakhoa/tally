@testable import MCPKit
import XCTest

final class MCPSetupLinkTests: XCTestCase {
    func testNormalizeWorkerURLHandlesBareHostAndTrailingMCP() {
        XCTAssertEqual(
            MCPSetupLink.normalizeWorkerURL("tally-mcp-server.abc.workers.dev/")?.absoluteString,
            "https://tally-mcp-server.abc.workers.dev"
        )
        XCTAssertEqual(
            MCPSetupLink.normalizeWorkerURL("https://tally-mcp-server.abc.workers.dev/mcp")?.absoluteString,
            "https://tally-mcp-server.abc.workers.dev"
        )
        XCTAssertEqual(
            MCPSetupLink.normalizeWorkerURL("http://127.0.0.1:8787/mcp")?.absoluteString,
            "http://127.0.0.1:8787"
        )
        XCTAssertNil(MCPSetupLink.normalizeWorkerURL("http://example.com"))
        XCTAssertNil(MCPSetupLink.normalizeWorkerURL("ftp://example.com"))
        XCTAssertNil(MCPSetupLink.normalizeWorkerURL("   "))
    }

    func testPairingDeepLinkRoundTripAndValidation() throws {
        let base = try XCTUnwrap(MCPSetupLink.normalizeWorkerURL("https://tally-mcp-server.abc.workers.dev"))
        XCTAssertEqual(MCPSetupLink.mcpURL(baseURL: base), "https://tally-mcp-server.abc.workers.dev/mcp")
        XCTAssertEqual(MCPSetupLink.quickConnectorURL(baseURL: base, token: "abc123"), "https://tally-mcp-server.abc.workers.dev/u/abc123/mcp")

        let link = try XCTUnwrap(MCPSetupLink.pairingDeepLink(baseURL: base, syncSecret: "sync-xyz", accessToken: "tok-456"))
        let parsed = try XCTUnwrap(MCPSetupLink.parsePairingDeepLink(link))
        XCTAssertEqual(parsed.baseURL, base)
        XCTAssertEqual(parsed.syncSecret, "sync-xyz")
        XCTAssertEqual(parsed.accessToken, "tok-456")

        XCTAssertNil(MCPSetupLink.parsePairingText("https://example.com/not-tally"))
        XCTAssertNil(MCPSetupLink.parsePairingText("tally://log?amount=10"))
        XCTAssertNil(MCPSetupLink.parsePairingText("tally://mcp?url=https://a.workers.dev&sync=only"))
    }
}
