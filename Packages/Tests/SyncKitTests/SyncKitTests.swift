import BudgetKit
import SyncKit
import XCTest

final class SyncKitTests: XCTestCase {
    func testLastWriteWinsAndTombstonePreservation() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        let local = TransactionRecord(
            id: "tx-1", name: "Coffee", amountMinor: 500, type: .expense, category: .food,
            dayKey: "2026-11-23", updatedAt: older, isDeleted: false
        )
        let remoteDeleted = TransactionRecord(
            id: "tx-1", name: "Coffee", amountMinor: 500, type: .expense, category: .food,
            dayKey: "2026-11-23", updatedAt: newer, isDeleted: true
        )

        let merged = SyncMerge.mergeTransaction(local: local, remote: remoteDeleted)
        XCTAssertTrue(merged.isDeleted)
        XCTAssertEqual(merged.updatedAt, newer)

        // Older edit arriving later must NOT resurrect the deleted transaction.
        let mergedAgain = SyncMerge.mergeTransaction(local: merged, remote: local)
        XCTAssertTrue(mergedAgain.isDeleted)
    }
}
