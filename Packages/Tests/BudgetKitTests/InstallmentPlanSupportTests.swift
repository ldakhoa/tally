import BudgetKit
import TallyCore
import XCTest

final class InstallmentPlanSupportTests: XCTestCase {
    private func loanDraft(
        amount: Int64 = 1_000_000,
        monthly: Int64 = 90_000,
        months: Int? = 12
    ) -> InstallmentPlanDraft {
        InstallmentPlanDraft(
            kind: .loan,
            name: "Car loan",
            lender: " DBS ",
            amountMinor: amount,
            monthlyPaymentMinor: monthly,
            months: months,
            firstPaymentDayKey: "2026-12-05",
            category: .bills,
            currency: .sgd
        )
    }

    // MARK: Draft validation

    func testLoanBelowPrincipalIsRejectedWithShortfall() {
        // 12 x 80,000 = 960,000 < 1,000,000
        let draft = loanDraft(monthly: 80_000)
        XCTAssertEqual(draft.issues, [.paymentsBelowPrincipal(shortfallMinor: 40_000)])
        XCTAssertFalse(draft.isValid)
        XCTAssertNil(draft.makeRecord())
    }

    func testLoanAtExactlyPrincipalIsValidAndInterestFree() throws {
        // 10 x 100,000 == 1,000,000 -> 0% loan
        let draft = loanDraft(monthly: 100_000, months: 10)
        XCTAssertTrue(draft.isValid)
        let record = try XCTUnwrap(draft.makeRecord())
        XCTAssertEqual(record.totalInterestMinor, 0)
        XCTAssertEqual(record.effectiveAnnualRate, 0)
    }

    func testValidLoanBuildsRecord() throws {
        let draft = loanDraft()
        XCTAssertTrue(draft.isValid)
        let record = try XCTUnwrap(draft.makeRecord())
        XCTAssertEqual(record.kind, .loan)
        XCTAssertEqual(record.principalMinor, 1_000_000)
        XCTAssertEqual(record.monthlyPaymentMinor, 90_000)
        XCTAssertEqual(record.totalMinor, 1_080_000)
        XCTAssertEqual(record.totalInterestMinor, 80_000)
        XCTAssertEqual(record.lender, "DBS")
        XCTAssertGreaterThan(record.effectiveAnnualRate, 0)
        XCTAssertEqual(record.fullSchedule.count, 12)
    }

    func testMissingFieldsReportIssues() {
        var draft = InstallmentPlanDraft(firstPaymentDayKey: "2026-12-05")
        XCTAssertEqual(draft.issues, [.missingName, .invalidAmount, .invalidMonths])
        draft.name = "Phone"
        draft.amountMinor = 120_000
        draft.months = 0
        XCTAssertEqual(draft.issues, [.invalidMonths])
        draft.months = InstallmentPlanDraft.maxMonths + 1
        XCTAssertEqual(draft.issues, [.invalidMonths])
        draft.months = 12
        XCTAssertTrue(draft.isValid)
        draft.firstPaymentDayKey = "garbage"
        XCTAssertEqual(draft.issues, [.invalidFirstPaymentDay])

        var loan = loanDraft(monthly: 0)
        XCTAssertEqual(loan.issues, [.missingMonthlyPayment])
        loan.name = "   "
        XCTAssertTrue(loan.issues.contains(.missingName))
    }

    func testPreviewRecordAppearsOnlyWhenUsable() {
        XCTAssertNil(loanDraft(monthly: 0).previewRecord())
        XCTAssertNil(loanDraft(months: nil).previewRecord())
        // Below principal still previews (rate 0) so the UI can show numbers next to the error.
        let below = loanDraft(monthly: 80_000).previewRecord()
        XCTAssertNotNil(below)
        XCTAssertEqual(below?.totalInterestMinor, 0)
        XCTAssertNotNil(loanDraft().previewRecord())
    }

    func testInstallmentDraftBuildsRecordWithoutLoanFields() throws {
        var draft = InstallmentPlanDraft(
            kind: .installment,
            name: "  Laptop ",
            lender: "ignored",
            amountMinor: 51_500,
            months: 12,
            firstPaymentDayKey: "2026-11-15",
            linkText: "https://example.com",
            currency: .sgd
        )
        draft.note = " 0% IPP "
        let record = try XCTUnwrap(draft.makeRecord())
        XCTAssertEqual(record.name, "Laptop")
        XCTAssertEqual(record.note, "0% IPP")
        XCTAssertEqual(record.totalMinor, 51_500)
        XCTAssertNil(record.principalMinor)
        XCTAssertNil(record.monthlyPaymentMinor)
        XCTAssertNil(record.lender)
        XCTAssertNil(record.linkURL)
    }

