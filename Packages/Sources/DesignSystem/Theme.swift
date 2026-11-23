import BudgetKit
import SwiftUI
import ThemeTokens

private var current: ResolvedThemeTokens { ThemeRuntime.shared.tokens }

// MARK: - Colors (Onsite Design Language)

extension Color {
    public static var ink: Color { current.colors.ink }
    public static var onInk: Color { current.colors.onInk }
    public static var accent: Color { current.colors.accent }
    public static var onAccent: Color { current.colors.onAccent }
    public static var live: Color { accent }
    public static var textPrimary: Color { current.colors.text }
    public static var textSecondary: Color { current.colors.textSecondary }
    public static var positive: Color { current.colors.positive }
    public static var caution: Color { current.colors.caution }
    public static var negative: Color { current.colors.negative }
    public static var info: Color { current.colors.info }
    public static var appBackground: Color { current.colors.page }
    public static var cardBackground: Color { current.colors.card }
    public static var editorBackground: Color { current.colors.editor }
    public static var hairline: Color { current.colors.hairline }
    public static var hairlineStrong: Color { current.colors.hairlineStrong }
    public static var separatorLine: Color { hairline }
    public static var fieldBackground: Color { current.colors.field }
    public static var rowSelection: Color { current.colors.rowSelection }
    public static var rowHover: Color { current.colors.rowHover }
    public static var softFill: Color { Color.textPrimary.opacity(0.065) }
    public static var trackFill: Color { textSecondary.opacity(0.2) }

    public init(hex: UInt32, alpha: Double = 1.0) {
        let c = ThemeColor(hex, alpha: alpha)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

extension CategoryID {
    public var color: Color { Color(hex: accentHex) }
    public var tintBackground: Color { color.opacity(0.14) }
}

extension GoalIcon {
    public var color: Color { Color(hex: accentHex) }
    public var tintBackground: Color { color.opacity(0.14) }
}

// MARK: - Typography (Avenir Next from Tally Web, scaled for Dynamic Type)

extension Font {
    public static var appDisplay: Font {
        .custom("AvenirNext-DemiBold", size: 32, relativeTo: .largeTitle)
    }

    public static var appTitle: Font {
        .custom("AvenirNext-DemiBold", size: 26, relativeTo: .title)
    }

    public static var appSection: Font {
        .custom("AvenirNext-DemiBold", size: 20, relativeTo: .title2)
    }

    public static var appHeading: Font {
        .custom("AvenirNext-DemiBold", size: 16.5, relativeTo: .headline)
    }

    public static var appBody: Font {
        .custom("AvenirNext-Regular", size: 16, relativeTo: .body)
    }

    public static var appBodyMedium: Font {
        .custom("AvenirNext-Medium", size: 16, relativeTo: .body)
    }

    public static var appSecondary: Font {
        .custom("AvenirNext-Regular", size: 14.5, relativeTo: .subheadline)
    }

    public static var appControl: Font {
        .custom("AvenirNext-Medium", size: 14.5, relativeTo: .subheadline)
    }

    public static var appControlLarge: Font {
        .custom("AvenirNext-DemiBold", size: 16, relativeTo: .body)
    }

    public static var appCaption: Font {
        .custom("AvenirNext-Regular", size: 12.5, relativeTo: .caption)
    }

    public static var appLabel: Font {
        .custom("AvenirNext-DemiBold", size: 12.5, relativeTo: .footnote)
    }

    public static var appMetric: Font {
        .custom("AvenirNext-DemiBold", size: 22, relativeTo: .title2).monospacedDigit()
    }

    public static var appMetricHero: Font {
        .custom("AvenirNext-DemiBold", size: 30, relativeTo: .largeTitle).monospacedDigit()
    }

    public static var appAmount: Font {
        .custom("AvenirNext-DemiBold", size: 15.5, relativeTo: .body).monospacedDigit()
    }
}

extension CGFloat {
    public static let titleTracking: CGFloat = -0.5
    public static let sectionTracking: CGFloat = -0.35
    public static let lineSpacing: CGFloat = 2.0
}

// MARK: - Radii & Surfaces (Onsite iOS look: floating 24pt cards in light mode, hairline in dark)

public enum Radius {
    public static let card: CGFloat = 24
    public static let panel: CGFloat = 16
    public static let field: CGFloat = 12
    public static let row: CGFloat = 10
    public static let control: CGFloat = 12
}

extension View {
    public func appTint() -> some View {
        modifier(ThemeRoot())
    }

    public func themeForeground() -> some View {
        foregroundStyle(Color.textPrimary)
    }

    public func cardSurface(cornerRadius: CGFloat = Radius.card, highlighted: Bool = false) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius, highlighted: highlighted))
    }

    public func floatingShadow(_ isOn: Bool = true) -> some View {
        shadow(color: .black.opacity(isOn ? 0.065 : 0), radius: 10, y: 4)
            .shadow(color: .black.opacity(isOn ? 0.035 : 0), radius: 1, y: 0.5)
    }

    public func documentColumn(maxWidth: CGFloat = 760) -> some View {
        modifier(DocumentColumnPadding())
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    public func pageBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }
}

private struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let highlighted: Bool

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let floats = colorScheme == .light && !highlighted

        content
            .background {
                shape.fill(Color.cardBackground)
                    .floatingShadow(floats)
            }
            .overlay {
                if highlighted {
                    shape.strokeBorder(Color.ink, lineWidth: 1.5)
                } else if !floats {
                    shape.strokeBorder(Color.hairline, lineWidth: 1)
                }
            }
    }
}

private struct DocumentColumnPadding: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
            .padding(.vertical, 16)
        #else
        content
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        #endif
    }
}
