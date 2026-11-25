#if os(macOS)
import Foundation
import MCPKit

public struct DetectedMCPClient: Identifiable, Equatable, Sendable {
    public let kind: MCPClientKind
    public let isInstalled: Bool
    public let state: MCPClientConnectionState
    public let configPath: String

    public var id: MCPClientKind { kind }

    public init(kind: MCPClientKind, isInstalled: Bool, state: MCPClientConnectionState, configPath: String) {
        self.kind = kind
        self.isInstalled = isInstalled
        self.state = state
        self.configPath = configPath
    }
}

public struct MCPBatchInstallResult: Equatable, Sendable {
    public let connected: [MCPClientKind]
    public let failures: [(kind: MCPClientKind, message: String)]

    public init(connected: [MCPClientKind], failures: [(kind: MCPClientKind, message: String)]) {
        self.connected = connected
        self.failures = failures
    }

    public static func == (lhs: MCPBatchInstallResult, rhs: MCPBatchInstallResult) -> Bool {
        lhs.connected == rhs.connected
            && lhs.failures.map(\.kind) == rhs.failures.map(\.kind)
            && lhs.failures.map(\.message) == rhs.failures.map(\.message)
    }
}

/// 1-tap detector and config writer for Mac AI assistants (Claude Code, Codex, Claude Desktop,
/// Antigravity, Cursor). Never touches other entries, comments, or sibling keys.
public enum MCPClientInstaller {
    public static let serverName = "tally"

    public static func configURL(
        for kind: MCPClientKind,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        switch kind {
        case .claudeCode:
            return homeDirectory.appendingPathComponent(".claude.json")
        case .codex:
            return homeDirectory.appendingPathComponent(".codex/config.toml")
        case .claudeDesktop:
            return homeDirectory.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
        case .antigravity:
            return homeDirectory.appendingPathComponent(".gemini/config/mcp_config.json")
        case .cursor:
            return homeDirectory.appendingPathComponent(".cursor/mcp.json")
        }
    }

    public static func isInstalled(
        _ kind: MCPClientKind,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> Bool {
        let fm = FileManager.default
        let configFile = configURL(for: kind, homeDirectory: homeDirectory)
        switch kind {
        case .claudeCode:
            if fm.fileExists(atPath: configFile.path) { return true }
            return binaryExists("claude", homeDirectory: homeDirectory)
        case .codex:
            if fm.fileExists(atPath: homeDirectory.appendingPathComponent(".codex").path) { return true }
            return binaryExists("codex", homeDirectory: homeDirectory)
        case .claudeDesktop:
            return fm.fileExists(atPath: applicationsDirectory.appendingPathComponent("Claude.app").path)
                || fm.fileExists(atPath: homeDirectory.appendingPathComponent("Library/Application Support/Claude").path)
        case .antigravity:
            return fm.fileExists(atPath: applicationsDirectory.appendingPathComponent("Antigravity.app").path)
                || fm.fileExists(atPath: homeDirectory.appendingPathComponent(".gemini/antigravity").path)
                || fm.fileExists(atPath: homeDirectory.appendingPathComponent(".gemini/config").path)
        case .cursor:
            return fm.fileExists(atPath: applicationsDirectory.appendingPathComponent("Cursor.app").path)
                || fm.fileExists(atPath: homeDirectory.appendingPathComponent(".cursor").path)
        }
    }

    public static func detectAll(
        endpoint: MCPEndpointConfig,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> [DetectedMCPClient] {
        MCPClientKind.allCases.map { kind in
            let url = configURL(for: kind, homeDirectory: homeDirectory)
            let installed = isInstalled(kind, homeDirectory: homeDirectory, applicationsDirectory: applicationsDirectory)
            let state = connectionState(for: kind, endpoint: endpoint, homeDirectory: homeDirectory)
            return DetectedMCPClient(
                kind: kind,
                isInstalled: installed,
                state: state,
                configPath: url.path
            )
        }
    }

    public static func connectionState(
        for kind: MCPClientKind,
        endpoint: MCPEndpointConfig,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> MCPClientConnectionState {
        let url = configURL(for: kind, homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return .notConfigured }
        if kind == .codex {
            return MCPClientConfig.inspectCodexTOML(
                String(data: data, encoding: .utf8),
                serverName: serverName,
                endpoint: endpoint
            )
        }
        return MCPClientConfig.inspectJSONConfig(data, serverName: serverName, endpoint: endpoint, kind: kind)
    }

    public static func connect(
        _ kind: MCPClientKind,
        endpoint: MCPEndpointConfig,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let url = configURL(for: kind, homeDirectory: homeDirectory)
        let existingData = try? Data(contentsOf: url)
        let updatedData: Data
        if kind == .codex {
            let existingText = existingData.flatMap { String(data: $0, encoding: .utf8) }
            let nextText = MCPClientConfig.upsertCodexTOML(existingText, serverName: serverName, endpoint: endpoint)
            updatedData = Data(nextText.utf8)
        } else {
            updatedData = try MCPClientConfig.upsertJSONConfig(
                existingData,
                serverName: serverName,
                endpoint: endpoint,
                kind: kind
            )
        }
        let defaultPerms: Int = (kind == .claudeCode || kind == .codex) ? 0o600 : 0o644
        try writeAtomicallyPreservingPermissions(data: updatedData, to: url, defaultPermissions: defaultPerms)
    }

    public static func connectAllInstalled(
        endpoint: MCPEndpointConfig,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> MCPBatchInstallResult {
        let detected = detectAll(
            endpoint: endpoint,
            homeDirectory: homeDirectory,
            applicationsDirectory: applicationsDirectory
        )
        var connected: [MCPClientKind] = []
        var failures: [(kind: MCPClientKind, message: String)] = []

        for client in detected where client.isInstalled && client.state != .connected {
            do {
                try connect(client.kind, endpoint: endpoint, homeDirectory: homeDirectory)
                connected.append(client.kind)
            } catch {
                failures.append((client.kind, error.localizedDescription))
            }
        }
        return MCPBatchInstallResult(connected: connected, failures: failures)
    }

    public static func disconnect(
        _ kind: MCPClientKind,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let url = configURL(for: kind, homeDirectory: homeDirectory)
        guard let data = try? Data(contentsOf: url) else { return }
        let updatedData: Data
        if kind == .codex {
            let text = String(decoding: data, as: UTF8.self)
            updatedData = Data(MCPClientConfig.removeCodexTOML(text, serverName: serverName).utf8)
        } else {
            updatedData = try MCPClientConfig.removeJSONConfig(data, serverName: serverName)
        }
        let defaultPerms: Int = (kind == .claudeCode || kind == .codex) ? 0o600 : 0o644
        try writeAtomicallyPreservingPermissions(data: updatedData, to: url, defaultPermissions: defaultPerms)
    }

    private static func writeAtomicallyPreservingPermissions(
        data: Data,
        to url: URL,
        defaultPermissions: Int
    ) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let existingPerms = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: existingPerms ?? defaultPermissions], ofItemAtPath: url.path)
    }

    private static func binaryExists(_ name: String, homeDirectory: URL) -> Bool {
        let fm = FileManager.default
        let candidates = [
            homeDirectory.appendingPathComponent(".local/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
        ]
        return candidates.contains { fm.isExecutableFile(atPath: $0) }
    }
}

public enum MCPCloudDeployError: LocalizedError, Sendable {
    case scriptNotFound
    case deployFailed(String)
    case invalidOutput

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Could not find tools/deploy-mcp in the Tally source folder."
        case .deployFailed(let detail):
            return detail.isEmpty ? "Cloudflare deployment failed." : detail
        case .invalidOutput:
            return "Deployment finished, but its output could not be parsed."
        }
    }
}