    func testEditingKeepsIdentitySettlementAndSource() throws {
        var existing = InstallmentPlanRecord(
            id: "plan-9",
            name: "Old",
            totalMinor: 51_500,
            months: 12,
            firstPaymentDayKey: "2026-11-15",
            sourceTransactionID: "tx-1",
            settledDayKey: "2027-03-01",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        existing.monthlyPaymentMinor = 4_292
        var draft = InstallmentPlanDraft(plan: existing)
        draft.name = "New"
        let updated = try XCTUnwrap(draft.makeRecord(existing: existing, now: Date(timeIntervalSince1970: 500)))
        XCTAssertEqual(updated.id, "plan-9")
        XCTAssertEqual(updated.sourceTransactionID, "tx-1")
        XCTAssertEqual(updated.settledDayKey, "2027-03-01")
        XCTAssertEqual(updated.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 500))
        // Total and months untouched -> the bank-quoted regular payment survives.
        XCTAssertEqual(updated.monthlyPaymentMinor, 4_292)

        draft.months = 6
        let shortened = try XCTUnwrap(draft.makeRecord(existing: existing))
        XCTAssertNil(shortened.monthlyPaymentMinor)
    }

    func testLoanRoundTripThroughDraftKeepsExplicitTotal() throws {
        // Bank's final payment differs: total is not monthly x months.
        let loan = InstallmentPlanRecord.loan(
            id: "loan-1",
            name: "Trust",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 90_000,
            months: 12,
            firstPaymentDayKey: "2026-12-05",
            totalMinor: 1_079_950,
            lender: "Trust"
        )
        var draft = InstallmentPlanDraft(plan: loan)
        XCTAssertEqual(draft.amountMinor, 1_000_000)
        XCTAssertEqual(draft.monthlyPaymentMinor, 90_000)
        draft.note = "changed note only"
        XCTAssertEqual(draft.makeRecord(existing: loan)?.totalMinor, 1_079_950)
        draft.monthlyPaymentMinor = 91_000
        XCTAssertEqual(draft.makeRecord(existing: loan)?.totalMinor, 1_092_000)
    }

    func testLinkIsDroppedWhenUnrecognized() throws {
        var draft = loanDraft()
        draft.linkText = "not a link"
        XCTAssertTrue(draft.linkIsUnrecognized)
        XCTAssertNil(try XCTUnwrap(draft.makeRecord()).linkURL)
        draft.linkText = "dbs.com.sg/loans"
        XCTAssertFalse(draft.linkIsUnrecognized)
        XCTAssertEqual(try XCTUnwrap(draft.makeRecord()).linkURL, "https://dbs.com.sg/loans")
    }

    // MARK: Link normalisation

    func testLinkNormalization() {
        XCTAssertEqual(InstallmentLink.normalized("https://www.dbs.com.sg/personal"), "https://www.dbs.com.sg/personal")
        XCTAssertEqual(InstallmentLink.normalized("  http://bank.example.com  "), "http://bank.example.com")
        XCTAssertEqual(InstallmentLink.normalized("dbs.com.sg"), "https://dbs.com.sg")
        XCTAssertEqual(InstallmentLink.normalized("dbsdigibank://"), "dbsdigibank://")
        XCTAssertEqual(InstallmentLink.normalized("trust-bank://loans/123"), "trust-bank://loans/123")
        XCTAssertEqual(InstallmentLink.normalized("HTTPS://Example.com/a"), "HTTPS://Example.com/a")

        XCTAssertNil(InstallmentLink.normalized(""))
        XCTAssertNil(InstallmentLink.normalized("   "))
        XCTAssertNil(InstallmentLink.normalized("hello"))
        XCTAssertNil(InstallmentLink.normalized("two words.com"))
        XCTAssertNil(InstallmentLink.normalized("https://"))
        XCTAssertNil(InstallmentLink.normalized("https://nodot"))
        XCTAssertNil(InstallmentLink.normalized("javascript:alert(1)"))
        XCTAssertNil(InstallmentLink.normalized("JavaScript://%0aalert(1)"))
        XCTAssertNil(InstallmentLink.normalized("file:///etc/passwd"))
        XCTAssertNil(InstallmentLink.normalized("data:text/html,<b>x</b>"))
        XCTAssertNil(InstallmentLink.normalized("/relative/path.html"))
    }

