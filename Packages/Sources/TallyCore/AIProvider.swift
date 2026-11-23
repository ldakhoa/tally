import Foundation

/// User-selectable AI engine powering Ask Tally, bank alert parsing, and Siri natural-language logging.
public enum AIProvider: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case auto
    case appleIntelligence = "apple"
    case claude

    public var id: String { rawValue }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .auto:
            return L10n.text(language, en: "Auto (Recommended)", vi: "Tự động (Khuyên dùng)", zh: "自动（推荐）")
        case .appleIntelligence:
            return L10n.text(language, en: "Apple Intelligence", vi: "Apple Intelligence", zh: "Apple 智能")
        case .claude:
            return "Claude (Anthropic)"
        }
    }

    public func shortTitle(in language: AppLanguage) -> String {
        switch self {
        case .auto:
            return L10n.text(language, en: "Auto", vi: "Tự động", zh: "自动")
        case .appleIntelligence:
            return L10n.text(language, en: "Apple Intelligence", vi: "Apple Intelligence", zh: "Apple 智能")
        case .claude:
            return "Claude"
        }
    }

    public func summary(in language: AppLanguage) -> String {
        switch self {
        case .auto:
            return L10n.text(
                language,
                en: "Uses on-device Apple Intelligence for fast Siri & alert parsing, and Claude for deep chat when configured.",
                vi: "Dùng Apple Intelligence trên máy cho Siri & đọc thông báo nhanh, và Claude cho chat chuyên sâu nếu có API key.",
                zh: "Siri 与通知解析优先使用本地 Apple 智能，配置密钥后深度对话使用 Claude。"
            )
        case .appleIntelligence:
            return L10n.text(
                language,
                en: "100% on-device, free, private, and works offline. Requires Apple Intelligence enabled on iOS.",
                vi: "Chạy hoàn toàn trên máy, miễn phí, riêng tư và offline. Cần bật Apple Intelligence trên iOS.",
                zh: "100% 本地运行，免费、隐私且支持离线。需要在 iOS 上开启 Apple 智能。"
            )
        case .claude:
            return L10n.text(
                language,
                en: "Uses Anthropic Claude API for all chat, Siri, and parsing. Best for complex multi-item analysis.",
                vi: "Dùng Anthropic Claude API cho mọi tác vụ chat, Siri và phân tích. Tốt nhất cho phân tích sâu.",
                zh: "全部对话、Siri 与解析均使用 Anthropic Claude API，适合复杂分析。"
            )
        }
    }
}

/// Purpose of an AI request so `.auto` mode can pick the optimal backend.
public enum AIRequestPurpose: Hashable, Sendable {
    case parsing
    case siri
    case assistantChat
}

/// Concrete backend selected at runtime.
public enum ResolvedAIBackend: String, Hashable, Sendable {
    case appleIntelligence
    case claude
}
