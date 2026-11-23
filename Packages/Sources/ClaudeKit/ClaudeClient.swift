import Foundation
import TallyCore
#if canImport(FoundationNetworking)
import Foundation
import TallyCoreNetworking
#endif

public protocol AIClient: Sendable {
    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error>
}

extension AIClient {
    public func complete(_ request: ClaudeRequest) async throws -> ClaudeCompletion {
        var result: ClaudeCompletion?
        for try await event in stream(request) {
            if case .finished(let completion) = event {
                result = completion
            }
        }
        try Task.checkCancellation()
        guard let result else {
            throw ClaudeError.malformedResponse("The reply ended early.")
        }
        return result
    }

    public func completeJSON<T: Decodable>(_ type: T.Type, _ request: ClaudeRequest) async throws -> T {
        precondition(request.jsonSchema != nil, "completeJSON needs a request with a jsonSchema")
        let completion = try await complete(request)
        if completion.wasTruncated { throw ClaudeError.truncated }
        do {
            return try JSONDecoder().decode(T.self, from: Data(completion.text.utf8))
        } catch {
            throw ClaudeError.malformedResponse("The reply did not match the expected format.")
        }
    }
}

public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 1,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.sleep = sleep
    }

    public static let `default` = RetryPolicy()
    public static let noRetries = RetryPolicy(maxRetries: 0)

    static func isRetryable(status: Int) -> Bool {
        status == 408 || status == 409 || status == 429 || status >= 500
    }

    func delay(afterAttempt attempt: Int, retryAfter: String?) -> TimeInterval {
        if let retryAfter, let seconds = TimeInterval(retryAfter), seconds >= 0 {
            return min(seconds, 30)
        }
        return baseDelay * pow(2, Double(attempt - 1))
    }
}

public struct ClaudeClient: AIClient {
    public let model: ClaudeModel
    private let apiKey: String
    public let workspaceID: String?
    private let transport: HTTPStreamingTransport
    private let baseURL: URL
    private let retryPolicy: RetryPolicy

    public init(
        apiKey: String,
        workspaceID: String? = nil,
        model: ClaudeModel = .default,
        transport: HTTPStreamingTransport,
        baseURL: URL? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = workspaceID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.workspaceID = workspace.isEmpty ? nil : workspace
        self.model = model
        self.transport = transport
        self.baseURL = baseURL ?? MessagesAPI.defaultBaseURL
        self.retryPolicy = retryPolicy
    }

    #if !canImport(FoundationNetworking)
    public init(
        apiKey: String,
        workspaceID: String? = nil,
        model: ClaudeModel = .default
    ) {
        self.init(apiKey: apiKey, workspaceID: workspaceID, model: model, transport: URLSessionTransport())
    }
    #endif

