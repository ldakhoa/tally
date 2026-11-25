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

final class InstallmentPlanSyncTests: XCTestCase {
    private func plan(updatedAt: Date, isDeleted: Bool = false, months: Int = 12) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: "plan-1", name: "SHOPEEPAY SG IPP", totalMinor: 51_500, months: months,
            firstPaymentDayKey: "2026-11-15", lender: "DBS", updatedAt: updatedAt, isDeleted: isDeleted
        )
    }

    func testMergePlanLastWriteWinsAndTombstones() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(SyncMerge.mergePlan(local: nil, remote: plan(updatedAt: older)).months, 12)

        let edited = SyncMerge.mergePlan(local: plan(updatedAt: older), remote: plan(updatedAt: newer, months: 6))
        XCTAssertEqual(edited.months, 6)
        let staleRemote = SyncMerge.mergePlan(local: plan(updatedAt: newer, months: 6), remote: plan(updatedAt: older))
        XCTAssertEqual(staleRemote.months, 6)

        let deleted = SyncMerge.mergePlan(local: plan(updatedAt: older), remote: plan(updatedAt: newer, isDeleted: true))
        XCTAssertTrue(deleted.isDeleted)
        // An older edit arriving later must not resurrect the deleted plan.
        XCTAssertTrue(SyncMerge.mergePlan(local: deleted, remote: plan(updatedAt: older)).isDeleted)
        // Tie: tombstone wins.
        XCTAssertTrue(SyncMerge.mergePlan(local: plan(updatedAt: newer), remote: plan(updatedAt: newer, isDeleted: true)).isDeleted)
        XCTAssertTrue(SyncMerge.mergePlan(local: plan(updatedAt: newer, isDeleted: true), remote: plan(updatedAt: newer)).isDeleted)
    }

    func testPlanRecordNameAndKind() {
        XCTAssertEqual(SyncMerge.cloudRecordName(kind: .plan, id: "abc"), "pl_abc")
        XCTAssertEqual(SyncRecordKind.plan.rawValue, "TallyInstallmentPlan")
        // Payment transactions use the deterministic plan-derived id.
        XCTAssertEqual(SyncMerge.cloudRecordName(kind: .transaction, id: "abc#3"), "tx_abc#3")
    }

    func testMaterializedPaymentsConvergeAcrossDevices() {
        // Two devices materialize the same payment independently: same id and content, so the
        // LWW merge collapses them into one record instead of duplicating.
        let p = plan(updatedAt: Date(timeIntervalSince1970: 1_000))
        let a = p.paymentTransaction(for: p.schedule[0])
        let b = p.paymentTransaction(for: p.schedule[0])
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a, b, "same plan revision, same payment record")
        let merged = SyncMerge.mergeTransaction(local: a, remote: b)
        XCTAssertEqual(merged.amountMinor, a.amountMinor)
        XCTAssertEqual(merged.planPaymentIndex, 0)
    }
}

