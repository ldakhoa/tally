import SwiftUI

#if os(iOS)
import UIKit
#endif

public enum PetMood: Equatable, Sendable {
    case happy
    case cozy
    case sleepy
    case alert
}

private let cozyPetInk = Color(hex: 0x4E382F)

// MARK: - Cute Hand-Drawn Golden Puppy (Matching AppIcon.png)

public struct ShibaPuppyView: View {
    public var mood: PetMood
    public var size: CGFloat
    public var isBouncing: Bool

    public init(mood: PetMood = .cozy, size: CGFloat = 68, isBouncing: Bool = false) {
        self.mood = mood
        self.size = size
        self.isBouncing = isBouncing
    }

    public var body: some View {
        let s = size / 68.0
        let stroke = max(1.1, 2.35 * s)
        let lineStyle = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)

        ZStack {
            // Plump curved golden tail tucked on the left side
            PuppyTailShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xF2BF72), Color(hex: 0xE3A04F)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(PuppyTailShape().stroke(cozyPetInk, style: lineStyle))
                .frame(width: 14 * s, height: 22 * s)
                .offset(x: -24 * s, y: 12 * s)
                .rotationEffect(.degrees(isBouncing ? -24 : -10), anchor: .bottomTrailing)

            // Left floppy drop ear
            FloppyPuppyEarShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xECA955), Color(hex: 0xDF9442)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(FloppyPuppyEarShape().stroke(cozyPetInk, style: lineStyle))
                .frame(width: 17 * s, height: 28 * s)
                .offset(x: -24 * s, y: -3 * s)
                .rotationEffect(.degrees(mood == .alert || isBouncing ? 14 : 6), anchor: .topTrailing)

            // Right floppy drop ear
            FloppyPuppyEarShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xECA955), Color(hex: 0xDF9442)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(FloppyPuppyEarShape().stroke(cozyPetInk, style: lineStyle))
                .scaleEffect(x: -1, y: 1)
                .frame(width: 17 * s, height: 28 * s)
                .offset(x: 24 * s, y: -3 * s)
                .rotationEffect(.degrees(mood == .alert || isBouncing ? -14 : -6), anchor: .topLeading)

            // Plump round golden head with tiny top hair tuft & warm cocoa outline
            ZStack {
                PuppyHeadSilhouette()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFCE0A2), Color(hex: 0xF2BE70)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Soft cream snout glow blended smoothly (no harsh oval seam)
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xFFF7E8, alpha: 0.92), Color(hex: 0xFFF7E8, alpha: 0)],
                            center: .center,
                            startRadius: 2 * s,
                            endRadius: 20 * s
                        )
                    )
                    .frame(width: 38 * s, height: 24 * s)
                    .offset(y: 11 * s)

                PuppyHeadSilhouette()
                    .stroke(cozyPetInk, style: lineStyle)
            }
            .frame(width: 52 * s, height: 48 * s)
            .offset(y: -1 * s)

            // Soft rosy cheeks
            HStack(spacing: 26 * s) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xF5969A, alpha: 0.68), Color(hex: 0xF5969A, alpha: 0)],
                            center: .center,
                            startRadius: 1 * s,
                            endRadius: 6 * s
                        )
                    )
                    .frame(width: 11 * s, height: 9 * s)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xF5969A, alpha: 0.68), Color(hex: 0xF5969A, alpha: 0)],
                            center: .center,
                            startRadius: 1 * s,
                            endRadius: 6 * s
                        )
                    )
                    .frame(width: 11 * s, height: 9 * s)
            }
            .offset(y: 7 * s)

            // Alert eyebrows (subtle cocoa arcs)
            if mood == .alert {
                HStack(spacing: 14 * s) {
                    Capsule()
                        .fill(cozyPetInk)
                        .frame(width: 6 * s, height: max(1.1, 1.8 * s))
                        .rotationEffect(.degrees(-14))
                    Capsule()
                        .fill(cozyPetInk)
                        .frame(width: 6 * s, height: max(1.1, 1.8 * s))
                        .rotationEffect(.degrees(14))
                }
                .offset(y: -7 * s)
            }

            // Expressive mood eyes
            HStack(spacing: 15 * s) {
                puppyEye(scale: s, stroke: stroke)
                puppyEye(scale: s, stroke: stroke)
            }
            .offset(y: 0.5 * s)

            // Cute dark cocoa nose + :3 smile + cheerful rosy tongue
            VStack(spacing: 1.5 * s) {
                Ellipse()
                    .fill(cozyPetInk)
                    .frame(width: 7 * s, height: 4.8 * s)

                if mood == .happy || isBouncing {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(Color(hex: 0xF48490))
                            .overlay(Capsule().stroke(cozyPetInk, lineWidth: max(0.9, stroke * 0.65)))
                            .frame(width: 5.5 * s, height: 6 * s)
                            .offset(y: 4 * s)

                        PetMouthShape()
                            .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.1, stroke * 0.85), lineCap: .round, lineJoin: .round))
                            .frame(width: 11.5 * s, height: 4.5 * s)
                    }
                } else if mood == .alert {
                    Circle()
                        .fill(Color(hex: 0xF48490))
                        .overlay(Circle().stroke(cozyPetInk, lineWidth: max(1.0, stroke * 0.72)))
                        .frame(width: 4.8 * s, height: 4.8 * s)
                        .offset(y: 1 * s)
                } else {
                    PetMouthShape()
                        .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.1, stroke * 0.85), lineCap: .round, lineJoin: .round))
                        .frame(width: 11.5 * s, height: 4.5 * s)
                }
            }
            .offset(y: 9.5 * s)

            // Coral collar + golden bell with horizontal slit
            ZStack {
                Capsule()
                    .fill(Color(hex: 0xE66F5E))
                    .overlay(Capsule().stroke(cozyPetInk, lineWidth: max(1.0, stroke * 0.85)))
                    .frame(width: 28 * s, height: 5.2 * s)
                    .offset(y: -1 * s)

                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFE066))
                        .overlay(Circle().stroke(cozyPetInk, lineWidth: max(1.0, stroke * 0.82)))
                        .frame(width: 8 * s, height: 8 * s)
                    Capsule()
                        .fill(cozyPetInk)
                        .frame(width: 3.6 * s, height: max(0.9, 1.3 * s))
                }
                .offset(y: 2.5 * s)
            }
            .offset(y: 23.5 * s)
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .offset(y: isBouncing ? -8 * s : 0)
        .scaleEffect(isBouncing ? 1.06 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.48), value: isBouncing)
    }

    @ViewBuilder
    private func puppyEye(scale s: CGFloat, stroke: CGFloat) -> some View {
        switch mood {
        case .happy:
            HappyEyeArc()
                .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.3, stroke * 0.95), lineCap: .round))
                .frame(width: 8.5 * s, height: 4.8 * s)
        case .sleepy:
            ClosedEyeArc()
                .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.2, stroke * 0.9), lineCap: .round))
                .frame(width: 8 * s, height: 4.2 * s)
        case .cozy, .alert:
            ZStack {
                Circle()
                    .fill(cozyPetInk)
                    .frame(width: 6.5 * s, height: 6.5 * s)
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.3 * s, height: 2.3 * s)
                    .offset(x: -1.3 * s, y: -1.4 * s)
            }
        }
    }
}

