import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPStreamingResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let lines: AsyncThrowingStream<String, Error>

    public init(statusCode: Int, headers: [String: String], lines: AsyncThrowingStream<String, Error>) {
        self.statusCode = statusCode
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.lines = lines
    }
}

public protocol HTTPStreamingTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPStreamingResponse
}

#if !canImport(FoundationNetworking)
public struct URLSessionTransport: HTTPStreamingTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPStreamingResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        let lines = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
        return HTTPStreamingResponse(statusCode: http.statusCode, headers: headers, lines: lines)
    }
}
#endif
