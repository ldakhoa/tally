import Foundation

/// App language preference: System, English, Tiếng Việt, or 中文 (Simplified Chinese).
/// Drives both the entire UI and Claude's reply language.
public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case system
    case english = "en"
    case vietnamese = "vi"
    case chinese = "zh"

    public var id: String { rawValue }

    public enum Resolved: String, Hashable, Sendable {
        case english = "en"
        case vietnamese = "vi"
        case chinese = "zh"
    }

    public var resolved: Resolved {
        switch self {
        case .english: return .english
        case .vietnamese: return .vietnamese
        case .chinese: return .chinese
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            if preferred.hasPrefix("vi") { return .vietnamese }
            if preferred.hasPrefix("zh") { return .chinese }
            return .english
        }
    }

    public var locale: Locale {
        switch resolved {
        case .english: return Locale(identifier: "en_SG")
        case .vietnamese: return Locale(identifier: "vi_VN")
        case .chinese: return Locale(identifier: "zh_CN")
        }
    }

    public func title(in current: AppLanguage) -> String {
        switch self {
        case .system: return L10n.text(current, en: "System", vi: "Theo máy", zh: "跟随系统")
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        case .chinese: return "中文"
        }
    }

    public var aiInstruction: String {
        switch resolved {
        case .english:
            return "Reply in natural, concise English."
        case .vietnamese:
            return "Trả lời bằng tiếng Việt tự nhiên, ngắn gọn, dễ hiểu."
        case .chinese:
            return "请用自然、简洁的简体中文回复。"
        }
    }
}

/// Lightweight trilingual helper (English, Vietnamese, Simplified Chinese) usable from every
/// module without SwiftUI or Bundle dependency.
public enum L10n {
    public static func text(_ language: AppLanguage, en: String, vi: String, zh: String) -> String {
        switch language.resolved {
        case .english: return en
        case .vietnamese: return vi
        case .chinese: return zh
        }
    }

    public static func today(_ language: AppLanguage) -> String {
        text(language, en: "Today", vi: "Hôm nay", zh: "今天")
    }

    public static func yesterday(_ language: AppLanguage) -> String {
        text(language, en: "Yesterday", vi: "Hôm qua", zh: "昨天")
    }

    public static func tomorrow(_ language: AppLanguage) -> String {
        text(language, en: "Tomorrow", vi: "Ngày mai", zh: "明天")
    }
}
