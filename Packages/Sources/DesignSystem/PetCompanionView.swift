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

// MARK: - Cute Animated Shiba Puppy

public struct ShibaPuppyView: View {
    public var mood: PetMood
    public var size: CGFloat
    public var isBouncing: Bool

    @State private var isBlinking = false
    @State private var breathe = false
    @State private var earWiggle = false
    @State private var tailWag = false

    public init(mood: PetMood = .cozy, size: CGFloat = 68, isBouncing: Bool = false) {
        self.mood = mood
        self.size = size
        self.isBouncing = isBouncing
    }

    public var body: some View {
        let s = size / 68.0
        ZStack {
            // Wagging tail behind
            Capsule()
                .fill(Color(hex: 0xDF9651))
                .frame(width: 10 * s, height: 22 * s)
                .overlay(
                    Capsule()
                        .fill(Color(hex: 0xFFF5E6))
                        .frame(width: 6 * s, height: 8 * s)
                        .offset(y: -6 * s)
                )
                .offset(x: 22 * s, y: 12 * s)
                .rotationEffect(.degrees(tailWag ? 26 : 6), anchor: .bottom)

            // Left ear
            PuppyEarShape()
                .fill(Color(hex: 0xDF9651))
                .frame(width: 20 * s, height: 24 * s)
                .overlay(
                    PuppyEarShape()
                        .fill(Color(hex: 0xF7B8B0))
                        .frame(width: 11 * s, height: 14 * s)
                        .offset(y: 3 * s)
                )
                .offset(x: -17 * s, y: -20 * s)
                .rotationEffect(.degrees((mood == .alert ? -26 : -16) + (earWiggle ? -5 : 2)), anchor: .bottom)

            // Right ear
            PuppyEarShape()
                .fill(Color(hex: 0xDF9651))
                .frame(width: 20 * s, height: 24 * s)
                .overlay(
                    PuppyEarShape()
                        .fill(Color(hex: 0xF7B8B0))
                        .frame(width: 11 * s, height: 14 * s)
                        .offset(y: 3 * s)
                )
                .offset(x: 17 * s, y: -20 * s)
                .rotationEffect(.degrees((mood == .alert ? 26 : 16) + (earWiggle ? 5 : -2)), anchor: .bottom)

            // Head base
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xF2B872), Color(hex: 0xE39B54)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 56 * s, height: 48 * s)
                .offset(y: 2 * s)

            // Cream cheeks & snout mask (classic Shiba look)
            Ellipse()
                .fill(Color(hex: 0xFFF6E9))
                .frame(width: 44 * s, height: 26 * s)
                .offset(y: 12 * s)

            // Cute cream eyebrows
            HStack(spacing: 14 * s) {
                Capsule()
                    .fill(Color(hex: 0xFFF6E9))
                    .frame(width: 7 * s, height: 4 * s)
                    .rotationEffect(.degrees(mood == .alert ? -14 : 0))
                Capsule()
                    .fill(Color(hex: 0xFFF6E9))
                    .frame(width: 7 * s, height: 4 * s)
                    .rotationEffect(.degrees(mood == .alert ? 14 : 0))
            }
            .offset(y: -8 * s)

            // Rosy cheeks
            HStack(spacing: 28 * s) {
                Ellipse()
                    .fill(Color(hex: 0xF59B9B, alpha: 0.55))
                    .frame(width: 10 * s, height: 6 * s)
                Ellipse()
                    .fill(Color(hex: 0xF59B9B, alpha: 0.55))
                    .frame(width: 10 * s, height: 6 * s)
            }
            .offset(y: 8 * s)

            // Eyes
            HStack(spacing: 16 * s) {
                petEye(scale: s)
                petEye(scale: s)
            }
            .offset(y: 1 * s)

