import BudgetKit
import SwiftUI

// MARK: - Shared Hand-Drawn Icon Style & Primitives

public enum CozyIconStyle: Sendable {
    /// Full Japanese watercolor pastel fills with warm cocoa ink outline (adapts to light/dark mode).
    case watercolor
    /// Clean hand-inked outline & soft fill tinted with a single color (ideal for dark pills or compact labels).
    case tinted(Color)
}

/// Shared hand-drawn four-point twinkling star shape with soft curved waists.
public struct CozyFourPointStarShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let rx = rect.width * 0.5
        let ry = rect.height * 0.5
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: cy), control: CGPoint(x: cx + rx * 0.16, y: cy - ry * 0.16))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.maxY), control: CGPoint(x: cx + rx * 0.16, y: cy + ry * 0.16))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: cy), control: CGPoint(x: cx - rx * 0.16, y: cy + ry * 0.16))
        p.addQuadCurve(to: CGPoint(x: cx, y: rect.minY), control: CGPoint(x: cx - rx * 0.16, y: cy - ry * 0.16))
        p.closeSubpath()
        return p
    }
}

/// Shared plump hand-drawn heart shape with soft curves.
public struct CozyHeartShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.92))
        p.addCurve(
            to: CGPoint(x: w * 0.06, y: h * 0.34),
            control1: CGPoint(x: w * 0.22, y: h * 0.72),
            control2: CGPoint(x: w * 0.04, y: h * 0.54)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.24),
            control1: CGPoint(x: w * 0.08, y: h * 0.08),
            control2: CGPoint(x: w * 0.42, y: h * 0.06)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.94, y: h * 0.34),
            control1: CGPoint(x: w * 0.58, y: h * 0.06),
            control2: CGPoint(x: w * 0.92, y: h * 0.08)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.92),
            control1: CGPoint(x: w * 0.96, y: h * 0.54),
            control2: CGPoint(x: w * 0.78, y: h * 0.72)
        )
        p.closeSubpath()
        return p
    }
}

/// Softly curved cottage roof silhouette.
private struct CozyPitchRoofShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + 1, y: rect.maxY))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + 1),
            control: CGPoint(x: rect.width * 0.26, y: rect.minY + 2.5)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - 1, y: rect.maxY),
            control: CGPoint(x: rect.width * 0.74, y: rect.minY + 2.5)
        )
        p.closeSubpath()
        return p
    }
}

/// Soft half-bowl shape for food.
private struct CozyBowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY * 0.85),
            control2: CGPoint(x: rect.width * 0.76, y: rect.maxY)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.width * 0.24, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY * 0.85)
        )
        p.closeSubpath()
        return p
    }
}

/// Soft rounded shield silhouette for emergency fund goal.
private struct CozyShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.04))
        p.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.22), control: CGPoint(x: w * 0.76, y: h * 0.08))
        p.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.96),
            control1: CGPoint(x: w * 0.94, y: h * 0.62),
            control2: CGPoint(x: w * 0.74, y: h * 0.86)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.08, y: h * 0.22),
            control1: CGPoint(x: w * 0.26, y: h * 0.86),
            control2: CGPoint(x: w * 0.06, y: h * 0.62)
        )
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.04), control: CGPoint(x: w * 0.24, y: h * 0.08))
        p.closeSubpath()
        return p
    }
}

/// Soft wavy steam line for warm bowls.
private struct CozySteamWispShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.height * 0.68),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.32)
        )
        return p
    }
}

/// Cute rounded toy airplane silhouette.
private struct CozyToyPlaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        // Pointing up-right
        p.move(to: CGPoint(x: w * 0.90, y: h * 0.14))
        p.addQuadCurve(to: CGPoint(x: w * 0.10, y: h * 0.44), control: CGPoint(x: w * 0.45, y: h * 0.20))
        p.addQuadCurve(to: CGPoint(x: w * 0.42, y: h * 0.56), control: CGPoint(x: w * 0.24, y: h * 0.54))
        p.addLine(to: CGPoint(x: w * 0.54, y: h * 0.88))
        p.addQuadCurve(to: CGPoint(x: w * 0.90, y: h * 0.14), control: CGPoint(x: w * 0.80, y: h * 0.54))
        p.closeSubpath()
        return p
    }
}

