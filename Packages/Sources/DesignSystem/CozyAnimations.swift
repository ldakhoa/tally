import SwiftUI

// MARK: - Cozy Entrance Animation

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
            .scaleEffect(appeared ? 1 : 0.98)
            .onAppear {
                guard !appeared else { return }
                let delay = min(Double(index) * 0.045, 0.28)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.82).delay(delay)) {
                    appeared = true
                }
            }
    }
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
