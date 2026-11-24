@testable import ClaudeKit
import TallyCore
import XCTest

final class ImageInputTests: XCTestCase {
    private let pixel = ClaudeImageSource(mediaType: "image/jpeg", base64Data: "/9j/4AAQSkZJRg==")

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testImageBlockEncodesAsBase64Source() throws {
        let object = try json(ClaudeContentBlock.image(pixel))
        XCTAssertEqual(object["type"] as? String, "image")
        let source = try XCTUnwrap(object["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source["data"] as? String, "/9j/4AAQSkZJRg==")
        XCTAssertEqual(Set(object.keys), ["type", "source"])
        XCTAssertEqual(Set(source.keys), ["type", "media_type", "data"])

        let decoded = try JSONDecoder().decode(ClaudeContentBlock.self, from: JSONEncoder().encode(ClaudeContentBlock.image(pixel)))
        XCTAssertEqual(decoded, .image(pixel))
    }

    func testUserMessageWithImagesPutsImagesBeforeText() throws {
        let message = ClaudeMessage.user("Add this receipt", images: [pixel, pixel])
        let object = try json(message)
        XCTAssertEqual(object["role"] as? String, "user")
        let content = try XCTUnwrap(object["content"] as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "image", "text"])
        XCTAssertEqual(content.last?["text"] as? String, "Add this receipt")
        XCTAssertEqual(message.imageCount, 2)
        XCTAssertTrue(message.isUserTurn)

        // No images: a plain string message, as before.
        let plain = try json(ClaudeMessage.user("hi", images: []))
        XCTAssertEqual(plain["content"] as? String, "hi")
        // Images only.
        let imageOnly = try json(ClaudeMessage.user("", images: [pixel]))
        XCTAssertEqual((imageOnly["content"] as? [[String: Any]])?.map { $0["type"] as? String }, ["image"])
    }

    func testRequestBodyCarriesImageBlocksUnescaped() throws {
        let request = ClaudeRequest(messages: [.user("Read this", images: [pixel])])
        let urlRequest = try MessagesAPI.urlRequest(
            for: request, model: .sonnet, apiKey: "test-key", baseURL: URL(string: "https://example.invalid")!
        )
        let body = String(decoding: try XCTUnwrap(urlRequest.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains(#""source":{"data":"/9j/4AAQSkZJRg==","media_type":"image/jpeg","type":"base64"}"#), body)
        XCTAssertTrue(body.contains(#""model":"claude-sonnet-5-5""#))
    }

    func testPlaceholderReplacesImagesForOldTurns() throws {
        let message = ClaudeMessage.user("What's this?", images: [pixel])
        let replaced = message.replacingImages(withPlaceholder: "[1 image attached earlier]")
        XCTAssertNil(replaced.blocks)
        XCTAssertEqual(replaced.content, "[1 image attached earlier]\nWhat's this?")
        XCTAssertEqual(replaced.imageCount, 0)
        // Messages without images are unchanged.
        XCTAssertEqual(ClaudeMessage.user("x").replacingImages(withPlaceholder: "p"), .user("x"))
        let tools = ClaudeMessage.toolResults([(id: "t", content: "ok", isError: false)])
        XCTAssertTrue(tools.isToolResults)
        XCTAssertFalse(tools.isUserTurn)
    }

    func testDescriptionNeverIncludesImageBytes() {
        let description = String(describing: ClaudeContentBlock.image(pixel))
        XCTAssertFalse(description.contains("4AAQ"))
        XCTAssertTrue(description.contains("image/jpeg"))
    }

    // MARK: Resize decisions

    func testTargetSizeKeepsAspectRatioAndNeverUpscales() {
        typealias Size = ImageUploadPolicy.PixelSize
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 4032, height: 3024)), Size(width: 1568, height: 1176))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 1170, height: 2532)), Size(width: 725, height: 1568))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 3000, height: 3000)), Size(width: 1568, height: 1568))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 800, height: 600)), Size(width: 800, height: 600))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 1568, height: 10)), Size(width: 1568, height: 10))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 20000, height: 2)), Size(width: 1568, height: 1))
        XCTAssertEqual(ImageUploadPolicy.targetSize(for: Size(width: 4032, height: 3024), longEdge: 1024), Size(width: 1024, height: 768))
        XCTAssertNil(ImageUploadPolicy.targetSize(for: Size(width: 0, height: 10)))
    }

    func testByteBudgets() {
        XCTAssertEqual(ImageUploadPolicy.base64Length(ofByteCount: 3), 4)
        XCTAssertEqual(ImageUploadPolicy.base64Length(ofByteCount: 4), 8)
        XCTAssertTrue(ImageUploadPolicy.fitsUploadBudget(byteCount: 900_000))
        XCTAssertFalse(ImageUploadPolicy.fitsUploadBudget(byteCount: 2_000_000))
        XCTAssertFalse(ImageUploadPolicy.fitsUploadBudget(byteCount: 0))
        XCTAssertTrue(ImageUploadPolicy.fitsAPILimit(byteCount: 7_000_000))
        XCTAssertFalse(ImageUploadPolicy.fitsAPILimit(byteCount: 8_000_000), "base64 of 8 MB exceeds the 10 MB API limit")
        XCTAssertEqual(ImageUploadPolicy.remainingSlots(current: 1), ImageUploadPolicy.maxImagesPerMessage - 1)
        XCTAssertEqual(ImageUploadPolicy.remainingSlots(current: 9), 0)
        XCTAssertTrue(ImageUploadPolicy.jpegQualities == ImageUploadPolicy.jpegQualities.sorted(by: >))
    }
}
