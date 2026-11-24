import Foundation

/// One parsed HTTP/1.1 request. Header names are lowercased.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    /// Request target without the query string.
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    /// `true` when the client asked for the connection to be closed after this response.
    public var wantsClose: Bool {
        headers["connection"]?.lowercased().contains("close") ?? false
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    /// A short plain-text response (errors).
    public static func text(_ status: Int, _ message: String, headers: [String: String] = [:]) -> HTTPResponse {
        var all = headers
        all["Content-Type"] = "text/plain; charset=utf-8"
        return HTTPResponse(status: status, headers: all, body: Data((message + "\n").utf8))
    }

    public static func json(_ status: Int, _ body: Data) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "application/json"], body: body)
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 413: return "Content Too Large"
        case 415: return "Unsupported Media Type"
        case 431: return "Request Header Fields Too Large"
        default: return status < 500 ? "Error" : "Internal Server Error"
        }
    }

    /// The bytes to write to the socket.
    public func serialized(keepAlive: Bool) -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = keepAlive ? "keep-alive" : "close"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    /// More bytes are needed.
    case incomplete
    /// A whole request, and how many bytes of the buffer it used.
    case request(HTTPRequest, consumed: Int)
    /// The bytes cannot be a request this server accepts; answer with this and close.
    case failure(HTTPResponse)
}

/// A small HTTP/1.1 request parser for the local MCP endpoint: request line, headers and a
/// `Content-Length` body. Chunked request bodies are refused.
public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 1024 * 1024

    public static func parse(_ buffer: Data) -> HTTPParseResult {
        let data = buffer.startIndex == 0 ? buffer : Data(buffer)
        let terminator = Data("\r\n\r\n".utf8)
        guard let headEnd = data.range(of: terminator, in: 0..<min(data.count, maxHeaderBytes + terminator.count)) else {
            return data.count > maxHeaderBytes ? .failure(.text(431, "Request headers too large")) : .incomplete
        }
        guard let head = String(data: data[0..<headEnd.lowerBound], encoding: .utf8) else {
            return .failure(.text(400, "Malformed request"))
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .failure(.text(400, "Malformed request line"))
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(.text(400, "Malformed header"))
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(.text(400, "Malformed header")) }
            headers[name] = value
        }

        if headers["transfer-encoding"] != nil {
            return .failure(.text(411, "Send the body with Content-Length"))
        }
        var length = 0
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw), parsed >= 0 else {
                return .failure(.text(400, "Malformed Content-Length"))
            }
            length = parsed
        }
        guard length <= maxBodyBytes else {
            return .failure(.text(413, "Request body too large"))
        }

        let bodyStart = headEnd.upperBound
        guard data.count >= bodyStart + length else { return .incomplete }

        let target = String(requestLine[1])
        let path = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? target
        let request = HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: path,
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + length)])
        )
        return .request(request, consumed: bodyStart + length)
    }
}
