import Foundation

/// Parsed Cloud MCP pairing credentials from a `tally://mcp?...` deep link or QR code.
public struct MCPPairingPayload: Equatable, Identifiable, Sendable {
    public var baseURL: URL
    public var syncSecret: String
    public var accessToken: String

    public var id: String { "\(baseURL.absoluteString)|\(accessToken)" }

    public init(baseURL: URL, syncSecret: String, accessToken: String) {
        self.baseURL = baseURL
        self.syncSecret = syncSecret
        self.accessToken = accessToken
    }
}

/// Pure helpers for building and parsing Cloud & Local MCP URLs and pairing links.
public enum MCPSetupLink {
    /// Normalizes a Cloudflare Worker URL (`https://...workers.dev` or loopback `http://127.0.0.1:...`).
    /// Strips any trailing `/mcp` or trailing slash so either a base URL or full `/mcp` URL works.
    public static func normalizeWorkerURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.contains("://") {
            withScheme = trimmed
        } else if trimmed.lowercased().hasPrefix("127.0.0.1") || trimmed.lowercased().hasPrefix("localhost") {
            withScheme = "http://\(trimmed)"
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard var comps = URLComponents(string: withScheme),
              let scheme = comps.scheme?.lowercased(),
              let host = comps.host?.lowercased(),
              !host.isEmpty
        else { return nil }

        if scheme == "http" {
            guard host == "127.0.0.1" || host == "localhost" else { return nil }
        } else if scheme != "https" {
            return nil
        }

        var path = comps.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.lowercased() == "/mcp" {
            path = ""
        }
        comps.path = path
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    public static func mcpURL(baseURL: URL) -> String {
        baseURL.appendingPathComponent("mcp").absoluteString
    }

    public static func quickConnectorURL(baseURL: URL, token: String) -> String {
        baseURL
            .appendingPathComponent("u")
            .appendingPathComponent(token)
            .appendingPathComponent("mcp")
            .absoluteString
    }

    public static func localQuickURL(port: Int, token: String) -> String {
        "http://127.0.0.1:\(port)/u/\(token)/mcp"
    }

    /// Builds `tally://mcp?url=...&sync=...&token=...` for QR codes, AirDrop, and `tools/deploy-mcp`.
    public static func pairingDeepLink(baseURL: URL, syncSecret: String, accessToken: String) -> URL? {
        let sync = syncSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sync.isEmpty, !token.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "tally"
        comps.host = "mcp"
        comps.queryItems = [
            URLQueryItem(name: "url", value: baseURL.absoluteString),
            URLQueryItem(name: "sync", value: sync),
            URLQueryItem(name: "token", value: token),
        ]
        return comps.url
    }

    public static func parsePairingDeepLink(_ url: URL) -> MCPPairingPayload? {
        guard url.scheme?.lowercased() == "tally",
              url.host?.lowercased() == "mcp",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var rawURL = ""
        var sync = ""
        var token = ""
        for item in comps.queryItems ?? [] {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            switch item.name.lowercased() {
            case "url": rawURL = value
            case "sync": sync = value
            case "token": token = value
            default: break
            }
        }

        guard let baseURL = normalizeWorkerURL(rawURL),
              !sync.isEmpty,
              !token.isEmpty
        else { return nil }

        return MCPPairingPayload(baseURL: baseURL, syncSecret: sync, accessToken: token)
    }

    public static func parsePairingText(_ raw: String) -> MCPPairingPayload? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return parsePairingDeepLink(url)
    }
}