final class SyncMergeReviewFixTests: XCTestCase {
    func testPlanMergeIsCommutativeOnFullTie() {
        let stamp = Date(timeIntervalSince1970: 5_000)
        let a = InstallmentPlanRecord(id: "p", name: "Same", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2026-01-15", updatedAt: stamp)
        var b = a
        b.months = 6
        b.firstPaymentDayKey = "2026-02-15"
        XCTAssertEqual(SyncMerge.mergePlan(local: a, remote: b), SyncMerge.mergePlan(local: b, remote: a))
        XCTAssertEqual(SyncMerge.mergePlan(local: a, remote: a), a)
    }

    func testTransactionMergeIsCommutativeOnFullTie() {
        let stamp = Date(timeIntervalSince1970: 5_000)
        let a = TransactionRecord(id: "t", name: "Same", amountMinor: 100, type: .expense, category: .food, dayKey: "2026-01-01", updatedAt: stamp)
        var b = a
        b.amountMinor = 200
        XCTAssertEqual(SyncMerge.mergeTransaction(local: a, remote: b), SyncMerge.mergeTransaction(local: b, remote: a))
    }
}

final class PlanPaymentMergePrecedenceTests: XCTestCase {
    private func plan(revision: Double = 500) -> InstallmentPlanRecord {
        InstallmentPlanRecord(id: "p", name: "IPP", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2026-01-15", updatedAt: Date(timeIntervalSince1970: revision))
    }

    private func userDeletion(_ tx: TransactionRecord, at t: Double) -> TransactionRecord {
        var deleted = tx
        deleted.isDeleted = true
        return deleted.recordingUserWrite(at: Date(timeIntervalSince1970: t))
    }

    private func withdrawal(_ tx: TransactionRecord, revision: Double) -> TransactionRecord {
        var content = PlanPaymentContent(tx)
        content.isDeleted = true
        let state = tx.effectivePaymentState.joined(with: PlanPaymentState(schedule: PlanPaymentScheduleWrite(
            planRevision: Date(timeIntervalSince1970: revision), content: content
        )))
        return tx.applying(state)
    }

    func testUserDeletionOutranksNewerAutomaticBookingBothWays() {
        let deletion = userDeletion(plan(revision: 500).paymentTransaction(for: plan().fullSchedule[3]), at: 1_000)
        let booking = plan(revision: 9_000).paymentTransaction(for: plan().fullSchedule[3])
        XCTAssertFalse(booking.hasUserPaymentWrite)
        XCTAssertTrue(SyncMerge.mergeTransaction(local: deletion, remote: booking).isDeleted)
        XCTAssertTrue(SyncMerge.mergeTransaction(local: booking, remote: deletion).isDeleted)

        // A schedule withdrawal must not replace the user deletion either.
        let withdrawn = withdrawal(booking, revision: 9_500)
        XCTAssertTrue(SyncMerge.mergeTransaction(local: deletion, remote: withdrawn).isUserDeletedPlanPayment)
    }

    func testLaterExplicitUserEditStillWins() {
        let deletion = userDeletion(plan().paymentTransaction(for: plan().fullSchedule[3]), at: 1_000)
        var edit = plan().paymentTransaction(for: plan().fullSchedule[3])
        edit.amountMinor = 12_345
        edit = edit.recordingUserWrite(at: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(SyncMerge.mergeTransaction(local: deletion, remote: edit).amountMinor, 12_345)
        XCTAssertEqual(SyncMerge.mergeTransaction(local: edit, remote: deletion).amountMinor, 12_345)
        XCTAssertFalse(SyncMerge.mergeTransaction(local: edit, remote: deletion).isDeleted)
    }

    func testConflictResolutionResendsOnlyWhenLocalWins() {
        let older = TransactionRecord(id: "t", name: "Old", amountMinor: 100, type: .expense, category: .food, dayKey: "2026-01-01", updatedAt: Date(timeIntervalSince1970: 1_000))
        var newer = older
        newer.name = "New"
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        let localWins = SyncMerge.resolveConflict(local: newer, server: older, merge: SyncMerge.mergeTransaction)
        XCTAssertTrue(localWins.resendLocal)
        XCTAssertEqual(localWins.merged, newer)

        let serverWins = SyncMerge.resolveConflict(local: older, server: newer, merge: SyncMerge.mergeTransaction)
        XCTAssertFalse(serverWins.resendLocal)
        XCTAssertEqual(serverWins.merged, newer)

        let same = SyncMerge.resolveConflict(local: newer, server: newer, merge: SyncMerge.mergeTransaction)
        XCTAssertFalse(same.resendLocal)

        let missingLocally = SyncMerge.resolveConflict(local: nil, server: older, merge: SyncMerge.mergeTransaction)
        XCTAssertFalse(missingLocally.resendLocal)
    }

    func testLegacyPayloadsDecodeWithoutNewFields() throws {
        let txJSON = #"{"id":"t","name":"x","amountMinor":100,"type":"expense","category":"food","dayKey":"2026-01-01","createdAt":0,"note":"","source":"manual","memberID":"me","memberName":"","needsReview":false,"updatedAt":0,"isDeleted":false,"planID":"p","planPaymentIndex":2}"#
        let tx = try JSONDecoder().decode(TransactionRecord.self, from: Data(txJSON.utf8))
        XCTAssertNil(tx.paymentState)
        // Without a state, a payment counts as an explicit user write at its `updatedAt`.
        XCTAssertTrue(tx.hasUserPaymentWrite)

        // A transaction written by the last shipped version (no plan fields at all) still decodes.
        let headJSON = #"{"id":"t","name":"x","amountMinor":100,"type":"expense","category":"food","dayKey":"2026-01-01","createdAt":0,"note":"","source":"manual","memberID":"me","memberName":"","needsReview":false,"updatedAt":0,"isDeleted":false}"#
        let head = try JSONDecoder().decode(TransactionRecord.self, from: Data(headJSON.utf8))
        XCTAssertNil(head.planID)
        XCTAssertNil(head.paymentState)
        XCTAssertFalse(head.isPlanPayment)

        let encoded = try JSONEncoder().encode(plan())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "deletionRemovesPayments")
        object.removeValue(forKey: "deletedDayKey")
        let legacy = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.deletionRemovesPayments)
        XCTAssertNil(legacy.deletedDayKey)
    }
}

/// Item 1: the plan-payment merge is a join. Every ordering and grouping of a set of writes to
/// one payment converges to one result, and that result honours "the latest explicit user
/// operation decides; automatic writes never override it".
final class PlanPaymentMergeConvergenceTests: XCTestCase {
    private func at(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }

