import Foundation

/// An image attached to an Ask Tally message, as stored with the chat history. Only the id and
/// pixel size live in the history JSON; the display copy (a downscaled JPEG, about 1024 px on the
/// long edge) is a separate file in `ChatImageStore`.
public struct ChatImageAttachment: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var width: Int
    public var height: Int

    public init(id: UUID = UUID(), width: Int, height: Int) {
        self.id = id
        self.width = width
        self.height = height
    }

    /// Width / height, 1 when unknown.
    public var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

/// Local, device-only files holding the display copies of chat images, next to
/// `ask-tally-history.json` (`Application Support/Tally/ask-tally-images/<uuid>.jpg`).
///
/// Chat history (and therefore these files) is never part of CloudKit sync or the JSON backup.
/// Nothing here logs image bytes.
public struct ChatImageStore: Sendable {
    public static let directoryName = "ask-tally-images"
    public static let fileExtension = "jpg"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The store beside the chat history file, or `nil` when Application Support is unavailable.
    public static func standard() -> ChatImageStore? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return ChatImageStore(directory: appSupport
            .appendingPathComponent("Tally", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true))
    }

    // MARK: Naming

    public static func fileName(for id: UUID) -> String {
        "\(id.uuidString.lowercased()).\(fileExtension)"
    }

    /// Attachment id encoded in a file name made by `fileName(for:)`, `nil` for anything else.
    public static func attachmentID(fromFileName name: String) -> UUID? {
        let suffix = ".\(fileExtension)"
        guard name.hasSuffix(suffix) else { return nil }
        let stem = String(name.dropLast(suffix.count))
        guard let id = UUID(uuidString: stem), fileName(for: id) == name else { return nil }
        return id
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(Self.fileName(for: id), isDirectory: false)
    }

    // MARK: Save / load

    public func save(_ jpegData: Data, for id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpegData.write(to: fileURL(for: id), options: [.atomic])
    }

    public func load(_ id: UUID) -> Data? {
        try? Data(contentsOf: fileURL(for: id))
    }

    public func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: Cleanup

    public func delete(_ ids: some Sequence<UUID>) {
        for id in ids {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
    }

    /// Removes every stored image (used when all chat history is cleared).
    public func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Ids of the images currently on disk.
    public func storedIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap(Self.attachmentID(fromFileName:)))
    }

    /// Deletes stored images no message references any more (e.g. left behind by a crash between
    /// saving an image and saving the history). Returns how many were removed.
    @discardableResult
    public func removeOrphans(keeping referenced: Set<UUID>) -> Int {
        let orphans = storedIDs().subtracting(referenced)
        delete(orphans)
        return orphans.count
    }
}

extension ChatSession {
    /// Ids of every image attached to this conversation's messages.
    public var attachmentIDs: Set<UUID> {
        Set(messages.flatMap { $0.attachments ?? [] }.map(\.id))
    }
}
