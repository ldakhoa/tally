import Foundation

/// Pure decisions for preparing chat images before upload (the pixel work itself lives in
/// `AppServices.ChatImageEncoder`, which uses ImageIO).
///
/// Messages API limits (vision docs, checked 2026-11): JPEG/PNG/GIF/WebP; at most 10 MB per image
/// after base64 encoding; at most 8000×8000 px; more than 20 images in one request lowers the
/// per-image limit to 3000 px; 128 MB per request. Images larger than the model's native
/// resolution are downscaled server-side anyway, so sending a long edge of about 1568 px keeps
/// requests small without losing what the model can read (receipts, bank-app screenshots).
public enum ImageUploadPolicy {
    /// Long edge (px) of the copy sent to the API.
    public static let uploadLongEdge = 1568
    /// Long edge (px) of the display copy kept with the chat history on this device.
    public static let displayLongEdge = 1024
    /// Images one message may carry (well under the API's 20-image threshold, since only the
    /// current turn ever carries image bytes).
    public static let maxImagesPerMessage = 5
    /// API limit per image, measured on the base64 string.
    public static let apiMaxBase64Bytes = 10 * 1024 * 1024
    /// Our own budget per uploaded image (raw JPEG bytes), far below the API limit.
    public static let targetMaxEncodedBytes = 1_500_000
    /// JPEG qualities tried in order until the encoded image fits `targetMaxEncodedBytes`.
    public static let jpegQualities: [Double] = [0.82, 0.72, 0.6, 0.5, 0.4]
    public static let mediaType = "image/jpeg"

    public struct PixelSize: Equatable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        public var longEdge: Int { max(width, height) }
    }

    /// Size that fits `longEdge` while keeping the aspect ratio. Never upscales; every side is at
    /// least 1 px. `nil` for an empty or invalid size.
    public static func targetSize(for size: PixelSize, longEdge: Int = uploadLongEdge) -> PixelSize? {
        guard size.width > 0, size.height > 0, longEdge > 0 else { return nil }
        guard size.longEdge > longEdge else { return size }
        let scale = Double(longEdge) / Double(size.longEdge)
        let width = size.width >= size.height ? longEdge : max(1, Int((Double(size.width) * scale).rounded()))
        let height = size.height > size.width ? longEdge : max(1, Int((Double(size.height) * scale).rounded()))
        return PixelSize(width: width, height: height)
    }

    /// Length of the base64 encoding of `byteCount` bytes.
    public static func base64Length(ofByteCount byteCount: Int) -> Int {
        ((max(0, byteCount) + 2) / 3) * 4
    }

    /// `true` when an encoded image of `byteCount` bytes fits our upload budget and the API limit.
    public static func fitsUploadBudget(byteCount: Int) -> Bool {
        byteCount > 0
            && byteCount <= targetMaxEncodedBytes
            && base64Length(ofByteCount: byteCount) <= apiMaxBase64Bytes
    }

    /// `true` when `byteCount` is still acceptable to the API even though it is over our budget
    /// (used after the lowest quality has been tried).
    public static func fitsAPILimit(byteCount: Int) -> Bool {
        byteCount > 0 && base64Length(ofByteCount: byteCount) <= apiMaxBase64Bytes
    }

    /// How many more images can be attached to a message already holding `current`.
    public static func remainingSlots(current: Int) -> Int {
        max(0, maxImagesPerMessage - current)
    }
}
