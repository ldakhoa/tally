import Foundation
import TallyCore

public struct ClaudeModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let supportsServerFallback: Bool

    public init(id: String, name: String, supportsServerFallback: Bool) {
        self.id = id
        self.name = name
        self.supportsServerFallback = supportsServerFallback
    }

    public func blurb(in language: AppLanguage) -> String {
        switch id {
        case Self.opus.id:
            return L10n.text(language,
                en: "Most thorough analysis and insights, slower and costs more.",
                vi: "Phân tích sâu nhất, chậm hơn và tốn phí cao hơn.",
                zh: "最深入的分析和洞察，速度较慢且费用较高。")
        case Self.sonnet.id:
            return L10n.text(language,
                en: "Recommended. Fast, accurate parsing and budget advice.",
                vi: "Khuyên dùng. Nhanh, đọc giao dịch chuẩn và tư vấn chi tiêu tốt.",
                zh: "推荐。速度快，解析准确且预算建议实用。")
        default:
            return L10n.text(language,
                en: "Fastest and cheapest — great for quick bank alert parsing.",
                vi: "Nhanh và tiết kiệm nhất — rất hợp để đọc thông báo ngân hàng.",
                zh: "最快最省费用——适合快速解析银行通知。")
        }
    }
}

extension ClaudeModel {
    public static let opus = ClaudeModel(
        id: "claude-opus-5-5",
        name: "Claude Opus 5.5",
        supportsServerFallback: true
    )

    public static let sonnet = ClaudeModel(
        id: "claude-sonnet-5-5",
        name: "Claude Sonnet 5.5",
        supportsServerFallback: true
    )

    public static let haiku = ClaudeModel(
        id: "claude-haiku-5-5",
        name: "Claude Haiku 5.5",
        supportsServerFallback: false
    )

    public static let all: [ClaudeModel] = [.sonnet, .haiku, .opus]
    public static let `default`: ClaudeModel = .sonnet

    public static func resolve(id: String?) -> ClaudeModel {
        all.first { $0.id == id } ?? .default
    }
}

public enum Effort: String, Codable, Sendable, CaseIterable {
    case low, medium, high, xhigh, max
}

public struct ClaudeTool: Codable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ClaudeToolUse: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var input: JSONValue

    public init(id: String, name: String, input: JSONValue) {
        self.id = id
        self.name = name
        self.input = input
    }
}

/// Base64 image for an `image` content block. Never log `base64Data`.
public struct ClaudeImageSource: Hashable, Sendable {
    /// `image/jpeg`, `image/png`, `image/gif` or `image/webp`.
    public var mediaType: String
    /// Standard base64 (no line breaks) of the encoded image bytes.
    public var base64Data: String

    public static let supportedMediaTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]

    public init(mediaType: String, base64Data: String) {
        self.mediaType = mediaType
        self.base64Data = base64Data
    }

    public init(mediaType: String, data: Data) {
        self.init(mediaType: mediaType, base64Data: data.base64EncodedString())
    }
}

public enum ClaudeContentBlock: Hashable, Sendable {
    case text(String)
    case image(ClaudeImageSource)
    case toolUse(ClaudeToolUse)
    case toolResult(toolUseID: String, content: String, isError: Bool = false)

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var isToolResult: Bool {
        if case .toolResult = self { return true }
        return false
    }
}

extension ClaudeContentBlock: CustomStringConvertible {
    /// Debug description that never includes image bytes.
    public var description: String {
        switch self {
        case .text(let text): return "text(\(text.count) chars)"
        case .image(let source): return "image(\(source.mediaType), \(source.base64Data.count) base64 chars)"
        case .toolUse(let tool): return "tool_use(\(tool.name))"
        case .toolResult(let id, _, let isError): return "tool_result(\(id)\(isError ? ", error" : ""))"
        }
    }
}