            // Snout: cute dark cocoa nose + smile
            VStack(spacing: 1 * s) {
                Ellipse()
                    .fill(Color(hex: 0x3D2820))
                    .frame(width: 8 * s, height: 5.5 * s)

                if mood == .happy || isBouncing {
                    // Happy open smile with tiny pink tongue
                    ZStack(alignment: .bottom) {
                        PetMouthShape()
                            .stroke(Color(hex: 0x3D2820), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                            .frame(width: 12 * s, height: 5 * s)
                        Capsule()
                            .fill(Color(hex: 0xF48B94))
                            .frame(width: 5.5 * s, height: 6 * s)
                            .offset(y: 3.5 * s)
                    }
                } else if mood == .alert {
                    Circle()
                        .stroke(Color(hex: 0x3D2820), lineWidth: 1.6 * s)
                        .frame(width: 5 * s, height: 5 * s)
                        .offset(y: 1 * s)
                } else {
                    PetMouthShape()
                        .stroke(Color(hex: 0x3D2820), style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                        .frame(width: 12 * s, height: 5 * s)
                }
            }
            .offset(y: 10 * s)

            // Little collar with gold bell
            Capsule()
                .fill(Color(hex: 0xE67360))
                .frame(width: 28 * s, height: 5 * s)
                .offset(y: 25 * s)
            Circle()
                .fill(Color(hex: 0xF7C957))
                .frame(width: 7 * s, height: 7 * s)
                .overlay(Circle().stroke(Color(hex: 0xC99327), lineWidth: 0.8 * s))
                .offset(y: 27 * s)
        }
        .frame(width: size, height: size)
        .scaleEffect(x: breathe ? 1.02 : 0.99, y: breathe ? 0.985 : 1.015, anchor: .bottom)
        .offset(y: isBouncing ? -9 * s : (breathe ? 1 * s : -1.5 * s))
        .animation(.spring(response: 0.32, dampingFraction: 0.45), value: isBouncing)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: mood == .happy ? 0.38 : 0.9).repeatForever(autoreverses: true)) {
                tailWag = true
            }
            withAnimation(.easeInOut(duration: 2.3).repeatForever(autoreverses: true)) {
                earWiggle = true
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.3))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.1)) { isBlinking = true }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeInOut(duration: 0.12)) { isBlinking = false }
            }
        }
    }

    @ViewBuilder
    private func petEye(scale s: CGFloat) -> some View {
        if mood == .sleepy || isBlinking {
            ClosedEyeArc()
                .stroke(Color(hex: 0x3D2820), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                .frame(width: 7.5 * s, height: 4 * s)
        } else if mood == .happy && isBouncing {
            HappyEyeArc()
                .stroke(Color(hex: 0x3D2820), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
                .frame(width: 8 * s, height: 5 * s)
        } else {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x3D2820))
                    .frame(width: 7 * s, height: 7 * s)
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.4 * s, height: 2.4 * s)
                    .offset(x: -1.4 * s, y: -1.5 * s)
            }
        }
    }
}

// MARK: - Cute Animated Cream Kitty

public struct CreamKittyView: View {
    public var mood: PetMood
    public var size: CGFloat
    public var isBouncing: Bool

    @State private var isBlinking = false
    @State private var breathe = false
    @State private var headTilt = false
    @State private var tailSway = false

    public init(mood: PetMood = .cozy, size: CGFloat = 68, isBouncing: Bool = false) {
        self.mood = mood
        self.size = size
        self.isBouncing = isBouncing
    }