    public func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let completion = try await self.run(request) { chunk in
                        continuation.yield(.text(chunk))
                    }
                    continuation.yield(.finished(completion))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func run(_ request: ClaudeRequest, onText: (String) -> Void) async throws -> ClaudeCompletion {
        let response = try await open(request)
        var completion = ClaudeCompletion()
        var pendingTools: [Int: (id: String, name: String, json: String)] = [:]
        var refusalCategory: String?
        var sawStop = false

        do {
            for try await line in response.lines {
                guard let signal = StreamDecoder.decode(line: line) else { continue }
                switch signal {
                case .messageStart(let model, let inputTokens):
                    completion.model = model
                    completion.inputTokens = inputTokens
                case .textDelta(let chunk):
                    completion.text += chunk
                    onText(chunk)
                case .toolUseStart(let index, let id, let name):
                    pendingTools[index] = (id: id, name: name, json: "")
                case .toolInputDelta(let index, let partialJSON):
                    pendingTools[index]?.json += partialJSON
                case .contentBlockStop(let index):
                    if let tool = pendingTools.removeValue(forKey: index) {
                        let raw = tool.json.trimmingCharacters(in: .whitespacesAndNewlines)
                        let input: JSONValue
                        if raw.isEmpty {
                            input = .object([:])
                        } else if let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)) {
                            input = decoded
                        } else {
                            input = .object([:])
                        }
                        completion.toolUses.append(ClaudeToolUse(id: tool.id, name: tool.name, input: input))
                    }
                case .messageDelta(let stopReason, let category, let outputTokens):
                    if let stopReason { completion.stopReason = stopReason }
                    if let category { refusalCategory = category }
                    if let outputTokens { completion.outputTokens = outputTokens }
                case .messageStop:
                    for (_, tool) in pendingTools.sorted(by: { $0.key < $1.key }) {
                        let raw = tool.json.trimmingCharacters(in: .whitespacesAndNewlines)
                        let input: JSONValue
                        if raw.isEmpty {
                            input = .object([:])
                        } else if let decoded = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)) {
                            input = decoded
                        } else {
                            input = .object([:])
                        }
                        completion.toolUses.append(ClaudeToolUse(id: tool.id, name: tool.name, input: input))
                    }
                    pendingTools.removeAll()
                    sawStop = true
                case .error(let type, let message):
                    throw ClaudeError.api(
                        status: Self.status(forErrorType: type),
                        type: type,
                        message: message,
                        requestID: response.headers["request-id"]
                    )
                }
            }
        } catch let error as ClaudeError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw ClaudeError.network(error.localizedDescription)
        }

        try Task.checkCancellation()
        if completion.stopReason == "refusal" {
            throw ClaudeError.refused(category: refusalCategory)
        }
        guard sawStop else {
            throw ClaudeError.malformedResponse("The reply ended early.")
        }
        return completion
    }

    private func open(_ request: ClaudeRequest) async throws -> HTTPStreamingResponse {
        guard !apiKey.isEmpty else { throw ClaudeError.missingAPIKey }
        let urlRequest: URLRequest
        do {
            urlRequest = try MessagesAPI.urlRequest(
                for: request, model: model, apiKey: apiKey, workspaceID: workspaceID, baseURL: baseURL
            )
        } catch {
            throw ClaudeError.malformedResponse("The request could not be encoded.")
        }

        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()

            let response: HTTPStreamingResponse
            do {
                response = try await transport.send(urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                if attempt <= retryPolicy.maxRetries {
                    try await retryPolicy.sleep(retryPolicy.delay(afterAttempt: attempt, retryAfter: nil))
                    continue
                }
                throw ClaudeError.network(error.localizedDescription)
            }

            if (200..<300).contains(response.statusCode) {
                return response
            }

            var body = ""
            do {
                for try await line in response.lines {
                    body += line
                    body += "\n"
                }
            } catch {}

            if attempt <= retryPolicy.maxRetries, RetryPolicy.isRetryable(status: response.statusCode) {
                let delay = retryPolicy.delay(afterAttempt: attempt, retryAfter: response.headers["retry-after"])
                try await retryPolicy.sleep(delay)
                continue
            }
            throw Self.error(status: response.statusCode, body: body, headers: response.headers)
        }
    }

    static func error(status: Int, body: String, headers: [String: String]) -> ClaudeError {
        let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: Data(body.utf8))
        return .api(
            status: status,
            type: envelope?.error?.type ?? "api_error",
            message: envelope?.error?.message ?? "",
            requestID: envelope?.requestID ?? headers["request-id"]
        )
    }

    public static func looksLikeWorkspaceID(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "wrkspc_"
        guard trimmed.hasPrefix(prefix), trimmed.count > prefix.count else { return false }
        return trimmed.dropFirst(prefix.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func status(forErrorType type: String) -> Int {
        switch type {
        case "invalid_request_error": return 400
        case "authentication_error": return 401
        case "billing_error": return 402
        case "permission_error": return 403
        case "not_found_error": return 404
        case "rate_limit_error": return 429
        case "overloaded_error": return 529
        default: return 500
        }
    }
}