    private func plan(revision: Double, total: Int64 = 120_000, months: Int = 12) -> InstallmentPlanRecord {
        InstallmentPlanRecord(id: "p", name: "IPP", totalMinor: total, months: months, firstPaymentDayKey: "2026-01-15", updatedAt: at(revision))
    }

    private func booking(revision: Double, total: Int64 = 120_000) -> TransactionRecord {
        let p = plan(revision: revision, total: total)
        return p.paymentTransaction(for: p.fullSchedule[3])
    }

    private func withdrawal(revision: Double) -> TransactionRecord {
        var p = plan(revision: revision)
        p.settledDayKey = "2026-02-01"
        return PlanPaymentLedger.reconcile(plan: p, payments: [booking(revision: 1)], todayKey: "2026-12-31", bookMissing: false)[0]
    }

    private func userWrite(_ base: TransactionRecord, at t: Double, deleted: Bool, amount: Int64? = nil, note: String = "") -> TransactionRecord {
        var tx = base
        tx.isDeleted = deleted
        if let amount { tx.amountMinor = amount }
        tx.note = note
        return tx.recordingUserWrite(at: at(t))
    }

    /// Writes from several devices: user deletion, edit, restore, bookings and withdrawals from
    /// older and newer plan revisions, same-revision booked/withdrawn, a timestamp tie and a
    /// payload from an app version without payment state.
    private func writes() -> [TransactionRecord] {
        var legacy = booking(revision: 1)
        legacy.paymentState = nil
        legacy.amountMinor = 4_321
        legacy.updatedAt = at(1_500)
        return [
            userWrite(booking(revision: 1), at: 1_000, deleted: true),          // t1 delete
            userWrite(booking(revision: 1), at: 2_000, deleted: false, amount: 777),  // t2 edit
            booking(revision: 3_000),                                            // t3 automatic booking
            withdrawal(revision: 3_000),                                         // same revision, withdrawn
            booking(revision: 4_000, total: 240_000),                            // newer revision
            withdrawal(revision: 500),                                           // stale withdrawal
            userWrite(booking(revision: 1), at: 2_000, deleted: false, amount: 778, note: "tie"),  // tie at t2
            legacy,                                                              // no state: user write at 1_500
        ]
    }

    private func merge(_ a: TransactionRecord, _ b: TransactionRecord) -> TransactionRecord {
        SyncMerge.mergeTransaction(local: a, remote: b)
    }

    func testDeleteEditBookingIsAssociative() {
        let deletion = userWrite(booking(revision: 1), at: 1_000, deleted: true)
        let edit = userWrite(booking(revision: 1), at: 2_000, deleted: false, amount: 777)
        let book = booking(revision: 3_000)
        let left = merge(merge(deletion, edit), book)
        let right = merge(merge(edit, book), deletion)
        XCTAssertEqual(left, right)
        XCTAssertEqual(left.amountMinor, 777, "the latest explicit user operation (the edit) decides")
        XCTAssertFalse(left.isDeleted)
    }

    func testAllOrderingsAndGroupingsConverge() {
        let all = writes()
        let expected = all.dropFirst().reduce(all[0], merge)
        // Rule: the latest explicit user write decides (the t2 tie breaks deterministically).
        XCTAssertFalse(expected.isDeleted)
        XCTAssertTrue([777, 778].contains(expected.amountMinor))
        XCTAssertEqual(expected.paymentState?.schedule?.planRevision, at(4_000), "newest revision kept for later use")

        // Commutative and idempotent pairwise.
        for a in all {
            XCTAssertEqual(merge(a, a), a)
            for b in all { XCTAssertEqual(merge(a, b), merge(b, a)) }
        }
        // Associative on every triple.
        for a in all { for b in all { for c in all {
            XCTAssertEqual(merge(merge(a, b), c), merge(a, merge(b, c)))
        } } }
        // Every permutation folded left and right.
        func permutations(_ items: [TransactionRecord]) -> [[TransactionRecord]] {
            guard items.count > 1 else { return [items] }
            return items.indices.flatMap { i -> [[TransactionRecord]] in
                var rest = items
                let head = rest.remove(at: i)
                return permutations(rest).map { [head] + $0 }
            }
        }
        for order in permutations(Array(all.prefix(7))) {
            let reference = all.prefix(7).dropFirst().reduce(all[0], merge)
            XCTAssertEqual(order.dropFirst().reduce(order[0], merge), reference)
            XCTAssertEqual(order.dropLast().reversed().reduce(order.last!) { merge($1, $0) }, reference)
        }
        // Random groupings (random binary trees) of shuffled writes, deterministic seed.
        var rng = SeededGenerator(seed: 42)
        for _ in 0..<500 {
            var pool = all.shuffled(using: &rng)
            while pool.count > 1 {
                let i = Int.random(in: 0..<pool.count, using: &rng)
                let a = pool.remove(at: i)
                let j = Int.random(in: 0..<pool.count, using: &rng)
                pool[j] = Bool.random(using: &rng) ? merge(a, pool[j]) : merge(pool[j], a)
            }
            XCTAssertEqual(pool[0], expected)
        }
    }