    public var body: some View {
        let s = size / 68.0
        ZStack {
            // Curled kitty tail
            KittyTailShape()
                .stroke(Color(hex: 0xF0C7A0), style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
                .frame(width: 20 * s, height: 22 * s)
                .offset(x: -23 * s, y: 12 * s)
                .rotationEffect(.degrees(tailSway ? -12 : 8), anchor: .bottomTrailing)

            // Left pointy kitty ear
            KittyEarShape()
                .fill(Color(hex: 0xFFFBF5))
                .frame(width: 20 * s, height: 22 * s)
                .overlay(
                    KittyEarShape()
                        .fill(Color(hex: 0xF7B8BE))
                        .frame(width: 11 * s, height: 13 * s)
                        .offset(y: 3 * s)
                )
                .offset(x: -16 * s, y: -19 * s)
                .rotationEffect(.degrees(-14))

            // Right pointy kitty ear (with cute apricot patch!)
            KittyEarShape()
                .fill(Color(hex: 0xF2B986))
                .frame(width: 20 * s, height: 22 * s)
                .overlay(
                    KittyEarShape()
                        .fill(Color(hex: 0xF7B8BE))
                        .frame(width: 11 * s, height: 13 * s)
                        .offset(y: 3 * s)
                )
                .offset(x: 16 * s, y: -19 * s)
                .rotationEffect(.degrees(14))

            // Head base
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFFFFF), Color(hex: 0xFDF2E6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 54 * s, height: 45 * s)
                .overlay(
                    // Cute calico forehead patch
                    Ellipse()
                        .fill(Color(hex: 0xF2B986, alpha: 0.72))
                        .frame(width: 18 * s, height: 12 * s)
                        .offset(x: 12 * s, y: -15 * s)
                        .clipShape(Ellipse().size(width: 54 * s, height: 45 * s))
                )
                .overlay(
                    Ellipse()
                        .stroke(Color(hex: 0xE8D5C4), lineWidth: 1 * s)
                )
                .offset(y: 2 * s)

            // Cute tiny whiskers
            HStack(spacing: 38 * s) {
                VStack(spacing: 3.5 * s) {
                    Capsule().fill(Color(hex: 0xB89B8B)).frame(width: 9 * s, height: 1.3 * s).rotationEffect(.degrees(8))
                    Capsule().fill(Color(hex: 0xB89B8B)).frame(width: 9 * s, height: 1.3 * s).rotationEffect(.degrees(-6))
                }
                VStack(spacing: 3.5 * s) {
                    Capsule().fill(Color(hex: 0xB89B8B)).frame(width: 9 * s, height: 1.3 * s).rotationEffect(.degrees(-8))
                    Capsule().fill(Color(hex: 0xB89B8B)).frame(width: 9 * s, height: 1.3 * s).rotationEffect(.degrees(6))
                }
            }
            .offset(y: 8 * s)

            // Rosy cheeks
            HStack(spacing: 26 * s) {
                Ellipse()
                    .fill(Color(hex: 0xF7A3AF, alpha: 0.55))
                    .frame(width: 9.5 * s, height: 5.5 * s)
                Ellipse()
                    .fill(Color(hex: 0xF7A3AF, alpha: 0.55))
                    .frame(width: 9.5 * s, height: 5.5 * s)
            }
            .offset(y: 8 * s)

            // Eyes
            HStack(spacing: 16 * s) {
                kittyEye(scale: s)
                kittyEye(scale: s)
            }
            .offset(y: 1 * s)

            // Pink nose + ":3" mouth
            VStack(spacing: 1 * s) {
                KittyNoseShape()
                    .fill(Color(hex: 0xF2949C))
                    .frame(width: 6.5 * s, height: 4.5 * s)

                PetMouthShape()
                    .stroke(Color(hex: 0x523B34), style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
                    .frame(width: 11 * s, height: 4.5 * s)
            }
            .offset(y: 9 * s)

            // Mint ribbon collar
            Capsule()
                .fill(Color(hex: 0x76BFA0))
                .frame(width: 26 * s, height: 4.5 * s)
                .offset(y: 24 * s)
            Circle()
                .fill(Color(hex: 0xFFF2B2))
                .frame(width: 6 * s, height: 6 * s)
                .offset(y: 26 * s)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(headTilt ? 2.5 : -2.5))
        .scaleEffect(x: breathe ? 0.99 : 1.02, y: breathe ? 1.015 : 0.985, anchor: .bottom)
        .offset(y: isBouncing ? -10 * s : (breathe ? -1.5 * s : 1 * s))
        .animation(.spring(response: 0.34, dampingFraction: 0.45), value: isBouncing)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
            withAnimation(.easeInOut(duration: 3.1).repeatForever(autoreverses: true)) {
                headTilt = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                tailSway = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4.0))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.1)) { isBlinking = true }
                try? await Task.sleep(for: .milliseconds(130))
                withAnimation(.easeInOut(duration: 0.12)) { isBlinking = false }
            }
        }
    }

    @ViewBuilder
    private func kittyEye(scale s: CGFloat) -> some View {
        if mood == .sleepy || isBlinking {
            ClosedEyeArc()
                .stroke(Color(hex: 0x4A342E), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                .frame(width: 7.5 * s, height: 4 * s)
        } else if mood == .happy && isBouncing {
            HappyEyeArc()
                .stroke(Color(hex: 0x4A342E), style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
                .frame(width: 8 * s, height: 5 * s)
        } else {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x4A342E))
                    .frame(width: 6.8 * s, height: 6.8 * s)
                Circle()
                    .fill(Color.white)
                    .frame(width: 2.3 * s, height: 2.3 * s)
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
            // Floating hearts & paws on tap
            ForEach(hearts) { item in
                Image(systemName: item.symbol)
                    .font(.system(size: item.size, weight: .bold))
                    .foregroundStyle(item.color)
                    .offset(x: item.x, y: item.animate ? -46 : -6)
                    .scaleEffect(item.animate ? 1.15 : 0.4)
                    .opacity(item.animate ? 0 : 0.95)
            }

            HStack(spacing: -6) {
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

    private func triggerLoveBurst() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif

        isBouncing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            isBouncing = false
        }

        let symbols = ["heart.fill", "pawprint.fill", "sparkle"]
        let colors: [Color] = [Color(hex: 0xF27D8D), Color(hex: 0xF5B959), Color(hex: 0xE67360)]
        let newBatch = (0..<4).map { idx in
            FloatingParticle(
                symbol: symbols[idx % symbols.count],
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

private struct FloatingParticle: Identifiable {
    let id = UUID()
    let symbol: String
    let color: Color
    let x: CGFloat
    let size: CGFloat
    var animate: Bool = false
}

// MARK: - Vector Shapes

private struct PuppyEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 1.04, y: rect.midY * 0.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 0.92)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX - rect.width * 0.04, y: rect.midY * 0.6)
        )
        return path
    }
}

private struct KittyEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 0.92, y: rect.midY * 0.5)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY * 0.5)
        )
        return path
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

private struct KittyTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.15),
            control1: CGPoint(x: rect.minX, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.midY)
        )
        return path
    }
}