// MARK: - Hand-Drawn Category Icons (All 11 Categories)

public struct CozyCategoryIcon: View {
    public let category: CategoryID
    public var size: CGFloat
    public var style: CozyIconStyle

    @Environment(\.colorScheme) private var colorScheme

    public init(category: CategoryID, size: CGFloat = 24, style: CozyIconStyle = .watercolor) {
        self.category = category
        self.size = size
        self.style = style
    }

    private var ink: Color {
        switch style {
        case .watercolor:
            return colorScheme == .dark ? Color(hex: 0x3D2C26) : Color(hex: 0x4E382F)
        case .tinted(let c):
            return c
        }
    }

    private var isWatercolor: Bool {
        if case .watercolor = style { return true }
        return false
    }

    private func fill(_ hex: UInt32, alpha: Double = 1.0, tintOpacity: Double = 0.22) -> Color {
        switch style {
        case .watercolor:
            return Color(hex: hex, alpha: alpha)
        case .tinted(let c):
            return c.opacity(tintOpacity)
        }
    }

    public var body: some View {
        let s = size / 28.0
        let stroke = max(1.15, 1.55 * s)

        Group {
            switch category {
            case .food:
                foodIcon(s: s, stroke: stroke)
            case .housing:
                housingIcon(s: s, stroke: stroke)
            case .transport:
                transportIcon(s: s, stroke: stroke)
            case .shopping:
                shoppingIcon(s: s, stroke: stroke)
            case .bills:
                billsIcon(s: s, stroke: stroke)
            case .health:
                healthIcon(s: s, stroke: stroke)
            case .entertainment:
                entertainmentIcon(s: s, stroke: stroke)
            case .other:
                otherIcon(s: s, stroke: stroke)
            case .salary:
                salaryIcon(s: s, stroke: stroke)
            case .freelance:
                freelanceIcon(s: s, stroke: stroke)
            case .income:
                incomeIcon(s: s, stroke: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // 1. Food & Drink: Cozy steaming rice/ramen bowl with chopsticks
    @ViewBuilder
    private func foodIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Soft steam wisps
            HStack(spacing: 4 * s) {
                CozySteamWispShape()
                    .stroke(isWatercolor ? Color(hex: 0xE68A6E) : ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round))
                    .frame(width: 3 * s, height: 5 * s)
                CozySteamWispShape()
                    .stroke(isWatercolor ? Color(hex: 0xE68A6E) : ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.2 * s, lineCap: .round))
                    .frame(width: 3 * s, height: 6 * s)
                    .offset(y: -1 * s)
            }
            .offset(x: -3.5 * s, y: -8.5 * s)

            // Chopsticks resting diagonally on the right
            Capsule()
                .fill(fill(0xD9A782, tintOpacity: 0.45))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.72))
                .frame(width: 11.5 * s, height: 2.1 * s)
                .rotationEffect(.degrees(-28))
                .offset(x: 5.5 * s, y: -4.8 * s)