// MARK: - Cute Hand-Drawn Calico Cream Kitty (Matching AppIcon.png)

public struct CreamKittyView: View {
    public var mood: PetMood
    public var size: CGFloat
    public var isBouncing: Bool

    public init(mood: PetMood = .cozy, size: CGFloat = 68, isBouncing: Bool = false) {
        self.mood = mood
        self.size = size
        self.isBouncing = isBouncing
    }

    public var body: some View {
        let s = size / 68.0
        let stroke = max(1.1, 2.35 * s)
        let lineStyle = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)

        ZStack {
            // Curled cream-apricot kitty tail on the right side
            KittyCurledTailShape()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFFDF9), Color(hex: 0xF5C794)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .overlay(KittyCurledTailShape().stroke(cozyPetInk, style: lineStyle))
                .frame(width: 14 * s, height: 22 * s)
                .offset(x: 24 * s, y: 12 * s)
                .rotationEffect(.degrees(isBouncing ? 18 : 6), anchor: .bottomLeading)

            // Left pointy rounded kitty ear (cream)
            KittyEarShape()
                .fill(Color(hex: 0xFFFFFF))
                .overlay(
                    KittyEarShape()
                        .fill(Color(hex: 0xFAC3C8))
                        .frame(width: 10.5 * s, height: 12 * s)
                        .offset(y: 2.5 * s)
                )
                .overlay(KittyEarShape().stroke(cozyPetInk, style: lineStyle))
                .frame(width: 18 * s, height: 20 * s)
                .offset(x: -16 * s, y: -18.5 * s)
                .rotationEffect(.degrees(-14))

