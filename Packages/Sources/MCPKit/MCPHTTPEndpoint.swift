import Foundation

/// MCP "Streamable HTTP" on one path, answering every POST with a single JSON body (no SSE).
///
/// Every request must carry `Authorization: Bearer <token>`. Requests whose `Host` or `Origin`
/// is not this machine are refused, so a web page cannot reach the server through the browser
/// (DNS rebinding).
public struct MCPHTTPEndpoint: Sendable {
    public static let defaultPath = "/mcp"

    public var path: String
    public var token: String
    public var core: MCPServerCore

    public init(path: String = MCPHTTPEndpoint.defaultPath, token: String, core: MCPServerCore) {
        self.path = path
        self.token = token
        self.core = core
    }

    public func respond(to request: HTTPRequest) async -> HTTPResponse {
        if let host = request.headers["host"], !Self.isLocalAuthority(host) {
            return .text(403, "Forbidden host")
        }
        if let origin = request.headers["origin"], !Self.isLocalOrigin(origin) {
            return .text(403, "Forbidden origin")
        }
        if let quickToken = Self.extractQuickToken(path: request.path) {
            guard !token.isEmpty, Self.constantTimeEquals(quickToken, token) else {
                return .text(401, "Missing or wrong bearer token", headers: ["WWW-Authenticate": "Bearer"])
            }
        } else if request.path == path {
            guard Self.isAuthorized(request.headers["authorization"], token: token) else {
                return .text(401, "Missing or wrong bearer token", headers: ["WWW-Authenticate": "Bearer"])
            }
        } else {
            return .text(404, "Not found. The MCP endpoint is \(path)")
        }
        guard request.method == "POST" else {
            // GET would open a server-to-client stream, which this server does not offer.
            return .text(405, "Use POST", headers: ["Allow": "POST"])
        }
        guard request.headers["content-type"]?.lowercased().contains("application/json") ?? false else {
            return .text(415, "Content-Type must be application/json")
        }
        guard let reply = await core.handle(body: request.body) else {
            return HTTPResponse(status: 202)
        }
        return .json(200, reply)
    }

    static func extractQuickToken(path: String) -> String? {
        let prefix = "/u/"
        let suffix = "/mcp"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix), path.count > prefix.count + suffix.count else {
            return nil
        }
        let middle = path.dropFirst(prefix.count).dropLast(suffix.count)
        guard !middle.contains("/"),
              let decoded = String(middle).removingPercentEncoding,
              !decoded.isEmpty
        else { return nil }
        return decoded
    }

    static let localHosts: Set<String> = ["127.0.0.1", "localhost", "[::1]"]

    /// `host` or `host:port` naming this machine.
    static func isLocalAuthority(_ authority: String) -> Bool {
        var host = authority.lowercased()
        if let colon = host.lastIndex(of: ":"), !host.hasSuffix("]"), host[host.index(after: colon)...].allSatisfy(\.isNumber) {
            host = String(host[..<colon])
        }
        return localHosts.contains(host)
    }

    static func isLocalOrigin(_ origin: String) -> Bool {
        guard let separator = origin.range(of: "://") else { return false }
        return isLocalAuthority(String(origin[separator.upperBound...]))
    }

    static func isAuthorized(_ header: String?, token: String) -> Bool {
        guard let header, !token.isEmpty else { return false }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(String(parts[1]).trimmingCharacters(in: .whitespaces), token)
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        var difference = UInt8(a.count == b.count ? 0 : 1)
        for index in 0..<max(a.count, b.count) {
            difference |= (index < a.count ? a[index] : 0) ^ (index < b.count ? b[index] : 0)
        }
        return difference == 0
    }
}