            Capsule()
                .fill(fill(0xD9A782, tintOpacity: 0.45))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.72))
                .frame(width: 11 * s, height: 2.1 * s)
                .rotationEffect(.degrees(-16))
                .offset(x: 6 * s, y: -2.5 * s)

            // Fluffy cream rice mound peeking above rim
            Ellipse()
                .fill(fill(0xFFFDF8, tintOpacity: 0.14))
                .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 16 * s, height: 8 * s)
                .offset(y: -1 * s)

            // Bowl base foot
            RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                .fill(fill(0xE88254, tintOpacity: 0.35))
                .overlay(RoundedRectangle(cornerRadius: 2 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 9 * s, height: 3.5 * s)
                .offset(y: 9 * s)

            // Chubby warm peach-orange bowl body
            CozyBowlShape()
                .fill(fill(0xF6A96C, tintOpacity: 0.28))
                .overlay(
                    CozyBowlShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 21 * s, height: 11.5 * s)
                .offset(y: 3.5 * s)

            // Cute rim stripe
            Capsule()
                .fill(fill(0xFFF6EB, tintOpacity: 0.55))
                .frame(width: 11 * s, height: 1.8 * s)
                .offset(y: 1.5 * s)
        }
    }

    // 2. Housing: Cozy cottage with peach curved roof, chimney & heart door
    @ViewBuilder
    private func housingIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Chimney
            RoundedRectangle(cornerRadius: 1.8 * s, style: .continuous)
                .fill(fill(0xF5B959, tintOpacity: 0.25))
                .overlay(RoundedRectangle(cornerRadius: 1.8 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.9))
                .frame(width: 4.5 * s, height: 7 * s)
                .offset(x: 6 * s, y: -6.2 * s)

            // Cottage wall
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(fill(0xFFF6EA, tintOpacity: 0.16))
                .overlay(RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 17.5 * s, height: 13 * s)
                .offset(y: 4.5 * s)

            // Curved peach roof
            CozyPitchRoofShape()
                .fill(fill(0xF28B76, tintOpacity: 0.34))
                .overlay(
                    CozyPitchRoofShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 22.5 * s, height: 11.5 * s)
                .offset(y: -4.2 * s)

            // Tiny heart doorway
            CozyHeartShape()
                .fill(isWatercolor ? Color(hex: 0xE67360) : ink.opacity(0.85))
                .frame(width: 6.5 * s, height: 6 * s)
                .offset(y: 5.5 * s)
        }
    }

    // 3. Transport: Chubby pastel sky-blue retro car with round headlights
    @ViewBuilder
    private func transportIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Cute wheels
            HStack(spacing: 9 * s) {
                Circle()
                    .fill(isWatercolor ? Color(hex: 0x5A433A) : ink)
                    .frame(width: 5.5 * s, height: 5.5 * s)
                Circle()
                    .fill(isWatercolor ? Color(hex: 0x5A433A) : ink)
                    .frame(width: 5.5 * s, height: 5.5 * s)
            }
            .offset(y: 7.5 * s)

            // Car cabin roof
            RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                .fill(fill(0xFFF9F0, tintOpacity: 0.18))
                .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 15 * s, height: 10 * s)
                .offset(y: -3.5 * s)

            // Windshield shine
            RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .fill(fill(0xCFE9FA, tintOpacity: 0.2))
                .frame(width: 10.5 * s, height: 5 * s)
                .offset(y: -3.8 * s)

            // Plump sky-blue car body
            RoundedRectangle(cornerRadius: 5.5 * s, style: .continuous)
                .fill(fill(0x7EC0E8, tintOpacity: 0.34))
                .overlay(RoundedRectangle(cornerRadius: 5.5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 22 * s, height: 10 * s)
                .offset(y: 2.8 * s)

            // Round honey headlights
            HStack(spacing: 11 * s) {
                Circle()
                    .fill(isWatercolor ? Color(hex: 0xFFE582) : ink.opacity(0.75))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.65))
                    .frame(width: 4 * s, height: 4 * s)
                Circle()
                    .fill(isWatercolor ? Color(hex: 0xFFE582) : ink.opacity(0.75))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.65))
                    .frame(width: 4 * s, height: 4 * s)
            }
            .offset(y: 3 * s)

            // Cute smiling bumper line
            Capsule()
                .fill(ink)
                .frame(width: 5.5 * s, height: 1.5 * s)
                .offset(y: 4.5 * s)
        }
    }

    // 4. Shopping: Plump rosy-pink tote bag with handle & cream heart charm
    @ViewBuilder
    private func shoppingIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Bag handle arc
            Circle()
                .trim(from: 0.5, to: 1.0)
                .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: 9.5 * s, height: 9.5 * s)
                .offset(y: -6.2 * s)

            // Plump rosy tote body
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                .fill(fill(0xF2A2C0, tintOpacity: 0.32))
                .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 19 * s, height: 16.5 * s)
                .offset(y: 2.5 * s)

            // Cream heart charm on bag
            CozyHeartShape()
                .fill(isWatercolor ? Color(hex: 0xFFF7F2) : ink.opacity(0.85))
                .overlay(CozyHeartShape().stroke(ink, lineWidth: isWatercolor ? stroke * 0.6 : 0))
                .frame(width: 7.5 * s, height: 7 * s)
                .offset(y: 3 * s)
        }
    }

    // 5. Bills & Utilities: Warm glowing honey lightbulb with sparkle rays
    @ViewBuilder
    private func billsIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Top & side cozy rays
            ForEach([-42.0, 0.0, 42.0], id: \.self) { angle in
                Capsule()
                    .fill(isWatercolor ? Color(hex: 0xE6A12E) : ink.opacity(0.75))
                    .frame(width: 1.6 * s, height: 3.2 * s)
                    .offset(y: -11.2 * s)
                    .rotationEffect(.degrees(angle))
            }

            // Screw base
            RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                .fill(fill(0x9BB4E8, tintOpacity: 0.32))
                .overlay(RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.9))
                .frame(width: 8 * s, height: 5.5 * s)
                .offset(y: 7.5 * s)

            // Warm honey glass bulb
            Circle()
                .fill(fill(0xFFE580, tintOpacity: 0.32))
                .overlay(Circle().stroke(ink, lineWidth: stroke))
                .frame(width: 15 * s, height: 15 * s)
                .offset(y: -1 * s)

            // Soft cream highlight inside bulb
            Circle()
                .fill(isWatercolor ? Color(hex: 0xFFFDF2) : ink.opacity(0.6))
                .frame(width: 4 * s, height: 4 * s)
                .offset(x: -2.8 * s, y: -3.5 * s)
        }
    }

    // 6. Health: Plump coral-rose heart with cream rounded medical cross
    @ViewBuilder
    private func healthIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            CozyHeartShape()
                .fill(fill(0xF28D9B, tintOpacity: 0.32))
                .overlay(
                    CozyHeartShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 22 * s, height: 20.5 * s)
                .offset(y: 0.5 * s)

            // Cute cream plus/cross inside
            ZStack {
                Capsule()
                    .fill(isWatercolor ? Color(hex: 0xFFF9F4) : ink.opacity(0.9))
                    .frame(width: 7.5 * s, height: 2.6 * s)
                Capsule()
                    .fill(isWatercolor ? Color(hex: 0xFFF9F4) : ink.opacity(0.9))
                    .frame(width: 2.6 * s, height: 7.5 * s)
            }
            .offset(y: -0.5 * s)
        }
    }

    // 7. Entertainment: Cute lavender cinema ticket / clapperboard with golden star
    @ViewBuilder
    private func entertainmentIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Plump lavender ticket/board
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                .fill(fill(0xC9B3F2, tintOpacity: 0.32))
                .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 21 * s, height: 16 * s)
                .offset(y: 1.5 * s)

            // Top clapper bar
            RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                .fill(fill(0x9E82D9, tintOpacity: 0.45))
                .overlay(RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.9))
                .frame(width: 21 * s, height: 5 * s)
                .rotationEffect(.degrees(-8))
                .offset(x: -0.5 * s, y: -6.5 * s)

            // Golden twinkling star in center
            CozyFourPointStarShape()
                .fill(isWatercolor ? Color(hex: 0xFFE373) : ink.opacity(0.9))
                .overlay(CozyFourPointStarShape().stroke(ink, lineWidth: isWatercolor ? stroke * 0.6 : 0))
                .frame(width: 8.5 * s, height: 8.5 * s)
                .offset(y: 2.5 * s)
        }
    }

    // 8. Other: Adorable warm caramel teddy bear head with round ears & rosy cheeks
    @ViewBuilder
    private func otherIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Round ears
            HStack(spacing: 11 * s) {
                Circle()
                    .fill(fill(0xCFA07E, tintOpacity: 0.32))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.9))
                    .frame(width: 7.5 * s, height: 7.5 * s)
                Circle()
                    .fill(fill(0xCFA07E, tintOpacity: 0.32))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.9))
                    .frame(width: 7.5 * s, height: 7.5 * s)
            }
            .offset(y: -6.5 * s)

            // Plump teddy head
            Ellipse()
                .fill(fill(0xDDA984, tintOpacity: 0.28))
                .overlay(Ellipse().stroke(ink, lineWidth: stroke))
                .frame(width: 20 * s, height: 17.5 * s)
                .offset(y: 1.5 * s)

            // Cream muzzle
            Ellipse()
                .fill(fill(0xFFF5E8, tintOpacity: 0.16))
                .frame(width: 9 * s, height: 6.5 * s)
                .offset(y: 4 * s)

            // Cute eyes & nose
            HStack(spacing: 6.5 * s) {
                Circle().fill(ink).frame(width: 2.2 * s, height: 2.2 * s)
                Circle().fill(ink).frame(width: 2.2 * s, height: 2.2 * s)
            }
            .offset(y: 0.2 * s)

            Ellipse()
                .fill(ink)
                .frame(width: 3.4 * s, height: 2.3 * s)
                .offset(y: 3 * s)

            // Rosy cheeks (watercolor mode)
            if isWatercolor {
                HStack(spacing: 10.5 * s) {
                    Circle().fill(Color(hex: 0xF59B9B, alpha: 0.65)).frame(width: 3.2 * s, height: 2.2 * s)
                    Circle().fill(Color(hex: 0xF59B9B, alpha: 0.65)).frame(width: 3.2 * s, height: 2.2 * s)
                }
                .offset(y: 3 * s)
            }
        }
    }

    // 9. Salary: Chubby matcha-mint coin pouch with peeking gold coin
    @ViewBuilder
    private func salaryIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Peeking gold coin
            Circle()
                .fill(fill(0xFFE378, tintOpacity: 0.35))
                .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 9.5 * s, height: 9.5 * s)
                .offset(x: 4.5 * s, y: -6.5 * s)

            // Pouch top ruffle
            Capsule()
                .fill(fill(0x7CC99C, tintOpacity: 0.35))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 9.5 * s, height: 4.2 * s)
                .offset(x: -1.5 * s, y: -6.5 * s)

            // Plump mint pouch body
            Ellipse()
                .fill(fill(0x95DCAC, tintOpacity: 0.30))
                .overlay(Ellipse().stroke(ink, lineWidth: stroke))
                .frame(width: 19 * s, height: 15.5 * s)
                .offset(x: -1.5 * s, y: 2.5 * s)

            // Golden ribbon tie
            Capsule()
                .fill(isWatercolor ? Color(hex: 0xF5B959) : ink.opacity(0.8))
                .frame(width: 9.5 * s, height: 2.2 * s)
                .offset(x: -1.5 * s, y: -4.2 * s)

            // Little sparkle dot on pouch
            Circle()
                .fill(isWatercolor ? Color(hex: 0xFFFDF5) : ink.opacity(0.6))
                .frame(width: 3 * s, height: 3 * s)
                .offset(x: -5.5 * s, y: 1 * s)
        }
    }

    // 10. Freelance: Twinkling golden-mint four-point stars
    @ViewBuilder
    private func freelanceIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            CozyFourPointStarShape()
                .fill(fill(0xFFE275, tintOpacity: 0.35))
                .overlay(
                    CozyFourPointStarShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 17 * s, height: 17 * s)
                .offset(x: -2 * s, y: 1.5 * s)

            CozyFourPointStarShape()
                .fill(fill(0x8AD6AE, tintOpacity: 0.4))
                .overlay(
                    CozyFourPointStarShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke * 0.8, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 9 * s, height: 9 * s)
                .offset(x: 7 * s, y: -6.5 * s)
        }
    }

    // 11. Other Income: Wrapped sage-mint gift box with coral bow
    @ViewBuilder
    private func incomeIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Bow loops on top
            HStack(spacing: 1 * s) {
                Ellipse()
                    .fill(fill(0xF28B76, tintOpacity: 0.35))
                    .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 6.5 * s, height: 4.5 * s)
                    .rotationEffect(.degrees(-22))
                Ellipse()
                    .fill(fill(0xF28B76, tintOpacity: 0.35))
                    .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 6.5 * s, height: 4.5 * s)
                    .rotationEffect(.degrees(22))
            }
            .offset(y: -8 * s)

            // Gift box body
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(fill(0x9DE0B8, tintOpacity: 0.30))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 13.5 * s)
                .offset(y: 3.5 * s)

            // Lid
            RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                .fill(fill(0xB8EBD0, tintOpacity: 0.38))
                .overlay(RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.9))
                .frame(width: 20.5 * s, height: 4.5 * s)
                .offset(y: -3.5 * s)

            // Vertical coral ribbon
            Rectangle()
                .fill(isWatercolor ? Color(hex: 0xF28B76) : ink.opacity(0.75))
                .frame(width: 3.2 * s, height: 15.5 * s)
                .offset(y: 2.2 * s)
        }
    }
}

