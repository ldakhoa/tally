import SwiftUI

// MARK: - Labels & Headings (Onsite components)

public struct Tag: View {
    public let text: String
    public var color: Color = .textSecondary

    public init(text: String, color: Color = .textSecondary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(.appCaption.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(isNeutral ? Color.textSecondary : color)
            .background(fill, in: Capsule())
    }

    private var isNeutral: Bool { color == .textSecondary || color == .secondary }
    private var fill: Color { isNeutral ? Color.textPrimary.opacity(0.07) : color.opacity(0.13) }
}

public struct SectionLabel: View {
    public let title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .font(.appLabel)
            .foregroundStyle(Color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

public struct SectionHeading: View {
    public let title: String
    public var actionLabel: String?
    public var action: (() -> Void)?

    public init(_ title: String) { self.title = title }

    public init(_ title: String, actionLabel: String, action: @escaping () -> Void) {
        self.title = title
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.appSection)
                .tracking(.sectionTracking)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let action, let actionLabel {
                Button(action: action) {
                    CozyUIIcon(.arrowRight, size: 15, color: Color.textPrimary)
                }
                .buttonStyle(IconButtonStyle(filled: true))
                .accessibilityLabel(actionLabel)
            }
        }
    }
}

public struct PageHeader: View {
    public let title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appTitle)
                .tracking(.titleTracking)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public func formSectionHeader(_ title: String) -> some View {
    SectionLabel(title).textCase(nil)
}

public func formSectionFooter(_ text: String) -> some View {
    Text(text)
        .font(.appCaption)
        .foregroundStyle(Color.textSecondary)
}

// MARK: - Cards & Icon Tiles

public struct Card<Content: View>: View {
    public var title: String?
    public var symbol: String?
    public var highlighted: Bool
    public let content: Content

    public init(_ title: String? = nil, symbol: String? = nil, highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.highlighted = highlighted
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    if let symbol {
                        if let cozy = CozyUIIconKind(sfSymbol: symbol) {
                            CozyUIIcon(cozy, size: 16, color: Color.textSecondary)
                        } else {
                            Image(systemName: symbol)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Text(title)
                        .font(.appHeading)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(highlighted: highlighted)
    }
}

public struct SettingsIconTile: View {
    public let symbol: String
    public var tint: Color?
    public var size: CGFloat
    public var glyphScale: CGFloat

    public init(symbol: String, tint: Color? = nil, size: CGFloat = 32, glyphScale: CGFloat = 0.5) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
        self.glyphScale = glyphScale
    }

    public var body: some View {
        if let cozy = CozyUIIconKind(sfSymbol: symbol) {
            CozySettingsStickerIcon(kind: cozy, size: size, tint: tint)
        } else {
            let iconColor = tint == nil ? Color.ink : Color.onAccent
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color.fieldBackground))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: size * glyphScale, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Progress Bar & Empty State

public struct TallyProgressBar: View {
    public let value: Double
    public var fill: Color

    @State private var animatedValue: Double = 0

    public init(value: Double, fill: Color = .positive) {
        self.value = value
        self.fill = fill
    }

    public var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, animatedValue))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.trackFill)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [fill.opacity(0.85), fill],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(clamped > 0 ? 10 : 0, proxy.size.width * clamped))
            }
        }
        .frame(height: 10)
        .onAppear {
            withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
                animatedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                animatedValue = newValue
            }
        }
    }
}

public struct EmptyStateCard: View {
    public let symbol: String
    public let title: String
    public let message: String
    public var actionTitle: String?
    public var action: (() -> Void)?

    public init(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 12) {
            CozyPetDuoView(mood: .sleepy, petSize: 54)
                .padding(.bottom, 2)
            Text(title)
                .font(.appHeading)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.appSecondary)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .pillButton(prominent: true)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }
}

// MARK: - Buttons (Onsite Ink Capsule + Soft Grey Rounded Rectangles)

public struct PillButtonStyle: ButtonStyle {
    public var prominent: Bool
    public var tint: Color?

    public init(prominent: Bool = false, tint: Color? = nil) {
        self.prominent = prominent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent, tint: tint)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    private var effectiveTint: Color? {
        tint ?? (configuration.role == .destructive ? .negative : nil)
    }

    private var foreground: Color {
        if prominent { return effectiveTint == nil ? .onInk : .onAccent }
        return effectiveTint ?? .textPrimary
    }

