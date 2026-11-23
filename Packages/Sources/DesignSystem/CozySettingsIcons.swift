import SwiftUI

// MARK: - Full-Watercolor Hand-Drawn Settings & KPI Sticker Icons

/// Renders a Japanese watercolor storybook sticker icon for `SettingsIconTile`
/// with warm cocoa ink outlines (`#4E382F`) and soft pastel fills.
public struct CozySettingsStickerIcon: View {
    public let kind: CozyUIIconKind
    public var size: CGFloat
    public var tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    public init(kind: CozyUIIconKind, size: CGFloat = 32, tint: Color? = nil) {
        self.kind = kind
        self.size = size
        self.tint = tint
    }

    private var ink: Color {
        colorScheme == .dark ? Color(hex: 0x3D2C26) : Color(hex: 0x4E382F)
    }

    private var pastelBackground: Color {
        let base = tint ?? defaultTint
        return colorScheme == .dark ? base.opacity(0.24) : base.opacity(0.16)
    }

    private var borderTint: Color {
        let base = tint ?? defaultTint
        return base.opacity(colorScheme == .dark ? 0.36 : 0.26)
    }

    private var defaultTint: Color {
        switch kind {
        case .sliders: return Color(hex: 0xE68A6E)
        case .sparkles, .wand: return Color(hex: 0xF0B243)
        case .bolt: return Color(hex: 0xE67360)
        case .envelope: return Color(hex: 0x5B9EC9)
        case .cloud: return Color(hex: 0x5B9EC9)
        case .people: return Color(hex: 0x459E6E)
        case .backup, .exportBox, .importBox: return Color(hex: 0x9C7FD1)
        case .key: return Color(hex: 0xD68A28)
        case .creditCard: return Color(hex: 0x459E6E)
        case .message: return Color(hex: 0xD68A28)
        case .leaf: return Color(hex: 0x459E6E)
        case .flame: return Color(hex: 0xE67360)
        case .calendar: return Color(hex: 0x5B9EC9)
        case .warning: return Color(hex: 0xD68A28)
        case .checkmark, .checkmarkCircle: return Color(hex: 0x459E6E)
        case .xmark, .xmarkCircle: return Color(hex: 0xD95B5B)
        default: return Color(hex: 0xA88874)
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
        if let img = CozyWatercolorAsset.settingsImage(for: kind) {
            img
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(borderTint, lineWidth: 1))
                .accessibilityHidden(true)
        } else {
            let s = (size * 0.72) / 24.0
            let stroke = max(1.15, 1.55 * s)
            let lineStyle = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)

            ZStack {
                shape.fill(pastelBackground)

                artwork(s: s, stroke: stroke, style: lineStyle)
                    .frame(width: size * 0.72, height: size * 0.72)
            }
            .frame(width: size, height: size)
            .overlay(shape.strokeBorder(borderTint, lineWidth: 1))
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func artwork(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        switch kind {
        case .sliders:
            slidersSticker(s: s, stroke: stroke)
        case .sparkles:
            sparklesSticker(s: s, style: style)
        case .wand:
            wandSticker(s: s, stroke: stroke, style: style)
        case .bolt:
            boltSticker(s: s, style: style)
        case .envelope:
            envelopeSticker(s: s, stroke: stroke, style: style)
        case .cloud:
            cloudSticker(s: s, style: style)
        case .people:
            peopleSticker(s: s, stroke: stroke)
        case .backup:
            backupSticker(s: s, stroke: stroke, style: style)
        case .key:
            keySticker(s: s, stroke: stroke, style: style)
        case .creditCard:
            creditCardSticker(s: s, stroke: stroke)
        case .message:
            messageSticker(s: s, stroke: stroke)
        case .calendar:
            calendarSticker(s: s, stroke: stroke)
        case .leaf:
            leafSticker(s: s, style: style)
        case .flame:
            flameSticker(s: s, style: style)
        case .exportBox:
            exportSticker(s: s, stroke: stroke, style: style)
        case .warning:
            warningSticker(s: s, style: style)
        case .checkmark, .checkmarkCircle:
            checkmarkSticker(s: s, stroke: stroke, style: style)
        case .xmark, .xmarkCircle:
            xmarkSticker(s: s, stroke: stroke, style: style)
        default:
            CozyUIIcon(kind, size: 22 * s, color: tint ?? defaultTint)
        }
    }

    // 1. General & Appearance: Cozy sliders with pastel peach, butter & matcha knobs
    @ViewBuilder
    private func slidersSticker(s: CGFloat, stroke: CGFloat) -> some View {
        VStack(spacing: 4.5 * s) {
            ZStack {
                Capsule().fill(ink).frame(width: 17 * s, height: 1.7 * s)
                Circle()
                    .fill(Color(hex: 0xF28B76))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 5.5 * s, height: 5.5 * s)
                    .offset(x: -4 * s)
            }
            ZStack {
                Capsule().fill(ink).frame(width: 17 * s, height: 1.7 * s)
                Circle()
                    .fill(Color(hex: 0xFFE378))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 5.5 * s, height: 5.5 * s)
                    .offset(x: 3.5 * s)
            }
            ZStack {
                Capsule().fill(ink).frame(width: 17 * s, height: 1.7 * s)
                Circle()
                    .fill(Color(hex: 0x8AD6AE))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 5.5 * s, height: 5.5 * s)
                    .offset(x: -1.5 * s)
            }
        }
    }

    // 2. AI Assistant: Twinkling golden & coral pastel stars
    @ViewBuilder
    private func sparklesSticker(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            CozyFourPointStarShape()
                .fill(Color(hex: 0xFFE375))
                .overlay(CozyFourPointStarShape().stroke(ink, style: style))
                .frame(width: 15.5 * s, height: 15.5 * s)
                .offset(x: -2.2 * s, y: 1.5 * s)

            CozyFourPointStarShape()
                .fill(Color(hex: 0xFFAE96))
                .overlay(CozyFourPointStarShape().stroke(ink, lineWidth: style.lineWidth * 0.78))
                .frame(width: 8.5 * s, height: 8.5 * s)
                .offset(x: 6.5 * s, y: -6 * s)

            Circle()
                .fill(Color(hex: 0x8AD6AE))
                .frame(width: 2.6 * s, height: 2.6 * s)
                .offset(x: 6.5 * s, y: 6.5 * s)
        }
    }

    // 3. Auto AI / Magic Wand: Caramel wand with glowing golden star tip
    @ViewBuilder
    private func wandSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Capsule()
                .fill(Color(hex: 0xD9A782))
                .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 15 * s, height: 3.2 * s)
                .rotationEffect(.degrees(-45))
                .offset(x: -2 * s, y: 2 * s)

            CozyFourPointStarShape()
                .fill(Color(hex: 0xFFE375))
                .overlay(CozyFourPointStarShape().stroke(ink, style: style))
                .frame(width: 11 * s, height: 11 * s)
                .offset(x: 4.5 * s, y: -4.5 * s)
        }
    }

    // 4. Auto-Capture & Shortcuts: Plump honey-gold lightning bolt
    @ViewBuilder
    private func boltSticker(s: CGFloat, style: StrokeStyle) -> some View {
        let bolt = Path { p in
            p.move(to: CGPoint(x: 13.5 * s, y: 2 * s))
            p.addLine(to: CGPoint(x: 5 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 11.2 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 9.8 * s, y: 22 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 10.5 * s))
            p.addLine(to: CGPoint(x: 12.6 * s, y: 10.5 * s))
            p.closeSubpath()
        }
        ZStack {
            bolt.fill(Color(hex: 0xFFE06B))
            bolt.stroke(ink, style: style)
        }
    }

    // 5. Cloud Bank Email Inbox: Cream stationery envelope with rosy heart seal
    @ViewBuilder
    private func envelopeSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(Color(hex: 0xFFF9F0))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 19.5 * s, height: 14.5 * s)

            Path { p in
                p.move(to: CGPoint(x: 3.2 * s, y: 6.5 * s))
                p.addQuadCurve(to: CGPoint(x: 12 * s, y: 12.5 * s), control: CGPoint(x: 7.5 * s, y: 11 * s))
                p.addQuadCurve(to: CGPoint(x: 20.8 * s, y: 6.5 * s), control: CGPoint(x: 16.5 * s, y: 11 * s))
            }
            .stroke(ink, style: style)

            CozyHeartShape()
                .fill(Color(hex: 0xF28B76))
                .frame(width: 5.5 * s, height: 5 * s)
                .offset(y: 0.8 * s)
        }
    }

    // 6. iCloud: Fluffy sky-blue & cream storybook cloud
    @ViewBuilder
    private func cloudSticker(s: CGFloat, style: StrokeStyle) -> some View {
        let cloud = Path { p in
            p.move(to: CGPoint(x: 6.5 * s, y: 17.5 * s))
            p.addCurve(to: CGPoint(x: 4.5 * s, y: 10.5 * s), control1: CGPoint(x: 2.5 * s, y: 17.5 * s), control2: CGPoint(x: 2 * s, y: 11.5 * s))
            p.addCurve(to: CGPoint(x: 14.5 * s, y: 7 * s), control1: CGPoint(x: 5.8 * s, y: 5.5 * s), control2: CGPoint(x: 12.5 * s, y: 4.5 * s))
            p.addCurve(to: CGPoint(x: 18 * s, y: 17.5 * s), control1: CGPoint(x: 21 * s, y: 7 * s), control2: CGPoint(x: 22 * s, y: 17.5 * s))
            p.closeSubpath()
        }
        ZStack {
            cloud.fill(
                LinearGradient(
                    colors: [Color(hex: 0xFFFDF9), Color(hex: 0xB8DDF7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            cloud.stroke(ink, style: style)
        }
    }

    // 7. Household Sharing: Cozy couple silhouettes with rosy heart
    @ViewBuilder
    private func peopleSticker(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            // Right partner (mint)
            VStack(spacing: 1 * s) {
                Circle()
                    .fill(Color(hex: 0x9DE0B8))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 6.5 * s, height: 6.5 * s)
                Capsule()
                    .fill(Color(hex: 0x9DE0B8))
                    .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.85))
                    .frame(width: 10 * s, height: 6 * s)
            }
            .offset(x: 4.5 * s, y: 1 * s)

            // Left partner (peach)
            VStack(spacing: 1 * s) {
                Circle()
                    .fill(Color(hex: 0xFFAE96))
                    .overlay(Circle().stroke(ink, lineWidth: stroke * 0.9))
                    .frame(width: 7.5 * s, height: 7.5 * s)
                Capsule()
                    .fill(Color(hex: 0xFFAE96))
                    .overlay(Capsule().stroke(ink, lineWidth: stroke * 0.9))
                    .frame(width: 11.5 * s, height: 6.5 * s)
            }
            .offset(x: -3.5 * s, y: 1.5 * s)

            // Tiny heart floating above
            CozyHeartShape()
                .fill(Color(hex: 0xF27D8D))
                .frame(width: 5.5 * s, height: 5 * s)
                .offset(x: 0.5 * s, y: -7.5 * s)
        }
    }

    // 8. Backup & Data: Cozy lavender archive box with exchange arrows
    @ViewBuilder
    private func backupSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                .fill(Color(hex: 0xDDD0F7))
                .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 18 * s)

            Path { p in
                // Up arrow left
                p.move(to: CGPoint(x: 9 * s, y: 16 * s))
                p.addLine(to: CGPoint(x: 9 * s, y: 8 * s))
                p.move(to: CGPoint(x: 6.5 * s, y: 10.5 * s))
                p.addLine(to: CGPoint(x: 9 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 11.5 * s, y: 10.5 * s))

                // Down arrow right
                p.move(to: CGPoint(x: 15 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 15 * s, y: 16 * s))
                p.move(to: CGPoint(x: 12.5 * s, y: 13.5 * s))
                p.addLine(to: CGPoint(x: 15 * s, y: 16 * s))
                p.addLine(to: CGPoint(x: 17.5 * s, y: 13.5 * s))
            }
            .stroke(ink, style: style)
        }
    }

    // 9. API Key: Vintage honey-gold key
    @ViewBuilder
    private func keySticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 10.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 20.5 * s, y: 12 * s))
                p.move(to: CGPoint(x: 16.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 15.8 * s))
                p.move(to: CGPoint(x: 19.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 19.5 * s, y: 14.8 * s))
            }
            .stroke(ink, style: style)

            Circle()
                .fill(Color(hex: 0xFFE378))
                .overlay(Circle().stroke(ink, lineWidth: stroke))
                .frame(width: 9 * s, height: 9 * s)
                .offset(x: -5 * s)

            Circle()
                .fill(Color(hex: 0xFFFDF5))
                .frame(width: 3 * s, height: 3 * s)
                .offset(x: -5.5 * s)
        }
    }

    // 10. Apple Pay / Card: Pastel mint bank card with golden chip
    @ViewBuilder
    private func creditCardSticker(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(Color(hex: 0x9DE0B8))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 19.5 * s, height: 14 * s)

            Rectangle()
                .fill(Color(hex: 0xFFF9F0))
                .frame(width: 18 * s, height: 3 * s)
                .offset(y: -2.8 * s)

            RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous)
                .fill(Color(hex: 0xFFE378))
                .overlay(RoundedRectangle(cornerRadius: 1.5 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.7))
                .frame(width: 5 * s, height: 3.5 * s)
                .offset(x: -4.5 * s, y: 2.8 * s)
        }
    }

    // 11. SMS / Message: Plump butter-cream speech bubble
    @ViewBuilder
    private func messageSticker(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                .fill(Color(hex: 0xFFF3D4))
                .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 19 * s, height: 14.5 * s)

            HStack(spacing: 3 * s) {
                Circle().fill(Color(hex: 0xE67360)).frame(width: 2.5 * s, height: 2.5 * s)
                Circle().fill(Color(hex: 0x459E6E)).frame(width: 2.5 * s, height: 2.5 * s)
                Circle().fill(Color(hex: 0x5B9EC9)).frame(width: 2.5 * s, height: 2.5 * s)
            }
        }
    }

    // 12. Daily Calendar: Cozy cream desk calendar with peach header
    @ViewBuilder
    private func calendarSticker(s: CGFloat, stroke: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(Color(hex: 0xFFF9F0))
                .overlay(RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 16 * s)
                .offset(y: 1.5 * s)

            RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .fill(Color(hex: 0xF28B76))
                .overlay(RoundedRectangle(cornerRadius: 3 * s, style: .continuous).stroke(ink, lineWidth: stroke * 0.85))
                .frame(width: 18 * s, height: 5.5 * s)
                .offset(y: -3.5 * s)

            HStack(spacing: 6.5 * s) {
                Capsule().fill(ink).frame(width: 2 * s, height: 4.2 * s)
                Capsule().fill(ink).frame(width: 2 * s, height: 4.2 * s)
            }
            .offset(y: -7 * s)

            HStack(spacing: 3.2 * s) {
                Circle().fill(Color(hex: 0x5B9EC9)).frame(width: 2.6 * s, height: 2.6 * s)
                Circle().fill(Color(hex: 0xE67360)).frame(width: 2.6 * s, height: 2.6 * s)
                Circle().fill(Color(hex: 0x8AD6AE)).frame(width: 2.6 * s, height: 2.6 * s)
            }
            .offset(y: 4 * s)
        }
    }

    // 13. Savings Rate: Plump matcha sprout leaf
    @ViewBuilder
    private func leafSticker(s: CGFloat, style: StrokeStyle) -> some View {
        let leaf = Path { p in
            p.move(to: CGPoint(x: 5.5 * s, y: 18.5 * s))
            p.addCurve(to: CGPoint(x: 19 * s, y: 5 * s), control1: CGPoint(x: 4.5 * s, y: 8 * s), control2: CGPoint(x: 11.5 * s, y: 4.5 * s))
            p.addCurve(to: CGPoint(x: 5.5 * s, y: 18.5 * s), control1: CGPoint(x: 19.5 * s, y: 13.5 * s), control2: CGPoint(x: 13.5 * s, y: 19.5 * s))
            p.closeSubpath()
        }
        ZStack {
            leaf.fill(Color(hex: 0x8AD6AE))
            leaf.stroke(ink, style: style)
            Path { p in
                p.move(to: CGPoint(x: 5 * s, y: 19 * s))
                p.addQuadCurve(to: CGPoint(x: 14.5 * s, y: 9.5 * s), control: CGPoint(x: 10.5 * s, y: 13 * s))
            }
            .stroke(ink, style: style)
        }
    }

    // 14. Peak Day: Warm coral campfire flame with golden inner glow
    @ViewBuilder
    private func flameSticker(s: CGFloat, style: StrokeStyle) -> some View {
        let outer = Path { p in
            p.move(to: CGPoint(x: 12 * s, y: 21 * s))
            p.addCurve(to: CGPoint(x: 6 * s, y: 13.5 * s), control1: CGPoint(x: 7.5 * s, y: 21 * s), control2: CGPoint(x: 5.5 * s, y: 17.5 * s))
            p.addCurve(to: CGPoint(x: 12.5 * s, y: 3 * s), control1: CGPoint(x: 6.5 * s, y: 9 * s), control2: CGPoint(x: 11.5 * s, y: 7 * s))
            p.addCurve(to: CGPoint(x: 18 * s, y: 13.5 * s), control1: CGPoint(x: 17 * s, y: 6.5 * s), control2: CGPoint(x: 18.5 * s, y: 10.5 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 21 * s), control1: CGPoint(x: 17.5 * s, y: 17.5 * s), control2: CGPoint(x: 16.5 * s, y: 21 * s))
            p.closeSubpath()
        }
        ZStack {
            outer.fill(Color(hex: 0xF28B76))
            outer.stroke(ink, style: style)
            Ellipse()
                .fill(Color(hex: 0xFFE378))
                .frame(width: 5.5 * s, height: 7 * s)
                .offset(y: 3.5 * s)
        }
    }

    // 15. Share Sheet / Export: Pastel peach tray + upward arrow
    @ViewBuilder
    private func exportSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(Color(hex: 0xFFE9DB))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(ink, lineWidth: stroke))
                .frame(width: 16.5 * s, height: 9.5 * s)
                .offset(y: 4.5 * s)

            Path { p in
                p.move(to: CGPoint(x: 12 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 13.5 * s))
                p.move(to: CGPoint(x: 8 * s, y: 8 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 16 * s, y: 8 * s))
            }
            .stroke(ink, style: style)
        }
    }

    // 16. Warning: Honey-amber rounded triangle
    @ViewBuilder
    private func warningSticker(s: CGFloat, style: StrokeStyle) -> some View {
        let tri = Path { p in
            p.move(to: CGPoint(x: 12 * s, y: 3.5 * s))
            p.addLine(to: CGPoint(x: 20.5 * s, y: 19.5 * s))
            p.addLine(to: CGPoint(x: 3.5 * s, y: 19.5 * s))
            p.closeSubpath()
        }
        ZStack {
            tri.fill(Color(hex: 0xFFE378))
            tri.stroke(ink, style: style)
            Capsule().fill(ink).frame(width: 2 * s, height: 5.5 * s).offset(y: 0.5 * s)
            Circle().fill(ink).frame(width: 2.3 * s, height: 2.3 * s).offset(y: 5.5 * s)
        }
    }

    // 17. Connected / Checkmark: Matcha circle + cream check
    @ViewBuilder
    private func checkmarkSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x8AD6AE))
                .overlay(Circle().stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 18 * s)

            Path { p in
                p.move(to: CGPoint(x: 8 * s, y: 12.2 * s))
                p.addLine(to: CGPoint(x: 11 * s, y: 15.2 * s))
                p.addLine(to: CGPoint(x: 16.2 * s, y: 9.2 * s))
            }
            .stroke(ink, style: style)
        }
    }

    // 18. Error / Xmark: Berry coral circle + cocoa X
    @ViewBuilder
    private func xmarkSticker(s: CGFloat, stroke: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xF5A4A4))
                .overlay(Circle().stroke(ink, lineWidth: stroke))
                .frame(width: 18 * s, height: 18 * s)

            Path { p in
                p.move(to: CGPoint(x: 8.8 * s, y: 8.8 * s))
                p.addLine(to: CGPoint(x: 15.2 * s, y: 15.2 * s))
                p.move(to: CGPoint(x: 15.2 * s, y: 8.8 * s))
                p.addLine(to: CGPoint(x: 8.8 * s, y: 15.2 * s))
            }
            .stroke(ink, style: style)
        }
    }
}