// MARK: - Hand-Drawn Savings Goal Icons (All 6 Goals)

public struct CozyGoalIcon: View {
    public let goal: GoalIcon
    public var size: CGFloat
    public var style: CozyIconStyle

    @Environment(\.colorScheme) private var colorScheme

    public init(goal: GoalIcon, size: CGFloat = 24, style: CozyIconStyle = .watercolor) {
        self.goal = goal
        self.size = size
        self.style = style
    }

    private var ink: Color {
        switch style {
        case .watercolor:
            return colorScheme == .dark ? Color(hex: 0x3D2C26) : Color(hex: 0x4E382F)
        case .tinted(let c):
            return c
        }
    }

    private var isWatercolor: Bool {
        if case .watercolor = style { return true }
        return false
    }

    private func fill(_ hex: UInt32, tintOpacity: Double = 0.25) -> Color {
        switch style {
        case .watercolor: return Color(hex: hex)
        case .tinted(let c): return c.opacity(tintOpacity)
        }
    }

    public var body: some View {
        let s = size / 28.0
        let stroke = max(1.15, 1.55 * s)

        Group {
            switch goal {
            case .target:
                targetIcon(s: s, stroke: stroke)
            case .shield:
                shieldIcon(s: s, stroke: stroke)
            case .plane:
                planeIcon(s: s, stroke: stroke)
            case .laptop:
                laptopIcon(s: s, stroke: stroke)
            case .house:
                CozyCategoryIcon(category: .housing, size: size, style: style)
            case .heart:
                familyHeartIcon(s: s, stroke: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func targetIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(fill(0xF69B86, tintOpacity: 0.28))
                .overlay(Circle().stroke(ink, lineWidth: stroke))
                .frame(width: 21 * s, height: 21 * s)

            Circle()
                .fill(fill(0xFFF9F0, tintOpacity: 0.12))
                .overlay(Circle().stroke(ink, lineWidth: stroke * 0.8))
                .frame(width: 13.5 * s, height: 13.5 * s)

            Circle()
                .fill(isWatercolor ? Color(hex: 0xE67360) : ink.opacity(0.85))
                .frame(width: 6 * s, height: 6 * s)

            // Cute golden dart sticking in top-right
            Capsule()
                .fill(isWatercolor ? Color(hex: 0xF5B959) : ink)
                .frame(width: 10 * s, height: 2 * s)
                .rotationEffect(.degrees(-45))
                .offset(x: 4.5 * s, y: -4.5 * s)
        }
    }

    @ViewBuilder
    private func shieldIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            CozyShieldShape()
                .fill(fill(0x95DCAC, tintOpacity: 0.30))
                .overlay(
                    CozyShieldShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 19.5 * s, height: 22 * s)

            // Hand-drawn soft checkmark
            Path { p in
                p.move(to: CGPoint(x: 9.5 * s, y: 14 * s))
                p.addLine(to: CGPoint(x: 13 * s, y: 17.5 * s))
                p.addLine(to: CGPoint(x: 19 * s, y: 10.5 * s))
            }
            .stroke(isWatercolor ? Color(hex: 0xFFFDF8) : ink, style: StrokeStyle(lineWidth: stroke * 1.25, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func planeIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Fluffy cream puff cloud below
            Capsule()
                .fill(fill(0xFFF9F0, tintOpacity: 0.2))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.75))
                .frame(width: 11 * s, height: 5.5 * s)
                .offset(x: -5.5 * s, y: 7.5 * s)

            // Sky-blue paper/toy airplane
            CozyToyPlaneShape()
                .fill(fill(0x88C8EE, tintOpacity: 0.34))
                .overlay(
                    CozyToyPlaneShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 21 * s, height: 21 * s)
                .offset(x: 1 * s, y: -1 * s)
        }
    }

