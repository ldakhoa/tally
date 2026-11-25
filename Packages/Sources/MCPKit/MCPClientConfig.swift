import Foundation

public enum MCPClientKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case claudeCode
    case codex
    case claudeDesktop
    case antigravity
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .claudeDesktop: return "Claude Desktop"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        }
    }
}

public enum MCPClientConnectionState: Equatable, Sendable {
    case notConfigured
    case connected
    case needsUpdate
}

public struct MCPEndpointConfig: Equatable, Sendable {
    public var url: String
    public var quickURL: String
    public var token: String

    public init(url: String, quickURL: String, token: String) {
        self.url = url
        self.quickURL = quickURL
        self.token = token
    }
}

public enum MCPClientConfigError: Error, Equatable, Sendable {
    case invalidJSON
    case unsupportedKindForJSON
}

/// Pure Foundation config editors for local desktop MCP clients (JSON and Codex TOML).
/// Preserves existing keys, sibling servers, comments, and unrelated sections.
public enum MCPClientConfig {
    public static func jsonServerEntry(for kind: MCPClientKind, endpoint: MCPEndpointConfig) -> [String: Any] {
        switch kind {
        case .claudeCode:
            return [
                "type": "http",
                "url": endpoint.url,
                "headers": ["Authorization": "Bearer \(endpoint.token)"],
            ]
        case .claudeDesktop:
            var args = ["-y", "mcp-remote", endpoint.quickURL]
            if endpoint.quickURL.lowercased().hasPrefix("http://") {
                args.append("--allow-http")
            }
            return [
                "command": "npx",
                "args": args,
            ]
        case .antigravity:
            return [
                "url": endpoint.quickURL,
            ]
        case .cursor:
            return [
                "url": endpoint.url,
                "headers": ["Authorization": "Bearer \(endpoint.token)"],
            ]
        case .codex:
            return [:]
        }
    }

    public static func inspectJSONConfig(
        _ data: Data?,
        serverName: String,
        endpoint: MCPEndpointConfig,
        kind: MCPClientKind
    ) -> MCPClientConnectionState {
        guard kind != .codex,
              let data,
              !isBlank(data),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverName] as? [String: Any]
        else { return .notConfigured }

        let expected = jsonServerEntry(for: kind, endpoint: endpoint)
        return NSDictionary(dictionary: entry).isEqual(to: expected) ? .connected : .needsUpdate
    }

    public static func upsertJSONConfig(
        _ data: Data?,
        serverName: String,
        endpoint: MCPEndpointConfig,
        kind: MCPClientKind
    ) throws -> Data {
        guard kind != .codex else { throw MCPClientConfigError.unsupportedKindForJSON }

        var root: [String: Any] = [:]
        if let data, !isBlank(data) {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPClientConfigError.invalidJSON
            }
            root = parsed
        }

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers[serverName] = jsonServerEntry(for: kind, endpoint: endpoint)
        root["mcpServers"] = servers

        let encoded = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return encoded + Data("\n".utf8)
    }

    public static func removeJSONConfig(_ data: Data, serverName: String) throws -> Data {
        guard !isBlank(data) else { return Data("{}\n".utf8) }
        guard var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPClientConfigError.invalidJSON
        }
        if var servers = root["mcpServers"] as? [String: Any] {
            servers.removeValue(forKey: serverName)
            root["mcpServers"] = servers
        }
        let encoded = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return encoded + Data("\n".utf8)
    }

    // MARK: - Codex TOML

    public static func codexSectionBlock(serverName: String, endpoint: MCPEndpointConfig) -> String {
        """
        [mcp_servers.\(serverName)]
        url = "\(escapeTOML(endpoint.url))"
        http_headers = { Authorization = "Bearer \(escapeTOML(endpoint.token))" }
        """
    }

    public static func inspectCodexTOML(
        _ content: String?,
        serverName: String,
        endpoint: MCPEndpointConfig
    ) -> MCPClientConnectionState {
        guard let content, !content.isEmpty else { return .notConfigured }
        let lines = splitLinesPreservingStructure(content)
        guard let range = codexSectionRange(in: lines, serverName: serverName) else {
            return .notConfigured
        }
        let slice = lines[range].joined(separator: "\n")
        let expectedURL = "url = \"\(escapeTOML(endpoint.url))\""
        let expectedHeader = "Bearer \(escapeTOML(endpoint.token))"
        if slice.contains(expectedURL) && slice.contains(expectedHeader) {
            return .connected
        }
        return .needsUpdate
    }

    public static func upsertCodexTOML(
        _ content: String?,
        serverName: String,
        endpoint: MCPEndpointConfig
    ) -> String {
        let block = codexSectionBlock(serverName: serverName, endpoint: endpoint)
        guard let content, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return block + "\n"
        }

        var lines = splitLinesPreservingStructure(content)
        let blockLines = block.components(separatedBy: "\n")

        if let range = codexSectionRange(in: lines, serverName: serverName) {
            lines.replaceSubrange(range, with: blockLines)
            var joined = lines.joined(separator: "\n")
            if !joined.hasSuffix("\n") { joined += "\n" }
            return joined
        }

        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        lines.append("")
        lines.append(contentsOf: blockLines)
        return lines.joined(separator: "\n") + "\n"
    }

    public static func removeCodexTOML(_ content: String, serverName: String) -> String {
        guard !content.isEmpty else { return "" }
        var lines = splitLinesPreservingStructure(content)
        while let range = codexSectionRange(in: lines, serverName: serverName) {
            lines.removeSubrange(range)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func codexSectionRange(in lines: [String], serverName: String) -> Range<Int>? {
        let exactHeader = "[mcp_servers.\(serverName)]"
        let childPrefix = "[mcp_servers.\(serverName)."
        var startIdx: Int?

        for (idx, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { continue }
            if startIdx == nil {
                if trimmed == exactHeader || trimmed.hasPrefix(childPrefix) {
                    startIdx = idx
                }
            } else {
                if trimmed == exactHeader || trimmed.hasPrefix(childPrefix) {
                    continue
                }
                return startIdx!..<idx
            }
        }
        if let startIdx {
            return startIdx..<lines.count
        }
        return nil
    }

    private static func splitLinesPreservingStructure(_ content: String) -> [String] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        if lines.last == "" && normalized.hasSuffix("\n") {
            lines.removeLast()
        }
        return lines
    }

    private static func escapeTOML(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func isBlank(_ data: Data) -> Bool {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
