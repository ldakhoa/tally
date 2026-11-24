@testable import AppServices
import CloudKit
import XCTest

/// Decision logic behind `CloudSync` (items 5–8). The CloudKit round trips themselves (zone
/// deletion events, `.serverRecordChanged`, `.limitExceeded`, engine replacement) cannot run in
/// unit tests; `CloudSync` only wires these helpers to the engine.
final class CloudSyncPolicyTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: "TallyHousehold", ownerName: CKCurrentUserDefaultName)
    private let otherZone = CKRecordZone.ID(zoneName: "TallyHousehold", ownerName: "_partner")

    // MARK: Item 5 — zone deletion reasons

    func testZoneDeletionReasonsPauseSyncAndNeverRecreate() {
        typealias P = CloudSyncPolicy
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: zone, reason: .purged, activeZoneID: zone, isOwner: true), .pauseSync(.purged))
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: zone, reason: .encryptedDataReset, activeZoneID: zone, isOwner: true), .pauseSync(.encryptedDataReset))
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: zone, reason: .deleted, activeZoneID: zone, isOwner: true), .pauseSync(.zoneDeleted))
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: otherZone, reason: .deleted, activeZoneID: otherZone, isOwner: false), .pauseSync(.sharedHouseholdUnavailable))
        // Another zone (e.g. a household this device no longer syncs) is ignored.
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: otherZone, reason: .purged, activeZoneID: zone, isOwner: true), .ignore)
        XCTAssertEqual(P.actionForZoneDeletion(zoneID: zone, reason: .purged, activeZoneID: nil, isOwner: true), .ignore)
    }

    func testMissingZoneIsRecreatedOnlyInTheRecoverableOwnerCase() {
        typealias P = CloudSyncPolicy
        XCTAssertEqual(P.actionForMissingZone(isOwner: true, errorCode: .zoneNotFound, userDidResetEncryptedData: false, recordHadServerChangeTag: false), .recreateZone)
        XCTAssertEqual(P.actionForMissingZone(isOwner: true, errorCode: .zoneNotFound, userDidResetEncryptedData: false, recordHadServerChangeTag: true), .pauseSync(.zoneDeleted))
        XCTAssertEqual(P.actionForMissingZone(isOwner: true, errorCode: .zoneNotFound, userDidResetEncryptedData: true, recordHadServerChangeTag: false), .pauseSync(.encryptedDataReset))
        XCTAssertEqual(P.actionForMissingZone(isOwner: true, errorCode: .userDeletedZone, userDidResetEncryptedData: false, recordHadServerChangeTag: false), .pauseSync(.purged))
        XCTAssertEqual(P.actionForMissingZone(isOwner: false, errorCode: .zoneNotFound, userDidResetEncryptedData: false, recordHadServerChangeTag: false), .pauseSync(.sharedHouseholdUnavailable))
    }

    func testPauseMessagesExplainHowToResumeAndMentionReinviting() {
        for reason in [CloudSyncPolicy.PauseReason.zoneDeleted, .purged, .encryptedDataReset] {
            let text = CloudSyncPolicy.message(for: reason, language: .english)
            XCTAssertTrue(text.contains("Turn on Sync with iCloud"), text)
            XCTAssertTrue(text.contains("invite your partner again"), text)
        }
        XCTAssertTrue(CloudSyncPolicy.recreatedZoneMessage(language: .english).contains("invite your partner again"))
    }

    // MARK: Item 6 — scoped sends

    func testBatchHonoursScopeAndActiveZoneBeforeLimit() {
        let pending: [CKSyncEngine.PendingRecordZoneChange] = (0..<150).map {
            .saveRecord(CKRecord.ID(recordName: "tx_\($0)", zoneID: zone))
        } + [.saveRecord(CKRecord.ID(recordName: "tx_other", zoneID: otherZone))]
        let wanted = CKRecord.ID(recordName: "tx_149", zoneID: zone)

        // Scoped send: only the requested record, even though it is beyond the first 100.
        XCTAssertEqual(CloudSyncPolicy.batch(pending, scope: .recordIDs([wanted]), activeZoneID: zone, limit: 100), [.saveRecord(wanted)])
        XCTAssertEqual(CloudSyncPolicy.batch(pending, scope: .all, activeZoneID: zone, limit: 100).count, 100)
        XCTAssertTrue(CloudSyncPolicy.batch(pending, scope: .zoneIDs([otherZone]), activeZoneID: zone, limit: 100).isEmpty)
        XCTAssertEqual(CloudSyncPolicy.batch(pending, scope: .all, activeZoneID: zone, limit: 12).count, 12)
        XCTAssertTrue(CloudSyncPolicy.batch(pending, scope: .all, activeZoneID: nil, limit: 100).isEmpty)
    }

    // MARK: Item 7 — bounded conflict retries, limitExceeded

    func testRepeatedConflictsBackOffUntilSaved() {
        var guardrail = ConflictRetryGuard()
        let key = CloudRecordKey(CKRecord.ID(recordName: "tx_1", zoneID: zone))
        XCTAssertEqual((0..<3).map { _ in guardrail.noteConflict(key) }, [.retryNow, .retryNow, .retryNow])
        XCTAssertFalse(guardrail.isBackingOff)
        XCTAssertEqual(guardrail.noteConflict(key), .backOff(30))
        XCTAssertTrue(guardrail.isBackingOff)
        XCTAssertEqual(guardrail.noteConflict(key), .backOff(60))
        for _ in 0..<20 { _ = guardrail.noteConflict(key) }
        XCTAssertEqual(guardrail.noteConflict(key), .backOff(ConflictRetryGuard.maxBackoff))
        // Another record is unaffected; a successful save resets the count.
        XCTAssertEqual(guardrail.noteConflict(CloudRecordKey(CKRecord.ID(recordName: "tx_2", zoneID: zone))), .retryNow)
        guardrail.noteSaved(key)
        XCTAssertFalse(guardrail.isBackingOff)
        XCTAssertEqual(guardrail.noteConflict(key), .retryNow)
    }

    func testLimitExceededHalvesBatchesAndRecovers() {
        var sizer = BatchSizer()
        XCTAssertEqual(sizer.limit, 100)
        sizer.noteLimitExceeded()
        sizer.noteLimitExceeded()
        XCTAssertEqual(sizer.limit, 25)
        for _ in 0..<10 { sizer.noteLimitExceeded() }
        XCTAssertEqual(sizer.limit, 1)
        for _ in 0..<10 { sizer.noteSuccess() }
        XCTAssertEqual(sizer.limit, 100)
    }

    // MARK: Item 8 — records outside the selected zone

    func testRecordsOutsideTheSelectedZoneAreIgnored() {
        XCTAssertTrue(CloudSyncPolicy.isInActiveZone(CKRecord.ID(recordName: "tx_1", zoneID: zone), activeZoneID: zone))
        XCTAssertFalse(CloudSyncPolicy.isInActiveZone(CKRecord.ID(recordName: "tx_1", zoneID: otherZone), activeZoneID: zone))
        XCTAssertFalse(CloudSyncPolicy.isInActiveZone(CKRecord.ID(recordName: "tx_1", zoneID: zone), activeZoneID: nil))
    }
}
