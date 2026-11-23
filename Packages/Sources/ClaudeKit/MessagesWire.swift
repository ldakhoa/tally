import Foundation
import TallyCore

struct MessagesBody: Encodable {
    struct OutputConfig: Encodable {
        struct Format: Encodable {
            let type = "json_schema"
            let schema: JSONValue
        }

        let effort: Effort
        let format: Format?
    }

    struct CacheControl: Encodable {
        let type = "ephemeral"
    }

    let model: String
    let maxTokens: Int
    let stream = true
    let system: String?
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]?
    let outputConfig: OutputConfig
    let cacheControl: CacheControl?
    let fallbacks: String?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case stream
        case system
        case messages
        case tools
        case outputConfig = "output_config"
        case cacheControl = "cache_control"
        case fallbacks
    }

    init(request: ClaudeRequest, model: ClaudeModel) {
        self.model = model.id
        self.maxTokens = request.maxTokens
        self.system = request.system
        self.messages = request.messages
        self.tools = request.tools.isEmpty ? nil : request.tools
        self.outputConfig = OutputConfig(
            effort: request.effort,
            format: request.jsonSchema.map { OutputConfig.Format(schema: $0) }
        )
        self.cacheControl = request.cacheConversation ? CacheControl() : nil
        self.fallbacks = model.supportsServerFallback ? "default" : nil
    }
}

enum MessagesAPI {
    static let version = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let defaultBaseURL = URL(string: "https://api.anthropic.com")!

    static func urlRequest(
        for request: ClaudeRequest,
        model: ClaudeModel,
        apiKey: String,
        workspaceID: String? = nil,
        baseURL: URL
    ) throws -> URLRequest {
        let body = MessagesBody(request: request, model: model)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try encoder.encode(body)
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(version, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            urlRequest.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
        if body.fallbacks != nil {
            urlRequest.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        return urlRequest
    }
}

struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let type: String?
        let message: String?
    }

    let error: Detail?
    let requestID: String?

    enum CodingKeys: String, CodingKey {
        case error
        case requestID = "request_id"
    }
}

enum StreamSignal: Equatable {
    case messageStart(model: String?, inputTokens: Int?)
    case textDelta(String)
    case toolUseStart(index: Int, id: String, name: String)
    case toolInputDelta(index: Int, partialJSON: String)
    case contentBlockStop(index: Int)
    case messageDelta(stopReason: String?, refusalCategory: String?, outputTokens: Int?)
    case messageStop
    case error(type: String, message: String)
}

enum StreamDecoder {
    private struct Event: Decodable {
        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }

        struct Message: Decodable {
            let model: String?
            let usage: Usage?
        }

        struct ContentBlock: Decodable {
            let type: String?
            let id: String?
            let name: String?
        }

        struct StopDetails: Decodable {
            let category: String?
        }

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let partialJSON: String?
            let stopReason: String?
            let stopDetails: StopDetails?
            enum CodingKeys: String, CodingKey {
                case type, text
                case partialJSON = "partial_json"
                case stopReason = "stop_reason"
                case stopDetails = "stop_details"
            }
        }

        let type: String
        let index: Int?
        let message: Message?
        let contentBlock: ContentBlock?
        let delta: Delta?
        let usage: Usage?
        let error: APIErrorEnvelope.Detail?

        enum CodingKeys: String, CodingKey {
            case type, index, message, delta, usage, error
            case contentBlock = "content_block"
        }
    }

    static func decode(line: String) -> StreamSignal? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty,
              let event = try? JSONDecoder().decode(Event.self, from: Data(payload.utf8))
        else { return nil }

        switch event.type {
        case "message_start":
            return .messageStart(model: event.message?.model, inputTokens: event.message?.usage?.inputTokens)
        case "content_block_start":
            guard let idx = event.index,
                  event.contentBlock?.type == "tool_use",
                  let id = event.contentBlock?.id,
                  let name = event.contentBlock?.name
            else { return nil }
            return .toolUseStart(index: idx, id: id, name: name)
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                return .textDelta(text)
            }
            if event.delta?.type == "input_json_delta", let idx = event.index, let partial = event.delta?.partialJSON, !partial.isEmpty {
                return .toolInputDelta(index: idx, partialJSON: partial)
            }
            return nil
        case "content_block_stop":
            guard let idx = event.index else { return nil }
            return .contentBlockStop(index: idx)
        case "message_delta":
            return .messageDelta(
                stopReason: event.delta?.stopReason,
                refusalCategory: event.delta?.stopDetails?.category,
                outputTokens: event.usage?.outputTokens
            )
        case "message_stop":
            return .messageStop
        case "error":
            return .error(
                type: event.error?.type ?? "api_error",
                message: event.error?.message ?? "The stream reported an error."
            )
        default:
            return nil
        }
    }
}
