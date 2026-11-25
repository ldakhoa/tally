import AppServices
import DesignSystem
import ImageIO
import SwiftUI
import TallyCore

// MARK: - Decoding

/// Decodes JPEG display copies off the main thread. Never logs image bytes.
enum ChatImageDecoder {
    static func cgImage(from data: Data, maxPixel: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        if let maxPixel {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

/// Loads `data()` once per `id` in the background and shows it filled into its frame, with a
/// quiet cozy placeholder while loading or when the file is missing or unreadable.
struct ChatImageTile: View {
    let id: UUID
    let data: @Sendable () -> Data?
    var maxPixel: Int = 480
    var cornerRadius: CGFloat = 14

    @State private var image: CGImage?
    @State private var didFail = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(Color.softFill).overlay {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                CozyUIIcon(.photo, size: 22, color: Color.textSecondary.opacity(didFail ? 0.45 : 0.3))
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.hairline, lineWidth: 1))
        .task(id: id) {
            let loader = data
            let maxPixel = maxPixel
            let decoded = await Task.detached(priority: .userInitiated) {
                loader().flatMap { ChatImageDecoder.cgImage(from: $0, maxPixel: maxPixel) }
            }.value
            image = decoded
            didFail = decoded == nil
        }
    }
}

// MARK: - Images in a sent message

/// A message's images: one image keeps its shape; several form a tidy two-column grid of square
/// rounded thumbnails. Tapping one opens the viewer.
struct ChatAttachmentGrid: View {
    let attachments: [ChatImageAttachment]
    let data: (ChatImageAttachment) -> (@Sendable () -> Data?)
    let onOpen: (ChatImageAttachment) -> Void
    var language: AppLanguage

    var body: some View {
        if attachments.count == 1, let only = attachments.first {
            let ratio = min(max(only.aspectRatio, 0.6), 1.8)
            tile(only)
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: 230, maxHeight: 260)
        } else {
            LazyVGrid(columns: [GridItem(.fixed(108), spacing: 6), GridItem(.fixed(108), spacing: 6)], alignment: .trailing, spacing: 6) {
                ForEach(attachments) { attachment in
                    tile(attachment).frame(width: 108, height: 108)
                }
            }
            .frame(width: 222)
        }
    }

    private func tile(_ attachment: ChatImageAttachment) -> some View {
        Button {
            CozyHaptics.light()
            onOpen(attachment)
        } label: {
            ChatImageTile(id: attachment.id, data: data(attachment))
                .contentShape(Rectangle())
        }
        .buttonStyle(.cozyCard)
        .accessibilityLabel(L10n.text(language, en: "Attached image", vi: "Ảnh đính kèm", zh: "附件图片"))
        .accessibilityHint(L10n.text(language, en: "Opens the image larger", vi: "Mở ảnh lớn hơn", zh: "放大查看图片"))
    }
}

// MARK: - Pending attachments in the composer

struct PendingAttachmentStrip: View {
    let images: [PreparedChatImage]
    let isPreparing: Bool
    let language: AppLanguage
    let onRemove: (PreparedChatImage) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    let display = image.displayJPEG
                    ChatImageTile(id: image.id, data: { display }, maxPixel: 200, cornerRadius: 12)
                        .frame(width: 58, height: 58)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                CozyHaptics.light()
                                onRemove(image)
                            } label: {
                                CozyUIIcon(.xmark, size: 9, color: Color.onInk, lineWidthScale: 1.3)
                                    .frame(width: 20, height: 20)
                                    .background(Color.ink, in: Circle())
                                    .overlay(Circle().strokeBorder(Color.cardBackground, lineWidth: 1.5))
                            }
                            .buttonStyle(.themedPlain)
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(L10n.text(language, en: "Remove image", vi: "Bỏ ảnh", zh: "移除图片"))
                        }
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                if isPreparing {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.softFill)
                        .frame(width: 58, height: 58)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Full-size viewer

struct ChatImageViewerItem: Identifiable, Hashable {
    let attachment: ChatImageAttachment
    var id: UUID { attachment.id }
}

/// Zoomable viewer for an attached image (pinch or double-tap to zoom, drag to pan), with a cozy
/// close control. Works the same on iPhone, iPad and Mac.
struct ChatImageViewer: View {
    let attachment: ChatImageAttachment
    let data: @Sendable () -> Data?
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var didFail = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.appBackground.ignoresSafeArea()

            GeometryReader { proxy in
                Group {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(magnify.simultaneously(with: pan))
                            .onTapGesture(count: 2) { toggleZoom() }
                            .accessibilityLabel(L10n.text(language, en: "Attached image", vi: "Ảnh đính kèm", zh: "附件图片"))
                    } else if didFail {
                        VStack(spacing: 10) {
                            CozyUIIcon(.photo, size: 40, color: Color.textSecondary.opacity(0.5))
                            Text(L10n.text(language, en: "This image is no longer available.", vi: "Ảnh này không còn nữa.", zh: "该图片已不可用。"))
                                .font(.appSecondary)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        ProgressView()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(16)

            Button {
                CozyHaptics.light()
                dismiss()
            } label: {
                CozyUIIcon(.xmark, size: 14, color: Color.textPrimary, lineWidthScale: 1.2)
                    .frame(width: 40, height: 40)
                    .background(Color.cardBackground, in: Circle())
                    .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
                    .shadow(color: Color(hex: 0x6B4423).opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(.cozyCard)
            .keyboardShortcut(.cancelAction)
            .padding(18)
            .accessibilityLabel(L10n.text(language, en: "Close", vi: "Đóng", zh: "关闭"))
        }
        .task(id: attachment.id) {
            let loader = data
            let decoded = await Task.detached(priority: .userInitiated) {
                loader().flatMap { ChatImageDecoder.cgImage(from: $0) }
            }.value
            image = decoded
            didFail = decoded == nil
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 760, minHeight: 480, idealHeight: 680)
        #endif
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in scale = min(max(lastScale * value.magnification, 1), 5) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { resetZoom() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if scale > 1 {
                resetZoom()
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
