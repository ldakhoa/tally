@testable import BudgetKit
import TallyCore
import XCTest

/// `InstallmentPlanRecord.alreadyPaidPaymentCount`: leading payments that count as paid but are
/// never booked as expenses by the plan.
final class AlreadyPaidPaymentsTests: XCTestCase {
    private func date(_ dayKey: String) -> Date {
        DateKey.date(fromDayKey: dayKey)!.addingTimeInterval(12 * 3600)
    }

    /// 24-month loan from 2026-01-15: 1,000.00 borrowed, 50.00 a month (1,200.00 in total).
    private func loan(alreadyPaid: Int? = nil, updatedAt: String = "2026-01-01") -> InstallmentPlanRecord {
        InstallmentPlanRecord.loan(
            id: "loan-1",
            name: "Car loan",
            principalMinor: 100_000,
            monthlyPaymentMinor: 5_000,
            months: 24,
            firstPaymentDayKey: "2026-01-15",
            lender: "DBS",
            alreadyPaidPaymentCount: alreadyPaid,
            createdAt: date("2026-01-01"),
            updatedAt: date(updatedAt)
        )
    }

    private func liveIndexes(_ records: [TransactionRecord]) -> [Int] {
        records.filter { !$0.isDeleted }.compactMap(\.planPaymentIndex).sorted()
    }

