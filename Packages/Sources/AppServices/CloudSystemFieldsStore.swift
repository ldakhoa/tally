import CloudKit
import Foundation

/// Full identity of a CloudKit record: zone name, zone owner and record name. Record names
/// alone collide across zones (private household vs. a partner's shared household).
struct CloudRecordKey: Hashable, Codable, Comparable {
    var zoneName: String
    var ownerName: String
    var recordName: String

    init(zoneName: String, ownerName: String, recordName: String) {
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.recordName = recordName
    }

    init(_ recordID: CKRecord.ID) {
        self.init(zoneName: recordID.zoneID.zoneName, ownerName: recordID.zoneID.ownerName, recordName: recordID.recordName)
    }

    static func < (lhs: CloudRecordKey, rhs: CloudRecordKey) -> Bool {
        (lhs.ownerName, lhs.zoneName, lhs.recordName) < (rhs.ownerName, rhs.zoneName, rhs.recordName)
    }
}

/// Persists each synced CloudKit record's encoded system fields (record ID, zone, change tag,
/// modification date) keyed by full record identity (`CloudRecordKey`), next to the
/// `CKSyncEngine` state file. Outgoing records are built on top of them so CloudKit sees the
/// server change tag and accepts updates instead of failing with `.serverRecordChanged` (Apple's
/// `lastKnownRecord` pattern from `sample-cloudkit-sync-engine`).
///
/// Only metadata lives here, never user data: losing the file is harmless (the next save of each
/// record conflicts once, the server copy's fields are stored, and the save is retried). It is
/// cleared whenever the sync engine state is reset (zone switch, account change, paused sync).
///
/// File format 2: `{ "version": 2, "entries": [{ key, entry }] }`. Format 1 (a dictionary keyed
/// by record name only) is migrated on load by re-keying each entry with the record ID archived
/// inside it; entries that cannot be decoded are dropped.
final class CloudSystemFieldsStore {
    struct Entry: Codable, Equatable {
        var data: Data
        var modifiedAt: Date?
    }

    private struct StoredEntry: Codable {
        var key: CloudRecordKey
        var entry: Entry
    }

    private struct FileV2: Codable {
        var version: Int
        var entries: [StoredEntry]
    }

    static let currentVersion = 2

    private(set) var entries: [CloudRecordKey: Entry]
    private let fileURL: URL
    private var isDirty = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = Self.load(from: fileURL)
        entries = loaded.entries
        isDirty = loaded.migrated
    }

    /// Decodes format 2, or migrates format 1. Anything unreadable starts empty.
    static func load(from fileURL: URL) -> (entries: [CloudRecordKey: Entry], migrated: Bool) {
        guard let data = try? Data(contentsOf: fileURL) else { return ([:], false) }
        let decoder = PropertyListDecoder()
        if let file = try? decoder.decode(FileV2.self, from: data), file.version == currentVersion {
            return (Dictionary(file.entries.map { ($0.key, $0.entry) }, uniquingKeysWith: { first, _ in first }), false)
        }
        if let legacy = try? decoder.decode([String: Entry].self, from: data) {
            var migrated: [CloudRecordKey: Entry] = [:]
            for (recordName, entry) in legacy {
                guard let record = unarchive(entry.data), record.recordID.recordName == recordName else { continue }
                migrated[CloudRecordKey(record.recordID)] = entry
            }
            return (migrated, true)
        }
        return ([:], true)
    }

    // MARK: Pure helpers

    static func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    /// Same rule as the sample's `setLastKnownRecordIfNewer`: keep the stored fields unless they
    /// have no modification date or the incoming record is strictly newer.
    static func shouldReplace(existing: Entry?, incomingModifiedAt: Date?) -> Bool {
        guard let existingDate = existing?.modifiedAt else { return true }
        guard let incomingModifiedAt else { return false }
        return existingDate < incomingModifiedAt
    }

    // MARK: Store

    /// Remembers `record`'s system fields if they are newer than the stored ones (fetched and
    /// saved records).
    func remember(_ record: CKRecord) {
        let key = CloudRecordKey(record.recordID)
        guard Self.shouldReplace(existing: entries[key], incomingModifiedAt: record.modificationDate) else { return }
        entries[key] = Entry(data: Self.archive(record), modifiedAt: record.modificationDate)
        isDirty = true
    }

    /// Stores `serverRecord`'s fields unconditionally: after `.serverRecordChanged` the server's
    /// change tag is the one the next save must carry, whatever the modification dates say.
    func replace(with serverRecord: CKRecord) {
        entries[CloudRecordKey(serverRecord.recordID)] = Entry(data: Self.archive(serverRecord), modifiedAt: serverRecord.modificationDate)
        isDirty = true
    }

    func forget(_ recordID: CKRecord.ID) {
        guard entries.removeValue(forKey: CloudRecordKey(recordID)) != nil else { return }
        isDirty = true
    }

    func removeAll() {
        entries = [:]
        isDirty = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Record to populate for an outgoing save: the stored server record (system fields only)
    /// when it matches `recordID` and `recordType`, otherwise a fresh record.
    func record(for recordID: CKRecord.ID, recordType: String) -> CKRecord {
        if let entry = entries[CloudRecordKey(recordID)],
           let stored = Self.unarchive(entry.data),
           stored.recordID == recordID,
           stored.recordType == recordType {
            return stored
        }
        return CKRecord(recordType: recordType, recordID: recordID)
    }

    func saveIfNeeded() {
        guard isDirty else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let file = FileV2(
            version: Self.currentVersion,
            entries: entries.keys.sorted().map { StoredEntry(key: $0, entry: entries[$0]!) }
        )
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: fileURL, options: .atomic)) != nil {
            isDirty = false
        }
    }
}
