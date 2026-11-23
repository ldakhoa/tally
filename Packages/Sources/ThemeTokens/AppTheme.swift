import Foundation
import TallyCore

/// The app's themes, matching Onsite's design language: Ink & Vermilion (default), Rosé Pine,
/// and Rosé Pine Moon.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case ink
    case rosePine
    case rosePineMoon

    public static let standard: AppTheme = .ink

    public var id: String { rawValue }

    public init(storedName: String?) {
        self = storedName.flatMap(AppTheme.init(rawValue:)) ?? .standard
    }

    public var title: String {
        switch self {
        case .ink: return "Ink & Vermilion"
        case .rosePine: return "Rosé Pine"
        case .rosePineMoon: return "Rosé Pine Moon"
        }
    }

    public func summary(in language: AppLanguage) -> String {
        switch self {
        case .ink:
            return L10n.text(language, en: "Warm ink on cream, with a vermilion accent", vi: "Mực ấm trên nền kem, nhấn đỏ son")
        case .rosePine:
            return L10n.text(language, en: "Rosé Pine Dawn in light, Rosé Pine in dark", vi: "Rosé Pine Dawn khi sáng, Rosé Pine khi tối")
        case .rosePineMoon:
            return L10n.text(language, en: "Rosé Pine Dawn in light, Rosé Pine Moon in dark", vi: "Rosé Pine Dawn khi sáng, Rosé Pine Moon khi tối")
        }
    }

    public static func choices(dark: Bool) -> [AppTheme] {
        dark ? allCases : [.ink, .rosePine]
    }

    public func choiceTitle(dark: Bool) -> String {
        !dark && self == .rosePine ? "Rosé Pine Dawn" : title
    }

    public func isChoice(_ choice: AppTheme, dark: Bool) -> Bool {
        AppTheme.choices(dark: dark).contains(self) ? self == choice : choice == .rosePine
    }

    public func choosing(_ choice: AppTheme, dark: Bool) -> AppTheme {
        isChoice(choice, dark: dark) ? self : choice
    }

    public var usesSystemSemanticColors: Bool { self == .ink }

    public func palette(dark: Bool) -> ThemePalette {
        switch self {
        case .ink: return dark ? .inkDark : .inkLight
        case .rosePine: return dark ? .rosePine(RosePine.main, dark: true) : .rosePine(RosePine.dawn, dark: false)
        case .rosePineMoon: return dark ? .rosePine(RosePine.moon, dark: true) : .rosePine(RosePine.dawn, dark: false)
        }
    }
}

/// Light or dark appearance per device (never synced).
public enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public init(storedName: String?) {
        self = storedName.flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .system: return L10n.text(language, en: "System", vi: "Theo máy")
        case .light: return L10n.text(language, en: "Light", vi: "Sáng")
        case .dark: return L10n.text(language, en: "Dark", vi: "Tối")
        }
    }
}

public struct ThemeColor: Hashable, Sendable {
    public var rgb: UInt32
    public var alpha: Double

    public init(_ rgb: UInt32, alpha: Double = 1) {
        self.rgb = rgb & 0xFFFFFF
        self.alpha = min(max(alpha, 0), 1)
    }

    public var red: Double { Double((rgb >> 16) & 0xFF) / 255 }
    public var green: Double { Double((rgb >> 8) & 0xFF) / 255 }
    public var blue: Double { Double(rgb & 0xFF) / 255 }

    public var hex: String { String(format: "#%06X", rgb) }

    public func withAlpha(_ alpha: Double) -> ThemeColor {
        ThemeColor(rgb, alpha: alpha)
    }

    public func over(_ background: ThemeColor) -> ThemeColor {
        guard alpha < 1 else { return self }
        func mix(_ top: Double, _ bottom: Double) -> UInt32 {
            UInt32((top * alpha + bottom * (1 - alpha)) * 255 + 0.5)
        }
        return ThemeColor(mix(red, background.red) << 16 | mix(green, background.green) << 8 | mix(blue, background.blue))
    }

    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public static func contrast(_ foreground: ThemeColor, on background: ThemeColor) -> Double {
        let top = foreground.over(background).relativeLuminance
        let bottom = background.relativeLuminance
        return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
    }
}

public struct IOSSurfaces: Hashable, Sendable {
    public var page: ThemeColor
    public var card: ThemeColor
    public var editor: ThemeColor

    public init(page: ThemeColor, card: ThemeColor, editor: ThemeColor) {
        self.page = page
        self.card = card
        self.editor = editor
    }
}

public struct ThemeVeils: Hashable, Sendable {
    public var base: ThemeColor
    public var hairline: Double
    public var hairlineStrong: Double
    public var field: Double
    public var rowSelection: Double
    public var rowHover: Double

    public init(base: ThemeColor, hairline: Double, hairlineStrong: Double, field: Double, rowSelection: Double, rowHover: Double) {
        self.base = base
        self.hairline = hairline
        self.hairlineStrong = hairlineStrong
        self.field = field
        self.rowSelection = rowSelection
        self.rowHover = rowHover
    }
}

public struct ThemePalette: Hashable, Sendable {
    public var ink: ThemeColor
    public var onInk: ThemeColor
    public var accent: ThemeColor
    public var onAccent: ThemeColor
    public var text: ThemeColor
    public var textSecondary: ThemeColor
    public var ios: IOSSurfaces
    public var veils: ThemeVeils
    public var positive: ThemeColor
    public var caution: ThemeColor
    public var negative: ThemeColor
    public var info: ThemeColor

