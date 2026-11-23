import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Bundle Resource Image Loader

public enum ChibiAsset: String, Sendable {
    case husband = "chibi_husband"
    case wife = "chibi_wife"
    case budgetPiggy = "icon_budget"

    public var image: Image? {
        guard let url = Bundle.module.url(forResource: rawValue, withExtension: "png") else {
            return nil
        }
        #if os(iOS)
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: uiImage)
        #else
        guard let nsImage = NSImage(contentsOfFile: url.path) else { return nil }
        return Image(nsImage: nsImage)
        #endif
    }
}

// MARK: - Couple Chibi Avatars

public struct ChibiAvatarView: View {
    public let asset: ChibiAsset
    public var size: CGFloat
    public var borderColor: Color

    public init(asset: ChibiAsset, size: CGFloat = 34, borderColor: Color = Color(hex: 0xFFFDF9)) {
        self.asset = asset
        self.size = size
        self.borderColor = borderColor
    }

    public var body: some View {
        Group {
            if let img = asset.image {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xFFE8D8)
                    .overlay(Text(asset == .husband ? "🐶" : "🐱").font(.system(size: size * 0.55)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(borderColor, lineWidth: max(1.5, size * 0.06)))
        .shadow(color: Color(hex: 0x6B4423, alpha: 0.14), radius: 3, y: 1.5)
        .accessibilityHidden(true)
    }
}

public struct CoupleAvatarsBadge: View {
    public var avatarSize: CGFloat
    public var showHeart: Bool

    @State private var heartPulse = false

    public init(avatarSize: CGFloat = 28, showHeart: Bool = true) {
        self.avatarSize = avatarSize
        self.showHeart = showHeart
    }

    public var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: -avatarSize * 0.24) {
                ChibiAvatarView(asset: .husband, size: avatarSize)
                ChibiAvatarView(asset: .wife, size: avatarSize)
            }
            if showHeart {
                Image(systemName: "heart.fill")
                    .font(.system(size: max(8, avatarSize * 0.3)))
                    .foregroundStyle(Color(hex: 0xF27D8D))
                    .offset(y: -avatarSize * 0.12)
                    .scaleEffect(heartPulse ? 1.16 : 0.94)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                            heartPulse = true
                        }
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Cozy Watercolor-Style Metric Icons (Income, Spending, Budget, Household)

public enum CozyMetricIconKind: Sendable {
    case income
    case spending
    case budget
    case household
}

public struct CozyMetricIcon: View {
    public let kind: CozyMetricIconKind
    public var size: CGFloat

    public init(kind: CozyMetricIconKind, size: CGFloat = 34) {
        self.kind = kind
        self.size = size
    }

    public var body: some View {
        switch kind {
        case .income:
            CozyIncomeSticker(size: size)
        case .spending:
            CozySpendingSticker(size: size)
        case .budget:
            CozyBudgetSticker(size: size)
        case .household:
            CoupleAvatarsBadge(avatarSize: size * 0.78, showHeart: true)
                .frame(height: size)
        }
    }
}

/// Cute hand-drawn watercolor-style Income sticker: mint coin pouch + smiling gold coin + sparkles.
private struct CozyIncomeSticker: View {
    let size: CGFloat
    @State private var sparkle = false

    var body: some View {
        let s = size / 36.0
        let ink = Color(hex: 0x4E382F)
        let shape = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xE8F8EE), Color(hex: 0xD3F0DE)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Cute golden coin peeking above the pouch
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFE787), Color(hex: 0xF5BC42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 14 * s, height: 14 * s)
                    .overlay(Circle().stroke(ink, lineWidth: 1.3 * s))
                Circle()
                    .stroke(Color(hex: 0xFFF7CC), lineWidth: 1 * s)
                    .frame(width: 9 * s, height: 9 * s)
            }
            .offset(x: 4 * s, y: -6.5 * s)
            .offset(y: sparkle ? -1.2 * s : 0.6 * s)