/// Runs `tools/deploy-mcp --json` from the Mac app for true 1-tap Cloudflare deployment.
public enum MCPCloudDeployer {
    public static func isValidRepoRoot(_ url: URL) -> Bool {
        let script = url.appendingPathComponent("tools/deploy-mcp")
        return FileManager.default.isExecutableFile(atPath: script.path)
    }

    public static func findRepoRoot(preferredPath: String) -> URL? {
        let trimmed = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
            if isValidRepoRoot(candidate) { return candidate }
        }

        var searchRoots: [URL] = [Bundle.main.bundleURL]
        if let exec = Bundle.main.executableURL {
            searchRoots.append(exec.deletingLastPathComponent())
        }
        searchRoots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
        searchRoots.append(URL(fileURLWithPath: #filePath))

        for start in searchRoots {
            var current = start
            for _ in 0..<10 {
                if isValidRepoRoot(current) { return current }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        return nil
    }

    public static func deploy(
        repoRoot: URL,
        onProgress: @escaping @MainActor (String) -> Void
    ) async throws -> MCPPairingPayload {
        let script = repoRoot.appendingPathComponent("tools/deploy-mcp")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            throw MCPCloudDeployError.scriptNotFound
        }

        let (exitCode, stdoutData, stderrText) = try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, "--json"]
            process.currentDirectoryURL = repoRoot

            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let extraPath = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:/usr/bin:/bin"
            env["PATH"] = env["PATH"].map { "\(extraPath):\($0)" } ?? extraPath
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let stderrCollector = LineCollector { line in
                Task { @MainActor in onProgress(line) }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty { stderrCollector.append(chunk) }
            }

            try process.run()
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            errPipe.fileHandleForReading.readabilityHandler = nil
            let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()
            if !tailErr.isEmpty { stderrCollector.append(tailErr) }
            stderrCollector.flush()

            return (process.terminationStatus, outData, stderrCollector.allText())
        }.value

        guard exitCode == 0 else {
            let lines = stderrText
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            throw MCPCloudDeployError.deployFailed(lines.last ?? "Exit code \(exitCode)")
        }

        struct DeployJSON: Decodable {
            let url: String
            let syncSecret: String
            let accessToken: String
        }
        guard let decoded = try? JSONDecoder().decode(DeployJSON.self, from: stdoutData),
              let baseURL = MCPSetupLink.normalizeWorkerURL(decoded.url),
              !decoded.syncSecret.isEmpty,
              !decoded.accessToken.isEmpty
        else {
            throw MCPCloudDeployError.invalidOutput
        }
        return MCPPairingPayload(baseURL: baseURL, syncSecret: decoded.syncSecret, accessToken: decoded.accessToken)
    }
}

private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var fullText = ""
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        var emitted: [String] = []
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[..<newline]
            buffer = Data(buffer[buffer.index(after: newline)...])
            let line = String(decoding: lineData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                fullText += (fullText.isEmpty ? "" : "\n") + line
                emitted.append(line)
            }
        }
        lock.unlock()
        for line in emitted { onLine(line) }
    }

    func flush() {
        var emitted: String?
        lock.lock()
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll()
            if !line.isEmpty {
                fullText += (fullText.isEmpty ? "" : "\n") + line
                emitted = line
            }
        }
        lock.unlock()
        if let emitted { onLine(emitted) }
    }

    func allText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return fullText
    }
}
#endif
