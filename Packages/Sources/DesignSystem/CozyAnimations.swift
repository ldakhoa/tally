import SwiftUI

#if os(iOS)
import UIKit
#endif

// MARK: - Pre-Warmed Zero-Lag Haptics

@MainActor
public enum CozyHaptics {
    #if os(iOS)
    private static let selectionGenerator: UISelectionFeedbackGenerator = {
        let g = UISelectionFeedbackGenerator()
        g.prepare()
        return g
    }()

    private static let lightGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    private static let softGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        return g
    }()

    private static let mediumGenerator: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .medium)
        g.prepare()
        return g
    }()

    private static let notificationGenerator: UINotificationFeedbackGenerator = {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        return g
    }()
    #endif

    public static func selection() {
        #if os(iOS)
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
        #endif
    }

    public static func light() {
        #if os(iOS)
        lightGenerator.impactOccurred()
        lightGenerator.prepare()
        #endif
    }

    public static func soft() {
        #if os(iOS)
        softGenerator.impactOccurred()
        softGenerator.prepare()
        #endif
    }

    public static func medium() {
        #if os(iOS)
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare()
        #endif
    }

    public static func success() {
        #if os(iOS)
        notificationGenerator.notificationOccurred(.success)
        notificationGenerator.prepare()
        #endif
    }
}

// MARK: - Cozy Entrance Animation (GPU-Only, Fires Once)

public struct CozyEntranceModifier: ViewModifier {
    public let index: Int

    @State private var appeared = false

    public init(index: Int = 0) {
        self.index = index
    }

    public func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .scaleEffect(appeared ? 1 : 0.985)
            .onAppear {
                guard !appeared else { return }
                let delay = min(Double(index) * 0.04, 0.24)
                withAnimation(.spring(response: 0.44, dampingFraction: 0.84).delay(delay)) {
                    appeared = true
                }
            }
    }
}

// MARK: - Tactile Bouncy Card Press Style (GPU-Only)

public struct CozyCardButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.58), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CozyCardButtonStyle {
    public static var cozyCard: CozyCardButtonStyle { CozyCardButtonStyle() }
}

extension View {
    public func cozyEntrance(index: Int = 0) -> some View {
        modifier(CozyEntranceModifier(index: index))
    }
}

// MARK: - Subtle Decorative Paw Prints Backdrop

public struct PawPrintBackdrop: View {
    public var tint: Color

    public init(tint: Color = .accent) {
        self.tint = tint
    }

    public var body: some View {
        ZStack {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 38))
                .foregroundStyle(tint.opacity(0.07))
                .rotationEffect(.degrees(-22))
                .offset(x: 118, y: -42)

            Image(systemName: "pawprint.fill")
                .font(.system(size: 24))
                .foregroundStyle(tint.opacity(0.06))
                .rotationEffect(.degrees(18))
                .offset(x: 146, y: 12)

            Image(systemName: "pawprint.fill")
                .font(.system(size: 28))
                .foregroundStyle(tint.opacity(0.05))
                .rotationEffect(.degrees(-14))
                .offset(x: -115, y: 46)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lightweight Celebratory Paw & Heart Burst

public struct CozyCelebrationOverlay: View {
    public let trigger: Int

    @State private var particles: [BurstParticle] = []

    public init(trigger: Int) {
        self.trigger = trigger
    }

    public var body: some View {
        ZStack {
            ForEach(particles) { p in
                Image(systemName: p.symbol)
                    .font(.system(size: p.size, weight: .bold))
                    .foregroundStyle(p.color)
                    .offset(x: p.animate ? p.endX : p.startX, y: p.animate ? p.endY : 0)
                    .rotationEffect(.degrees(p.animate ? p.rotation : 0))
                    .scaleEffect(p.animate ? 1.1 : 0.35)
                    .opacity(p.animate ? 0 : 0.95)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            fireBurst()
        }
    }

    private func fireBurst() {
        CozyHaptics.success()
        CozySounds.play(.success)
        let symbols = ["pawprint.fill", "heart.fill", "sparkle", "heart.fill", "pawprint.fill", "sparkle"]
        let colors: [Color] = [
            Color(hex: 0xE67360),
            Color(hex: 0xF27D8D),
            Color(hex: 0xF5B959),
            Color(hex: 0x6EC492),
            Color(hex: 0x9C7FD1),
            Color(hex: 0xF2A92C)
        ]

        let batch = (0..<6).map { i in
            BurstParticle(
                symbol: symbols[i],
                color: colors[i],
                size: CGFloat.random(in: 14...20),
                startX: CGFloat.random(in: -30...30),
                endX: CGFloat.random(in: -110...110),
                endY: CGFloat.random(in: -170 ... -85),
                rotation: Double.random(in: -40...40)
            )
        }
        particles.append(contentsOf: batch)

        for item in batch {
            withAnimation(.easeOut(duration: 0.9)) {
                if let idx = particles.firstIndex(where: { $0.id == item.id }) {
                    particles[idx].animate = true
                }
            }
        }

        let ids = Set(batch.map(\.id))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            particles.removeAll { ids.contains($0.id) }
        }
    }
}

private struct BurstParticle: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let size: CGFloat
    let startX: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let rotation: Double
    var animate = false
}