            // Chubby mint coin pouch with rosy cheeks & happy smile
            ZStack {
                // Pouch tie ruffle
                Capsule()
                    .fill(Color(hex: 0x77C99A))
                    .frame(width: 10 * s, height: 4.5 * s)
                    .overlay(Capsule().stroke(ink, lineWidth: 1.2 * s))
                    .offset(y: -8 * s)

                // Pouch body
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x9DE0B8), Color(hex: 0x6EC492)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 22 * s, height: 18 * s)
                    .overlay(Ellipse().stroke(ink, lineWidth: 1.3 * s))
                    .offset(y: 2 * s)

                // Ribbon tie
                Capsule()
                    .fill(Color(hex: 0xF5B959))
                    .frame(width: 11 * s, height: 2.5 * s)
                    .offset(y: -5.5 * s)

                // Cute smiling face on pouch
                HStack(spacing: 5 * s) {
                    Circle().fill(ink).frame(width: 2 * s, height: 2 * s)
                    Circle().fill(ink).frame(width: 2 * s, height: 2 * s)
                }
                .offset(y: 1.5 * s)

                HStack(spacing: 9 * s) {
                    Circle().fill(Color(hex: 0xF5999E, alpha: 0.7)).frame(width: 3.5 * s, height: 2.2 * s)
                    Circle().fill(Color(hex: 0xF5999E, alpha: 0.7)).frame(width: 3.5 * s, height: 2.2 * s)
                }
                .offset(y: 3.5 * s)
            }
            .offset(x: -2 * s, y: 2 * s)

            // Tiny sparkle star
            Image(systemName: "sparkle")
                .font(.system(size: 7.5 * s, weight: .bold))
                .foregroundStyle(Color(hex: 0xF2B138))
                .offset(x: -11 * s, y: -9 * s)
                .scaleEffect(sparkle ? 1.18 : 0.82)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color(hex: 0x459E6E, alpha: 0.22), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                sparkle = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Cute hand-drawn watercolor-style Spending sticker: peach shopping bag + mini boba cup + happy face.
private struct CozySpendingSticker: View {
    let size: CGFloat
    @State private var sway = false

    var body: some View {
        let s = size / 36.0
        let ink = Color(hex: 0x4E382F)
        let shape = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)

        ZStack {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xFFF1E8), Color(hex: 0xFFE2D3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Mini boba/milk tea cup peeking out on the right
            ZStack {
                // Straw
                Capsule()
                    .fill(Color(hex: 0xE67360))
                    .frame(width: 2.2 * s, height: 7 * s)
                    .rotationEffect(.degrees(14))
                    .offset(x: 1 * s, y: -6.5 * s)
                // Cup
                RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                    .fill(Color(hex: 0xF7D7B5))
                    .frame(width: 9 * s, height: 11 * s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                            .stroke(ink, lineWidth: 1.1 * s)
                    )
                // Lid
                Capsule()
                    .fill(Color(hex: 0xFFFDF9))
                    .frame(width: 10.5 * s, height: 2.8 * s)
                    .overlay(Capsule().stroke(ink, lineWidth: 1 * s))
                    .offset(y: -4.5 * s)
            }
            .offset(x: 7.5 * s, y: -2 * s)
            .rotationEffect(.degrees(sway ? 4 : -2))

            // Cute coral-peach shopping bag with handle & smiling face
            ZStack {
                // Handle arc
                Circle()
                    .trim(from: 0.5, to: 1.0)
                    .stroke(ink, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                    .frame(width: 9 * s, height: 9 * s)
                    .offset(y: -8 * s)

                // Bag body
                RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFAE96), Color(hex: 0xEE846E)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 19 * s, height: 17 * s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5 * s, style: .continuous)
                            .stroke(ink, lineWidth: 1.3 * s)
                    )
                    .offset(y: 1.5 * s)

                // Cute face on bag
                HStack(spacing: 5 * s) {
                    Circle().fill(ink).frame(width: 2 * s, height: 2 * s)
                    Circle().fill(ink).frame(width: 2 * s, height: 2 * s)
                }
                .offset(y: 0.5 * s)

                HStack(spacing: 8.5 * s) {
                    Circle().fill(Color(hex: 0xFFD2C9, alpha: 0.85)).frame(width: 3.2 * s, height: 2 * s)
                    Circle().fill(Color(hex: 0xFFD2C9, alpha: 0.85)).frame(width: 3.2 * s, height: 2 * s)
                }
                .offset(y: 2.5 * s)

                Image(systemName: "heart.fill")
                    .font(.system(size: 4.5 * s))
                    .foregroundStyle(Color(hex: 0xFFF7F2))
                    .offset(y: 5.5 * s)
            }
            .offset(x: -3 * s, y: 2.5 * s)
            .rotationEffect(.degrees(sway ? -2.5 : 2.5))
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(Color(hex: 0xE67360, alpha: 0.24), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                sway = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Hand-painted watercolor piggy bank sticker for Budget Left!
private struct CozyBudgetSticker: View {
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
        Group {
            if let img = ChibiAsset.budgetPiggy.image {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xEDF5FC)
                    .overlay(Text("🐷").font(.system(size: size * 0.54)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(hex: 0x5B9EC9, alpha: 0.22), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