            // Right pointy rounded kitty ear (warm apricot)
            KittyEarShape()
                .fill(Color(hex: 0xF4BC86))
                .overlay(
                    KittyEarShape()
                        .fill(Color(hex: 0xFAC3C8))
                        .frame(width: 10.5 * s, height: 12 * s)
                        .offset(y: 2.5 * s)
                )
                .overlay(KittyEarShape().stroke(cozyPetInk, style: lineStyle))
                .frame(width: 18 * s, height: 20 * s)
                .offset(x: 16 * s, y: -18.5 * s)
                .rotationEffect(.degrees(14))

            // Plump cream head with signature apricot forehead patch & crisp cocoa outline
            ZStack {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFFFFF), Color(hex: 0xFDF3E7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Ellipse()
                    .fill(Color(hex: 0xF5C08D))
                    .frame(width: 24 * s, height: 18 * s)
                    .offset(x: 14 * s, y: -14 * s)
            }
            .clipShape(Ellipse())
            .overlay(Ellipse().stroke(cozyPetInk, style: lineStyle))
            .frame(width: 54 * s, height: 45 * s)
            .offset(y: 1 * s)

            // Delicate cocoa whiskers on left & right sides
            HStack(spacing: 40 * s) {
                VStack(spacing: 3.5 * s) {
                    Capsule().fill(cozyPetInk.opacity(0.72)).frame(width: 9.5 * s, height: max(1.0, 1.45 * s)).rotationEffect(.degrees(8))
                    Capsule().fill(cozyPetInk.opacity(0.72)).frame(width: 9.5 * s, height: max(1.0, 1.45 * s)).rotationEffect(.degrees(-6))
                }
                VStack(spacing: 3.5 * s) {
                    Capsule().fill(cozyPetInk.opacity(0.72)).frame(width: 9.5 * s, height: max(1.0, 1.45 * s)).rotationEffect(.degrees(-8))
                    Capsule().fill(cozyPetInk.opacity(0.72)).frame(width: 9.5 * s, height: max(1.0, 1.45 * s)).rotationEffect(.degrees(6))
                }
            }
            .offset(y: 8 * s)

            // Soft rosy cheeks
            HStack(spacing: 26 * s) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xF7A3AF, alpha: 0.72), Color(hex: 0xF7A3AF, alpha: 0)],
                            center: .center,
                            startRadius: 1 * s,
                            endRadius: 6 * s
                        )
                    )
                    .frame(width: 11 * s, height: 8.5 * s)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0xF7A3AF, alpha: 0.72), Color(hex: 0xF7A3AF, alpha: 0)],
                            center: .center,
                            startRadius: 1 * s,
                            endRadius: 6 * s
                        )
                    )
                    .frame(width: 11 * s, height: 8.5 * s)
            }
            .offset(y: 7.5 * s)

            // Expressive mood eyes
            HStack(spacing: 15.5 * s) {
                kittyEye(scale: s, stroke: stroke)
                kittyEye(scale: s, stroke: stroke)
            }
            .offset(y: 0.5 * s)

            // Pink nose + crisp :3 cocoa mouth
            VStack(spacing: 1.2 * s) {
                KittyNoseShape()
                    .fill(Color(hex: 0xF28D97))
                    .overlay(KittyNoseShape().stroke(cozyPetInk, lineWidth: max(0.8, stroke * 0.55)))
                    .frame(width: 6.2 * s, height: 4.2 * s)

                PetMouthShape()
                    .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.1, stroke * 0.85), lineCap: .round, lineJoin: .round))
                    .frame(width: 11 * s, height: 4.5 * s)
            }
            .offset(y: 8.5 * s)

            // Matcha-mint collar + golden bell with horizontal slit
            ZStack {
                Capsule()
                    .fill(Color(hex: 0x6FBC9A))
                    .overlay(Capsule().stroke(cozyPetInk, lineWidth: max(1.0, stroke * 0.85)))
                    .frame(width: 26 * s, height: 5 * s)
                    .offset(y: -1 * s)

                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFFE066))
                        .overlay(Circle().stroke(cozyPetInk, lineWidth: max(1.0, stroke * 0.82)))
                        .frame(width: 7.5 * s, height: 7.5 * s)
                    Capsule()
                        .fill(cozyPetInk)
                        .frame(width: 3.4 * s, height: max(0.9, 1.2 * s))
                }
                .offset(y: 2.3 * s)
            }
            .offset(y: 23.5 * s)
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .offset(y: isBouncing ? -9 * s : 0)
        .scaleEffect(isBouncing ? 1.06 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.48), value: isBouncing)
    }

    @ViewBuilder
    private func kittyEye(scale s: CGFloat, stroke: CGFloat) -> some View {
        switch mood {
        case .happy:
            HappyEyeArc()
                .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.3, stroke * 0.95), lineCap: .round))
                .frame(width: 8.5 * s, height: 4.8 * s)
        case .sleepy:
            ClosedEyeArc()
                .stroke(cozyPetInk, style: StrokeStyle(lineWidth: max(1.2, stroke * 0.9), lineCap: .round))
                .frame(width: 8 * s, height: 4.2 * s)
        case .cozy, .alert:
            ZStack {
                Circle()
                    .fill(cozyPetInk)
                    .frame(width: 6.4 * s, height: 6.4 * s)
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.2 * s, height: 2.2 * s)
                    .offset(x: -1.3 * s, y: -1.4 * s)
            }
        }
    }
}

