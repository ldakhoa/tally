import BudgetKit
import Observation
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
    public static var sidebarBackground: Color { current.colors.sidebar }
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

// MARK: - Typography (Cozy SF Pro Rounded, scaled for Dynamic Type)

extension Font {
    public static var appDisplay: Font {
        .system(size: 32, weight: .bold, design: .rounded)
    }

    public static var appTitle: Font {
        .system(size: 26, weight: .bold, design: .rounded)
    }

    public static var appSection: Font {
        .system(size: 20, weight: .bold, design: .rounded)
    }

    public static var appHeading: Font {
        .system(size: 16.5, weight: .semibold, design: .rounded)
    }

    public static var appBody: Font {
        .system(size: 16, weight: .regular, design: .rounded)
    }

    public static var appBodyMedium: Font {
        .system(size: 16, weight: .medium, design: .rounded)
    }

    public static var appSecondary: Font {
        .system(size: 14.5, weight: .regular, design: .rounded)
    }

    public static var appControl: Font {
        .system(size: 14.5, weight: .semibold, design: .rounded)
    }

    public static var appControlLarge: Font {
        .system(size: 16, weight: .bold, design: .rounded)
    }

    public static var appCaption: Font {
        .system(size: 12.5, weight: .medium, design: .rounded)
    }

    public static var appLabel: Font {
        .system(size: 12.5, weight: .bold, design: .rounded)
    }

    public static var appMetric: Font {
        .system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
    }

    public static var appMetricHero: Font {
        .system(size: 32, weight: .heavy, design: .rounded).monospacedDigit()
    }

    public static var appAmount: Font {
        .system(size: 15.5, weight: .bold, design: .rounded).monospacedDigit()
    }
}

extension CGFloat {
    public static let titleTracking: CGFloat = 0.0
    public static let sectionTracking: CGFloat = 0.0
    public static let lineSpacing: CGFloat = 2.5
}

// MARK: - Radii & Surfaces (Cozy plush cards with warm honey shadows)

public enum Radius {
    public static let card: CGFloat = 26
    public static let panel: CGFloat = 18
    public static let field: CGFloat = 14
    public static let row: CGFloat = 12
    public static let control: CGFloat = 14
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
        shadow(color: Color(hex: 0x6B4423, alpha: isOn ? 0.08 : 0), radius: 8, y: 3)
    }

    public func documentColumn(maxWidth: CGFloat = 760) -> some View {
        modifier(DocumentColumnPadding())
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    public func pageBackground() -> some View {
        background(Color.appBackground.ignoresSafeArea())
    }

    /// Gives sheets a comfortable native window size on macOS while keeping iOS/iPadOS sheet sizing unchanged.
    @ViewBuilder
    public func cozySheetFrame(
        minWidth: CGFloat = 460,
        idealWidth: CGFloat = 520,
        minHeight: CGFloat = 520,
        idealHeight: CGFloat = 620
    ) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: idealWidth, minHeight: minHeight, idealHeight: idealHeight)
        #else
        self
        #endif
    }

    /// Styles Settings `Form` views consistently across iOS/iPadOS and macOS grouped cards.
    @ViewBuilder
    public func cozyGroupedForm() -> some View {
        #if os(macOS)
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .pageBackground()
        #else
        scrollContentBackground(.hidden)
            .pageBackground()
        #endif
    }

    /// Reads the live viewport width of a container (such as a `ScrollView`) for adaptive wide layouts.
    public func readViewportWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ViewportWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(ViewportWidthKey.self) { newWidth in
            if abs(width.wrappedValue - newWidth) > 1 {
                width.wrappedValue = newWidth
            }
        }
    }
}

private struct ViewportWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
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

private struct TabBarBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

@MainActor
@Observable
public final class TabBarVisibility {
    public private(set) var hiddenTabs: Set<String> = []

    public init() {}

    public func setHidden(_ hidden: Bool, for tabID: String) {
        if hidden {
            if !hiddenTabs.contains(tabID) {
                hiddenTabs.insert(tabID)
            }
        } else {
            if hiddenTabs.contains(tabID) {
                hiddenTabs.remove(tabID)
            }
        }
    }

    public func isHidden(for tabID: String) -> Bool {
        hiddenTabs.contains(tabID)
    }
}

private struct TabBarVisibilityKey: EnvironmentKey {
    static let defaultValue: TabBarVisibility? = nil
}

extension EnvironmentValues {
    public var tabBarBottomInset: CGFloat {
        get { self[TabBarBottomInsetKey.self] }
        set { self[TabBarBottomInsetKey.self] = newValue }
    }

    public var tabBarVisibility: TabBarVisibility? {
        get { self[TabBarVisibilityKey.self] }
        set { self[TabBarVisibilityKey.self] = newValue }
    }
}

private struct DocumentColumnPadding: ViewModifier {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.tabBarBottomInset) private var tabBarBottomInset

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
            .padding(.top, 16)
            .padding(.bottom, 16 + tabBarBottomInset)
        #else
        content
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 16 + tabBarBottomInset)
        #endif
    }
}