    private func merged(_ base: [TransactionRecord], _ revisions: [TransactionRecord]) -> [TransactionRecord] {
        var byID = Dictionary(base.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for revision in revisions { byID[revision.id] = revision }
        return Array(byID.values)
    }

    // MARK: Schedule & progress

    func testDefaultKeepsCurrentBehaviour() {
        let plain = loan()
        XCTAssertEqual(plain.effectiveAlreadyPaidCount, 0)
        XCTAssertEqual(loan(alreadyPaid: 0).progress(todayKey: "2026-11-24"), plain.progress(todayKey: "2026-11-24"))
        XCTAssertTrue(InstallmentScheduleRow.rows(for: plain, todayKey: "2026-11-24").allSatisfy { $0.state != .paidOutsidePlan })
    }

    func testProgressCountsAlreadyPaidPaymentsAsPaid() {
        // Nine payments made (Jan-Sep), today is 2026-11-24: eleven are due by date.
        let p = loan(alreadyPaid: 9)
        let progress = p.progress(todayKey: "2026-11-24")
        XCTAssertEqual(progress.paidCount, 11)
        XCTAssertEqual(progress.remainingMinor, 13 * 5_000)
        XCTAssertEqual(progress.nextPaymentDayKey, "2026-12-15")

        // Paid ahead of the calendar: more already-paid payments than are due by date.
        let ahead = loan(alreadyPaid: 14).progress(todayKey: "2026-11-24")
        XCTAssertEqual(ahead.paidCount, 14)
        XCTAssertEqual(ahead.remainingMinor, 10 * 5_000)
        XCTAssertEqual(ahead.nextPaymentDayKey, "2027-03-15")
        let rows = loan(alreadyPaid: 14).amortizationSchedule
        XCTAssertEqual(ahead.outstandingPrincipalMinor, rows[13].outstandingPrincipalMinor)
        XCTAssertEqual(ahead.interestPaidMinor, rows.prefix(14).reduce(0) { $0 + $1.interestMinor })
        XCTAssertEqual(ahead.interestRemainingMinor, rows.dropFirst(14).reduce(0) { $0 + $1.interestMinor })
    }

    func testFullyAlreadyPaidPlanIsCompletedAndOwesNothing() {
        let p = loan(alreadyPaid: 24)
        let progress = p.progress(todayKey: "2026-02-01")
        XCTAssertTrue(progress.isCompleted)
        XCTAssertEqual(progress.remainingMinor, 0)
        XCTAssertEqual(progress.outstandingPrincipalMinor, 0)
        XCTAssertEqual(InstallmentPlanRecord.remainingDebtMinor(plans: [p], todayKey: "2026-02-01"), 0)
        XCTAssertEqual(InstallmentPlanRecord.outstandingPrincipalMinor(plans: [p], todayKey: "2026-02-01"), 0)
        let overview = CommitmentsOverview(plans: [p], todayKey: "2026-02-01")
        XCTAssertEqual(overview.active.count, 0)
        XCTAssertEqual(overview.committedThisMonthMinor, 0)
        XCTAssertEqual(overview.remainingDebtMinor, 0)
    }

    func testCommitmentsOverviewUsesAlreadyPaidProgress() {
        let overview = CommitmentsOverview(plans: [loan(alreadyPaid: 14)], todayKey: "2026-11-24")
        XCTAssertEqual(overview.remainingDebtMinor, 10 * 5_000)
        XCTAssertEqual(overview.nextPayment?.payment.dayKey, "2027-03-15")
        // The month's scheduled payment is still this month's commitment, whoever booked it.
        XCTAssertEqual(overview.committedThisMonthMinor, 5_000)
    }

    func testScheduleRowsMarkAlreadyPaidPaymentsDistinctly() {
        let rows = InstallmentScheduleRow.rows(for: loan(alreadyPaid: 9), todayKey: "2026-11-24")
        XCTAssertEqual(rows.filter { $0.state == .paidOutsidePlan }.map(\.index), Array(0..<9))
        XCTAssertEqual(rows.filter { $0.state == .paid }.map(\.index), [9, 10])
        XCTAssertEqual(rows.filter { $0.state == .upcoming }.count, 13)

        var settled = loan(alreadyPaid: 9)
        settled.settledDayKey = "2026-05-20"
        let settledRows = InstallmentScheduleRow.rows(for: settled, todayKey: "2026-11-24")
        XCTAssertEqual(settledRows.filter { $0.state == .paidOutsidePlan }.count, 5)
        XCTAssertEqual(settledRows.filter { $0.state == .cancelled }.count, 19)
    }

    func testSettlementPreviewDoesNotCountUnbookedPaymentsAsRemoved() {
        let preview = InstallmentSettlementPreview(plan: loan(alreadyPaid: 9), settleDayKey: "2026-03-01", todayKey: "2026-11-24")
        // Cancelled Mar-Nov are due by today, but Mar-Sep were never booked by the plan.
        XCTAssertEqual(preview.cancelledPaymentCount, 22)
        XCTAssertEqual(preview.bookedPaymentsRemovedCount, 2)
    }

    // MARK: Validation & draft

    func testValidationRejectsOutOfRangeCounts() {
        XCTAssertTrue(loan(alreadyPaid: 24).hasValidTerms)
        XCTAssertFalse(loan(alreadyPaid: 25).hasValidTerms)
        XCTAssertFalse(loan(alreadyPaid: -1).hasValidTerms)

        var draft = InstallmentPlanDraft(plan: loan(alreadyPaid: 9))
        XCTAssertEqual(draft.alreadyPaidCount, 9)
        XCTAssertTrue(draft.isValid)
        draft.alreadyPaidCount = 30
        XCTAssertEqual(draft.issues, [.alreadyPaidOutOfRange(maxCount: 24)])
        draft.alreadyPaidCount = 0
        XCTAssertNil(draft.makeRecord(existing: loan(alreadyPaid: 9))?.alreadyPaidPaymentCount)
        draft.alreadyPaidCount = 3
        XCTAssertEqual(draft.makeRecord(existing: loan())?.alreadyPaidPaymentCount, 3)
        XCTAssertTrue(draft.startsOnOrBefore("2026-11-24"))
        XCTAssertFalse(draft.startsOnOrBefore("2025-12-31"))
        XCTAssertEqual(draft.duePaymentCount(todayKey: "2026-11-24"), 11)
    }

    // MARK: Materialisation & reconcile

    func testMaterialisationNeverBooksAlreadyPaidPayments() {
        let booked = PlanPaymentLedger.reconcile(plan: loan(alreadyPaid: 9), payments: [], todayKey: "2026-11-24", bookMissing: true)
        XCTAssertEqual(liveIndexes(booked), [9, 10])
        XCTAssertTrue(booked.allSatisfy { !$0.isDeleted })
        // Idempotent.
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: loan(alreadyPaid: 9), payments: booked, todayKey: "2026-11-24", bookMissing: true).isEmpty)
        // A deleted plan keeping its payments still never books them.
        var deleted = loan(alreadyPaid: 9, updatedAt: "2026-11-24")
        deleted.isDeleted = true
        deleted.deletionRemovesPayments = false
        deleted.deletedDayKey = "2026-11-24"
        XCTAssertEqual(PlanPaymentLedger.scheduleWrite(plan: deleted, index: 3, todayKey: "2026-11-24")?.isBooked, false)
        XCTAssertEqual(PlanPaymentLedger.scheduleWrite(plan: deleted, index: 9, todayKey: "2026-11-24")?.isBooked, true)
    }

    func testRaisingCountWithdrawsAutomaticBookingsButKeepsUserEdits() {
        // Added with no already-paid payments: Jan-Nov booked.
        var payments = PlanPaymentLedger.reconcile(plan: loan(), payments: [], todayKey: "2026-11-24", bookMissing: true)
        XCTAssertEqual(liveIndexes(payments), Array(0...10))

        // The user edited March and deleted April explicitly.
        let marchID = InstallmentPlanRecord.paymentTransactionID(planID: "loan-1", index: 2)
        let aprilID = InstallmentPlanRecord.paymentTransactionID(planID: "loan-1", index: 3)
        var march = payments.first { $0.id == marchID }!
        march.note = "paid late"
        march = march.recordingUserWrite(at: date("2026-03-20"))
        var april = payments.first { $0.id == aprilID }!
        april.isDeleted = true
        april = april.recordingUserWrite(at: date("2026-04-20"))
        payments = merged(payments, [march, april])

        // Later revision says nine payments were already recorded elsewhere.
        let raised = loan(alreadyPaid: 9, updatedAt: "2026-11-24")
        let revisions = PlanPaymentLedger.reconcile(plan: raised, payments: payments, todayKey: "2026-11-24", bookMissing: true)
        payments = merged(payments, revisions)
        XCTAssertEqual(liveIndexes(payments), [2, 9, 10], "automatic bookings for 0..<9 withdrawn; the user's edit stays")
        XCTAssertEqual(payments.first { $0.id == marchID }?.note, "paid late")
        XCTAssertEqual(payments.first { $0.id == aprilID }?.isDeleted, true)
        XCTAssertFalse(revisions.contains { $0.id == marchID || $0.id == aprilID }, "user-decided payments are never touched")
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: raised, payments: payments, todayKey: "2026-11-24", bookMissing: true).isEmpty)
    }

    func testLoweringCountBooksNewlyUncoveredDuePayments() {
        let start = loan(alreadyPaid: 9)
        var payments = PlanPaymentLedger.reconcile(plan: start, payments: [], todayKey: "2026-11-24", bookMissing: true)
        XCTAssertEqual(liveIndexes(payments), [9, 10])

        let lowered = loan(alreadyPaid: 6, updatedAt: "2026-11-24")
        payments = merged(payments, PlanPaymentLedger.reconcile(plan: lowered, payments: payments, todayKey: "2026-11-24", bookMissing: true))
        XCTAssertEqual(liveIndexes(payments), [6, 7, 8, 9, 10])

        // Raise, then lower again: the withdrawn bookings come back under the newest revision.
        let raised = loan(alreadyPaid: 10, updatedAt: "2026-11-25")
        payments = merged(payments, PlanPaymentLedger.reconcile(plan: raised, payments: payments, todayKey: "2026-11-25", bookMissing: true))
        XCTAssertEqual(liveIndexes(payments), [10])
        let loweredAgain = loan(alreadyPaid: 8, updatedAt: "2026-11-26")
        payments = merged(payments, PlanPaymentLedger.reconcile(plan: loweredAgain, payments: payments, todayKey: "2026-11-26", bookMissing: true))
        XCTAssertEqual(liveIndexes(payments), [8, 9, 10])
    }

    func testArrivingBookingFromOlderRevisionIsWithdrawn() {
        // Another device booked February under the revision without already-paid payments.
        let old = loan()
        let february = old.paymentTransaction(for: old.fullSchedule[1])
        let current = loan(alreadyPaid: 9, updatedAt: "2026-11-24")
        let out = PlanPaymentLedger.reconcile(plan: current, payments: [february], todayKey: "2026-11-24", bookMissing: false)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.isDeleted, true)
        // Merging in either order converges on the withdrawn state.
        XCTAssertEqual(
            february.effectivePaymentState.joined(with: out[0].effectivePaymentState),
            out[0].effectivePaymentState.joined(with: february.effectivePaymentState)
        )
    }

    // MARK: Backup & coding

    func testBackupRoundTripsAlreadyPaidCount() throws {
        let p = loan(alreadyPaid: 9)
        let data = try WebBackupCodec.encode(currency: .sgd, transactions: [], budgets: [], goals: [], plans: [p])
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"alreadyPaidPayments\" : 9"))
        let decoded = try WebBackupCodec.decode(data)
        XCTAssertEqual(decoded.plans.first?.alreadyPaidPaymentCount, 9)

        // A backup holding a booked payment for an already-paid index restores it as a user write
        // (the plan's schedule does not book that index).
        var booked = loan().paymentTransaction(for: p.fullSchedule[2])
        booked.paymentState = nil
        let restored = PlanPaymentLedger.importedPayment(booked, plan: p)
        XCTAssertNotNil(restored.paymentState?.user)
    }

    func testRecordJSONWithoutFieldStillDecodes() throws {
        let data = try JSONEncoder().encode(loan(alreadyPaid: 9))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["alreadyPaidPaymentCount"] as? Int, 9)
        object.removeValue(forKey: "alreadyPaidPaymentCount")
        let legacy = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.alreadyPaidPaymentCount)
        XCTAssertEqual(legacy.effectiveAlreadyPaidCount, 0)
    }
}