// MARK: - Interactive Couple Pet Duo (Puppy + Kitty with tap hearts!)

public struct CozyPetDuoView: View {
    public var mood: PetMood
    public var petSize: CGFloat

    @State private var isBouncing = false
    @State private var hearts: [FloatingParticle] = []

    public init(mood: PetMood = .cozy, petSize: CGFloat = 60) {
        self.mood = mood
        self.petSize = petSize
    }

    public var body: some View {
        ZStack {
            // Floating hearts & sparkles on tap
            ForEach(hearts) { item in
                particleView(item)
                    .offset(x: item.x, y: item.animate ? -46 : -6)
                    .scaleEffect(item.animate ? 1.15 : 0.4)
                    .opacity(item.animate ? 0 : 0.95)
            }

            HStack(spacing: -4) {
                ShibaPuppyView(mood: mood, size: petSize, isBouncing: isBouncing)
                CreamKittyView(mood: mood, size: petSize, isBouncing: isBouncing)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            triggerLoveBurst()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Puppy and Kitty companions")
        .accessibilityHint("Tap to pet them")
    }

    @ViewBuilder
    private func particleView(_ item: FloatingParticle) -> some View {
        switch item.kind {
        case .heart:
            CozyHeartShape()
                .fill(item.color)
                .frame(width: item.size, height: item.size)
        case .sparkle:
            CozyFourPointStarShape()
                .fill(item.color)
                .frame(width: item.size, height: item.size)
        case .paw:
            Image(systemName: "pawprint.fill")
                .font(.system(size: item.size, weight: .bold))
                .foregroundStyle(item.color)
        }
    }

    private func triggerLoveBurst() {
        CozyHaptics.soft()
        CozySounds.play(.love)

        isBouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            isBouncing = false
        }

        let kinds: [ParticleKind] = [.heart, .paw, .sparkle]
        let colors: [Color] = [Color(hex: 0xF27D8D), Color(hex: 0xF5B959), Color(hex: 0xE67360)]
        let newBatch = (0..<4).map { idx in
            FloatingParticle(
                kind: kinds[idx % kinds.count],
                color: colors[idx % colors.count],
                x: CGFloat.random(in: -34...34),
                size: CGFloat.random(in: 11...15)
            )
        }
        hearts.append(contentsOf: newBatch)

        for particle in newBatch {
            withAnimation(.easeOut(duration: 0.95)) {
                if let index = hearts.firstIndex(where: { $0.id == particle.id }) {
                    hearts[index].animate = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hearts.removeAll { $0.id == particle.id }
            }
        }
    }
}

private enum ParticleKind {
    case heart, paw, sparkle
}

private struct FloatingParticle: Identifiable {
    let id = UUID()
    let kind: ParticleKind
    let color: Color
    let x: CGFloat
    let size: CGFloat
    var animate: Bool = false
}

// MARK: - Vector Shapes

private struct PuppyHeadSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        // Start left-center, sweep up past the top hair tuft, around right cheek, and back across chin
        p.move(to: CGPoint(x: w * 0.04, y: h * 0.56))
        p.addCurve(
            to: CGPoint(x: w * 0.43, y: h * 0.09),
            control1: CGPoint(x: w * 0.02, y: h * 0.24),
            control2: CGPoint(x: w * 0.22, y: h * 0.10)
        )
        // Little top hair tuft (cowlick)
        p.addQuadCurve(to: CGPoint(x: w * 0.48, y: h * 0.01), control: CGPoint(x: w * 0.45, y: h * 0.03))
        p.addQuadCurve(to: CGPoint(x: w * 0.53, y: h * 0.07), control: CGPoint(x: w * 0.50, y: h * 0.05))
        p.addQuadCurve(to: CGPoint(x: w * 0.59, y: h * 0.02), control: CGPoint(x: w * 0.56, y: h * 0.03))
        p.addQuadCurve(to: CGPoint(x: w * 0.61, y: h * 0.10), control: CGPoint(x: w * 0.60, y: h * 0.06))
        // Right side & plump cheeks
        p.addCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.56),
            control1: CGPoint(x: w * 0.80, y: h * 0.12),
            control2: CGPoint(x: w * 0.98, y: h * 0.26)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.98),
            control1: CGPoint(x: w * 0.96, y: h * 0.84),
            control2: CGPoint(x: w * 0.76, y: h * 0.98)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.56),
            control1: CGPoint(x: w * 0.24, y: h * 0.98),
            control2: CGPoint(x: w * 0.04, y: h * 0.84)
        )
        p.closeSubpath()
        return p
    }
}

