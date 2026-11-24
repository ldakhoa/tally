import BudgetKit
import SwiftUI

// MARK: - Hand-Drawn UI, Action, Settings & KPI Icons

public enum CozyUIIconKind: String, CaseIterable, Hashable, Sendable {
    // Primary actions
    case plus
    case sparkles
    case bolt
    case trash
    case compose
    case copy
    case refresh
    case play
    case wand
    case xmark

    // Navigation & chevrons
    case chevronLeft
    case chevronRight
    case chevronDown
    case chevronUpDown
    case arrowRight
    case arrowUp
    case arrowLeftCircle
    case trendUp
    case trendDown

    // Input & composer
    case calendar
    case list
    case note
    case keypad
    case person
    case people
    case mic
    case stop
    case backspace
    case xmarkCircle
    case checkmark
    case checkmarkCircle
    case warning
    case eye
    case eyeClosed

    // Settings, KPI & transaction sources
    case sliders
    case envelope
    case cloud
    case backup
    case exportBox
    case importBox
    case key
    case creditCard
    case bell
    case message
    case pencil
    case leaf
    case flame
    case photo

    /// Maps legacy SF Symbol names used across `SettingsIconTile` and `Card` to hand-drawn cozy icons.
    public init?(sfSymbol: String) {
        switch sfSymbol {
        case "plus", "plus.circle.fill": self = .plus
        case "sparkles", "sparkle", "apple.intelligence", "sparkles.rectangle.stack": self = .sparkles
        case "wand.and.stars": self = .wand
        case "bolt.horizontal.fill", "bolt.horizontal.circle", "bolt.fill": self = .bolt
        case "trash": self = .trash
        case "square.and.pencil": self = .compose
        case "doc.on.doc": self = .copy
        case "arrow.clockwise", "arrow.triangle.2.circlepath": self = .refresh
        case "play.fill": self = .play
        case "xmark": self = .xmark
        case "chevron.left": self = .chevronLeft
        case "chevron.right": self = .chevronRight
        case "chevron.down": self = .chevronDown
        case "chevron.up.chevron.down": self = .chevronUpDown
        case "arrow.right": self = .arrowRight
        case "arrow.up": self = .arrowUp
        case "arrow.left.circle": self = .arrowLeftCircle
        case "arrow.up.right", "arrow.up.right.square", "arrow.up.forward.app.fill": self = .trendUp
        case "arrow.down.right": self = .trendDown
        case "calendar", "calendar.day.timeline.left": self = .calendar
        case "photo", "photo.on.rectangle", "photo.badge.plus": self = .photo
        case "list.bullet", "list.bullet.rectangle": self = .list
        case "note.text", "note.text.badge.plus": self = .note
        case "number.square": self = .keypad
        case "person.fill", "person.badge.plus": self = .person
        case "person.2.fill": self = .people
        case "mic.fill": self = .mic
        case "stop.fill", "stop.circle.fill": self = .stop
        case "delete.left": self = .backspace
        case "xmark.circle.fill": self = .xmarkCircle
        case "checkmark": self = .checkmark
        case "checkmark.circle.fill": self = .checkmarkCircle
        case "exclamationmark.triangle.fill", "exclamationmark": self = .warning
        case "slider.horizontal.3": self = .sliders
        case "envelope", "envelope.fill", "envelope.badge.fill": self = .envelope
        case "icloud.fill": self = .cloud
        case "arrow.up.arrow.down.circle": self = .backup
        case "square.and.arrow.up", "square.and.arrow.up.fill": self = .exportBox
        case "square.and.arrow.down": self = .importBox
        case "key.fill": self = .key
        case "creditcard.fill": self = .creditCard
        case "bell.badge.fill": self = .bell
        case "message.fill": self = .message
        case "pencil": self = .pencil
        case "leaf.fill": self = .leaf
        case "flame.fill": self = .flame
        default: return nil
        }
    }

    public static func from(source: TransactionSource) -> CozyUIIconKind {
        switch source {
        case .manual: return .pencil
        case .applePay: return .creditCard
        case .bankEmail: return .envelope
        case .bankNotification: return .bell
        case .shortcut: return .bolt
        case .aiQuickAdd: return .sparkles
        case .imported: return .importBox
        }
    }
}

public struct CozyUIIcon: View {
    public let kind: CozyUIIconKind
    public var size: CGFloat
    public var color: Color?
    public var lineWidthScale: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(
        _ kind: CozyUIIconKind,
        size: CGFloat = 18,
        color: Color? = nil,
        lineWidthScale: CGFloat = 1.0
    ) {
        self.kind = kind
        self.size = size
        self.color = color
        self.lineWidthScale = lineWidthScale
    }

    private var strokeColor: Color {
        if let color { return color }
        return colorScheme == .dark ? Color(hex: 0xFAF0E6) : Color(hex: 0x4E382F)
    }

