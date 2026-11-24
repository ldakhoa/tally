import SwiftUI

// Reward-loop building blocks for Budgets, Goals and Commitments: hero surface, progress ring,
// milestone bar, rolling numbers, coin burst, trophy / coin stickers, streak flame, payment dots.
// Everything animates GPU-friendly properties only and settles instantly under Reduce Motion.

// MARK: - Hero Surface

public enum CozyHeroTone: Sendable {
    case peach, mint, honey

    func gradient(dark: Bool) -> [Color] {
        switch (self, dark) {
        case (.peach, false): return [Color(hex: 0xFFE9D8), Color(hex: 0xFFF5E6)]
        case (.peach, true): return [Color(hex: 0x3A2A25), Color(hex: 0x2F2224)]
        case (.mint, false): return [Color(hex: 0xDFF4E6), Color(hex: 0xFFF8EC)]
        case (.mint, true): return [Color(hex: 0x25332B), Color(hex: 0x2A2320)]
        case (.honey, false): return [Color(hex: 0xFFEFC9), Color(hex: 0xFFF8EC)]
        case (.honey, true): return [Color(hex: 0x3B3022), Color(hex: 0x2C2320)]
        }
    }

    public var tint: Color {
        switch self {
        case .peach: return .accent
        case .mint: return .positive
        case .honey: return .caution
        }
    }
}

private struct CozyHeroSurface: ViewModifier {
    let tone: CozyHeroTone

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let isDark = colorScheme == .dark

        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(LinearGradient(
                        colors: tone.gradient(dark: isDark),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    PawPrintBackdrop(tint: tone.tint)
                }
                .clipShape(shape)
                .floatingShadow(!isDark)
            }
            .overlay {
                shape.strokeBorder(tone.tint.opacity(isDark ? 0.26 : 0.22), lineWidth: 1)
            }
    }
}

extension View {
    /// Pastel gradient hero card with the paw-print backdrop (the featured card of a screen).
    public func cozyHeroSurface(_ tone: CozyHeroTone = .peach) -> some View {
        modifier(CozyHeroSurface(tone: tone))
    }
}

// MARK: - Progress Ring

/// Circular progress that sweeps in from zero, with a bright knob riding the tip.
public struct CozyProgressRing<Center: View>: View {
    public let value: Double
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var colors: [Color]
    private let animatesOnAppear: Bool
    private let center: Center

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        value: Double,
        size: CGFloat = 84,
        lineWidth: CGFloat = 10,
        colors: [Color],
        animatesOnAppear: Bool = true,
        @ViewBuilder center: () -> Center
    ) {
        self.value = value
        self.size = size
        self.lineWidth = lineWidth
        self.colors = colors
        self.animatesOnAppear = animatesOnAppear
        self.center = center()
        _shown = State(initialValue: animatesOnAppear ? 0 : value)
    }

    public var body: some View {
        let clamped = min(1, max(0, shown))
        let gradientColors = colors.count >= 2 ? colors : [colors.first ?? .accent, colors.first ?? .accent]

        ZStack {
            Circle().stroke(Color.trackFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: gradientColors,
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(clamped, 0.05))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if clamped > 0.03 {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: lineWidth * 0.36, height: lineWidth * 0.36)
                    .offset(y: -(size - lineWidth) / 2)
                    .rotationEffect(.degrees(360 * clamped))
            }
            center
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .onAppear {
            if animatesOnAppear, shown != value { update(to: value, initial: true) }
        }
        .onChange(of: value) { _, newValue in update(to: newValue, initial: false) }
    }

    private func update(to newValue: Double, initial: Bool) {
        guard !reduceMotion else {
            shown = newValue
            return
        }
        withAnimation(.spring(response: initial ? 0.9 : 0.6, dampingFraction: 0.8).delay(initial ? 0.12 : 0)) {
            shown = newValue
        }
    }
}

// MARK: - Milestone Bar

