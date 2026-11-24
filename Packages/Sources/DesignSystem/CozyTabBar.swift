import SwiftUI

// MARK: - Cozy Hand-Crafted Tab Bar Icons

public enum CozyTabIconKind: Hashable, Sendable {
    case overview
    case transactions
    case statistics
    case budgets
    case settings
}

public struct CozyTabIconView: View {
    public let kind: CozyTabIconKind
    public let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(kind: CozyTabIconKind, isSelected: Bool) {
        self.kind = kind
        self.isSelected = isSelected
    }

    private var strokeColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color(hex: 0x653742) : Color(hex: 0x4E382F)
        }
        if colorScheme == .dark {
            switch kind {
            case .overview, .transactions, .statistics: return Color.textSecondary
            case .budgets, .settings: break
            }
        }
        return Color.textSecondary.opacity(0.75)
    }

    public var body: some View {
        Group {
            switch kind {
            case .overview:
                CozyCottageIcon(isSelected: isSelected, stroke: strokeColor)
            case .transactions:
                CozyJournalIcon(isSelected: isSelected, stroke: strokeColor)
            case .statistics:
                CozyBarsIcon(isSelected: isSelected, stroke: strokeColor)
            case .budgets:
                CozyPiggyBankIcon(isSelected: isSelected, stroke: strokeColor)
            case .settings:
                CozyBlossomIcon(isSelected: isSelected, stroke: strokeColor)
            }
        }
        .frame(width: 28, height: 28)
        .drawingGroup()
        .scaleEffect(isSelected ? 1.12 : 0.96)
        .offset(y: isSelected ? -1.5 : 0)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.72), value: isSelected)
    }
}

/// 1. Overview: Cozy little cottage with a pastel peach roof & tiny heart!
private struct CozyCottageIcon: View {
    let isSelected: Bool
    let stroke: Color

    var body: some View {
        ZStack {
            // Chimney
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isSelected ? Color(hex: 0xF5B959) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(stroke, lineWidth: 1.7)
                )
                .frame(width: 5, height: 8)
                .offset(x: 6.5, y: -6.5)

            // Cottage wall
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isSelected ? Color(hex: 0xFFF5E6) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(stroke, lineWidth: 1.8)
                )
                .frame(width: 19, height: 14)
                .offset(y: 4.5)

            // Cute rounded pitched roof
            CottageRoofShape()
                .fill(isSelected ? Color(hex: 0xF28B76) : Color.clear)
                .overlay(
                    CottageRoofShape()
                        .stroke(stroke, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 24, height: 12)
                .offset(y: -4.5)

            // Tiny heart doorway
            Image(systemName: "heart.fill")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(isSelected ? Color(hex: 0xE67360) : stroke.opacity(0.8))
                .offset(y: 5.5)
        }
    }
}

private struct CottageRoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 1),
            control: CGPoint(x: rect.width * 0.28, y: rect.minY + 3)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - 1, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.72, y: rect.minY + 3)
        )
        p.closeSubpath()
        return p
    }
}

/// 2. Transactions: Cozy diary / receipt notebook with a cheerful golden coin!
private struct CozyJournalIcon: View {
    let isSelected: Bool
    let stroke: Color

    var body: some View {
        ZStack {
            // Soft notebook page
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(isSelected ? Color(hex: 0xFFF9F0) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                        .stroke(stroke, lineWidth: 1.8)
                )
                .frame(width: 18, height: 22)
                .offset(x: -2)

            // Cute pastel entry lines
            VStack(alignment: .leading, spacing: 3.5) {
                Capsule()
                    .fill(isSelected ? Color(hex: 0xE67360) : stroke.opacity(0.75))
                    .frame(width: 9.5, height: 2.2)
                Capsule()
                    .fill(isSelected ? Color(hex: 0x6EC492) : stroke.opacity(0.55))
                    .frame(width: 7.5, height: 2.2)
                Capsule()
                    .fill(isSelected ? Color(hex: 0xF5B959) : stroke.opacity(0.55))
                    .frame(width: 5.5, height: 2.2)
            }
            .offset(x: -3, y: -1)

            // Cute golden coin badge tucked in bottom-right
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: 0xFFD966) : Color.cardBackground)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(stroke, lineWidth: 1.6))
                Circle()
                    .fill(isSelected ? Color(hex: 0xE69524) : stroke.opacity(0.7))
                    .frame(width: 3, height: 3)
            }
            .offset(x: 7, y: 6.5)
        }
    }
}

/// 3. Statistics: Three chubby pastel rounded bars with a twinkling star!
private struct CozyBarsIcon: View {
    let isSelected: Bool
    let stroke: Color

