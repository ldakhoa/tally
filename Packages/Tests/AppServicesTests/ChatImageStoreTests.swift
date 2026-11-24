@testable import AppServices
import ClaudeKit
import Foundation
import ImageIO
import XCTest

final class ChatImageStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-chat-images-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var store: ChatImageStore { ChatImageStore(directory: root.appendingPathComponent(ChatImageStore.directoryName)) }

    func testNamingRoundTrip() {
        let id = UUID()
        let name = ChatImageStore.fileName(for: id)
        XCTAssertEqual(name, "\(id.uuidString.lowercased()).jpg")
        XCTAssertEqual(ChatImageStore.attachmentID(fromFileName: name), id)
        XCTAssertNil(ChatImageStore.attachmentID(fromFileName: "notes.txt"))
        XCTAssertNil(ChatImageStore.attachmentID(fromFileName: "\(id.uuidString).jpg"), "only the canonical lowercase name")
        XCTAssertEqual(store.fileURL(for: id).lastPathComponent, name)
        XCTAssertEqual(store.fileURL(for: id).deletingLastPathComponent().lastPathComponent, "ask-tally-images")
    }

    func testSaveLoadAndDelete() throws {
        let a = UUID(), b = UUID()
        XCTAssertNil(store.load(a))
        try store.save(Data([1, 2, 3]), for: a)
        try store.save(Data([4, 5]), for: b)
        XCTAssertEqual(store.load(a), Data([1, 2, 3]))
        XCTAssertEqual(store.storedIDs(), [a, b])
        store.delete([a])
        XCTAssertNil(store.load(a))
        XCTAssertTrue(store.exists(b))
        store.deleteAll()
        XCTAssertTrue(store.storedIDs().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testRemoveOrphansKeepsReferencedImages() throws {
        let kept = UUID(), orphan = UUID()
        try store.save(Data([1]), for: kept)
        try store.save(Data([2]), for: orphan)
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("unrelated.txt"))
        XCTAssertEqual(store.removeOrphans(keeping: [kept]), 1)
        XCTAssertTrue(store.exists(kept))
        XCTAssertFalse(store.exists(orphan))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("unrelated.txt").path))
    }

    // MARK: History lifecycle

    private func writeHistory(_ sessions: [ChatSession], active: UUID?) throws -> URL {
        let url = root.appendingPathComponent("ask-tally-history.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(PersistedChatHistory(activeSessionID: active, sessions: sessions)).write(to: url)
        return url
    }

    private func session(images: [ChatImageAttachment], text: String = "Add this receipt") -> ChatSession {
        ChatSession(title: text, messages: [
            ChatEntry(role: .user, text: text, attachments: images),
            ChatEntry(role: .assistant, text: "Saved."),
        ])
    }

    @MainActor
    func testHistoryReferencesImagesAndDeletesThemWithTheirConversation() throws {
        let first = ChatImageAttachment(width: 1024, height: 768)
        let second = ChatImageAttachment(width: 600, height: 1024)
        let orphan = UUID()
        try store.save(Data([1]), for: first.id)
        try store.save(Data([2]), for: second.id)
        try store.save(Data([3]), for: orphan)
        let s1 = session(images: [first])
        let s2 = session(images: [second], text: "Loan screenshot")
        let url = try writeHistory([s1, s2], active: s1.id)

        let service = AssistantService(historyFileURL: url, imageStore: store)
        // Loading removes files no message references.
        XCTAssertFalse(store.exists(orphan))
        XCTAssertEqual(service.messages.first?.attachments, [first])
        XCTAssertEqual(service.imageData(for: first), Data([1]))

        // The context resent to the model carries a placeholder, never image bytes.
        XCTAssertEqual(service.wireHistory.first?.imageCount, 0)
        XCTAssertTrue(service.wireHistory.first?.content.contains("attached 1 image here earlier") == true)
        XCTAssertTrue(service.wireHistory.first?.content.contains("Add this receipt") == true)

        // The history JSON stores only ids and sizes, not image data.
        let json = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(json.contains(first.id.uuidString))

        // Deleting a conversation deletes its images only.
        service.deleteSession(id: s2.id)
        XCTAssertFalse(store.exists(second.id))
        XCTAssertTrue(store.exists(first.id))

        // Starting a new chat keeps the old conversation (and its images) in history.
        service.startNewChat()
        XCTAssertTrue(store.exists(first.id))
        XCTAssertEqual(service.sessions.count, 1)

        // Deleting the conversation that was active also removes its images.
        let reloaded = AssistantService(historyFileURL: url, imageStore: store)
        reloaded.selectSession(reloaded.sessions[0])
        reloaded.deleteSession(id: s1.id)
        XCTAssertFalse(store.exists(first.id))
    }

    @MainActor
    func testClearAllHistoryRemovesEveryImage() throws {
        let image = ChatImageAttachment(width: 10, height: 10)
        try store.save(Data([9]), for: image.id)
        let s = session(images: [image])
        let url = try writeHistory([s], active: s.id)
        let service = AssistantService(historyFileURL: url, imageStore: store)
        service.clearAllHistory()
        XCTAssertTrue(store.storedIDs().isEmpty)
        XCTAssertTrue(service.sessions.isEmpty)
    }

    @MainActor
    func testHistoryWithoutAttachmentsStillDecodes() throws {
        // History JSON written before images existed (no `attachments` key).
        let legacy = #"{"sessions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"Hi","updatedAt":0,"messages":[{"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","role":"user","text":"Hi","actions":[],"timestamp":0}]}]}"#
        let url = root.appendingPathComponent("ask-tally-history.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: url)
        let service = AssistantService(historyFileURL: url, imageStore: store)
        XCTAssertEqual(service.sessions.count, 1)
        XCTAssertNil(service.sessions[0].messages[0].attachments)
    }

    // MARK: Encoder

    func testEncoderDownscalesAndReencodesAsJPEG() throws {
        let png = try XCTUnwrap(Self.solidPNG(width: 3000, height: 2000))
        let prepared = try ChatImageEncoder.prepare(png)
        XCTAssertEqual(prepared.pixelWidth, 1024)
        XCTAssertEqual(prepared.pixelHeight, 683)
        XCTAssertEqual(Array(prepared.uploadJPEG.prefix(2)), [0xFF, 0xD8], "JPEG magic")
        XCTAssertTrue(ImageUploadPolicy.fitsUploadBudget(byteCount: prepared.uploadJPEG.count))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(prepared.uploadJPEG as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 1568)
        XCTAssertEqual(prepared.claudeSource.mediaType, "image/jpeg")
        XCTAssertThrowsError(try ChatImageEncoder.prepare(Data("not an image".utf8)))
    }

    private static func solidPNG(width: Int, height: Int) -> Data? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0.9, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
