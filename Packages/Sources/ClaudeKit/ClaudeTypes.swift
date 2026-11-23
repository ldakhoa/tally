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
                vi: "Phân tích sâu nhất, chậm hơn và tốn phí cao hơn.")
        case Self.sonnet.id:
            return L10n.text(language,
                en: "Recommended. Fast, accurate parsing and budget advice.",
                vi: "Khuyên dùng. Nhanh, đọc giao dịch chuẩn và tư vấn chi tiêu tốt.")
        default:
            return L10n.text(language,
                en: "Fastest and cheapest — great for quick bank alert parsing.",
                vi: "Nhanh và tiết kiệm nhất — rất hợp để đọc thông báo ngân hàng.")
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

public struct ClaudeMessage: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public var role: Role
    public var content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> ClaudeMessage { .init(role: .user, content: content) }
    public static func assistant(_ content: String) -> ClaudeMessage { .init(role: .assistant, content: content) }
}

public struct ClaudeRequest: Hashable, Sendable {
    public var system: String?
    public var messages: [ClaudeMessage]
    public var maxTokens: Int
    public var effort: Effort
    public var jsonSchema: JSONValue?
    public var cacheConversation: Bool

    public init(
        system: String? = nil,
        messages: [ClaudeMessage],
        maxTokens: Int = 4_096,
        effort: Effort = .low,
        jsonSchema: JSONValue? = nil,
        cacheConversation: Bool = false
    ) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.effort = effort
        self.jsonSchema = jsonSchema
        self.cacheConversation = cacheConversation
    }
}

public struct ClaudeCompletion: Hashable, Sendable {
    public var text: String
    public var stopReason: String?
    public var model: String?
    public var inputTokens: Int?
    public var outputTokens: Int?

    public init(
        text: String = "",
        stopReason: String? = nil,
        model: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil
    ) {
        self.text = text
        self.stopReason = stopReason
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var wasTruncated: Bool { stopReason == "max_tokens" }
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
                vi: "Thêm Anthropic API key trong Cài đặt để dùng tính năng AI.")
        case .api(let status, _, let message, _):
            switch apiProblem ?? .other {
            case .workspaceRequired:
                return L10n.text(language,
                    en: "This API key needs a Workspace ID (starts with wrkspc_) in Settings.",
                    vi: "API key này cần Workspace ID (bắt đầu bằng wrkspc_) trong Cài đặt.")
            case .invalidWorkspaceID:
                return L10n.text(language,
                    en: "The Workspace ID in Settings is invalid.",
                    vi: "Workspace ID trong Cài đặt không hợp lệ.")
            case .workspaceNotFound:
                return L10n.text(language,
                    en: "Workspace not found for this API key.",
                    vi: "Không tìm thấy Workspace cho API key này.")
            case .outOfCredit:
                return L10n.text(language,
                    en: "Your Anthropic API account has run out of credit.",
                    vi: "Tài khoản Anthropic API đã hết credit.")
            case .keyRejected:
                return L10n.text(language,
                    en: "The API key was rejected. Check it in Settings.",
                    vi: "API key bị từ chối. Hãy kiểm tra lại trong Cài đặt.")
            case .billing:
                return L10n.text(language,
                    en: "Check Billing in the Claude Console.",
                    vi: "Kiểm tra mục Billing trên Claude Console.")
            case .notAllowed:
                return message.isEmpty
                    ? L10n.text(language, en: "This API key is not allowed to do that.", vi: "API key không có quyền thực hiện yêu cầu này.")
                    : message
            case .modelUnavailable:
                return L10n.text(language,
                    en: "The selected model is unavailable for this key. Pick another in Settings.",
                    vi: "Model đã chọn không khả dụng với key này. Hãy chọn model khác trong Cài đặt.")
            case .rateLimited:
                return L10n.text(language, en: "Rate limit reached. Try again in a moment.", vi: "Đạt giới hạn tốc độ. Thử lại sau giây lát.")
            case .overloaded:
                return L10n.text(language, en: "Claude is overloaded right now. Try again shortly.", vi: "Claude đang quá tải. Thử lại sau giây lát.")
            case .serverError:
                return L10n.text(language, en: "Claude API error (\(status)). Try again.", vi: "Lỗi Claude API (\(status)). Thử lại sau.")
            case .other:
                return message.isEmpty
                    ? L10n.text(language, en: "Request failed (\(status)).", vi: "Yêu cầu thất bại (\(status)).")
                    : message
            }
        case .refused:
            return L10n.text(language, en: "Claude declined to answer this request.", vi: "Claude từ chối trả lời yêu cầu này.")
        case .truncated:
            return L10n.text(language, en: "The reply was cut off. Try again.", vi: "Phản hồi bị cắt ngắn. Hãy thử lại.")
        case .malformedResponse(let detail):
            return detail
        case .network(let detail):
            return L10n.text(language, en: "Network problem: \(detail)", vi: "Lỗi mạng: \(detail)")
        }
    }
}

extension ClaudeError: LocalizedError {
    public var errorDescription: String? {
        localizedMessage(in: .english)
    }
}