    var body: some View {
        ZStack {
            HStack(alignment: .bottom, spacing: 3) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isSelected ? Color(hex: 0x8AD6AE) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(stroke, lineWidth: 1.7))
                    .frame(width: 6, height: 11)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isSelected ? Color(hex: 0xFFD972) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(stroke, lineWidth: 1.7))
                    .frame(width: 6, height: 18)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isSelected ? Color(hex: 0xF49A86) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).stroke(stroke, lineWidth: 1.7))
                    .frame(width: 6, height: 14)
            }
            .offset(y: 2.5)

            // Tiny cozy sparkle on top-left
            Image(systemName: "sparkle")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isSelected ? Color(hex: 0xF2A92C) : stroke.opacity(0.65))
                .offset(x: -8.5, y: -8.5)
        }
    }
}

/// 4. Budgets & Goals: Cute chubby pastel piggy bank with a golden coin on top!
private struct CozyPiggyBankIcon: View {
    let isSelected: Bool
    let stroke: Color

    var body: some View {
        ZStack {
            // Golden coin dropping into the piggy bank slot
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: 0xFFD966) : Color.clear)
                    .overlay(Circle().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
                if isSelected {
                    Circle()
                        .fill(Color(hex: 0xE69524))
                        .frame(width: 2.5, height: 2.5)
                }
            }
            .offset(y: -9.5)

            // Cute piggy ears
            HStack(spacing: 11) {
                Ellipse()
                    .fill(isSelected ? Color(hex: 0xF7B0B8) : Color.clear)
                    .overlay(Ellipse().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 5.5, height: 6.5)
                    .rotationEffect(.degrees(-22))
                Ellipse()
                    .fill(isSelected ? Color(hex: 0xF7B0B8) : Color.clear)
                    .overlay(Ellipse().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 5.5, height: 6.5)
                    .rotationEffect(.degrees(22))
            }
            .offset(y: -4.5)

            // Little feet
            HStack(spacing: 8) {
                Capsule()
                    .fill(isSelected ? Color(hex: 0xF5A4AE) : Color.clear)
                    .overlay(Capsule().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 4.5, height: 5)
                Capsule()
                    .fill(isSelected ? Color(hex: 0xF5A4AE) : Color.clear)
                    .overlay(Capsule().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 4.5, height: 5)
            }
            .offset(y: 9.5)

            // Chubby piggy body
            Ellipse()
                .fill(isSelected ? Color(hex: 0xFFD2D8) : Color.clear)
                .overlay(Ellipse().stroke(stroke, lineWidth: 1.8))
                .frame(width: 22, height: 16.5)
                .offset(y: 2)

            // Coin slot line on top
            Capsule()
                .fill(stroke)
                .frame(width: 6, height: 1.6)
                .offset(y: -3.5)

            // Cute piggy snout
            Ellipse()
                .fill(isSelected ? Color(hex: 0xF7A8B2) : Color.cardBackground)
                .overlay(Ellipse().stroke(stroke, lineWidth: 1.4))
                .frame(width: 8.5, height: 6)
                .overlay {
                    HStack(spacing: 2.2) {
                        Circle().fill(stroke).frame(width: 1.5, height: 1.5)
                        Circle().fill(stroke).frame(width: 1.5, height: 1.5)
                    }
                }
                .offset(y: 3.5)

            // Cute eyes
            HStack(spacing: 9.5) {
                Circle().fill(stroke).frame(width: 2.2, height: 2.2)
                Circle().fill(stroke).frame(width: 2.2, height: 2.2)
            }
            .offset(y: 0.5)
        }
    }
}

/// 5. Settings: Cozy 6-petal daisy blossom with a warm honey center!
private struct CozyBlossomIcon: View {
    let isSelected: Bool
    let stroke: Color

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { idx in
                Circle()
                    .fill(isSelected ? Color(hex: 0xFFF3E4) : Color.clear)
                    .overlay(Circle().stroke(stroke, lineWidth: 1.5))
                    .frame(width: 8.5, height: 8.5)
                    .offset(y: -6.2)
                    .rotationEffect(.degrees(Double(idx) * 60))
            }
            Circle()
                .fill(isSelected ? Color(hex: 0xFFD966) : Color.cardBackground)
                .frame(width: 9.5, height: 9.5)
                .overlay(Circle().stroke(stroke, lineWidth: 1.7))
        }
        .rotationEffect(.degrees(isSelected ? 30 : 0))
    }
}

// MARK: - Floating Icon-Only Cozy Tab Bar

public struct CozyTabBarItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let icon: CozyTabIconKind
    public let accessibilityLabel: String
    public let badgeCount: Int

    public init(id: ID, icon: CozyTabIconKind, accessibilityLabel: String, badgeCount: Int = 0) {
        self.id = id
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.badgeCount = badgeCount
    }
}

public struct CozyFloatingTabBar<ID: Hashable>: View {
    public let items: [CozyTabBarItem<ID>]
    @Binding public var selection: ID

    @State private var dragX: CGFloat? = nil
    @State private var dragStartSelection: ID? = nil
    @Environment(\.colorScheme) private var colorScheme

