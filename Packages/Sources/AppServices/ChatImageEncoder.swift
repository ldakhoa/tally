import ClaudeKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An image picked for an Ask Tally message, already downscaled and re-encoded as JPEG: one copy
/// for the API (`ImageUploadPolicy.uploadLongEdge`) and a smaller display copy kept with the
/// chat history (`ImageUploadPolicy.displayLongEdge`). Held in memory only until the turn is sent.
public struct PreparedChatImage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let uploadJPEG: Data
    public let displayJPEG: Data
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(id: UUID = UUID(), uploadJPEG: Data, displayJPEG: Data, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.uploadJPEG = uploadJPEG
        self.displayJPEG = displayJPEG
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var attachment: ChatImageAttachment {
        ChatImageAttachment(id: id, width: pixelWidth, height: pixelHeight)
    }

    public var claudeSource: ClaudeImageSource {
        ClaudeImageSource(mediaType: ImageUploadPolicy.mediaType, data: uploadJPEG)
    }
}

/// Downscales and re-encodes picked images with ImageIO (same code on iOS, iPadOS and macOS).
/// Sizing decisions come from `ImageUploadPolicy`. Never logs image bytes.
public enum ChatImageEncoder {
    public enum Failure: Error, Equatable {
        case unreadable
        case tooLarge
    }

    /// Prepares any image the system can decode (JPEG, PNG, HEIC, GIF, TIFF, WebP, ...). Applies
    /// the EXIF orientation, strips metadata (location etc.) by re-encoding, and keeps the upload
    /// copy within `ImageUploadPolicy.targetMaxEncodedBytes` when possible.
    public static func prepare(_ data: Data) throws -> PreparedChatImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { throw Failure.unreadable }

        guard let upload = thumbnail(source, longEdge: ImageUploadPolicy.uploadLongEdge),
              let display = thumbnail(source, longEdge: ImageUploadPolicy.displayLongEdge)
        else { throw Failure.unreadable }

        var uploadData: Data?
        for quality in ImageUploadPolicy.jpegQualities {
            guard let encoded = jpeg(upload, quality: quality) else { continue }
            uploadData = encoded
            if ImageUploadPolicy.fitsUploadBudget(byteCount: encoded.count) { break }
        }
        guard let uploadData else { throw Failure.unreadable }
        guard ImageUploadPolicy.fitsAPILimit(byteCount: uploadData.count) else { throw Failure.tooLarge }
        guard let displayData = jpeg(display, quality: 0.8) else { throw Failure.unreadable }

        return PreparedChatImage(
            uploadJPEG: uploadData,
            displayJPEG: displayData,
            pixelWidth: display.width,
            pixelHeight: display.height
        )
    }

    /// Re-encodes an existing display copy for upload (used when retrying a turn after relaunch,
    /// when only the display copy is still on disk).
    public static func prepareFromDisplayCopy(_ data: Data, id: UUID) -> PreparedChatImage? {
        guard let prepared = try? prepare(data) else { return nil }
        return PreparedChatImage(
            id: id,
            uploadJPEG: prepared.uploadJPEG,
            displayJPEG: data,
            pixelWidth: prepared.pixelWidth,
            pixelHeight: prepared.pixelHeight
        )
    }

    /// Orientation-corrected image whose long edge is at most `longEdge` (never upscaled).
    private static func thumbnail(_ source: CGImageSource, longEdge: Int) -> CGImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let target = ImageUploadPolicy.targetSize(
            for: ImageUploadPolicy.PixelSize(width: width, height: height),
            longEdge: longEdge
        )
        let maxPixel = target?.longEdge ?? longEdge
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