    private var fill: Color {
        if prominent { return effectiveTint ?? .ink }
        if let effectiveTint { return effectiveTint.opacity(0.12) }
        return .softFill
    }

    var body: some View {
        let shape = prominent ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        configuration.label
            .font(.appControl)
            .lineLimit(1)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    shape.fill(fill)
                    if configuration.isPressed {
                        shape.fill(prominent ? Color.onInk.opacity(0.18) : Color.rowSelection)
                    }
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.52), value: configuration.isPressed)
    }
}

public struct BlockButtonStyle: ButtonStyle {
    public var prominent: Bool
    public var tint: Color?

    public init(prominent: Bool = true, tint: Color? = nil) {
        self.prominent = prominent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        BlockButtonBody(configuration: configuration, prominent: prominent, tint: tint)
    }
}

private struct BlockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let tint: Color?

    @Environment(\.isEnabled) private var isEnabled

    private var effectiveTint: Color? {
        tint ?? (configuration.role == .destructive ? .negative : nil)
    }

    private var foreground: Color {
        if prominent { return effectiveTint == nil ? .onInk : .onAccent }
        return effectiveTint ?? .textPrimary
    }

    private var fill: Color {
        if prominent { return effectiveTint ?? .ink }
        if let effectiveTint { return effectiveTint.opacity(0.12) }
        return .softFill
    }

    var body: some View {
        let shape = prominent ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        configuration.label
            .font(.appControlLarge)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 16)
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    shape.fill(fill)
                    if configuration.isPressed {
                        shape.fill(prominent ? Color.onInk.opacity(0.18) : Color.rowSelection)
                    }
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

public struct IconButtonStyle: ButtonStyle {
    public var filled: Bool
    public init(filled: Bool = false) { self.filled = filled }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appControl)
            .themeForeground()
            .frame(width: 36, height: 36)
            .background {
                if filled {
                    Circle().fill(configuration.isPressed ? Color.rowSelection : Color.softFill)
                } else if configuration.isPressed {
                    Circle().fill(Color.rowSelection)
                }
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.50), value: configuration.isPressed)
    }
}

public struct ThemedPlainButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .themeForeground()
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension ButtonStyle where Self == ThemedPlainButtonStyle {
    public static var themedPlain: ThemedPlainButtonStyle { ThemedPlainButtonStyle() }
}

extension View {
    public func pillButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        buttonStyle(PillButtonStyle(prominent: prominent, tint: tint))
    }

    public func blockButton(prominent: Bool = true, tint: Color? = nil) -> some View {
        buttonStyle(BlockButtonStyle(prominent: prominent, tint: tint))
    }

    public func tallyField() -> some View {
        self
            .font(.appBody)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    }
}

// MARK: - ChipPicker (Onsite horizontal capsule selector)

public struct ChipPicker<Value: Hashable>: View {
    public let title: String
    @Binding public var selection: Value
    public let options: [Value]
    public let sideMargin: CGFloat
    public let label: (Value) -> String
    public let symbol: (Value) -> String?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        _ title: String,
        selection: Binding<Value>,
        options: [Value],
        sideMargin: CGFloat = 16,
        label: @escaping (Value) -> String,
        symbol: @escaping (Value) -> String? = { _ in nil }
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.sideMargin = sideMargin
        self.label = label
        self.symbol = symbol
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection
                    let floats = colorScheme == .light && !isSelected
                    Button {
                        CozyHaptics.selection()
                        CozySounds.play(.tick)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { selection = option }
                    } label: {
                        HStack(spacing: 6) {
                            if let sym = symbol(option) {
                                if let cozy = CozyUIIconKind(sfSymbol: sym) {
                                    CozyUIIcon(cozy, size: 14, color: isSelected ? Color.onInk : Color.textPrimary)
                                } else {
                                    Image(systemName: sym).imageScale(.small)
                                }
                            }
                            Text(label(option)).lineLimit(1)
                        }
                        .font(.appControl)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                        .background {
                            Capsule()
                                .fill(isSelected ? Color.ink : Color.cardBackground)
                                .floatingShadow(floats)
                        }
                        .overlay {
                            if !isSelected && !floats {
                                Capsule().strokeBorder(Color.hairlineStrong, lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.themedPlain)
                }
            }
            .padding(.horizontal, sideMargin)
            .padding(.vertical, 4)
        }
        .accessibilityLabel(title)
    }
}
