import Observation
import SwiftUI
import ThemeTokens

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformColor = UIColor
#endif

func dynamicColor(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
    #if os(macOS)
    return NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
    #else
    return UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
    }
    #endif
}

public func platformColor(_ color: ThemeColor) -> PlatformColor {
    #if os(macOS)
    return NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    #else
    return UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    #endif
}

public struct ResolvedThemeTokens {
    public let theme: AppTheme
    public let accent: PlatformColor
    public let text: PlatformColor
    public let page: PlatformColor
    public let colors: Colors

    public struct Colors {
        public let ink, onInk, accent, onAccent, text, textSecondary: Color
        public let page, card, editor, sidebar: Color
        public let hairline, hairlineStrong, field, rowSelection, rowHover: Color
        public let positive, caution, negative, info: Color
    }

    public init(theme: AppTheme) {
        self.theme = theme
        let light = theme.palette(dark: false)
        let dark = theme.palette(dark: true)
        func pair(_ value: (ThemePalette) -> ThemeColor) -> PlatformColor {
            dynamicColor(light: platformColor(value(light)), dark: platformColor(value(dark)))
        }
        func toColor(_ native: PlatformColor) -> Color {
            #if os(macOS)
            Color(nsColor: native)
            #else
            Color(uiColor: native)
            #endif
        }

        let ink = pair(\.ink)
        let onInk = pair(\.onInk)
        let accent = pair(\.accent)
        let onAccent = pair(\.onAccent)
        let text = pair(\.text)
        let textSecondary = pair(\.textSecondary)
        let page = pair(\.ios.page)
        let card = pair(\.ios.card)
        let editor = pair(\.ios.editor)
        let sidebar = dynamicColor(light: platformColor(light.ios.editor), dark: platformColor(dark.ios.card))
        let hairline = pair(\.hairline)
        let hairlineStrong = pair(\.hairlineStrong)
        let field = pair(\.field)
        let rowSelection = pair(\.rowSelection)
        let rowHover = pair(\.rowHover)
        let positive = pair(\.positive)
        let caution = pair(\.caution)
        let negative = pair(\.negative)
        let info = pair(\.info)

        self.accent = accent
        self.text = text
        self.page = page
        self.colors = Colors(
            ink: toColor(ink), onInk: toColor(onInk), accent: toColor(accent), onAccent: toColor(onAccent),
            text: toColor(text), textSecondary: toColor(textSecondary),
            page: toColor(page), card: toColor(card), editor: toColor(editor), sidebar: toColor(sidebar),
            hairline: toColor(hairline), hairlineStrong: toColor(hairlineStrong), field: toColor(field),
            rowSelection: toColor(rowSelection), rowHover: toColor(rowHover),
            positive: toColor(positive), caution: toColor(caution), negative: toColor(negative), info: toColor(info)
        )
    }
}

/// Live theme switching runtime, matching Onsite's zero-rebuild ThemeRuntime pattern.
@Observable
public final class ThemeRuntime {
    public static let shared = ThemeRuntime()

    public private(set) var theme: AppTheme = .standard
    public private(set) var appearance: AppAppearance = .system

    @ObservationIgnored private let all: [AppTheme: ResolvedThemeTokens]
    @ObservationIgnored private var hasApplied = false

    private init() {
        var map: [AppTheme: ResolvedThemeTokens] = [:]
        for item in AppTheme.allCases {
            map[item] = ResolvedThemeTokens(theme: item)
        }
        self.all = map
    }

    public var tokens: ResolvedThemeTokens { tokens(for: theme) }

    public func tokens(for theme: AppTheme) -> ResolvedThemeTokens {
        all[theme] ?? all[.standard]!
    }

    public func update(theme: AppTheme, appearance: AppAppearance) {
        let apply = { [self] in
            let themeChanged = theme != self.theme
            let appearanceChanged = appearance != self.appearance || !hasApplied
            guard themeChanged || appearanceChanged else { return }
            if themeChanged { self.theme = theme }
            if appearanceChanged { self.appearance = appearance }
            MainActor.assumeIsolated { applyToWindows() }
            hasApplied = true
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    #if os(macOS)
    @MainActor
    public func applyToWindows() {
        switch appearance {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        let page = tokens.page
        for window in NSApplication.shared.windows {
            window.backgroundColor = page
        }
    }
    #else
    @MainActor
    public func applyToWindows() {
        let style: UIUserInterfaceStyle
        switch appearance {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        let tint = tokens.accent
        let text = tokens.text
        let navTitleFont = Self.roundedFont(size: 17, weight: .bold)
        let largeTitleBase = Self.roundedFont(size: 32, weight: .bold)
        let largeTitleFont = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: largeTitleBase)

        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: text, .font: navTitleFont]
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: text, .font: largeTitleFont]
        UITabBar.appearance().unselectedItemTintColor = text
        UISearchTextField.appearance().textColor = text

        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                if window.overrideUserInterfaceStyle != style { window.overrideUserInterfaceStyle = style }
                window.tintColor = tint
                Self.applyText(text, navTitleFont: navTitleFont, largeTitleFont: largeTitleFont, toBarsIn: window)
            }
        }
    }

    @MainActor
    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    @MainActor
    private static func applyText(_ text: UIColor, navTitleFont: UIFont, largeTitleFont: UIFont, toBarsIn view: UIView) {
        if let bar = view as? UINavigationBar {
            bar.titleTextAttributes = [.foregroundColor: text, .font: navTitleFont]
            bar.largeTitleTextAttributes = [.foregroundColor: text, .font: largeTitleFont]
        } else if let field = view as? UISearchTextField {
            field.textColor = text
        } else if let bar = view as? UITabBar {
            bar.unselectedItemTintColor = text
        }
        for subview in view.subviews {
            applyText(text, navTitleFont: navTitleFont, largeTitleFont: largeTitleFont, toBarsIn: subview)
        }
    }
    #endif
}

struct ThemeRoot: ViewModifier {
    func body(content: Content) -> some View {
        let colors = ThemeRuntime.shared.tokens.colors
        content
            .tint(colors.accent)
            .foregroundStyle(colors.text)
            .lineSpacing(.lineSpacing)
            .onAppear { ThemeRuntime.shared.applyToWindows() }
    }
}
