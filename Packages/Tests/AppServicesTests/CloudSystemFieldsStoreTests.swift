@testable import AppServices
import CloudKit
import SyncKit
import XCTest

/// Pure parts of the CloudKit system-field handling. The CloudKit round trip itself (change tags
/// issued by the server, `.serverRecordChanged` retries) is not exercised here.
final class CloudSystemFieldsStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private let zone = CKRecordZone.ID(zoneName: "TallyHousehold", ownerName: CKCurrentUserDefaultName)

    func testArchiveRoundTripKeepsIdentity() throws {
        let id = CKRecord.ID(recordName: "tx_abc#3", zoneID: zone)
        let record = CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: id)
        record["payload"] = Data("secret".utf8) as CKRecordValue
        let restored = try XCTUnwrap(CloudSystemFieldsStore.unarchive(CloudSystemFieldsStore.archive(record)))
        XCTAssertEqual(restored.recordID, id)
        XCTAssertEqual(restored.recordType, SyncRecordKind.transaction.rawValue)
        // System fields only: user data is never stored here.
        XCTAssertNil(restored["payload"])
    }

    func testStoredFieldsSurviveRelaunchAndMatchOnlyTheSameRecord() throws {
        let url = directory.appendingPathComponent("SystemFields.plist")
        let id = CKRecord.ID(recordName: "pl_p1", zoneID: zone)
        let store = CloudSystemFieldsStore(fileURL: url)
        store.remember(CKRecord(recordType: SyncRecordKind.plan.rawValue, recordID: id))
        store.saveIfNeeded()

        let relaunched = CloudSystemFieldsStore(fileURL: url)
        XCTAssertNotNil(relaunched.entries[CloudRecordKey(id)])
        XCTAssertEqual(relaunched.record(for: id, recordType: SyncRecordKind.plan.rawValue).recordID, id)

        // Different zone (e.g. after switching household) or type: never reuse the fields.
        let otherZone = CKRecord.ID(recordName: "pl_p1", zoneID: CKRecordZone.ID(zoneName: "TallyHousehold", ownerName: "_partner"))
        XCTAssertEqual(relaunched.record(for: otherZone, recordType: SyncRecordKind.plan.rawValue).recordID, otherZone)
        XCTAssertEqual(relaunched.record(for: id, recordType: SyncRecordKind.goal.rawValue).recordType, SyncRecordKind.goal.rawValue)

        relaunched.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(CloudSystemFieldsStore(fileURL: url).entries.isEmpty)
    }

    func testMissingFileStartsEmpty() {
        XCTAssertTrue(CloudSystemFieldsStore(fileURL: directory.appendingPathComponent("none.plist")).entries.isEmpty)
    }

    func testOnlyNewerFieldsReplaceStoredOnes() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        XCTAssertTrue(CloudSystemFieldsStore.shouldReplace(existing: nil, incomingModifiedAt: nil))
        XCTAssertTrue(CloudSystemFieldsStore.shouldReplace(existing: .init(data: Data(), modifiedAt: nil), incomingModifiedAt: old))
        XCTAssertTrue(CloudSystemFieldsStore.shouldReplace(existing: .init(data: Data(), modifiedAt: old), incomingModifiedAt: new))
        XCTAssertFalse(CloudSystemFieldsStore.shouldReplace(existing: .init(data: Data(), modifiedAt: new), incomingModifiedAt: old))
        XCTAssertFalse(CloudSystemFieldsStore.shouldReplace(existing: .init(data: Data(), modifiedAt: new), incomingModifiedAt: nil))
    }

    // MARK: Item 7 — identity and replacement

    func testSameRecordNameInTwoZonesKeepsBothEntries() throws {
        let url = directory.appendingPathComponent("SystemFields.plist")
        let store = CloudSystemFieldsStore(fileURL: url)
        let mine = CKRecord.ID(recordName: "tx_1", zoneID: zone)
        let partners = CKRecord.ID(recordName: "tx_1", zoneID: CKRecordZone.ID(zoneName: "TallyHousehold", ownerName: "_partner"))
        store.remember(CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: mine))
        store.remember(CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: partners))
        XCTAssertEqual(store.entries.count, 2)
        store.saveIfNeeded()
        let relaunched = CloudSystemFieldsStore(fileURL: url)
        XCTAssertEqual(Set(relaunched.entries.keys), [CloudRecordKey(mine), CloudRecordKey(partners)])
        relaunched.forget(partners)
        XCTAssertEqual(Array(relaunched.entries.keys), [CloudRecordKey(mine)])
    }

    /// The format-1 file (keyed by record name) migrates by re-keying each entry with the record
    /// ID archived inside it; undecodable entries are dropped.
    func testLegacyFileMigratesToFullIdentity() throws {
        let url = directory.appendingPathComponent("SystemFields.plist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = CKRecord.ID(recordName: "gl_g1", zoneID: zone)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy: [String: CloudSystemFieldsStore.Entry] = [
            "gl_g1": .init(data: CloudSystemFieldsStore.archive(CKRecord(recordType: SyncRecordKind.goal.rawValue, recordID: id)), modifiedAt: stamp),
            "tx_garbage": .init(data: Data("not an archive".utf8), modifiedAt: nil),
        ]
        try PropertyListEncoder().encode(legacy).write(to: url)

        let migrated = CloudSystemFieldsStore(fileURL: url)
        XCTAssertEqual(Array(migrated.entries.keys), [CloudRecordKey(id)])
        XCTAssertEqual(migrated.entries[CloudRecordKey(id)]?.modifiedAt, stamp)
        migrated.saveIfNeeded()
        XCTAssertEqual(CloudSystemFieldsStore(fileURL: url).entries.keys.first, CloudRecordKey(id))
    }

    func testUnreadableFileStartsEmpty() throws {
        let url = directory.appendingPathComponent("SystemFields.plist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: url)
        XCTAssertTrue(CloudSystemFieldsStore(fileURL: url).entries.isEmpty)
    }

    /// After `.serverRecordChanged` the server's fields replace the stored ones even when the
    /// stored entry looks newer (or the server record carries no date).
    func testServerRecordFromConflictAlwaysReplacesStoredFields() throws {
        let url = directory.appendingPathComponent("SystemFields.plist")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = CKRecord.ID(recordName: "tx_9", zoneID: zone)
        let future = Date(timeIntervalSince1970: 4_000_000_000)
        let legacy: [String: CloudSystemFieldsStore.Entry] = [
            "tx_9": .init(data: CloudSystemFieldsStore.archive(CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: id)), modifiedAt: future),
        ]
        try PropertyListEncoder().encode(legacy).write(to: url)
        let store = CloudSystemFieldsStore(fileURL: url)
        let server = CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: id)

        store.remember(server)
        XCTAssertEqual(store.entries[CloudRecordKey(id)]?.modifiedAt, future, "fetched/saved records keep the newer-only rule")
        store.replace(with: server)
        XCTAssertNil(store.entries[CloudRecordKey(id)]?.modifiedAt, "conflict server record replaced the stored fields")
    }
}