    @ViewBuilder
    private func laptopIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Screen lid
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(fill(0xC9B3F2, tintOpacity: 0.30))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 13 * s)
                .offset(y: -2.5 * s)

            // Inner cream display
            RoundedRectangle(cornerRadius: 2.2 * s, style: .continuous)
                .fill(fill(0xFFF9F2, tintOpacity: 0.14))
                .frame(width: 13 * s, height: 8.5 * s)
                .offset(y: -2.5 * s)

            // Tiny heart on screen
            CozyHeartShape()
                .fill(isWatercolor ? Color(hex: 0xF28B76) : ink.opacity(0.85))
                .frame(width: 5 * s, height: 4.5 * s)
                .offset(y: -2.3 * s)

            // Plump keyboard base
            Capsule()
                .fill(fill(0xB49AE8, tintOpacity: 0.40))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.9))
                .frame(width: 22.5 * s, height: 4.2 * s)
                .offset(y: 6.5 * s)
        }
    }

    @ViewBuilder
    private func familyHeartIcon(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Back peach heart
            CozyHeartShape()
                .fill(fill(0xFFBF9E, tintOpacity: 0.25))
                .overlay(
                    CozyHeartShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke * 0.9, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 13 * s, height: 12 * s)
                .offset(x: 5.5 * s, y: -4 * s)

            // Front rosy heart
            CozyHeartShape()
                .fill(fill(0xF599B2, tintOpacity: 0.35))
                .overlay(
                    CozyHeartShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 17 * s, height: 16 * s)
                .offset(x: -2.5 * s, y: 2 * s)
        }
    }
}