    public init(
        ink: ThemeColor, onInk: ThemeColor, accent: ThemeColor, onAccent: ThemeColor,
        text: ThemeColor, textSecondary: ThemeColor, ios: IOSSurfaces, veils: ThemeVeils,
        positive: ThemeColor, caution: ThemeColor, negative: ThemeColor, info: ThemeColor
    ) {
        self.ink = ink
        self.onInk = onInk
        self.accent = accent
        self.onAccent = onAccent
        self.text = text
        self.textSecondary = textSecondary
        self.ios = ios
        self.veils = veils
        self.positive = positive
        self.caution = caution
        self.negative = negative
        self.info = info
    }

    public var hairline: ThemeColor { veils.base.withAlpha(veils.hairline) }
    public var hairlineStrong: ThemeColor { veils.base.withAlpha(veils.hairlineStrong) }
    public var field: ThemeColor { veils.base.withAlpha(veils.field) }
    public var rowSelection: ThemeColor { veils.base.withAlpha(veils.rowSelection) }
    public var rowHover: ThemeColor { veils.base.withAlpha(veils.rowHover) }
}

extension ThemePalette {
    public static let inkLight = ThemePalette(
        ink: ThemeColor(0x171210),
        onInk: ThemeColor(0xFFFFFF),
        accent: ThemeColor(0xD2351F),
        onAccent: ThemeColor(0xFFFFFF),
        text: ThemeColor(0x171210),
        textSecondary: ThemeColor(0x171210, alpha: 0.6),
        ios: IOSSurfaces(page: ThemeColor(0xFAF7F1), card: ThemeColor(0xFFFDF8), editor: ThemeColor(0xF5F2EE)),
        veils: ThemeVeils(base: ThemeColor(0x171210), hairline: 0.10, hairlineStrong: 0.22, field: 0.045, rowSelection: 0.06, rowHover: 0.035),
        positive: ThemeColor(0x287A4B),
        caution: ThemeColor(0xD9820B),
        negative: ThemeColor(0xD2351F),
        info: ThemeColor(0x2C7F94)
    )

    public static let inkDark = ThemePalette(
        ink: ThemeColor(0xF7F3EC),
        onInk: ThemeColor(0x171210),
        accent: ThemeColor(0xE5533D),
        onAccent: ThemeColor(0xFFFFFF),
        text: ThemeColor(0xF7F3EC),
        textSecondary: ThemeColor(0xF7F3EC, alpha: 0.6),
        ios: IOSSurfaces(page: ThemeColor(0x141110), card: ThemeColor(0x1E1A17), editor: ThemeColor(0x2D2926)),
        veils: ThemeVeils(base: ThemeColor(0xF7F3EC), hairline: 0.10, hairlineStrong: 0.22, field: 0.07, rowSelection: 0.08, rowHover: 0.045),
        positive: ThemeColor(0x30D158),
        caution: ThemeColor(0xFF9F0A),
        negative: ThemeColor(0xFF453A),
        info: ThemeColor(0x40C8E0)
    )
}

public enum RosePine {
    public struct Variant: Hashable, Sendable {
        public var base, surface, overlay, muted, subtle, text: ThemeColor
        public var love, gold, rose, pine, foam, iris: ThemeColor
    }

    public static let main = Variant(
        base: ThemeColor(0x191724), surface: ThemeColor(0x1F1D2E), overlay: ThemeColor(0x26233A),
        muted: ThemeColor(0x6E6A86), subtle: ThemeColor(0x908CAA), text: ThemeColor(0xE0DEF4),
        love: ThemeColor(0xEB6F92), gold: ThemeColor(0xF6C177), rose: ThemeColor(0xEBBCBA),
        pine: ThemeColor(0x31748F), foam: ThemeColor(0x9CCFD8), iris: ThemeColor(0xC4A7E7)
    )

    public static let moon = Variant(
        base: ThemeColor(0x232136), surface: ThemeColor(0x2A273F), overlay: ThemeColor(0x393552),
        muted: ThemeColor(0x6E6A86), subtle: ThemeColor(0x908CAA), text: ThemeColor(0xE0DEF4),
        love: ThemeColor(0xEB6F92), gold: ThemeColor(0xF6C177), rose: ThemeColor(0xEA9A97),
        pine: ThemeColor(0x3E8FB0), foam: ThemeColor(0x9CCFD8), iris: ThemeColor(0xC4A7E7)
    )

    public static let dawn = Variant(
        base: ThemeColor(0xFAF4ED), surface: ThemeColor(0xFFFAF3), overlay: ThemeColor(0xF2E9E1),
        muted: ThemeColor(0x9893A5), subtle: ThemeColor(0x797593), text: ThemeColor(0x464261),
        love: ThemeColor(0xB4637A), gold: ThemeColor(0xEA9D34), rose: ThemeColor(0xD7827E),
        pine: ThemeColor(0x286983), foam: ThemeColor(0x56949F), iris: ThemeColor(0x907AA9)
    )
}

extension ThemePalette {
    static func rosePine(_ variant: RosePine.Variant, dark: Bool) -> ThemePalette {
        let defaults = dark ? ThemePalette.inkDark.veils : ThemePalette.inkLight.veils
        return ThemePalette(
            ink: variant.text,
            onInk: variant.base,
            accent: dark ? variant.rose : variant.love,
            onAccent: variant.base,
            text: variant.text,
            textSecondary: variant.subtle,
            ios: IOSSurfaces(page: variant.base, card: variant.surface, editor: variant.overlay),
            veils: ThemeVeils(
                base: variant.text, hairline: defaults.hairline, hairlineStrong: defaults.hairlineStrong,
                field: defaults.field, rowSelection: defaults.rowSelection, rowHover: defaults.rowHover
            ),
            positive: dark ? variant.foam : variant.pine,
            caution: variant.gold,
            negative: variant.love,
            info: variant.iris
        )
    }
}
