#if os(macOS)
@testable import AppServices
import MCPKit
import XCTest

final class MCPClientInstallerTests: XCTestCase {
    private var tempRoot: URL!
    private var homeDir: URL!
    private var appsDir: URL!

    private let endpoint = MCPEndpointConfig(
        url: "https://tally-mcp.example.workers.dev/mcp",
        quickURL: "https://tally-mcp.example.workers.dev/u/tok123/mcp",
        token: "tok123"
    )

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("tally-mcp-installer-tests-\(UUID().uuidString)", isDirectory: true)
        homeDir = tempRoot.appendingPathComponent("home", isDirectory: true)
        appsDir = tempRoot.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: homeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testDetectsAndConnectsAllInstalledClientsPreservingPermissionsAndSiblingConfig() throws {
        let fm = FileManager.default

        // Seed existing ~/.claude.json with 0o600
        let claudeFile = MCPClientInstaller.configURL(for: .claudeCode, homeDirectory: homeDir)
        try Data("{\"mcpServers\":{\"other\":{\"type\":\"http\",\"url\":\"https://x.test\"}}}\n".utf8).write(to: claudeFile)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeFile.path)

        // Seed ~/.codex/config.toml with 0o600
        let codexDir = homeDir.appendingPathComponent(".codex", isDirectory: true)
        try fm.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let codexFile = MCPClientInstaller.configURL(for: .codex, homeDirectory: homeDir)
        try Data("# keep me\nmodel = \"gpt-5\"\n".utf8).write(to: codexFile)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: codexFile.path)

        // Seed Antigravity 0-byte mcp_config.json + .app
        let agyDir = homeDir.appendingPathComponent(".gemini/config", isDirectory: true)
        try fm.createDirectory(at: agyDir, withIntermediateDirectories: true)
        try Data().write(to: MCPClientInstaller.configURL(for: .antigravity, homeDirectory: homeDir))
        try fm.createDirectory(at: appsDir.appendingPathComponent("Antigravity.app"), withIntermediateDirectories: true)

        // Seed Claude.app (not Cursor)
        try fm.createDirectory(at: appsDir.appendingPathComponent("Claude.app"), withIntermediateDirectories: true)

        let before = MCPClientInstaller.detectAll(endpoint: endpoint, homeDirectory: homeDir, applicationsDirectory: appsDir)
        XCTAssertTrue(before.first(where: { $0.kind == .claudeCode })?.isInstalled == true)
        XCTAssertTrue(before.first(where: { $0.kind == .codex })?.isInstalled == true)
        XCTAssertTrue(before.first(where: { $0.kind == .claudeDesktop })?.isInstalled == true)
        XCTAssertTrue(before.first(where: { $0.kind == .antigravity })?.isInstalled == true)
        XCTAssertTrue(before.first(where: { $0.kind == .cursor })?.isInstalled == false)
        XCTAssertTrue(before.allSatisfy { $0.state == .notConfigured })

        let batch = MCPClientInstaller.connectAllInstalled(endpoint: endpoint, homeDirectory: homeDir, applicationsDirectory: appsDir)
        XCTAssertTrue(batch.failures.isEmpty)
        XCTAssertEqual(Set(batch.connected), [.claudeCode, .codex, .claudeDesktop, .antigravity])

        let after = MCPClientInstaller.detectAll(endpoint: endpoint, homeDirectory: homeDir, applicationsDirectory: appsDir)
        XCTAssertEqual(after.first(where: { $0.kind == .claudeCode })?.state, .connected)
        XCTAssertEqual(after.first(where: { $0.kind == .codex })?.state, .connected)
        XCTAssertEqual(after.first(where: { $0.kind == .claudeDesktop })?.state, .connected)
        XCTAssertEqual(after.first(where: { $0.kind == .antigravity })?.state, .connected)
        XCTAssertEqual(after.first(where: { $0.kind == .cursor })?.state, .notConfigured)

        // Verify 0o600 permissions preserved
        let claudePerms = (try fm.attributesOfItem(atPath: claudeFile.path)[.posixPermissions] as? NSNumber)?.intValue
        let codexPerms = (try fm.attributesOfItem(atPath: codexFile.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(claudePerms, 0o600)
        XCTAssertEqual(codexPerms, 0o600)

        // Verify Codex comment kept & Claude sibling kept
        let codexText = try String(contentsOf: codexFile, encoding: .utf8)
        XCTAssertTrue(codexText.contains("# keep me"))
        XCTAssertTrue(codexText.contains("[mcp_servers.tally]"))

        // Disconnect one client cleanly
        try MCPClientInstaller.disconnect(.claudeCode, homeDirectory: homeDir)
        XCTAssertEqual(
            MCPClientInstaller.connectionState(for: .claudeCode, endpoint: endpoint, homeDirectory: homeDir),
            .notConfigured
        )
        let claudeAfterDisconnect = try Data(contentsOf: claudeFile)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: claudeAfterDisconnect) as? [String: Any])
        XCTAssertNotNil((parsed["mcpServers"] as? [String: Any])?["other"])
    }
}
#endif