extension ClaudeContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, source
        case toolUseID = "tool_use_id"
        case content
        case isError = "is_error"
    }

    private enum ImageSourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            let source = try container.nestedContainer(keyedBy: ImageSourceKeys.self, forKey: .source)
            let sourceType = try source.decode(String.self, forKey: .type)
            guard sourceType == "base64" else {
                throw DecodingError.dataCorruptedError(forKey: .type, in: source, debugDescription: "Unsupported image source \(sourceType)")
            }
            self = .image(ClaudeImageSource(
                mediaType: try source.decode(String.self, forKey: .mediaType),
                base64Data: try source.decode(String.self, forKey: .data)
            ))
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(ClaudeToolUse(id: id, name: name, input: input))
        case "tool_result":
            let toolUseID = try container.decode(String.self, forKey: .toolUseID)
            let content = try container.decode(String.self, forKey: .content)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            self = .toolResult(toolUseID: toolUseID, content: content, isError: isError)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content block type \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let image):
            try container.encode("image", forKey: .type)
            var source = container.nestedContainer(keyedBy: ImageSourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode(image.mediaType, forKey: .mediaType)
            try source.encode(image.base64Data, forKey: .data)
        case .toolUse(let tool):
            try container.encode("tool_use", forKey: .type)
            try container.encode(tool.id, forKey: .id)
            try container.encode(tool.name, forKey: .name)
            try container.encode(tool.input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .toolUseID)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        }
    }
}

public struct ClaudeMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public var role: Role
    public var content: String
    public var blocks: [ClaudeContentBlock]?

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
        self.blocks = nil
    }

    public init(role: Role, blocks: [ClaudeContentBlock]) {
        self.role = role
        self.content = blocks.compactMap {
            if case .text(let t) = $0 { return t }
            return nil
        }.joined()
        self.blocks = blocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(Role.self, forKey: .role)
        if let str = try? container.decode(String.self, forKey: .content) {
            self.content = str
            self.blocks = nil
        } else {
            let decodedBlocks = try container.decode([ClaudeContentBlock].self, forKey: .content)
            self.blocks = decodedBlocks
            self.content = decodedBlocks.compactMap {
                if case .text(let t) = $0 { return t }
                return nil
            }.joined()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if let blocks {
            try container.encode(blocks, forKey: .content)
        } else {
            try container.encode(content, forKey: .content)
        }
    }

    public static func user(_ content: String) -> ClaudeMessage { .init(role: .user, content: content) }
    /// A user turn with images. Images come first, then the text (the order the Messages API
    /// recommends); with no images this is a plain text message.
    public static func user(_ text: String, images: [ClaudeImageSource]) -> ClaudeMessage {
        guard !images.isEmpty else { return .user(text) }
        var blocks: [ClaudeContentBlock] = images.map { .image($0) }
        if !text.isEmpty { blocks.append(.text(text)) }
        return .init(role: .user, blocks: blocks)
    }
    public static func assistant(_ content: String) -> ClaudeMessage { .init(role: .assistant, content: content) }

    /// `true` for a user message carrying tool results (part of a tool loop, not a user turn).
    public var isToolResults: Bool {
        role == .user && (blocks?.contains(where: \.isToolResult) ?? false)
    }

    /// `true` for a message the user typed (text and/or images), as opposed to tool results.
    public var isUserTurn: Bool { role == .user && !isToolResults }

    public var imageCount: Int { blocks?.filter(\.isImage).count ?? 0 }

    /// The same message with every image block replaced by one short text placeholder, so old
    /// turns are not resent with their image bytes.
    public func replacingImages(withPlaceholder placeholder: String) -> ClaudeMessage {
        guard let blocks, blocks.contains(where: \.isImage) else { return self }
        var result: [ClaudeContentBlock] = [.text(placeholder)]
        result.append(contentsOf: blocks.filter { !$0.isImage })
        if result.allSatisfy({ if case .text = $0 { return true } else { return false } }) {
            return .init(role: role, content: result.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined(separator: "\n"))
        }
        return .init(role: role, blocks: result)
    }
    public static func assistant(blocks: [ClaudeContentBlock]) -> ClaudeMessage { .init(role: .assistant, blocks: blocks) }
    public static func toolResults(_ results: [(id: String, content: String, isError: Bool)]) -> ClaudeMessage {
        .init(role: .user, blocks: results.map { .toolResult(toolUseID: $0.id, content: $0.content, isError: $0.isError) })
    }
}

