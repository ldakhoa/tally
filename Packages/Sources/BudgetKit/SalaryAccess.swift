import ClaudeKit
import Foundation
import TallyCore

/// The one route by which the model can ask to see salary-inclusive figures: a tool call that
/// shows a consent card in the chat. The app decides; the model only gets the outcome.
public enum SalaryAccessTool {
    public static let name = "request_salary_access"

    public static let tool = ClaudeTool(
        name: name,
        description: "Ask the user to unlock salary-inclusive figures (income, net, savings rate, debt-to-income) when a tool result says they are locked and your answer genuinely needs them. Shows a consent card in the chat and waits for the user's choice. At most once per user message.",
        inputSchema: .schemaObject([
            ("reason", .schemaString("One sentence, in the user's language, saying why the answer needs salary-inclusive figures.")),
        ], required: ["reason"])
    )

    /// Longest reason shown on the card.
    public static let maxReasonLength = 240

    /// The reason to show, or `nil` when the model sent none.
    public static func reason(from input: JSONValue) -> String? {
        guard let raw = input["reason"]?.stringValue else { return nil }
        let collapsed = raw.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > maxReasonLength ? String(collapsed.prefix(maxReasonLength - 1)) + "…" : collapsed
    }
}

/// What happened to one salary access request.
public enum SalaryAccessOutcome: String, Codable, Hashable, Sendable {
    /// The user allowed and the gate revealed salary (after authentication when required).
    case granted
    /// Salary was already visible, so nothing was asked.
    case alreadyVisible
    /// The user tapped Not now (or left the screen).
    case declined
    /// The user allowed but authentication failed or was cancelled.
    case authFailed
    /// The reply was stopped while the card was waiting.
    case cancelled
    /// A second request in the same user message: refused without asking.
    case alreadyRequested
    /// No chat screen can show the card (e.g. Siri).
    case unavailable
    /// The model sent no reason.
    case invalid

    public var isGranted: Bool { self == .granted || self == .alreadyVisible }

    /// Tool result for the model. Fixed protocol text (not advice), so the model's next step does
    /// not depend on guessing what happened.
    public var toolResult: String {
        let withoutIncome = "Do not estimate, infer or back-calculate salary or income from other figures. Offer only what you can do without income, such as spending, budget and debt analysis, and do not call request_salary_access again in this message."
        switch self {
        case .granted:
            return "granted: the user unlocked salary figures. Call the figure tools again to get the salary-inclusive numbers, then continue your answer."
        case .alreadyVisible:
            return "granted: salary figures are already visible. Call the figure tools again if you need them, then continue your answer."
        case .declined:
            return "declined: the user chose not to share salary figures. " + withoutIncome
        case .authFailed:
            return "declined: authentication failed or was cancelled, so salary stays hidden. " + withoutIncome
        case .cancelled:
            return "declined: the request was dismissed. " + withoutIncome
        case .alreadyRequested:
            return "declined: salary access was already requested in this message. " + withoutIncome
        case .unavailable:
            return "declined: salary access cannot be requested here; the user can show salary with the eye button in the app. " + withoutIncome
        case .invalid:
            return "Error: reason is required (one sentence saying why salary-inclusive figures are needed)."
        }
    }

    public var isError: Bool { self == .invalid }
}

/// The consent card as kept in chat history: what was asked and how it ended. Never holds a
/// salary figure.
public struct SalaryConsentRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case pending
        case allowed
        case declined
        case authFailed
        case cancelled
    }

    public let id: UUID
    public let reason: String
    public var status: Status
    public let askedAt: Date

    public init(id: UUID = UUID(), reason: String, status: Status = .pending, askedAt: Date = Date()) {
        self.id = id
        self.reason = reason
        self.status = status
        self.askedAt = askedAt
    }

    public static func status(for outcome: SalaryAccessOutcome) -> Status {
        switch outcome {
        case .granted, .alreadyVisible: return .allowed
        case .declined, .alreadyRequested, .unavailable, .invalid: return .declined
        case .authFailed: return .authFailed
        case .cancelled: return .cancelled
        }
    }

    /// Card headline once decided (or while waiting).
    public func title(in language: AppLanguage) -> String {
        switch status {
        case .pending:
            return L10n.text(language, en: "Tally would like to use your salary figures", vi: "Tally muốn dùng số liệu lương của bạn", zh: "Tally 想使用您的工资数据")
        case .allowed:
            return L10n.text(language, en: "Salary figures allowed", vi: "Đã cho phép dùng số liệu lương", zh: "已允许使用工资数据")
        case .declined:
            return L10n.text(language, en: "Salary figures not shared", vi: "Không chia sẻ số liệu lương", zh: "未共享工资数据")
        case .authFailed:
            return L10n.text(language, en: "Authentication failed — salary stays hidden", vi: "Xác thực không thành công — lương vẫn được ẩn", zh: "身份验证未通过——工资仍保持隐藏")
        case .cancelled:
            return L10n.text(language, en: "Request dismissed — salary stays hidden", vi: "Đã bỏ yêu cầu — lương vẫn được ẩn", zh: "请求已取消——工资仍保持隐藏")
        }
    }
}