    func testLinkURLForOpening() {
        XCTAssertEqual(InstallmentLink.url(from: "https://dbs.com.sg")?.host, "dbs.com.sg")
        XCTAssertEqual(InstallmentLink.url(from: "dbsdigibank://")?.scheme, "dbsdigibank")
        XCTAssertNil(InstallmentLink.url(from: nil))
        XCTAssertNil(InstallmentLink.url(from: "javascript:alert(1)"))
        XCTAssertNil(InstallmentLink.url(from: "nonsense"))
    }

    // MARK: Rate format

    func testRatePercentFormatting() {
        XCTAssertEqual(InstallmentRateFormat.percent(0.0542, language: .english), "5.42%")
        XCTAssertEqual(InstallmentRateFormat.percent(0.0542, language: .vietnamese), "5,42%")
        XCTAssertEqual(InstallmentRateFormat.percent(0.0542, language: .chinese), "5.42%")
        XCTAssertEqual(InstallmentRateFormat.percent(0, language: .english), "0%")
        XCTAssertEqual(InstallmentRateFormat.percent(-0.1, language: .english), "0%")
        XCTAssertEqual(InstallmentRateFormat.percent(.nan, language: .english), "0%")
        XCTAssertEqual(InstallmentRateFormat.percent(0.12, language: .english), "12.00%")
    }

    // MARK: Commitments overview

