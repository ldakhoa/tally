import BudgetKit
import TallyCore
import XCTest

/// Regression tests for the installment/loan review findings D–G and I.
final class InstallmentReviewFixTests: XCTestCase {
    // MARK: D — import validation

    func testBackupWithHugeMonthsIsSkippedNotCrashing() throws {
        let json = """
        {"version":1,"currency":"SGD","transactions":[],"budgets":{},"goals":[],
         "plans":[{"id":"p-huge","name":"Bad","kind":"installment","total":120000,
                   "months":9223372036854775807,"firstPaymentDate":"2026-01-15","category":"shopping",
                   "deletedPaymentIndexes":[1]},
                  {"id":"p-ok","name":"Good","kind":"installment","total":120000,
                   "months":12,"firstPaymentDate":"2026-01-15","category":"shopping"}]}
        """
        let decoded = try WebBackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.plans.map(\.id), ["p-ok"])
        XCTAssertFalse(decoded.transactions.contains { $0.planID == "p-huge" })
    }

    func testBackupWithOverflowingMonthlyPaymentIsSkipped() throws {
        let json = """
        {"version":1,"currency":"VND","transactions":[],"budgets":{},"goals":[],
         "plans":[{"id":"p-big","name":"Bad","kind":"loan","total":9223372036854775807,
                   "months":600,"firstPaymentDate":"2026-01-15","category":"bills",
                   "monthlyPayment":9223372036854775807,"principal":100}]}
        """
        let decoded = try WebBackupCodec.decode(Data(json.utf8))
        XCTAssertTrue(decoded.plans.isEmpty)
    }

    func testPaymentAmountsNeverTrapOnExtremeInput() {
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: .max, months: .max, step: 100), [])
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: .max, months: 600, regularMinor: .max, step: 100).count, 600)
        let amounts = InstallmentPlanRecord.paymentAmounts(totalMinor: .max, months: 600, step: 100)
        XCTAssertEqual(amounts.count, 600)
        XCTAssertTrue(amounts.allSatisfy { $0 > 0 })
    }

    // MARK: E — rounding

    func testTinyVNDInstallmentCannotProduceZeroPayments() {
        // ₫5 over 12 months: storage 500, step 100.
        let plan = InstallmentPlanRecord(name: "Tiny", totalMinor: 500, months: 12, firstPaymentDayKey: "2026-01-15", currency: .vnd)
        XCTAssertTrue(plan.fullSchedule.allSatisfy { $0.amountMinor > 0 })

        let draft = InstallmentPlanDraft(name: "Tiny", amountMinor: 500, months: 12, firstPaymentDayKey: "2026-01-15", currency: .vnd)
        XCTAssertFalse(draft.isValid)
        XCTAssertNil(draft.makeRecord())
    }

    func testExplicitVNDMonthlyPaymentIsRoundedToWholeDong() throws {
        let draft = InstallmentPlanDraft(
            kind: .loan, name: "Loan", amountMinor: 1_000, monthlyPaymentMinor: 155,
            months: 12, firstPaymentDayKey: "2026-01-15", currency: .vnd
        )
        let record = try XCTUnwrap(draft.makeRecord())
        XCTAssertTrue(record.fullSchedule.allSatisfy { $0.amountMinor % 100 == 0 }, "\(record.fullSchedule.map(\.amountMinor))")

        let amounts = InstallmentPlanRecord.paymentAmounts(totalMinor: 155 * 12, months: 12, regularMinor: 155, step: 100)
        XCTAssertTrue(amounts.dropLast().allSatisfy { $0 % 100 == 0 }, "\(amounts)")
    }

    // MARK: F — amortization

    func testLongLoanLastRowHasNonNegativeInterest() {
        let loan = InstallmentPlanRecord.loan(
            name: "Mortgage", principalMinor: 627_021, monthlyPaymentMinor: 3_212,
            months: 240, firstPaymentDayKey: "2026-01-10"
        )
        let rows = loan.amortizationSchedule
        XCTAssertEqual(rows.count, 240)
        XCTAssertTrue(rows.allSatisfy { $0.interestMinor >= 0 && $0.principalMinor >= 0 }, "last: \(String(describing: rows.last))")
        XCTAssertEqual(rows.last?.outstandingPrincipalMinor, 0)
        XCTAssertEqual(rows.map(\.paymentMinor).reduce(0, +), loan.totalMinor)
        XCTAssertEqual(rows.map(\.principalMinor).reduce(0, +), 627_021)
        XCTAssertEqual(rows.map(\.interestMinor).reduce(0, +), loan.totalInterestMinor)
        for row in rows { XCTAssertEqual(row.interestMinor + row.principalMinor, row.paymentMinor) }
    }

    // MARK: G — backup tombstones outside a shortened term

    func testDeletedPaymentIndexBeyondShortenedTermSurvivesBackup() throws {
        let plan = InstallmentPlanRecord(id: "p-g", name: "Phone", totalMinor: 90_000, months: 3, firstPaymentDayKey: "2026-01-15", currency: .sgd)
        // Payment 6 was deleted while the plan still ran 12 months.
        let longer = InstallmentPlanRecord(id: "p-g", name: "Phone", totalMinor: 90_000, months: 12, firstPaymentDayKey: "2026-01-15", currency: .sgd)
        var tomb = longer.paymentTransaction(for: longer.fullSchedule[6])
        tomb.isDeleted = true
        tomb = tomb.recordingUserWrite(at: Date())

        let data = try WebBackupCodec.encode(currency: .sgd, transactions: [tomb], budgets: [], goals: [], plans: [plan])
        let decoded = try WebBackupCodec.decode(data)
        let restored = decoded.transactions.first { $0.id == InstallmentPlanRecord.paymentTransactionID(planID: "p-g", index: 6) }
        XCTAssertEqual(restored?.isDeleted, true)
        XCTAssertEqual(restored?.planPaymentIndex, 6)
    }

    // MARK: I — rate solver bracket

    func testSolverFindsRateOutsideInitialBracket() {
        let rate = InstallmentMath.solveMonthlyRate(principalMinor: 1, payments: [1_000])
        XCTAssertEqual(rate, 999, accuracy: 1e-6)
        // Normal and zero-interest cases unchanged.
        XCTAssertEqual(InstallmentMath.solveMonthlyRate(principalMinor: 1_000, payments: [500, 500]), 0)
        let normal = InstallmentMath.solveMonthlyRate(principalMinor: 1_000_000, payments: Array(repeating: 88_849, count: 12))
        XCTAssertEqual(normal, 0.01, accuracy: 1e-4)
    }
}