public struct ClaudeRequest: Hashable, Sendable {
    public var system: String?
    public var messages: [ClaudeMessage]
    public var maxTokens: Int
    public var effort: Effort
    public var jsonSchema: JSONValue?
    public var tools: [ClaudeTool]
    public var cacheConversation: Bool

    public init(
        system: String? = nil,
        messages: [ClaudeMessage],
        maxTokens: Int = 4_096,
        effort: Effort = .low,
        jsonSchema: JSONValue? = nil,
        tools: [ClaudeTool] = [],
        cacheConversation: Bool = false
    ) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.effort = effort
        self.jsonSchema = jsonSchema
        self.tools = tools
        self.cacheConversation = cacheConversation
    }
}

public struct ClaudeCompletion: Hashable, Sendable {
    public var text: String
    public var toolUses: [ClaudeToolUse]
    public var stopReason: String?
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(
        text: String = "",
        toolUses: [ClaudeToolUse] = [],
        stopReason: String? = nil,
        model: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.text = text
        self.toolUses = toolUses
        self.stopReason = stopReason
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var wasTruncated: Bool { stopReason == "max_tokens" }
    public var needsToolExecution: Bool { !toolUses.isEmpty }

    public var assistantBlocks: [ClaudeContentBlock] {
        var result: [ClaudeContentBlock] = []
        if !text.isEmpty {
            result.append(.text(text))
        }
        result.append(contentsOf: toolUses.map { .toolUse($0) })
        return result
    }
}

public enum ClaudeStreamEvent: Hashable, Sendable {
    case text(String)
    case finished(ClaudeCompletion)
}

public enum ClaudeError: Error, Equatable, Sendable {
    case missingAPIKey
    case api(status: Int, type: String, message: String, requestID: String?)
    case refused(category: String?)
    case truncated
    case malformedResponse(String)
    case network(String)
}

public enum APIProblem: Equatable, Sendable {
    case workspaceRequired
    case invalidWorkspaceID
    case workspaceNotFound
    case outOfCredit
    case keyRejected
    case billing
    case notAllowed
    case modelUnavailable
    case rateLimited
    case overloaded
    case serverError
    case other

    public static func classify(status: Int, type: String, message: String) -> APIProblem {
        let lowered = message.lowercased()
        if lowered.contains("not scoped to a workspace") { return .workspaceRequired }
        if lowered.contains("anthropic-workspace-id") {
            return lowered.contains("valid workspace id") ? .invalidWorkspaceID : .workspaceRequired
        }
        if lowered.hasPrefix("workspace "), lowered.contains("not found") { return .workspaceNotFound }
        if lowered.contains("credit balance") { return .outOfCredit }
        switch (status, type) {
        case (401, _), (_, "authentication_error"): return .keyRejected
        case (402, _), (_, "billing_error"): return .billing
        case (403, _), (_, "permission_error"): return .notAllowed
        case (404, _), (_, "not_found_error"): return .modelUnavailable
        case (429, _), (_, "rate_limit_error"): return .rateLimited
        case (529, _), (_, "overloaded_error"): return .overloaded
        case (500..., _): return .serverError
        default: return .other
        }
    }
}

extension ClaudeError {
    public var apiProblem: APIProblem? {
        guard case .api(let status, let type, let message, _) = self else { return nil }
        return APIProblem.classify(status: status, type: type, message: message)
    }