private struct FloppyPuppyEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.78, y: h * 0.06))
        p.addCurve(
            to: CGPoint(x: w * 0.14, y: h * 0.58),
            control1: CGPoint(x: w * 0.34, y: h * 0.06),
            control2: CGPoint(x: w * 0.06, y: h * 0.30)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.94),
            control1: CGPoint(x: w * 0.18, y: h * 0.86),
            control2: CGPoint(x: w * 0.48, y: h * 1.00)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.06),
            control1: CGPoint(x: w * 0.96, y: h * 0.82),
            control2: CGPoint(x: w * 0.98, y: h * 0.32)
        )
        p.closeSubpath()
        return p
    }
}

private struct PuppyTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.88, y: h * 0.90))
        p.addCurve(
            to: CGPoint(x: w * 0.14, y: h * 0.28),
            control1: CGPoint(x: w * 0.20, y: h * 0.88),
            control2: CGPoint(x: w * 0.04, y: h * 0.54)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.66, y: h * 0.10),
            control1: CGPoint(x: w * 0.22, y: h * 0.04),
            control2: CGPoint(x: w * 0.54, y: h * 0.02)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.90),
            control1: CGPoint(x: w * 0.84, y: h * 0.26),
            control2: CGPoint(x: w * 0.96, y: h * 0.60)
        )
        p.closeSubpath()
        return p
    }
}

private struct KittyEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.04))
        p.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.94), control: CGPoint(x: w * 0.92, y: h * 0.34))
        p.addQuadCurve(to: CGPoint(x: w * 0.06, y: h * 0.94), control: CGPoint(x: w * 0.50, y: h * 0.98))
        p.addQuadCurve(to: CGPoint(x: w * 0.50, y: h * 0.04), control: CGPoint(x: w * 0.08, y: h * 0.34))
        p.closeSubpath()
        return p
    }
}

private struct KittyCurledTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.12, y: h * 0.90))
        p.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.24),
            control1: CGPoint(x: w * 0.82, y: h * 0.92),
            control2: CGPoint(x: w * 0.98, y: h * 0.52)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.36, y: h * 0.10),
            control1: CGPoint(x: w * 0.82, y: h * 0.04),
            control2: CGPoint(x: w * 0.48, y: h * 0.02)
        )
        p.addCurve(
            to: CGPoint(x: w * 0.12, y: h * 0.90),
            control1: CGPoint(x: w * 0.18, y: h * 0.24),
            control2: CGPoint(x: w * 0.06, y: h * 0.60)
        )
        p.closeSubpath()
        return p
    }
}

private struct KittyNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.35)
        )
        path.closeSubpath()
        return path
    }
}

private struct PetMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.2),
            control: CGPoint(x: rect.width * 0.25, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
            control: CGPoint(x: rect.width * 0.75, y: rect.maxY)
        )
        return path
    }
}

private struct ClosedEyeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.4)
        )
        return path
    }
}

private struct HappyEyeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3)
        )
        return path
    }
}