final class PlanPaymentLedgerTests: XCTestCase {
    private func plan(first: String = "2026-09-15") -> InstallmentPlanRecord {
        InstallmentPlanRecord(id: "p", name: "Sofa", totalMinor: 120_000, months: 12, firstPaymentDayKey: first)
    }

    private func byID(_ records: [TransactionRecord]) -> [String: TransactionRecord] {
        Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }

    func testStartMovedLaterWithdrawsAndRebooksWhenDue() {
        let original = plan()
        let booked = PlanPaymentLedger.reconcile(plan: original, payments: [], todayKey: "2026-11-24", bookMissing: true)
        XCTAssertEqual(booked.count, 3)

        var moved = plan(first: "2027-01-15")
        moved.updatedAt = original.updatedAt.addingTimeInterval(60)
        let revisions = PlanPaymentLedger.reconcile(plan: moved, payments: booked, todayKey: "2026-11-24", bookMissing: true)
        XCTAssertEqual(revisions.count, 3)
        XCTAssertTrue(revisions.allSatisfy { $0.isDeleted && $0.planPaymentIndex != nil && !$0.hasUserPaymentWrite })
        XCTAssertFalse(revisions.contains { $0.isUserDeletedPlanPayment })

        let state = Array(byID(booked).merging(byID(revisions)) { $1 }.values)
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: moved, payments: state, todayKey: "2026-12-31", bookMissing: true).isEmpty)
        let rebooked = PlanPaymentLedger.reconcile(plan: moved, payments: state, todayKey: "2027-01-15", bookMissing: true)
        XCTAssertEqual(rebooked.map(\.dayKey), ["2027-01-15"])
        XCTAssertEqual(rebooked.first?.isDeleted, false)
    }

    func testUserDeletionIsNeverRebooked() {
        let p = plan()
        var deleted = p.paymentTransaction(for: p.fullSchedule[0])
        deleted.isDeleted = true
        deleted = deleted.recordingUserWrite(at: Date())
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: p, payments: [deleted], todayKey: "2026-09-30", bookMissing: true).isEmpty)
    }

    func testArrivalCheckLeavesUserEditsAndSameRevisionBookingsAlone() {
        var p = plan()
        // Booked by a device whose local day was already 2027-02-15 (same plan revision).
        let early = p.paymentTransaction(for: p.fullSchedule[5])
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: p, payments: [early], todayKey: "2026-11-24", bookMissing: false).isEmpty)

        var edited = p.paymentTransaction(for: p.fullSchedule[5])
        edited.amountMinor = 1
        edited = edited.recordingUserWrite(at: Date())
        p.settledDayKey = "2026-12-01"
        p.updatedAt = p.updatedAt.addingTimeInterval(60)
        XCTAssertTrue(PlanPaymentLedger.reconcile(plan: p, payments: [edited], todayKey: "2026-11-24", bookMissing: false).isEmpty,
                      "automatic withdrawal never overrides a user edit")
        let out = PlanPaymentLedger.reconcile(plan: p, payments: [early], todayKey: "2026-11-24", bookMissing: false)
        XCTAssertEqual(out.map(\.isDeleted), [true], "a booking from an older revision is withdrawn")
    }

    func testDeletedPlanKeepsPaymentsUpToDeletionDayOrRemovesAll() {
        var p = plan()
        let payments = p.fullSchedule.prefix(4).map { p.paymentTransaction(for: $0) }  // Sep–Dec
        p.isDeleted = true
        p.deletedDayKey = "2026-11-20"
        p.updatedAt = p.updatedAt.addingTimeInterval(60)
        let kept = PlanPaymentLedger.reconcile(plan: p, payments: payments, todayKey: "2026-11-20", bookMissing: false)
        XCTAssertEqual(kept.filter(\.isDeleted).map(\.dayKey), ["2026-12-15"])

        p.deletionRemovesPayments = true
        let removed = PlanPaymentLedger.reconcile(plan: p, payments: payments, todayKey: "2026-11-20", bookMissing: false)
        XCTAssertEqual(removed.count, 4)
        XCTAssertTrue(removed.allSatisfy(\.isUserDeletedPlanPayment))
    }

    /// Item 3: retention after "delete plan, keep payments" follows the deleted plan's schedule
    /// and the payment index, not the arriving payment's own (stale) date.
    func testDeleteAndKeepUsesDeletedPlansScheduleNotStaleDate() {
        let march = plan(first: "2026-03-15")
        let staleMarchBooking = march.paymentTransaction(for: march.fullSchedule[0])  // index 0 on 03-15
        var deleted = plan(first: "2026-04-15")  // a plan edit moved index 0 to April
        deleted.updatedAt = march.updatedAt.addingTimeInterval(120)
        deleted.isDeleted = true
        deleted.deletionRemovesPayments = false
        deleted.deletedDayKey = "2026-03-20"
        let out = PlanPaymentLedger.reconcile(plan: deleted, payments: [staleMarchBooking], todayKey: "2026-03-25", bookMissing: false)
        XCTAssertEqual(out.map(\.isDeleted), [true])
        XCTAssertEqual(out.first?.dayKey, "2026-04-15")

        // A payment the deleted plan scheduled on or before the deletion day is kept, rewritten to
        // the deleted revision's content.
        var deletedLater = deleted
        deletedLater.deletedDayKey = "2026-04-20"
        let kept = PlanPaymentLedger.reconcile(plan: deletedLater, payments: [staleMarchBooking], todayKey: "2026-04-25", bookMissing: false)
        XCTAssertEqual(kept.map(\.isDeleted), [false])
        XCTAssertEqual(kept.first?.dayKey, "2026-04-15")
    }

    func testDraftReportsTooSmallAmount() {
        let draft = InstallmentPlanDraft(name: "Tiny", amountMinor: 500, months: 12, firstPaymentDayKey: "2026-01-15", currency: .vnd)
        XCTAssertEqual(draft.issues, [.amountTooSmallForMonths(minimumMinor: 1_200)])
        XCTAssertTrue(InstallmentPlanDraft(name: "Ok", amountMinor: 1_200, months: 12, firstPaymentDayKey: "2026-01-15", currency: .vnd).isValid)
    }

    func testRemotePayloadValidation() {
        var huge = plan()
        huge.months = Int.max
        XCTAssertFalse(huge.hasValidTerms)
        var overflowing = plan()
        overflowing.totalMinor = .max
        XCTAssertFalse(overflowing.hasValidTerms)
        XCTAssertTrue(plan().hasValidTerms)
        XCTAssertEqual(InstallmentPlanDraft.maxMonths, InstallmentPlanRecord.maxMonths)
    }

    func testConvertedPlanIDIsDeterministic() {
        XCTAssertEqual(
            InstallmentPlanRecord.convertedPlanID(sourceTransactionID: "tx-1"),
            InstallmentPlanRecord.convertedPlanID(sourceTransactionID: "tx-1")
        )
    }
}

final class TrendChartBarTests: XCTestCase {
    func testMonthsWithHiddenSalaryAreNotPlotted() {
        let trend = [
            MonthlyTrendPoint(monthKey: "2026-10", incomeMinor: 900_000, spendingMinor: 120_000, transactionCount: 5, includesSalary: true),
            MonthlyTrendPoint(monthKey: "2026-11", incomeMinor: 800_000, spendingMinor: 90_000, transactionCount: 4, includesSalary: true),
        ]
        let hidden = TrendChartBar.bars(for: trend, hideSalary: true)
        XCTAssertFalse(hidden.contains { $0.kind == .income })
        XCTAssertEqual(hidden.map(\.amountMinor).max(), 120_000, "axis scale must come from spending only")

        let visible = TrendChartBar.bars(for: trend, hideSalary: false)
        XCTAssertEqual(visible.filter { $0.kind == .income }.map(\.amountMinor), [900_000, 800_000])
    }
}