/// Plump five-point star used for milestone markers, coins and trophies.
public struct CozyStarShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.5
        var path = Path()
        for i in 0..<10 {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = (Double(i) * 36.0 - 90.0) * .pi / 180
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Progress bar whose fill slides in (transform only), with a one-off sheen and optional star
/// markers that pop as the fill passes them. `milestones` are fractions in 0...1.
public struct CozyMilestoneBar: View {
    public let value: Double
    public var fill: Color
    public var milestones: [Double]
    public var height: CGFloat
    private let animatesOnAppear: Bool

    @State private var shown: Double = 0
    @State private var revealed = false
    @State private var sheenDone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        value: Double,
        fill: Color = .positive,
        milestones: [Double] = [],
        height: CGFloat = 12,
        animatesOnAppear: Bool = true
    ) {
        self.value = value
        self.fill = fill
        self.milestones = milestones
        self.height = height
        self.animatesOnAppear = animatesOnAppear
        _shown = State(initialValue: animatesOnAppear ? 0 : value)
        _revealed = State(initialValue: !animatesOnAppear)
        _sheenDone = State(initialValue: !animatesOnAppear)
    }

    private var markerSize: CGFloat { height + 8 }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let clamped = min(1, max(0, shown))
            let visible = clamped > 0 ? max(clamped, height / max(width, 1)) : 0

            ZStack(alignment: .leading) {
                Capsule().fill(Color.trackFill)
                Capsule()
                    .fill(LinearGradient(colors: [fill.opacity(0.72), fill], startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .leading) {
                        LinearGradient(
                            colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 54)
                        .offset(x: sheenDone ? width + 10 : -64)
                    }
                    .clipShape(Capsule())
                    .offset(x: -(1 - visible) * width)
            }
            .frame(height: height)
            .clipShape(Capsule())
            .frame(maxHeight: .infinity)
            .overlay {
                ForEach(Array(milestones.enumerated()), id: \.offset) { index, milestone in
                    let reached = revealed && value >= milestone - 0.000_1
                    marker(reached: reached)
                        .scaleEffect(reached ? 1 : 0.8)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.46).delay(0.3 + Double(index) * 0.11),
                            value: reached
                        )
                        .position(
                            x: min(max(markerSize / 2, CGFloat(milestone) * width), width - markerSize / 2),
                            y: proxy.size.height / 2
                        )
                }
            }
        }
        .frame(height: milestones.isEmpty ? height : markerSize)
        .accessibilityHidden(true)
        .onAppear {
            guard animatesOnAppear, !revealed else { return }
            if reduceMotion {
                shown = value
                revealed = true
                return
            }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { shown = value }
            revealed = true
            withAnimation(.easeInOut(duration: 1.0).delay(0.55)) { sheenDone = true }
        }
        .onChange(of: value) { _, newValue in
            if reduceMotion {
                shown = newValue
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { shown = newValue }
            }
        }
    }

    private func marker(reached: Bool) -> some View {
        ZStack {
            Circle()
                .fill(reached ? Color(hex: 0xFFD966) : Color.cardBackground)
            Circle()
                .strokeBorder(reached ? Color(hex: 0xC98A1B) : Color.hairlineStrong, lineWidth: 1.2)
            CozyStarShape()
                .fill(reached ? Color(hex: 0xFFFBEA) : Color.textSecondary.opacity(0.32))
                .padding(markerSize * 0.22)
        }
        .frame(width: markerSize, height: markerSize)
    }
}

// MARK: - Rolling Number

private struct CozyRollingNumber: View, Animatable {
    var value: Double
    let format: (Int64) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(format(Int64(value.rounded())))
    }
}

/// A figure that counts up from zero on first appearance and rolls to each new value.
public struct CozyCountUpText: View {
    public let value: Int64
    private let format: (Int64) -> String

    @State private var displayed: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Int64, format: @escaping (Int64) -> String) {
        self.value = value
        self.format = format
    }

    public var body: some View {
        CozyRollingNumber(value: displayed, format: format)
            .monospacedDigit()
            .accessibilityLabel(format(value))
            .onAppear { roll(to: value, duration: 0.85) }
            .onChange(of: value) { _, newValue in roll(to: newValue, duration: 0.55) }
    }

    private func roll(to newValue: Int64, duration: Double) {
        guard !reduceMotion else {
            displayed = Double(newValue)
            return
        }
        withAnimation(.easeOut(duration: duration)) { displayed = Double(newValue) }
    }
}

// MARK: - Coin & Trophy Stickers

/// Butter-gold coin with a cream star, matching the piggy-bank tab icon.
public struct CozyCoinView: View {
    public var size: CGFloat