    func testAutomaticWritesNeverOverrideUserOperationWhateverTimestamps() {
        let deletion = userWrite(booking(revision: 1), at: 1_000, deleted: true)
        for automatic in [booking(revision: 9_000), withdrawal(revision: 9_000), booking(revision: 10_000, total: 240_000)] {
            XCTAssertTrue(merge(deletion, automatic).isUserDeletedPlanPayment)
            XCTAssertTrue(merge(automatic, deletion).isUserDeletedPlanPayment)
        }
    }

    func testOlderRevisionNeverBeatsNewerRevision() {
        let newer = booking(revision: 4_000, total: 240_000)
        let staleBooking = booking(revision: 3_000)
        XCTAssertEqual(merge(newer, staleBooking).amountMinor, 20_000)
        XCTAssertEqual(merge(staleBooking, newer).amountMinor, 20_000)
        XCTAssertFalse(merge(booking(revision: 4_000), withdrawal(revision: 3_000)).isDeleted)
        // Same revision: booked beats withdrawn (due on some device's day).
        XCTAssertFalse(merge(booking(revision: 3_000), withdrawal(revision: 3_000)).isDeleted)
    }
}

/// Small deterministic PRNG (SplitMix64) for reproducible property tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// `InstallmentPlanRecord.alreadyPaidPaymentCount` through CloudKit payloads and plan merge.
final class AlreadyPaidPlanSyncTests: XCTestCase {
    private func plan(alreadyPaid: Int?, revision: Double) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: "p", name: "Loan", kind: .loan, totalMinor: 120_000, months: 24, firstPaymentDayKey: "2026-01-15",
            monthlyPaymentMinor: 5_000, principalMinor: 100_000, alreadyPaidPaymentCount: alreadyPaid,
            updatedAt: Date(timeIntervalSince1970: revision)
        )
    }

    func testPayloadRoundTripAndLegacyPayload() throws {
        let record = plan(alreadyPaid: 9, revision: 10)
        let decoded = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.alreadyPaidPaymentCount, 9)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        object.removeValue(forKey: "alreadyPaidPaymentCount")
        let legacy = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.alreadyPaidPaymentCount)
    }

    func testMergeKeepsNewerRevisionsCountInEitherOrder() {
        let older = plan(alreadyPaid: nil, revision: 10)
        let newer = plan(alreadyPaid: 9, revision: 20)
        XCTAssertEqual(SyncMerge.mergePlan(local: older, remote: newer).alreadyPaidPaymentCount, 9)
        XCTAssertEqual(SyncMerge.mergePlan(local: newer, remote: older).alreadyPaidPaymentCount, 9)
        // Same revision, different counts: deterministic on both devices.
        let a = plan(alreadyPaid: 3, revision: 30)
        let b = plan(alreadyPaid: 5, revision: 30)
        XCTAssertEqual(SyncMerge.mergePlan(local: a, remote: b), SyncMerge.mergePlan(local: b, remote: a))
    }
}

final class HouseholdSettingsSyncTests: XCTestCase {
    func testHouseholdSettingsMergeAndRecordName() {
        XCTAssertEqual(SyncRecordKind.householdSettings.rawValue, "TallyHouseholdSettings")
        XCTAssertEqual(
            SyncMerge.cloudRecordName(kind: .householdSettings, id: HouseholdSettingsRecord.singletonID),
            "hs_household"
        )

        let older = HouseholdSettingsRecord(currency: .sgd, updatedAt: Date(timeIntervalSince1970: 1_000))
        let newer = HouseholdSettingsRecord(currency: .vnd, updatedAt: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(SyncMerge.mergeHouseholdSettings(local: nil, remote: newer), newer)
        XCTAssertEqual(SyncMerge.mergeHouseholdSettings(local: older, remote: newer), newer)
        XCTAssertEqual(SyncMerge.mergeHouseholdSettings(local: newer, remote: older), newer)

        // Tie on updatedAt is commutative and idempotent
        let t = Date(timeIntervalSince1970: 3_000)
        let a = HouseholdSettingsRecord(currency: .sgd, updatedAt: t)
        let b = HouseholdSettingsRecord(currency: .vnd, updatedAt: t)
        XCTAssertEqual(
            SyncMerge.mergeHouseholdSettings(local: a, remote: b),
            SyncMerge.mergeHouseholdSettings(local: b, remote: a)
        )
        XCTAssertEqual(SyncMerge.mergeHouseholdSettings(local: a, remote: a), a)
    }
}