    public init(items: [CozyTabBarItem<ID>], selection: Binding<ID>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        let isDark = colorScheme == .dark
        let barTint: Color = isDark ? Color(hex: 0x2B221F, alpha: 0.78) : Color(hex: 0xFFFDF9, alpha: 0.72)
        let activePillFill: Color = isDark
            ? Color(hex: 0x4E3B34, alpha: dragX != nil ? 0.95 : 0.88)
            : Color(hex: 0xFFE9DB, alpha: dragX != nil ? 0.95 : 0.88)
        let badgeStrokeFill: Color = isDark ? Color(hex: 0x2B221F) : Color(hex: 0xFFFDF9)
        let specularBorder = LinearGradient(
            colors: isDark
                ? [Color.white.opacity(0.18), Color.white.opacity(0.05)]
                : [Color.white.opacity(0.85), Color(hex: 0xE67360, alpha: 0.22)],
            startPoint: .top,
            endPoint: .bottom
        )
        let pillSpecular = LinearGradient(
            colors: isDark
                ? [Color.white.opacity(0.24), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.9), Color(hex: 0xE67360, alpha: 0.16)],
            startPoint: .top,
            endPoint: .bottom
        )

        GeometryReader { geo in
            let horizontalInset: CGFloat = 8
            let innerWidth = max(0, geo.size.width - horizontalInset * 2)
            let count = max(1, items.count)
            let slotWidth = innerWidth / CGFloat(count)
            let selectedIndex = items.firstIndex(where: { $0.id == selection }) ?? 0
            let isDragging = dragX != nil
            let maxPillX = max(0, innerWidth - slotWidth)
            let pillX: CGFloat = {
                if let dragX {
                    return min(max(dragX - slotWidth * 0.5, 0), maxPillX)
                }
                return CGFloat(selectedIndex) * slotWidth
            }()

            ZStack(alignment: .leading) {
                // Pure-GPU sliding liquid-glass pill (zero layout passes)
                if slotWidth > 0 {
                    Capsule()
                        .fill(activePillFill)
                        .overlay {
                            if isDragging {
                                Capsule()
                                    .strokeBorder(pillSpecular, lineWidth: 1.2)
                            }
                        }
                        .frame(width: slotWidth, height: 44)
                        .scaleEffect(x: isDragging ? 1.07 : 1.0, y: isDragging ? 1.12 : 1.0)
                        .offset(x: pillX)
                        .animation(
                            isDragging
                                ? .interactiveSpring(response: 0.12, dampingFraction: 0.9)
                                : .interactiveSpring(response: 0.26, dampingFraction: 0.78),
                            value: pillX
                        )
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.72), value: isDragging)
                }

                // Icon row
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        let isSelected = selection == item.id
                        ZStack(alignment: .topTrailing) {
                            CozyTabIconView(kind: item.icon, isSelected: isSelected)

                            if item.badgeCount > 0 {
                                Text("\(min(item.badgeCount, 99))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.onAccent)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.accent, in: Capsule())
                                    .overlay(Capsule().strokeBorder(badgeStrokeFill, lineWidth: 1.5))
                                    .offset(x: 9, y: -6)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.accessibilityLabel)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction {
                            guard selection != item.id else {
                                CozyHaptics.light()
                                CozySounds.play(.tick)
                                return
                            }
                            CozyHaptics.selection()
                            CozySounds.play(.tick)
                            selection = item.id
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 6)
            .frame(width: geo.size.width, height: 60)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule()
                        .fill(barTint)
                        .shadow(color: Color(hex: 0x5A3F37, alpha: isDark ? 0.3 : 0.12), radius: 10, y: 4)
                }
            }
            .overlay {
                Capsule().strokeBorder(specularBorder, lineWidth: 1)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard slotWidth > 0 else { return }
                        if dragStartSelection == nil {
                            dragStartSelection = selection
                        }
                        let localX = min(max(value.location.x - horizontalInset, 0), innerWidth)
                        dragX = localX
                        let hoveredIndex = min(max(Int(localX / slotWidth), 0), items.count - 1)
                        let hoveredID = items[hoveredIndex].id
                        if hoveredID != selection {
                            CozyHaptics.selection()
                            CozySounds.play(.tick)
                            selection = hoveredID
                        }
                    }
                    .onEnded { value in
                        guard slotWidth > 0 else {
                            dragStartSelection = nil
                            dragX = nil
                            return
                        }
                        let localX = min(max(value.location.x - horizontalInset, 0), innerWidth)
                        let targetIndex = min(max(Int(localX / slotWidth), 0), items.count - 1)
                        let targetID = items[targetIndex].id
                        let wasTapOnCurrent = abs(value.translation.width) < 6 && dragStartSelection == targetID
                        if wasTapOnCurrent {
                            CozyHaptics.light()
                            CozySounds.play(.tick)
                        } else if selection != targetID {
                            CozyHaptics.selection()
                            CozySounds.play(.tick)
                            selection = targetID
                        }
                        dragStartSelection = nil
                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.78)) {
                            dragX = nil
                        }
                    }
            )
            .accessibilityElement(children: .contain)
        }
        .frame(height: 60)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}