    public init(size: CGFloat = 18) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle().fill(LinearGradient(
                colors: [Color(hex: 0xFFE680), Color(hex: 0xF5B959)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            Circle().strokeBorder(Color(hex: 0xA86F1C), lineWidth: max(1, size * 0.075))
            Circle()
                .strokeBorder(Color(hex: 0xFFF6D2, alpha: 0.9), lineWidth: max(0.8, size * 0.055))
                .padding(size * 0.15)
            CozyStarShape()
                .fill(Color(hex: 0xFFFBEA))
                .frame(width: size * 0.4, height: size * 0.4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Hand-drawn golden trophy cup with cocoa outline.
public struct CozyTrophyView: View {
    public var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 22) {
        self.size = size
    }

    public var body: some View {
        let s = size / 24
        let ink = colorScheme == .dark ? Color(hex: 0xFAF0E6) : Color(hex: 0x4E382F)
        let style = StrokeStyle(lineWidth: max(1.2, 1.7 * s), lineCap: .round, lineJoin: .round)

        let bowl = Path { p in
            p.move(to: CGPoint(x: 7 * s, y: 4.5 * s))
            p.addLine(to: CGPoint(x: 17 * s, y: 4.5 * s))
            p.addCurve(to: CGPoint(x: 12 * s, y: 14 * s), control1: CGPoint(x: 17 * s, y: 10.5 * s), control2: CGPoint(x: 15 * s, y: 14 * s))
            p.addCurve(to: CGPoint(x: 7 * s, y: 4.5 * s), control1: CGPoint(x: 9 * s, y: 14 * s), control2: CGPoint(x: 7 * s, y: 10.5 * s))
            p.closeSubpath()
        }
        let handles = Path { p in
            p.move(to: CGPoint(x: 7.2 * s, y: 6 * s))
            p.addQuadCurve(to: CGPoint(x: 4 * s, y: 8.2 * s), control: CGPoint(x: 3.6 * s, y: 5.8 * s))
            p.addQuadCurve(to: CGPoint(x: 8.2 * s, y: 11 * s), control: CGPoint(x: 4.6 * s, y: 10.8 * s))
            p.move(to: CGPoint(x: 16.8 * s, y: 6 * s))
            p.addQuadCurve(to: CGPoint(x: 20 * s, y: 8.2 * s), control: CGPoint(x: 20.4 * s, y: 5.8 * s))
            p.addQuadCurve(to: CGPoint(x: 15.8 * s, y: 11 * s), control: CGPoint(x: 19.4 * s, y: 10.8 * s))
        }
        let stem = Path { p in
            p.move(to: CGPoint(x: 12 * s, y: 14 * s))
            p.addLine(to: CGPoint(x: 12 * s, y: 17.2 * s))
        }
        let base = Path(
            roundedRect: CGRect(x: 7.8 * s, y: 17.2 * s, width: 8.4 * s, height: 3 * s),
            cornerRadius: 1.4 * s
        )

        ZStack {
            handles.stroke(ink, style: style)
            bowl.fill(LinearGradient(colors: [Color(hex: 0xFFE680), Color(hex: 0xF5B959)], startPoint: .top, endPoint: .bottom))
            bowl.stroke(ink, style: style)
            stem.stroke(ink, style: style)
            base.fill(Color(hex: 0xF5B959))
            base.stroke(ink, style: style)
            CozyStarShape()
                .fill(Color(hex: 0xFFFBEA))
                .frame(width: 4.6 * s, height: 4.6 * s)
                .position(x: 12 * s, y: 8.6 * s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Warm flame that breathes while a streak is alive.
public struct CozyStreakFlame: View {
    public var size: CGFloat
    public var isActive: Bool

    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat = 18, isActive: Bool = true) {
        self.size = size
        self.isActive = isActive
    }

    public var body: some View {
        CozyUIIcon(.flame, size: size, color: isActive ? Color(hex: 0xEE7B2D) : Color.textSecondary.opacity(0.6))
            .scaleEffect(pulsing ? 1.14 : 1, anchor: .bottom)
            .onAppear {
                guard isActive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Stat Tile

/// Small tinted tile for a hero card's supporting figure: glyph, value, then a caption.
public struct CozyStatTile<Icon: View>: View {
    public let value: String
    public let label: String
    public var tint: Color
    private let icon: Icon

    public init(value: String, label: String, tint: Color = .accent, @ViewBuilder icon: () -> Icon) {
        self.value = value
        self.label = label
        self.tint = tint
        self.icon = icon()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                icon
                Text(value)
                    .font(.appAmount)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
        .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Payment Dots

/// One plump segment per payment; paid ones fill in one after another and the next due one glows.
/// Falls back to a plain bar when there are too many payments to draw individually.
public struct CozyPaymentDots: View {
    public let total: Int
    public let paid: Int
    public var fill: Color
    public var maxSegments: Int
    private let animatesOnAppear: Bool

    @State private var revealed = false
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(total: Int, paid: Int, fill: Color = .accent, maxSegments: Int = 24, animatesOnAppear: Bool = true) {
        self.total = total
        self.paid = paid
        self.fill = fill
        self.maxSegments = maxSegments
        self.animatesOnAppear = animatesOnAppear
        _revealed = State(initialValue: !animatesOnAppear)
    }

    public var body: some View {
        if total < 1 || total > maxSegments {
            CozyMilestoneBar(
                value: total > 0 ? Double(paid) / Double(total) : 0,
                fill: fill,
                height: 10,
                animatesOnAppear: animatesOnAppear
            )
        } else {
            HStack(spacing: total > 12 ? 2 : 3) {
                ForEach(0..<total, id: \.self) { index in
                    let isPaid = index < paid
                    Capsule()
                        .fill(isPaid && revealed ? fill : Color.trackFill)
                        .frame(height: 10)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            if index == paid {
                                Capsule().strokeBorder(fill.opacity(glowing || !animatesOnAppear ? 0.85 : 0.35), lineWidth: 1.4)
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.25).delay(0.1 + Double(index) * 0.035),
                            value: revealed
                        )
                }
            }
            .accessibilityHidden(true)
            .onAppear {
                guard animatesOnAppear, !revealed else { return }
                revealed = true
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
        }
    }
}

// MARK: - Coin Burst Celebration

/// Fountain of gold coins and stars: fires once whenever `trigger` changes.
public struct CozyCoinBurstOverlay: View {
    public let trigger: Int
    public var coinCount: Int
    public var playsFeedback: Bool

    @State private var bursts: [CoinBurst] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(trigger: Int, coinCount: Int = 10, playsFeedback: Bool = true) {
        self.trigger = trigger
        self.coinCount = coinCount
        self.playsFeedback = playsFeedback
    }

    public var body: some View {
        ZStack {
            ForEach(bursts) { burst in
                ForEach(burst.particles) { particle in
                    CoinParticleView(particle: particle)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in fire() }
    }

    private func fire() {
        if playsFeedback {
            CozyHaptics.success()
            CozySounds.play(.coin)
        }
        guard !reduceMotion else { return }

        let burst = CoinBurst(particles: (0..<max(1, coinCount)).map { index in
            CoinParticle(
                isStar: index % 4 == 3,
                size: CGFloat.random(in: 13...21),
                startX: CGFloat.random(in: -18...18),
                driftX: CGFloat.random(in: -120...120),
                rise: CGFloat.random(in: 70...150),
                fall: CGFloat.random(in: 60...130),
                spin: Double.random(in: 360...900),
                delay: Double(index) * 0.022
            )
        })
        bursts.append(burst)
        let id = burst.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            bursts.removeAll { $0.id == id }
        }
    }
}

private struct CoinBurst: Identifiable {
    let id = UUID()
    let particles: [CoinParticle]
}

private struct CoinParticle: Identifiable {
    let id = UUID()
    let isStar: Bool
    let size: CGFloat
    let startX: CGFloat
    let driftX: CGFloat
    let rise: CGFloat
    let fall: CGFloat
    let spin: Double
    let delay: Double
}

private struct CoinParticleView: View {
    let particle: CoinParticle

    @State private var launched = false
    @State private var falling = false

    var body: some View {
        Group {
            if particle.isStar {
                CozyStarShape()
                    .fill(Color(hex: 0xFFC94D))
                    .frame(width: particle.size * 0.8, height: particle.size * 0.8)
                    .rotationEffect(.degrees(launched ? particle.spin / 4 : 0))
            } else {
                CozyCoinView(size: particle.size)
                    .rotation3DEffect(.degrees(launched ? particle.spin : 0), axis: (x: 0, y: 1, z: 0))
            }
        }
        .offset(
            x: particle.startX + (launched ? particle.driftX * 0.6 : 0) + (falling ? particle.driftX * 0.4 : 0),
            y: (launched ? -particle.rise : 0) + (falling ? particle.fall : 0)
        )
        .scaleEffect(launched ? 1 : 0.3)
        .opacity(falling ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.42).delay(particle.delay)) { launched = true }
            withAnimation(.easeIn(duration: 0.6).delay(particle.delay + 0.4)) { falling = true }
        }
    }
}