    public var body: some View {
        let s = size / 24.0
        let lw = max(1.35, 1.85 * s * lineWidthScale)
        let style = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

        Group {
            switch kind {
            case .plus:
                plusIcon(s: s, lw: lw)
            case .sparkles:
                sparklesIcon(s: s, lw: lw)
            case .bolt:
                boltIcon(s: s, style: style)
            case .trash:
                trashIcon(s: s, style: style)
            case .compose:
                composeIcon(s: s, style: style)
            case .copy:
                copyIcon(s: s, style: style)
            case .refresh:
                refreshIcon(s: s, style: style)
            case .play:
                playIcon(s: s, style: style)
            case .wand:
                wandIcon(s: s, style: style)
            case .xmark:
                xmarkIcon(s: s, style: style)
            case .chevronLeft:
                chevronIcon(direction: .left, s: s, style: style)
            case .chevronRight:
                chevronIcon(direction: .right, s: s, style: style)
            case .chevronDown:
                chevronIcon(direction: .down, s: s, style: style)
            case .chevronUpDown:
                chevronUpDownIcon(s: s, style: style)
            case .arrowRight:
                arrowIcon(direction: .right, s: s, style: style)
            case .arrowUp:
                arrowIcon(direction: .up, s: s, style: style)
            case .arrowLeftCircle:
                arrowLeftCircleIcon(s: s, style: style)
            case .trendUp:
                trendIcon(up: true, s: s, style: style)
            case .trendDown:
                trendIcon(up: false, s: s, style: style)
            case .eye:
                eyeIcon(open: true, s: s, style: style)
            case .eyeClosed:
                eyeIcon(open: false, s: s, style: style)
            case .calendar:
                calendarIcon(s: s, style: style)
            case .list:
                listIcon(s: s, lw: lw)
            case .note:
                noteIcon(s: s, style: style)
            case .keypad:
                keypadIcon(s: s, style: style)
            case .person:
                personIcon(s: s, style: style)
            case .people:
                peopleIcon(s: s, style: style)
            case .mic:
                micIcon(s: s, style: style)
            case .stop:
                RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                    .fill(strokeColor)
                    .frame(width: 12 * s, height: 12 * s)
            case .backspace:
                backspaceIcon(s: s, style: style)
            case .xmarkCircle:
                xmarkCircleIcon(s: s, style: style)
            case .checkmark:
                checkmarkIcon(s: s, style: style)
            case .checkmarkCircle:
                checkmarkCircleIcon(s: s, style: style)
            case .warning:
                warningIcon(s: s, style: style)
            case .sliders:
                slidersIcon(s: s, style: style)
            case .envelope:
                envelopeIcon(s: s, style: style)
            case .cloud:
                cloudIcon(s: s, style: style)
            case .backup:
                backupIcon(s: s, style: style)
            case .exportBox:
                boxTransferIcon(up: true, s: s, style: style)
            case .importBox:
                boxTransferIcon(up: false, s: s, style: style)
            case .key:
                keyIcon(s: s, style: style)
            case .creditCard:
                creditCardIcon(s: s, style: style)
            case .bell:
                bellIcon(s: s, style: style)
            case .message:
                messageIcon(s: s, style: style)
            case .pencil:
                pencilIcon(s: s, style: style)
            case .leaf:
                leafIcon(s: s, style: style)
            case .flame:
                flameIcon(s: s, style: style)
            case .photo:
                photoIcon(s: s, style: style)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: - Primary Actions

    /// Plump, hand-drawn felt-tip `+` icon with soft rounded capsules.
    @ViewBuilder
    private func plusIcon(s: CGFloat, lw: CGFloat) -> some View {
        let thickness = max(2.2, 3.0 * s * lineWidthScale)
        ZStack {
            Capsule()
                .fill(strokeColor)
                .frame(width: 15.5 * s, height: thickness)
            Capsule()
                .fill(strokeColor)
                .frame(width: thickness, height: 15.5 * s)
        }
    }

    @ViewBuilder
    private func sparklesIcon(s: CGFloat, lw: CGFloat) -> some View {
        ZStack {
            CozyFourPointStarShape()
                .fill(strokeColor.opacity(0.22))
                .overlay(
                    CozyFourPointStarShape()
                        .stroke(strokeColor, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round, lineJoin: .round))
                )
                .frame(width: 15 * s, height: 15 * s)
                .offset(x: -2 * s, y: 1.5 * s)

            CozyFourPointStarShape()
                .fill(strokeColor)
                .frame(width: 7.5 * s, height: 7.5 * s)
                .offset(x: 6.5 * s, y: -6.5 * s)
        }
    }

    @ViewBuilder
    private func boltIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let bolt = Path { p in
            p.move(to: CGPoint(x: 13.5 * s, y: 2.5 * s))
            p.addLine(to: CGPoint(x: 5.5 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 11.5 * s, y: 13 * s))
            p.addLine(to: CGPoint(x: 10 * s, y: 21.5 * s))
            p.addLine(to: CGPoint(x: 18.5 * s, y: 10.5 * s))
            p.addLine(to: CGPoint(x: 12.5 * s, y: 10.5 * s))
            p.closeSubpath()
        }
        ZStack {
            bolt.fill(strokeColor.opacity(0.24))
            bolt.stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func trashIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            // Lid handle
            RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                .stroke(strokeColor, style: style)
                .frame(width: 6 * s, height: 3 * s)
                .offset(y: -8 * s)

            // Top rim
            Capsule()
                .fill(strokeColor)
                .frame(width: 17 * s, height: style.lineWidth)
                .offset(y: -5.5 * s)

            // Rounded bin body
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(strokeColor.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 13.5 * s, height: 13.5 * s)
                .offset(y: 2.5 * s)

            // Inner lines
            HStack(spacing: 3.5 * s) {
                Capsule().fill(strokeColor).frame(width: 1.5 * s, height: 6.5 * s)
                Capsule().fill(strokeColor).frame(width: 1.5 * s, height: 6.5 * s)
            }
            .offset(y: 2.5 * s)
        }
    }

    @ViewBuilder
    private func composeIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(strokeColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 16 * s, height: 16 * s)
                .offset(x: -1.5 * s, y: 1.5 * s)

            Path { p in
                p.move(to: CGPoint(x: 11 * s, y: 13 * s))
                p.addLine(to: CGPoint(x: 19.5 * s, y: 4.5 * s))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: style.lineWidth * 1.25, lineCap: .round))
        }
    }

    @ViewBuilder
    private func copyIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous)
                .stroke(strokeColor.opacity(0.75), style: style)
                .frame(width: 11.5 * s, height: 13.5 * s)
                .offset(x: -2.8 * s, y: -2.2 * s)

            RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous)
                .fill(strokeColor.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 3.5 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 11.5 * s, height: 13.5 * s)
                .offset(x: 2.8 * s, y: 2.5 * s)
        }
    }

    @ViewBuilder
    private func refreshIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .trim(from: 0.14, to: 0.88)
                .stroke(strokeColor, style: style)
                .frame(width: 15.5 * s, height: 15.5 * s)

            Path { p in
                p.move(to: CGPoint(x: 15.5 * s, y: 4.5 * s))
                p.addLine(to: CGPoint(x: 19.5 * s, y: 6.5 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 10 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func playIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let tri = Path { p in
            p.move(to: CGPoint(x: 7.5 * s, y: 5 * s))
            p.addLine(to: CGPoint(x: 18.5 * s, y: 12 * s))
            p.addLine(to: CGPoint(x: 7.5 * s, y: 19 * s))
            p.closeSubpath()
        }
        ZStack {
            tri.fill(strokeColor.opacity(0.28))
            tri.stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func wandIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 5 * s, y: 19 * s))
                p.addLine(to: CGPoint(x: 14.5 * s, y: 9.5 * s))
            }
            .stroke(strokeColor, style: StrokeStyle(lineWidth: style.lineWidth * 1.25, lineCap: .round))

            CozyFourPointStarShape()
                .fill(strokeColor.opacity(0.3))
                .overlay(CozyFourPointStarShape().stroke(strokeColor, style: style))
                .frame(width: 10 * s, height: 10 * s)
                .offset(x: 4.5 * s, y: -4.5 * s)
        }
    }

    @ViewBuilder
    private func xmarkIcon(s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 6.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 17.5 * s, y: 17.5 * s))
            p.move(to: CGPoint(x: 17.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 6.5 * s, y: 17.5 * s))
        }
        .stroke(strokeColor, style: style)
    }

    // MARK: - Navigation & Arrows

    private enum Direction { case left, right, down, up }

    @ViewBuilder
    private func chevronIcon(direction: Direction, s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            switch direction {
            case .left:
                p.move(to: CGPoint(x: 15 * s, y: 6 * s))
                p.addLine(to: CGPoint(x: 9 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 15 * s, y: 18 * s))
            case .right:
                p.move(to: CGPoint(x: 9.5 * s, y: 6 * s))
                p.addLine(to: CGPoint(x: 15.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 9.5 * s, y: 18 * s))
            case .down:
                p.move(to: CGPoint(x: 6 * s, y: 9.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 15.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 9.5 * s))
            case .up:
                p.move(to: CGPoint(x: 6 * s, y: 15 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 9 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 15 * s))
            }
        }
        .stroke(strokeColor, style: style)
    }

    @ViewBuilder
    private func chevronUpDownIcon(s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 7.5 * s, y: 9.5 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 5.5 * s))
            p.addLine(to: CGPoint(x: 16.5 * s, y: 9.5 * s))

            p.move(to: CGPoint(x: 7.5 * s, y: 14.5 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 18.5 * s))
            p.addLine(to: CGPoint(x: 16.5 * s, y: 14.5 * s))
        }
        .stroke(strokeColor, style: style)
    }

    @ViewBuilder
    private func arrowIcon(direction: Direction, s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            switch direction {
            case .right:
                p.move(to: CGPoint(x: 5.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 18.5 * s, y: 12 * s))
                p.move(to: CGPoint(x: 13.5 * s, y: 7 * s))
                p.addLine(to: CGPoint(x: 18.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 13.5 * s, y: 17 * s))
            case .up:
                p.move(to: CGPoint(x: 12 * s, y: 18.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 5.5 * s))
                p.move(to: CGPoint(x: 7 * s, y: 10.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 5.5 * s))
                p.addLine(to: CGPoint(x: 17 * s, y: 10.5 * s))
            default:
                break
            }
        }
        .stroke(strokeColor, style: style)
    }

    @ViewBuilder
    private func arrowLeftCircleIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(strokeColor.opacity(0.14))
                .overlay(Circle().stroke(strokeColor, style: style))
                .frame(width: 18 * s, height: 18 * s)

            Path { p in
                p.move(to: CGPoint(x: 15.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 8.5 * s, y: 12 * s))
                p.move(to: CGPoint(x: 11.5 * s, y: 9 * s))
                p.addLine(to: CGPoint(x: 8.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 11.5 * s, y: 15 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func trendIcon(up: Bool, s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            if up {
                p.move(to: CGPoint(x: 6 * s, y: 17.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 6.5 * s))
                p.move(to: CGPoint(x: 10.5 * s, y: 6.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 6.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 14 * s))
            } else {
                p.move(to: CGPoint(x: 6 * s, y: 6.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 17.5 * s))
                p.move(to: CGPoint(x: 10.5 * s, y: 17.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 17.5 * s))
                p.addLine(to: CGPoint(x: 18 * s, y: 10 * s))
            }
        }
        .stroke(strokeColor, style: style)
    }

    // MARK: - Input, Composer & Calendar

    @ViewBuilder
    private func eyeIcon(open: Bool, s: CGFloat, style: StrokeStyle) -> some View {
        let c = 12 * s
        ZStack {
            if open {
                // Almond-shaped eye outline
                Path { p in
                    p.move(to: CGPoint(x: 2.5 * s, y: c))
                    p.addQuadCurve(to: CGPoint(x: 21.5 * s, y: c), control: CGPoint(x: 12 * s, y: 1.5 * s))
                    p.addQuadCurve(to: CGPoint(x: 2.5 * s, y: c), control: CGPoint(x: 12 * s, y: 22.5 * s))
                }
                .fill(strokeColor.opacity(0.12))
                Path { p in
                    p.move(to: CGPoint(x: 2.5 * s, y: c))
                    p.addQuadCurve(to: CGPoint(x: 21.5 * s, y: c), control: CGPoint(x: 12 * s, y: 1.5 * s))
                    p.addQuadCurve(to: CGPoint(x: 2.5 * s, y: c), control: CGPoint(x: 12 * s, y: 22.5 * s))
                }
                .stroke(strokeColor, style: style)
                Circle()
                    .stroke(strokeColor, style: style)
                    .frame(width: 6.5 * s, height: 6.5 * s)
                Circle()
                    .fill(strokeColor)
                    .frame(width: 2.2 * s, height: 2.2 * s)
            } else {
                // Sleepy closed lid with lashes
                Path { p in
                    p.move(to: CGPoint(x: 2.5 * s, y: 9 * s))
                    p.addQuadCurve(to: CGPoint(x: 21.5 * s, y: 9 * s), control: CGPoint(x: 12 * s, y: 19.5 * s))
                }
                .stroke(strokeColor, style: style)
                Path { p in
                    p.move(to: CGPoint(x: 6.2 * s, y: 13.4 * s))
                    p.addLine(to: CGPoint(x: 4.4 * s, y: 16.4 * s))
                    p.move(to: CGPoint(x: 12 * s, y: 15.4 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
                    p.move(to: CGPoint(x: 17.8 * s, y: 13.4 * s))
                    p.addLine(to: CGPoint(x: 19.6 * s, y: 16.4 * s))
                }
                .stroke(strokeColor, style: style)
            }
        }
        .frame(width: 24 * s, height: 24 * s)
    }

    @ViewBuilder
    /// Little framed picture: rounded frame, a soft sun and two plump hills.
    private func photoIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(strokeColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 19 * s, height: 16 * s)

            Circle()
                .fill(strokeColor)
                .frame(width: 3.6 * s, height: 3.6 * s)
                .offset(x: 4.2 * s, y: -3 * s)

            Path { path in
                path.move(to: CGPoint(x: 3.5 * s, y: 17 * s))
                path.addQuadCurve(to: CGPoint(x: 10.5 * s, y: 11.2 * s), control: CGPoint(x: 6.2 * s, y: 11 * s))
                path.addQuadCurve(to: CGPoint(x: 14 * s, y: 14 * s), control: CGPoint(x: 12.6 * s, y: 11.6 * s))
                path.addQuadCurve(to: CGPoint(x: 20.5 * s, y: 16.5 * s), control: CGPoint(x: 17.4 * s, y: 12.4 * s))
            }
            .stroke(strokeColor, style: style)
            .frame(width: 24 * s, height: 24 * s)
        }
    }

    private func calendarIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            // Rounded calendar body
            RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                .fill(strokeColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 17.5 * s, height: 15.5 * s)
                .offset(y: 1.5 * s)

            // Top divider bar
            Capsule()
                .fill(strokeColor)
                .frame(width: 17 * s, height: style.lineWidth * 0.85)
                .offset(y: -2.2 * s)

            // Two ring hooks
            HStack(spacing: 6.5 * s) {
                Capsule().fill(strokeColor).frame(width: 2 * s, height: 4.5 * s)
                Capsule().fill(strokeColor).frame(width: 2 * s, height: 4.5 * s)
            }
            .offset(y: -7 * s)

            // Cute date dots
            HStack(spacing: 3 * s) {
                Circle().fill(strokeColor).frame(width: 2.3 * s, height: 2.3 * s)
                Circle().fill(strokeColor).frame(width: 2.3 * s, height: 2.3 * s)
                Circle().fill(strokeColor.opacity(0.55)).frame(width: 2.3 * s, height: 2.3 * s)
            }
            .offset(y: 3.5 * s)
        }
    }

    @ViewBuilder
    private func listIcon(s: CGFloat, lw: CGFloat) -> some View {
        VStack(spacing: 3.8 * s) {
            ForEach(0..<3, id: \.self) { idx in
                HStack(spacing: 3 * s) {
                    Circle().fill(strokeColor).frame(width: 2.8 * s, height: 2.8 * s)
                    Capsule()
                        .fill(strokeColor)
                        .frame(width: (idx == 1 ? 9.5 : 12) * s, height: max(1.6, lw))
                }
            }
        }
    }

    @ViewBuilder
    private func noteIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(strokeColor.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 16 * s, height: 17.5 * s)

            VStack(alignment: .leading, spacing: 3 * s) {
                Capsule().fill(strokeColor).frame(width: 9 * s, height: 1.7 * s)
                Capsule().fill(strokeColor.opacity(0.7)).frame(width: 7 * s, height: 1.7 * s)
                Capsule().fill(strokeColor.opacity(0.5)).frame(width: 5 * s, height: 1.7 * s)
            }
        }
    }

    @ViewBuilder
    private func keypadIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                .fill(strokeColor.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 17.5 * s, height: 17.5 * s)

            VStack(spacing: 3 * s) {
                HStack(spacing: 3 * s) {
                    Circle().fill(strokeColor).frame(width: 3 * s, height: 3 * s)
                    Circle().fill(strokeColor).frame(width: 3 * s, height: 3 * s)
                }
                HStack(spacing: 3 * s) {
                    Circle().fill(strokeColor).frame(width: 3 * s, height: 3 * s)
                    Circle().fill(strokeColor).frame(width: 3 * s, height: 3 * s)
                }
            }
        }
    }

    @ViewBuilder
    private func personIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(strokeColor.opacity(0.22))
                .overlay(Circle().stroke(strokeColor, style: style))
                .frame(width: 7.5 * s, height: 7.5 * s)
                .offset(y: -4.8 * s)

            Capsule()
                .trim(from: 0.5, to: 1.0)
                .fill(strokeColor.opacity(0.22))
                .overlay(Capsule().trim(from: 0.5, to: 1.0).stroke(strokeColor, style: style))
                .frame(width: 15 * s, height: 12 * s)
                .offset(y: 7 * s)
        }
    }

    @ViewBuilder
    private func peopleIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            personIcon(s: s * 0.78, style: StrokeStyle(lineWidth: style.lineWidth * 0.85, lineCap: .round, lineJoin: .round))
                .offset(x: 4.5 * s, y: -0.8 * s)
            personIcon(s: s * 0.88, style: style)
                .offset(x: -3 * s, y: 0.5 * s)
        }
    }

    @ViewBuilder
    private func micIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Capsule()
                .fill(strokeColor.opacity(0.24))
                .overlay(Capsule().stroke(strokeColor, style: style))
                .frame(width: 7.5 * s, height: 11.5 * s)
                .offset(y: -3 * s)

            Circle()
                .trim(from: 0.04, to: 0.46)
                .stroke(strokeColor, style: style)
                .frame(width: 13.5 * s, height: 13.5 * s)
                .offset(y: -2 * s)

            Path { p in
                p.move(to: CGPoint(x: 12 * s, y: 17 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 20.5 * s))
                p.move(to: CGPoint(x: 8.5 * s, y: 20.5 * s))
                p.addLine(to: CGPoint(x: 15.5 * s, y: 20.5 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func backspaceIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let shape = Path { p in
            p.move(to: CGPoint(x: 8.5 * s, y: 6 * s))
            p.addLine(to: CGPoint(x: 19 * s, y: 6 * s))
            p.addQuadCurve(to: CGPoint(x: 21 * s, y: 8 * s), control: CGPoint(x: 21 * s, y: 6 * s))
            p.addLine(to: CGPoint(x: 21 * s, y: 16 * s))
            p.addQuadCurve(to: CGPoint(x: 19 * s, y: 18 * s), control: CGPoint(x: 21 * s, y: 18 * s))
            p.addLine(to: CGPoint(x: 8.5 * s, y: 18 * s))
            p.addLine(to: CGPoint(x: 3.5 * s, y: 12 * s))
            p.closeSubpath()
        }
        ZStack {
            shape.fill(strokeColor.opacity(0.12))
            shape.stroke(strokeColor, style: style)
            Path { p in
                p.move(to: CGPoint(x: 11.5 * s, y: 9.5 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 14.5 * s))
                p.move(to: CGPoint(x: 16.5 * s, y: 9.5 * s))
                p.addLine(to: CGPoint(x: 11.5 * s, y: 14.5 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func xmarkCircleIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(strokeColor.opacity(0.18))
                .overlay(Circle().stroke(strokeColor, style: style))
                .frame(width: 17.5 * s, height: 17.5 * s)
            Path { p in
                p.move(to: CGPoint(x: 9 * s, y: 9 * s))
                p.addLine(to: CGPoint(x: 15 * s, y: 15 * s))
                p.move(to: CGPoint(x: 15 * s, y: 9 * s))
                p.addLine(to: CGPoint(x: 9 * s, y: 15 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func checkmarkIcon(s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 5.5 * s, y: 12.5 * s))
            p.addLine(to: CGPoint(x: 10 * s, y: 17 * s))
            p.addLine(to: CGPoint(x: 18.5 * s, y: 7.5 * s))
        }
        .stroke(strokeColor, style: style)
    }

    @ViewBuilder
    private func checkmarkCircleIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(strokeColor.opacity(0.2))
                .overlay(Circle().stroke(strokeColor, style: style))
                .frame(width: 18 * s, height: 18 * s)
            Path { p in
                p.move(to: CGPoint(x: 8 * s, y: 12.2 * s))
                p.addLine(to: CGPoint(x: 11 * s, y: 15 * s))
                p.addLine(to: CGPoint(x: 16 * s, y: 9.5 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func warningIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let tri = Path { p in
            p.move(to: CGPoint(x: 12 * s, y: 3.5 * s))
            p.addLine(to: CGPoint(x: 20.5 * s, y: 19 * s))
            p.addLine(to: CGPoint(x: 3.5 * s, y: 19 * s))
            p.closeSubpath()
        }
        ZStack {
            tri.fill(strokeColor.opacity(0.2))
            tri.stroke(strokeColor, style: style)
            Capsule()
                .fill(strokeColor)
                .frame(width: 1.9 * s, height: 5.5 * s)
                .offset(y: 0.5 * s)
            Circle()
                .fill(strokeColor)
                .frame(width: 2.2 * s, height: 2.2 * s)
                .offset(y: 5.2 * s)
        }
    }

    // MARK: - Settings, KPI & Source Icons

    @ViewBuilder
    private func slidersIcon(s: CGFloat, style: StrokeStyle) -> some View {
        VStack(spacing: 4.5 * s) {
            ZStack {
                Capsule().fill(strokeColor).frame(width: 17 * s, height: style.lineWidth * 0.85)
                Circle()
                    .fill(strokeColor)
                    .frame(width: 4.8 * s, height: 4.8 * s)
                    .offset(x: -4 * s)
            }
            ZStack {
                Capsule().fill(strokeColor).frame(width: 17 * s, height: style.lineWidth * 0.85)
                Circle()
                    .fill(strokeColor)
                    .frame(width: 4.8 * s, height: 4.8 * s)
                    .offset(x: 3.5 * s)
            }
            ZStack {
                Capsule().fill(strokeColor).frame(width: 17 * s, height: style.lineWidth * 0.85)
                Circle()
                    .fill(strokeColor)
                    .frame(width: 4.8 * s, height: 4.8 * s)
                    .offset(x: -1.5 * s)
            }
        }
    }

    @ViewBuilder
    private func envelopeIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(strokeColor.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 18.5 * s, height: 13.5 * s)

            Path { p in
                p.move(to: CGPoint(x: 4 * s, y: 7 * s))
                p.addQuadCurve(to: CGPoint(x: 12 * s, y: 12.8 * s), control: CGPoint(x: 8 * s, y: 11.2 * s))
                p.addQuadCurve(to: CGPoint(x: 20 * s, y: 7 * s), control: CGPoint(x: 16 * s, y: 11.2 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func cloudIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let cloud = Path { p in
            p.move(to: CGPoint(x: 7 * s, y: 17 * s))
            p.addCurve(to: CGPoint(x: 5 * s, y: 10.5 * s), control1: CGPoint(x: 3 * s, y: 17 * s), control2: CGPoint(x: 2.5 * s, y: 11.5 * s))
            p.addCurve(to: CGPoint(x: 14.5 * s, y: 7.5 * s), control1: CGPoint(x: 6 * s, y: 6 * s), control2: CGPoint(x: 12.5 * s, y: 5 * s))
            p.addCurve(to: CGPoint(x: 18 * s, y: 17 * s), control1: CGPoint(x: 20.5 * s, y: 7.5 * s), control2: CGPoint(x: 21.5 * s, y: 17 * s))
            p.closeSubpath()
        }
        ZStack {
            cloud.fill(strokeColor.opacity(0.2))
            cloud.stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func backupIcon(s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            // Up arrow left
            p.move(to: CGPoint(x: 8.5 * s, y: 17.5 * s))
            p.addLine(to: CGPoint(x: 8.5 * s, y: 6.5 * s))
            p.move(to: CGPoint(x: 5.5 * s, y: 9.5 * s))
            p.addLine(to: CGPoint(x: 8.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 11.5 * s, y: 9.5 * s))

            // Down arrow right
            p.move(to: CGPoint(x: 15.5 * s, y: 6.5 * s))
            p.addLine(to: CGPoint(x: 15.5 * s, y: 17.5 * s))
            p.move(to: CGPoint(x: 12.5 * s, y: 14.5 * s))
            p.addLine(to: CGPoint(x: 15.5 * s, y: 17.5 * s))
            p.addLine(to: CGPoint(x: 18.5 * s, y: 14.5 * s))
        }
        .stroke(strokeColor, style: style)
    }

    @ViewBuilder
    private func boxTransferIcon(up: Bool, s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 5 * s, y: 13 * s))
                p.addLine(to: CGPoint(x: 5 * s, y: 17.5 * s))
                p.addQuadCurve(to: CGPoint(x: 7 * s, y: 19.5 * s), control: CGPoint(x: 5 * s, y: 19.5 * s))
                p.addLine(to: CGPoint(x: 17 * s, y: 19.5 * s))
                p.addQuadCurve(to: CGPoint(x: 19 * s, y: 17.5 * s), control: CGPoint(x: 19 * s, y: 19.5 * s))
                p.addLine(to: CGPoint(x: 19 * s, y: 13 * s))

                p.move(to: CGPoint(x: 12 * s, y: 4.5 * s))
                p.addLine(to: CGPoint(x: 12 * s, y: 14.5 * s))
                if up {
                    p.move(to: CGPoint(x: 8.5 * s, y: 8 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 4.5 * s))
                    p.addLine(to: CGPoint(x: 15.5 * s, y: 8 * s))
                } else {
                    p.move(to: CGPoint(x: 8.5 * s, y: 11 * s))
                    p.addLine(to: CGPoint(x: 12 * s, y: 14.5 * s))
                    p.addLine(to: CGPoint(x: 15.5 * s, y: 11 * s))
                }
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func keyIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            Circle()
                .fill(strokeColor.opacity(0.2))
                .overlay(Circle().stroke(strokeColor, style: style))
                .frame(width: 8 * s, height: 8 * s)
                .offset(x: -5 * s)

            Path { p in
                p.move(to: CGPoint(x: 11 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 20 * s, y: 12 * s))
                p.move(to: CGPoint(x: 16.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 15.5 * s))
                p.move(to: CGPoint(x: 19.5 * s, y: 12 * s))
                p.addLine(to: CGPoint(x: 19.5 * s, y: 14.8 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func creditCardIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                .fill(strokeColor.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 4 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 19 * s, height: 13.5 * s)

            Capsule()
                .fill(strokeColor)
                .frame(width: 18.5 * s, height: 2.2 * s)
                .offset(y: -2.5 * s)

            RoundedRectangle(cornerRadius: 1.2 * s, style: .continuous)
                .fill(strokeColor.opacity(0.65))
                .frame(width: 4.5 * s, height: 3 * s)
                .offset(x: -4.8 * s, y: 2.8 * s)
        }
    }

    @ViewBuilder
    private func bellIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let bell = Path { p in
            p.move(to: CGPoint(x: 5.5 * s, y: 16 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 5 * s), control1: CGPoint(x: 7 * s, y: 12 * s), control2: CGPoint(x: 7 * s, y: 5 * s))
            p.addCurve(to: CGPoint(x: 18.5 * s, y: 16 * s), control1: CGPoint(x: 17 * s, y: 5 * s), control2: CGPoint(x: 17 * s, y: 12 * s))
            p.closeSubpath()
        }
        ZStack {
            bell.fill(strokeColor.opacity(0.2))
            bell.stroke(strokeColor, style: style)
            Circle()
                .fill(strokeColor)
                .frame(width: 3.2 * s, height: 3.2 * s)
                .offset(y: 7 * s)
        }
    }

    @ViewBuilder
    private func messageIcon(s: CGFloat, style: StrokeStyle) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                .fill(strokeColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 6 * s, style: .continuous).stroke(strokeColor, style: style))
                .frame(width: 18 * s, height: 14 * s)
                .offset(y: -1 * s)

            HStack(spacing: 3 * s) {
                Circle().fill(strokeColor).frame(width: 2.2 * s, height: 2.2 * s)
                Circle().fill(strokeColor).frame(width: 2.2 * s, height: 2.2 * s)
                Circle().fill(strokeColor).frame(width: 2.2 * s, height: 2.2 * s)
            }
            .offset(y: -1 * s)
        }
    }

    @ViewBuilder
    private func pencilIcon(s: CGFloat, style: StrokeStyle) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 5 * s, y: 19 * s))
            p.addLine(to: CGPoint(x: 7 * s, y: 13.5 * s))
            p.addLine(to: CGPoint(x: 16.5 * s, y: 4 * s))
            p.addLine(to: CGPoint(x: 20 * s, y: 7.5 * s))
            p.addLine(to: CGPoint(x: 10.5 * s, y: 17 * s))
            p.closeSubpath()
        }
        .fill(strokeColor.opacity(0.2))
        .overlay {
            Path { p in
                p.move(to: CGPoint(x: 5 * s, y: 19 * s))
                p.addLine(to: CGPoint(x: 7 * s, y: 13.5 * s))
                p.addLine(to: CGPoint(x: 16.5 * s, y: 4 * s))
                p.addLine(to: CGPoint(x: 20 * s, y: 7.5 * s))
                p.addLine(to: CGPoint(x: 10.5 * s, y: 17 * s))
                p.closeSubpath()
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func leafIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let leaf = Path { p in
            p.move(to: CGPoint(x: 6 * s, y: 18 * s))
            p.addCurve(to: CGPoint(x: 18.5 * s, y: 5.5 * s), control1: CGPoint(x: 5 * s, y: 8.5 * s), control2: CGPoint(x: 11.5 * s, y: 5 * s))
            p.addCurve(to: CGPoint(x: 6 * s, y: 18 * s), control1: CGPoint(x: 19 * s, y: 13.5 * s), control2: CGPoint(x: 13.5 * s, y: 19 * s))
            p.closeSubpath()
        }
        ZStack {
            leaf.fill(strokeColor.opacity(0.26))
            leaf.stroke(strokeColor, style: style)
            Path { p in
                p.move(to: CGPoint(x: 5.5 * s, y: 18.5 * s))
                p.addQuadCurve(to: CGPoint(x: 14.5 * s, y: 9.5 * s), control: CGPoint(x: 10.5 * s, y: 13 * s))
            }
            .stroke(strokeColor, style: style)
        }
    }

    @ViewBuilder
    private func flameIcon(s: CGFloat, style: StrokeStyle) -> some View {
        let flame = Path { p in
            p.move(to: CGPoint(x: 12 * s, y: 20.5 * s))
            p.addCurve(to: CGPoint(x: 6.5 * s, y: 13.5 * s), control1: CGPoint(x: 8 * s, y: 20.5 * s), control2: CGPoint(x: 6 * s, y: 17.5 * s))
            p.addCurve(to: CGPoint(x: 12.5 * s, y: 3.5 * s), control1: CGPoint(x: 7 * s, y: 9.5 * s), control2: CGPoint(x: 11.5 * s, y: 7.5 * s))
            p.addCurve(to: CGPoint(x: 17.5 * s, y: 13.5 * s), control1: CGPoint(x: 16.5 * s, y: 7 * s), control2: CGPoint(x: 18 * s, y: 10.5 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 20.5 * s), control1: CGPoint(x: 17 * s, y: 17.5 * s), control2: CGPoint(x: 16 * s, y: 20.5 * s))
            p.closeSubpath()
        }
        ZStack {
            flame.fill(strokeColor.opacity(0.28))
            flame.stroke(strokeColor, style: style)
        }
    }
}