    private func plan(
        _ id: String,
        name: String,
        total: Int64 = 120_000,
        months: Int = 12,
        first: String,
        settled: String? = nil
    ) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: id,
            name: name,
            totalMinor: total,
            months: months,
            firstPaymentDayKey: first,
            currency: .sgd,
            settledDayKey: settled
        )
    }

    func testOverviewSplitsActiveAndCompletedAndSortsByNextPayment() {
        let today = "2026-11-10"
        let soon = plan("a", name: "Zeta", first: "2026-06-12")      // next 2026-11-12
        let later = plan("b", name: "Alpha", first: "2026-06-25")    // next 2026-11-25
        let done = plan("c", name: "Done", months: 3, first: "2026-01-05")     // finished 2026-03-05
        let settled = plan("d", name: "Settled", first: "2026-01-05", settled: "2026-08-01")
        let deleted = { var p = plan("e", name: "Gone", first: "2026-06-01"); p.isDeleted = true; return p }()

        let overview = CommitmentsOverview(plans: [later, done, deleted, soon, settled], todayKey: today)
        XCTAssertEqual(overview.active.map(\.plan.id), ["a", "b"])
        XCTAssertEqual(overview.completed.map(\.plan.id), ["d", "c"]) // most recently finished first
        XCTAssertFalse(overview.isEmpty)
        XCTAssertEqual(overview.nextPayment?.plan.id, "a")
        XCTAssertEqual(overview.nextPayment?.payment.dayKey, "2026-11-12")
    }

    func testOverviewSummaryCountsOnlyActivePlans() {
        let today = "2026-11-10"
        let a = plan("a", name: "A", total: 120_000, first: "2026-06-12") // 10,000/month; paid Jun..Oct (5)
        let b = plan("b", name: "B", total: 60_000, months: 6, first: "2026-09-25") // 10,000/month; paid Sep, Oct
        let done = plan("c", name: "Done", total: 30_000, months: 3, first: "2026-01-10")
        let overview = CommitmentsOverview(plans: [a, b, done], todayKey: today)
        // November payments: a on the 12th and b on the 25th. Completed plan contributes nothing.
        XCTAssertEqual(overview.committedThisMonthMinor, 20_000)
        // a: Nov..May = 7 payments left; b: Nov..Feb = 4 payments left.
        XCTAssertEqual(overview.remainingDebtMinor, 7 * 10_000 + 4 * 10_000)
    }

    func testOverviewEmptyAndAllCompleted() {
        XCTAssertTrue(CommitmentsOverview(plans: [], todayKey: "2026-11-10").isEmpty)
        let done = plan("c", name: "Done", total: 30_000, months: 3, first: "2026-01-10")
        let overview = CommitmentsOverview(plans: [done], todayKey: "2026-11-10")
        XCTAssertTrue(overview.active.isEmpty)
        XCTAssertEqual(overview.completed.count, 1)
        XCTAssertNil(overview.nextPayment)
        XCTAssertEqual(overview.committedThisMonthMinor, 0)
        XCTAssertEqual(overview.remainingDebtMinor, 0)
    }

    func testFutureSettlementStillCountsAsActive() {
        let p = plan("s", name: "S", first: "2026-06-12", settled: "2026-12-31")
        let overview = CommitmentsOverview(plans: [p], todayKey: "2026-11-10")
        XCTAssertEqual(overview.active.count, 1)
        XCTAssertTrue(overview.completed.isEmpty)
    }

    // MARK: Settlement preview

    func testSettlementPreviewForLoanReportsInterestSaved() {
        let loan = InstallmentPlanRecord.loan(
            name: "Loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 90_000,
            months: 12,
            firstPaymentDayKey: "2026-06-05"
        )
        // Settle on 2026-10-20: payments Jun..Oct (5) paid, Nov..May (7) cancelled.
        let preview = InstallmentSettlementPreview(plan: loan, settleDayKey: "2026-10-20", todayKey: "2026-11-10")
        XCTAssertEqual(preview.cancelledPaymentCount, 7)
        XCTAssertEqual(preview.cancelledPaymentsMinor, 7 * 90_000)
        XCTAssertEqual(preview.bookedPaymentsRemovedCount, 1) // Nov 5 already booked
        XCTAssertGreaterThan(preview.interestSavedMinor, 0)
        XCTAssertLessThan(preview.interestSavedMinor, loan.totalInterestMinor)
        XCTAssertGreaterThan(preview.payoffPrincipalMinor, 0)
        XCTAssertLessThan(preview.payoffPrincipalMinor, 1_000_000)

        // Cross-check with the data layer's own progress as of the settlement day.
        var settled = loan
        settled.settledDayKey = "2026-10-20"
        let progress = settled.progress(todayKey: "2026-10-20")
        XCTAssertEqual(preview.interestSavedMinor, progress.interestSavedMinor)
        XCTAssertEqual(preview.payoffPrincipalMinor, progress.settlementPrincipalMinor)
    }

    func testSettlementPreviewForInterestFreeInstallment() {
        let p = plan("i", name: "IPP", total: 120_000, first: "2026-06-12")
        let preview = InstallmentSettlementPreview(plan: p, settleDayKey: "2026-11-10", todayKey: "2026-11-10")
        XCTAssertEqual(preview.interestSavedMinor, 0)
        XCTAssertEqual(preview.cancelledPaymentCount, 7) // Nov 12 .. May 12
        XCTAssertEqual(preview.cancelledPaymentsMinor, 70_000)
        XCTAssertEqual(preview.bookedPaymentsRemovedCount, 0)
        XCTAssertEqual(preview.payoffPrincipalMinor, 70_000)
    }

    func testSettlementPreviewWithNothingLeft() {
        let p = plan("i", name: "IPP", total: 30_000, months: 3, first: "2026-01-10")
        let preview = InstallmentSettlementPreview(plan: p, settleDayKey: "2026-11-10", todayKey: "2026-11-10")
        XCTAssertEqual(preview.cancelledPaymentCount, 0)
        XCTAssertEqual(preview.interestSavedMinor, 0)
        XCTAssertEqual(preview.payoffPrincipalMinor, 0)
    }

    // MARK: Schedule rows

    func testScheduleRowsMarkPaidUpcomingAndCancelled() {
        let p = plan("r", name: "R", total: 60_000, months: 6, first: "2026-09-10", settled: "2026-11-15")
        let rows = InstallmentScheduleRow.rows(for: p, todayKey: "2026-11-10")
        XCTAssertEqual(rows.map(\.state), [.paid, .paid, .paid, .cancelled, .cancelled, .cancelled])
        XCTAssertTrue(rows.allSatisfy { $0.interestMinor == nil })

        let open = plan("o", name: "O", total: 60_000, months: 6, first: "2026-09-10")
        XCTAssertEqual(
            InstallmentScheduleRow.rows(for: open, todayKey: "2026-11-10").map(\.state),
            [.paid, .paid, .paid, .upcoming, .upcoming, .upcoming]
        )
    }

    func testScheduleRowsCarryAmortizationForLoans() {
        let loan = InstallmentPlanRecord.loan(
            name: "Loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 90_000,
            months: 12,
            firstPaymentDayKey: "2026-06-05"
        )
        let rows = InstallmentScheduleRow.rows(for: loan, todayKey: "2026-11-10")
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(rows.last?.outstandingPrincipalMinor, 0)
        XCTAssertEqual(rows.compactMap(\.interestMinor).reduce(0, +), loan.totalInterestMinor)
        XCTAssertEqual(rows.filter { $0.state == .paid }.count, 6)
        XCTAssertEqual(rows.first.map { ($0.interestMinor ?? 0) + ($0.principalMinor ?? 0) }, 90_000)
    }
}