// MARK: - Hand-Drawn Piggy Bank Badge Icon (Budgets Pill)

public struct CozyPiggyIcon: View {
    public var size: CGFloat
    public var style: CozyIconStyle

    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 20, style: CozyIconStyle = .watercolor) {
        self.size = size
        self.style = style
    }

    private var ink: Color {
        switch style {
        case .watercolor:
            return colorScheme == .dark ? Color(hex: 0x3D2C26) : Color(hex: 0x4E382F)
        case .tinted(let c):
            return c
        }
    }

    private var isWatercolor: Bool {
        if case .watercolor = style { return true }
        return false
    }

    private func fill(_ hex: UInt32, tintOpacity: Double = 0.25) -> Color {
        switch style {
        case .watercolor: return Color(hex: hex)
        case .tinted(let c): return c.opacity(tintOpacity)
        }
    }

    public var body: some View {
        let s = size / 24.0
        let stroke = max(1.1, 1.45 * s)

        ZStack {
            // Golden coin dropping into slot
            Circle()
                .fill(fill(0xFFE066, tintOpacity: 0.35))
                .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 6.5 * s, height: 6.5 * s)
                .offset(y: -8 * s)

            // Cute ears
            HStack(spacing: 8.5 * s) {
                Ellipse()
                    .fill(fill(0xF7B0B8, tintOpacity: 0.3))
                    .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 4.5 * s, height: 5.5 * s)
                    .rotationEffect(.degrees(-22))
                Ellipse()
                    .fill(fill(0xF7B0B8, tintOpacity: 0.3))
                    .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 4.5 * s, height: 5.5 * s)
                    .rotationEffect(.degrees(22))
            }
            .offset(y: -4 * s)

            // Little feet
            HStack(spacing: 6.5 * s) {
                Capsule()
                    .fill(fill(0xF5A4AE, tintOpacity: 0.3))
                    .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 3.8 * s, height: 4.2 * s)
                Capsule()
                    .fill(fill(0xF5A4AE, tintOpacity: 0.3))
                    .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 3.8 * s, height: 4.2 * s)
            }
            .offset(y: 7.5 * s)

            // Chubby piggy body
            Ellipse()
                .fill(fill(0xFFD2D8, tintOpacity: 0.28))
                .overlay(Ellipse().stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 13.5 * s)
                .offset(y: 1.5 * s)

            // Coin slot line
            Capsule()
                .fill(ink)
                .frame(width: 5 * s, height: max(1.0, 1.3 * s))
                .offset(y: -3 * s)

            // Snout
            Ellipse()
                .fill(fill(0xF7A8B2, tintOpacity: 0.36))
                .overlay(Ellipse().stroke(ink, lineWidth: stroke * 0.8))
                .frame(width: 7 * s, height: 4.8 * s)
                .overlay {
                    HStack(spacing: 1.8 * s) {
                        Circle().fill(ink).frame(width: 1.3 * s, height: 1.3 * s)
                        Circle().fill(ink).frame(width: 1.3 * s, height: 1.3 * s)
                    }
                }
                .offset(y: 2.8 * s)

            // Eyes
            HStack(spacing: 7.8 * s) {
                Circle().fill(ink).frame(width: 1.8 * s, height: 1.8 * s)
                Circle().fill(ink).frame(width: 1.8 * s, height: 1.8 * s)
            }
            .offset(y: 0.2 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
