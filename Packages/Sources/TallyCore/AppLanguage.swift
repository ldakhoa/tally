import Foundation

/// App language preference: System, English, or Tiếng Việt.
/// Drives both the entire UI and Claude's reply language.
public enum AppLanguage: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case system
    case english = "en"
    case vietnamese = "vi"

    public var id: String { rawValue }

    public enum Resolved: String, Hashable, Sendable {
        case english = "en"
        case vietnamese = "vi"
    }

    public var resolved: Resolved {
        switch self {
        case .english: return .english
        case .vietnamese: return .vietnamese
        case .system:
            let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
            return preferred.hasPrefix("vi") ? .vietnamese : .english
        }
    }

    public var locale: Locale {
        switch resolved {
        case .english: return Locale(identifier: "en_SG")
        case .vietnamese: return Locale(identifier: "vi_VN")
        }
    }

    public func title(in current: AppLanguage) -> String {
        switch self {
        case .system: return L10n.text(current, en: "System", vi: "Theo máy")
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    public var aiInstruction: String {
        switch resolved {
        case .english:
            return "Reply in natural, concise English."
        case .vietnamese:
            return "Trả lời bằng tiếng Việt tự nhiên, ngắn gọn, dễ hiểu."
        }
    }
}

/// Lightweight bilingual helper (English & Vietnamese) usable from every module without
/// SwiftUI or Bundle dependency.
public enum L10n {
    public static func text(_ language: AppLanguage, en: String, vi: String) -> String {
        language.resolved == .vietnamese ? vi : en
    }

    public static func today(_ language: AppLanguage) -> String {
        text(language, en: "Today", vi: "Hôm nay")
    }

    public static func yesterday(_ language: AppLanguage) -> String {
        text(language, en: "Yesterday", vi: "Hôm qua")
    }

    public static func tomorrow(_ language: AppLanguage) -> String {
        text(language, en: "Tomorrow", vi: "Ngày mai")
    }
}