    public func localizedMessage(in language: AppLanguage) -> String {
        switch self {
        case .missingAPIKey:
            return L10n.text(language,
                en: "Add your Anthropic API key in Settings to use AI features.",
                vi: "Thêm Anthropic API key trong Cài đặt để dùng tính năng AI.",
                zh: "请在设置中添加您的 Anthropic API 密钥以使用 AI 功能。")
        case .api(let status, _, let message, _):
            switch apiProblem ?? .other {
            case .workspaceRequired:
                return L10n.text(language,
                    en: "This API key needs a Workspace ID (starts with wrkspc_) in Settings.",
                    vi: "API key này cần Workspace ID (bắt đầu bằng wrkspc_) trong Cài đặt.",
                    zh: "此 API 密钥需要在设置中填写 Workspace ID（以 wrkspc_ 开头）。")
            case .invalidWorkspaceID:
                return L10n.text(language,
                    en: "The Workspace ID in Settings is invalid.",
                    vi: "Workspace ID trong Cài đặt không hợp lệ.",
                    zh: "设置中的 Workspace ID 无效。")
            case .workspaceNotFound:
                return L10n.text(language,
                    en: "Workspace not found for this API key.",
                    vi: "Không tìm thấy Workspace cho API key này.",
                    zh: "未找到此 API 密钥对应的 Workspace。")
            case .outOfCredit:
                return L10n.text(language,
                    en: "Your Anthropic API account has run out of credit.",
                    vi: "Tài khoản Anthropic API đã hết credit.",
                    zh: "您的 Anthropic API 账户余额已用尽。")
            case .keyRejected:
                return L10n.text(language,
                    en: "The API key was rejected. Check it in Settings.",
                    vi: "API key bị từ chối. Hãy kiểm tra lại trong Cài đặt.",
                    zh: "API 密钥被拒绝，请在设置中检查。")
            case .billing:
                return L10n.text(language,
                    en: "Check Billing in the Claude Console.",
                    vi: "Kiểm tra mục Billing trên Claude Console.",
                    zh: "请在 Claude Console 中检查账单设置。")
            case .notAllowed:
                return message.isEmpty
                    ? L10n.text(language, en: "This API key is not allowed to do that.", vi: "API key không có quyền thực hiện yêu cầu này.", zh: "此 API 密钥无权执行该操作。")
                    : message
            case .modelUnavailable:
                return L10n.text(language,
                    en: "The selected model is unavailable for this key. Pick another in Settings.",
                    vi: "Model đã chọn không khả dụng với key này. Hãy chọn model khác trong Cài đặt.",
                    zh: "所选模型对此密钥不可用，请在设置中更换模型。")
            case .rateLimited:
                return L10n.text(language, en: "Rate limit reached. Try again in a moment.", vi: "Đạt giới hạn tốc độ. Thử lại sau giây lát.", zh: "已达到请求频率限制，请稍后再试。")
            case .overloaded:
                return L10n.text(language, en: "Claude is overloaded right now. Try again shortly.", vi: "Claude đang quá tải. Thử lại sau giây lát.", zh: "Claude 当前负载过高，请稍后重试。")
            case .serverError:
                return L10n.text(language, en: "Claude API error (\(status)). Try again.", vi: "Lỗi Claude API (\(status)). Thử lại sau.", zh: "Claude API 错误（\(status)），请重试。")
            case .other:
                return message.isEmpty
                    ? L10n.text(language, en: "Request failed (\(status)).", vi: "Yêu cầu thất bại (\(status)).", zh: "请求失败（\(status)）。")
                    : message
            }
        case .refused:
            return L10n.text(language, en: "Claude declined to answer this request.", vi: "Claude từ chối trả lời yêu cầu này.", zh: "Claude 拒绝回答此请求。")
        case .truncated:
            return L10n.text(language, en: "The reply was cut off. Try again.", vi: "Phản hồi bị cắt ngắn. Hãy thử lại.", zh: "回复被截断，请重试。")
        case .malformedResponse(let detail):
            return detail
        case .network(let detail):
            return L10n.text(language, en: "Network problem: \(detail)", vi: "Lỗi mạng: \(detail)", zh: "网络问题：\(detail)")
        }
    }
}

extension ClaudeError: LocalizedError {
    public var errorDescription: String? {
        localizedMessage(in: .english)
    }
}
