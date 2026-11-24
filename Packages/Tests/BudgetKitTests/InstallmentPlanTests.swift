import BudgetKit
import TallyCore
import XCTest

final class InstallmentPlanTests: XCTestCase {
    private func shopeePlan(first: String = "2026-11-15", settled: String? = nil) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: "plan-1",
            name: "SHOPEEPAY SG IPP",
            totalMinor: 51_500,
            months: 12,
            firstPaymentDayKey: first,
            category: .shopping,
            currency: .sgd,
            settledDayKey: settled
        )
    }

    // MARK: Schedule

    func testPaymentAmountsRoundHalfUpWithRemainderLast() {
        let amounts = InstallmentPlanRecord.paymentAmounts(totalMinor: 51_500, months: 12)
        XCTAssertEqual(amounts.count, 12)
        XCTAssertEqual(Array(amounts.prefix(11)), Array(repeating: 4_292, count: 11))
        XCTAssertEqual(amounts.last, 4_288)
        XCTAssertEqual(amounts.reduce(0, +), 51_500)

        // Exact division.
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 120_000, months: 12), Array(repeating: 10_000, count: 12))
        // Rounds down below .5.
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 10_001, months: 3), [3_334, 3_334, 3_333])
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 10_000, months: 3), [3_333, 3_333, 3_334])
    }

    func testPaymentAmountsGuards() {
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 51_500, months: 0), [])
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 51_500, months: -3), [])
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 0, months: 12), [])
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 51_500, months: 1), [51_500])
        // Terms that cannot yield 4 positive payments produce no schedule (review finding E)
        // instead of zero-value payments.
        XCTAssertEqual(InstallmentPlanRecord.paymentAmounts(totalMinor: 2, months: 4), [])
        // Rounding up must never make the final payment zero or negative.
        let small = InstallmentPlanRecord.paymentAmounts(totalMinor: 7, months: 4)
        XCTAssertEqual(small.reduce(0, +), 7)
        XCTAssertTrue(small.allSatisfy { $0 > 0 })

        var plan = shopeePlan()
        plan.months = 0
        XCTAssertTrue(plan.schedule.isEmpty)
        plan = shopeePlan(first: "not-a-date")
        XCTAssertTrue(plan.schedule.isEmpty)
    }

    func testZeroDecimalCurrencyRoundsToWholeDong() {
        // 10,000,000 VND (storage = dong x 100) over 3 months.
        let plan = InstallmentPlanRecord(
            name: "Điện thoại trả góp",
            totalMinor: 1_000_000_000,
            months: 3,
            firstPaymentDayKey: "2026-11-05",
            currency: .vnd
        )
        let amounts = plan.schedule.map(\.amountMinor)
        XCTAssertEqual(amounts, [333_333_300, 333_333_300, 333_333_400])
        XCTAssertTrue(amounts.allSatisfy { $0 % 100 == 0 })
    }

    func testRegularMonthlyPaymentWithDifferentFinalPayment() {
        let amounts = InstallmentPlanRecord.paymentAmounts(totalMinor: 1_066_179, months: 12, regularMinor: 88_849)
        XCTAssertEqual(Array(amounts.prefix(11)), Array(repeating: 88_849, count: 11))
        XCTAssertEqual(amounts.last, 88_840)
    }

    func testScheduleClampsDayOfMonth() {
        var plan = shopeePlan(first: "2026-01-31")
        plan.months = 14
        let days = plan.schedule.map(\.dayKey)
        XCTAssertEqual(days[0], "2026-01-31")
        XCTAssertEqual(days[1], "2026-02-28")
        XCTAssertEqual(days[2], "2026-03-31")
        XCTAssertEqual(days[3], "2026-04-30")
        XCTAssertEqual(days[11], "2026-12-31")
        XCTAssertEqual(days[12], "2027-01-31")
        XCTAssertEqual(days[13], "2027-02-28")

        // Leap year February.
        plan = shopeePlan(first: "2027-11-30")
        plan.months = 4
        XCTAssertEqual(plan.schedule.map(\.dayKey), ["2027-11-30", "2027-12-30", "2028-01-30", "2028-02-29"])

        plan = shopeePlan(first: "2028-01-29")
        plan.months = 2
        XCTAssertEqual(plan.schedule.map(\.dayKey), ["2028-01-29", "2028-02-29"])
    }

    func testPaymentTransactionIsDeterministicExpense() {
        let plan = shopeePlan()
        let payment = plan.schedule[2]
        let tx = plan.paymentTransaction(for: payment)
        XCTAssertEqual(tx.id, "plan-1#2")
        XCTAssertEqual(tx.planID, "plan-1")
        XCTAssertEqual(tx.planPaymentIndex, 2)
        XCTAssertEqual(tx.type, .expense)
        XCTAssertEqual(tx.amountMinor, 4_292)
        XCTAssertEqual(tx.dayKey, "2027-01-15")
        XCTAssertTrue(tx.isPlanPayment)
        XCTAssertFalse(tx.isConvertedPlanSource)
    }

    // MARK: Progress

    func testProgressAndAggregates() {
        let plan = shopeePlan()
        let before = plan.progress(todayKey: "2026-11-14")
        XCTAssertEqual(before.paidCount, 0)
        XCTAssertEqual(before.remainingMinor, 51_500)
        XCTAssertEqual(before.nextPaymentDayKey, "2026-11-15")
        XCTAssertFalse(before.isCompleted)

        let mid = plan.progress(todayKey: "2026-12-20")
        XCTAssertEqual(mid.paidCount, 2)
        XCTAssertEqual(mid.paidMinor, 8_584)
        XCTAssertEqual(mid.remainingMinor, 51_500 - 8_584)
        XCTAssertEqual(mid.nextPaymentDayKey, "2027-01-15")
        XCTAssertEqual(mid.nextPaymentMinor, 4_292)
        XCTAssertEqual(mid.interestPaidMinor, 0)
        XCTAssertEqual(mid.outstandingPrincipalMinor, mid.remainingMinor)

        let done = plan.progress(todayKey: "2027-10-15")
        XCTAssertTrue(done.isCompleted)
        XCTAssertEqual(done.paidMinor, 51_500)
        XCTAssertEqual(done.remainingMinor, 0)
        XCTAssertNil(done.nextPayment)

        var deleted = shopeePlan()
        deleted.id = "plan-deleted"
        deleted.isDeleted = true
        let other = InstallmentPlanRecord(id: "plan-2", name: "Laptop", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2026-12-01")
        let plans = [plan, other, deleted]
        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2026-12", plans: plans), 4_292 + 10_000)
        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2026-11", plans: plans), 4_292)
        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2027-10", plans: plans), 4_288 + 10_000)
        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2027-12", plans: plans), 0)
        XCTAssertEqual(
            InstallmentPlanRecord.remainingDebtMinor(plans: plans, todayKey: "2026-12-20"),
            (51_500 - 8_584) + (120_000 - 10_000)
        )
    }

    // MARK: Loans

    func testSolvesMonthlyRateForStandardAnnuity() {
        // 10,000.00 at 1%/month over 12 months -> 888.49/month.
        let loan = InstallmentPlanRecord.loan(
            name: "Personal loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 88_849,
            months: 12,
            firstPaymentDayKey: "2026-01-10",
            lender: "DBS",
            linkURL: "https://www.dbs.com.sg"
        )
        XCTAssertEqual(loan.kind, .loan)
        XCTAssertEqual(loan.totalMinor, 1_066_188)
        XCTAssertEqual(loan.totalInterestMinor, 66_188)
        XCTAssertEqual(loan.effectiveMonthlyRate, 0.01, accuracy: 1e-5)
        XCTAssertEqual(loan.effectiveAnnualRate, 0.12, accuracy: 1e-4)
        XCTAssertEqual(loan.compoundedAnnualRate, pow(1.01, 12) - 1, accuracy: 1e-4)
    }

    func testFlatRateLoanEffectiveRate() {
        // 3% p.a. flat on 10,000 over 12 months: total 10,300, payment 858.33 (last 858.37).
        let loan = InstallmentPlanRecord.loan(
            name: "Flat loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 85_833,
            months: 12,
            firstPaymentDayKey: "2026-01-10",
            totalMinor: 1_030_000
        )
        XCTAssertEqual(loan.schedule.last?.amountMinor, 85_837)
        // Known conversion: 3% flat over 1 year is about 5.4% EIR.
        XCTAssertGreaterThan(loan.effectiveAnnualRate, 0.053)
        XCTAssertLessThan(loan.effectiveAnnualRate, 0.056)
    }

    func testAmortizationClosesAtZero() {
        let loan = InstallmentPlanRecord.loan(
            name: "Car loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 88_849,
            months: 12,
            firstPaymentDayKey: "2026-01-10"
        )
        let rows = loan.amortizationSchedule
        XCTAssertEqual(rows.count, 12)
        XCTAssertEqual(rows.first?.interestMinor, 10_000)
        XCTAssertEqual(rows.first?.principalMinor, 78_849)
        XCTAssertEqual(rows.last?.outstandingPrincipalMinor, 0)
        XCTAssertEqual(rows.map(\.interestMinor).reduce(0, +), loan.totalInterestMinor)
        XCTAssertEqual(rows.map(\.principalMinor).reduce(0, +), 1_000_000)
        for row in rows {
            XCTAssertEqual(row.interestMinor + row.principalMinor, row.paymentMinor)
            XCTAssertGreaterThanOrEqual(row.interestMinor, 0)
        }
        for (a, b) in zip(rows, rows.dropFirst()) {
            XCTAssertGreaterThan(a.outstandingPrincipalMinor, b.outstandingPrincipalMinor)
            XCTAssertGreaterThanOrEqual(a.interestMinor, b.interestMinor)
        }

        let progress = loan.progress(todayKey: "2026-03-10")
        XCTAssertEqual(progress.paidCount, 3)
        XCTAssertEqual(progress.outstandingPrincipalMinor, rows[2].outstandingPrincipalMinor)
        XCTAssertEqual(progress.interestPaidMinor, rows.prefix(3).map(\.interestMinor).reduce(0, +))
        XCTAssertEqual(progress.interestRemainingMinor, loan.totalInterestMinor - progress.interestPaidMinor)
    }

    func testZeroPercentMatchesSimpleSchedule() {
        let plan = shopeePlan()
        XCTAssertEqual(plan.effectiveMonthlyRate, 0)
        XCTAssertEqual(plan.totalInterestMinor, 0)
        let rows = plan.amortizationSchedule
        XCTAssertEqual(rows.map(\.paymentMinor), plan.schedule.map(\.amountMinor))
        XCTAssertEqual(rows.map(\.principalMinor), plan.schedule.map(\.amountMinor))
        XCTAssertTrue(rows.allSatisfy { $0.interestMinor == 0 })
        XCTAssertEqual(rows.last?.outstandingPrincipalMinor, 0)

        // A loan whose total equals its principal is the same 0% case.
        let zeroLoan = InstallmentPlanRecord.loan(
            name: "0% loan", principalMinor: 51_500, monthlyPaymentMinor: 4_292,
            months: 12, firstPaymentDayKey: "2026-11-15", totalMinor: 51_500
        )
        XCTAssertEqual(zeroLoan.effectiveMonthlyRate, 0)
        XCTAssertEqual(zeroLoan.schedule.map(\.amountMinor), plan.schedule.map(\.amountMinor))
        XCTAssertEqual(zeroLoan.amortizationSchedule.map(\.principalMinor), rows.map(\.principalMinor))
        let a = zeroLoan.progress(todayKey: "2027-02-01")
        let b = plan.progress(todayKey: "2027-02-01")
        XCTAssertEqual(a.paidMinor, b.paidMinor)
        XCTAssertEqual(a.remainingMinor, b.remainingMinor)
        XCTAssertEqual(a.outstandingPrincipalMinor, b.outstandingPrincipalMinor)
        XCTAssertEqual(a.interestRemainingMinor, 0)
    }

    func testEarlySettlement() {
        var loan = InstallmentPlanRecord.loan(
            id: "loan-1",
            name: "Trust loan",
            principalMinor: 1_000_000,
            monthlyPaymentMinor: 88_849,
            months: 12,
            firstPaymentDayKey: "2026-01-10"
        )
        let rows = loan.amortizationSchedule
        loan.settledDayKey = "2026-03-20"

        XCTAssertEqual(loan.schedule.count, 3)
        XCTAssertEqual(loan.fullSchedule.count, 12)

        let progress = loan.progress(todayKey: "2026-04-01")
        XCTAssertTrue(progress.isCompleted)
        XCTAssertTrue(progress.isSettled)
        XCTAssertEqual(progress.paidCount, 3)
        XCTAssertEqual(progress.remainingMinor, 0)
        XCTAssertNil(progress.nextPayment)
        XCTAssertEqual(progress.outstandingPrincipalMinor, 0)
        XCTAssertEqual(progress.interestRemainingMinor, 0)
        XCTAssertEqual(progress.settlementPrincipalMinor, rows[2].outstandingPrincipalMinor)
        XCTAssertEqual(progress.interestSavedMinor, loan.totalInterestMinor - progress.interestPaidMinor)

        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2026-03", plans: [loan]), 88_849)
        XCTAssertEqual(InstallmentPlanRecord.committedMinor(inMonth: "2026-04", plans: [loan]), 0)
        XCTAssertEqual(InstallmentPlanRecord.remainingDebtMinor(plans: [loan], todayKey: "2026-04-01"), 0)
        XCTAssertEqual(InstallmentPlanRecord.outstandingPrincipalMinor(plans: [loan], todayKey: "2026-04-01"), 0)

        // Settled installment before any payment: nothing owed at all.
        let early = shopeePlan(settled: "2026-11-01")
        XCTAssertTrue(early.schedule.isEmpty)
        XCTAssertTrue(early.progress(todayKey: "2026-11-02").isCompleted)
        XCTAssertEqual(early.progress(todayKey: "2026-11-02").remainingMinor, 0)
    }

    // MARK: Hint

    func testInstallmentHint() {
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "SHOPEEPAY SG IPP"))
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "Card", rawSourceText: "Merchant: LAZADA IPP-12M"))
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "Apple Store instalment plan"))
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "0% Installment 12 months"))
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "Mua điện thoại trả góp"))
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(name: "TRA GOP 0%"))
        XCTAssertFalse(InstallmentHint.looksLikeInstallment(name: "Shipping fee"))
        XCTAssertFalse(InstallmentHint.looksLikeInstallment(name: "HIPPO CAFE"))
        XCTAssertFalse(InstallmentHint.looksLikeInstallment(name: "Coffee", rawSourceText: "Paid at Starbucks"))

        let tx = TransactionRecord(name: "SHOPEEPAY SG IPP", amountMinor: 51_500, type: .expense, category: .shopping, dayKey: "2026-11-15")
        XCTAssertTrue(InstallmentHint.looksLikeInstallment(tx))
        let income = TransactionRecord(name: "IPP refund", amountMinor: 100, type: .income, category: .income, dayKey: "2026-11-15")
        XCTAssertFalse(InstallmentHint.looksLikeInstallment(income))
        let payment = shopeePlan().paymentTransaction(for: shopeePlan().schedule[0])
        XCTAssertFalse(InstallmentHint.looksLikeInstallment(payment))
    }

    // MARK: Codable compatibility

    func testTransactionWithoutPlanKeysStillDecodes() throws {
        let tx = TransactionRecord(
            id: "t1", name: "Coffee", amountMinor: 500, type: .expense, category: .food,
            dayKey: "2026-11-23", planID: "p", planPaymentIndex: 1
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(tx)) as? [String: Any])
        XCTAssertNotNil(json["planID"])
        json.removeValue(forKey: "planID")
        json.removeValue(forKey: "planPaymentIndex")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(TransactionRecord.self, from: legacy)
        XCTAssertEqual(decoded.id, "t1")
        XCTAssertNil(decoded.planID)
        XCTAssertNil(decoded.planPaymentIndex)
        XCTAssertFalse(decoded.isPlanPayment)

        let roundTrip = try JSONDecoder().decode(TransactionRecord.self, from: JSONEncoder().encode(tx))
        XCTAssertEqual(roundTrip, tx)
    }

    func testPlanWithoutOptionalKeysDecodes() throws {
        let plan = InstallmentPlanRecord.loan(
            name: "Loan", principalMinor: 1_000_000, monthlyPaymentMinor: 88_849, months: 12,
            firstPaymentDayKey: "2026-01-10", lender: "Trust", linkURL: "https://trustbank.sg"
        )
        let roundTrip = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(roundTrip, plan)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any])
        for key in ["monthlyPaymentMinor", "principalMinor", "sourceTransactionID", "lender", "linkURL", "settledDayKey"] {
            json.removeValue(forKey: key)
        }
        let minimal = try JSONDecoder().decode(InstallmentPlanRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(minimal.lender)
        XCTAssertNil(minimal.linkURL)
        XCTAssertNil(minimal.principalMinor)
        XCTAssertEqual(minimal.totalMinor, plan.totalMinor)
    }

    // MARK: Backup

    func testBackupRoundTripWithPlans() throws {
        let loan = InstallmentPlanRecord.loan(
            id: "loan-1", name: "Car loan", principalMinor: 1_000_000, monthlyPaymentMinor: 88_849,
            months: 12, firstPaymentDayKey: "2026-01-10", currency: .sgd, lender: "DBS", linkURL: "dbs://loan"
        )
        var settled = shopeePlan()
        settled.settledDayKey = "2027-01-31"
        let paid = loan.paymentTransaction(for: loan.schedule[0])
        var userDeleted = loan.paymentTransaction(for: loan.schedule[1])
        userDeleted.isDeleted = true
        userDeleted = userDeleted.recordingUserWrite(at: Date())

        let data = try WebBackupCodec.encode(
            currency: .sgd,
            transactions: [paid, userDeleted],
            budgets: [],
            goals: [],
            plans: [loan, settled]
        )
        let decoded = try WebBackupCodec.decode(data)
        XCTAssertEqual(decoded.plans.count, 2)
        let restoredLoan = try XCTUnwrap(decoded.plans.first { $0.id == "loan-1" })
        XCTAssertEqual(restoredLoan.kind, .loan)
        XCTAssertEqual(restoredLoan.totalMinor, loan.totalMinor)
        XCTAssertEqual(restoredLoan.monthlyPaymentMinor, 88_849)
        XCTAssertEqual(restoredLoan.principalMinor, 1_000_000)
        XCTAssertEqual(restoredLoan.lender, "DBS")
        XCTAssertEqual(restoredLoan.linkURL, "dbs://loan")
        XCTAssertEqual(restoredLoan.schedule, loan.schedule)
        XCTAssertEqual(decoded.plans.first { $0.id == "plan-1" }?.settledDayKey, "2027-01-31")

        let restoredPaid = try XCTUnwrap(decoded.transactions.first { $0.id == paid.id })
        XCTAssertEqual(restoredPaid.planID, "loan-1")
        XCTAssertEqual(restoredPaid.planPaymentIndex, 0)
        XCTAssertFalse(restoredPaid.isDeleted)
        // The user-deleted payment comes back as a tombstone so a restore does not re-book it.
        let tomb = try XCTUnwrap(decoded.transactions.first { $0.id == userDeleted.id })
        XCTAssertTrue(tomb.isDeleted)
        XCTAssertTrue(tomb.isUserDeletedPlanPayment)
        XCTAssertEqual(tomb.planPaymentIndex, 1)
        // A restored payment that matches its plan is a schedule booking, not a user write.
        XCTAssertFalse(restoredPaid.hasUserPaymentWrite)
    }

    func testWebPrototypeBackupWithoutPlansStillImports() throws {
        let json = """
        {"version":1,"currency":"SGD","budgets":{"2026-11/food":50000},"goals":[],
         "transactions":[{"id":"w1","date":"2026-11-02","name":"Lunch","category":"food","type":"expense","amount":1250}]}
        """
        let decoded = try WebBackupCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.transactions.count, 1)
        XCTAssertNil(decoded.transactions[0].planID)
        XCTAssertTrue(decoded.plans.isEmpty)

        // Exports without plans omit the native-only keys entirely.
        let exported = try WebBackupCodec.encode(currency: .sgd, transactions: decoded.transactions, budgets: [], goals: [])
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertFalse(text.contains("plans"))
        XCTAssertFalse(text.contains("planID"))
    }

    // MARK: Dedup interplay

    func testConvertedOriginalBlocksResentAlert() {
        let t0 = Date(timeIntervalSince1970: 1_763_900_000)
        var original = TransactionRecord(
            id: "email-abc", name: "SHOPEEPAY SG IPP", amountMinor: 51_500, type: .expense, category: .shopping,
            dayKey: "2026-11-15", createdAt: t0, source: .bankEmail, memberID: "me"
        )
        original.isDeleted = true
        original.planID = "plan-1"
        XCTAssertTrue(original.isConvertedPlanSource)

        // Same email delivered again: exact-ID match against the tombstone.
        var resent = original
        resent.isDeleted = false
        resent.planID = nil
        let exact = TransactionDeduplicator.findDuplicate(for: resent, in: [original])
        XCTAssertEqual(exact?.reason, .exactID)
        XCTAssertEqual(exact?.existing.isDeleted, true)

        // Same purchase reported by another alert id (e.g. SMS) still matches the converted original.
        let sms = TransactionRecord(
            id: "sms-1", name: "SHOPEEPAY SG", amountMinor: 51_500, type: .expense, category: .shopping,
            dayKey: "2026-11-15", createdAt: t0.addingTimeInterval(120), source: .bankNotification, memberID: "me"
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: sms, in: [original]))

        // An ordinary user-deleted transaction is not a duplicate candidate for a different id.
        var plainDeleted = original
        plainDeleted.planID = nil
        XCTAssertNil(TransactionDeduplicator.findDuplicate(for: sms, in: [plainDeleted]))
    }

    func testPlanPaymentsAreIgnoredByDeduplication() {
        let plan = shopeePlan()
        let payment = plan.paymentTransaction(for: plan.schedule[0])
        let alert = TransactionRecord(
            id: "email-x", name: "SHOPEEPAY SG IPP", amountMinor: 4_292, type: .expense, category: .shopping,
            dayKey: "2026-11-15", createdAt: payment.createdAt, source: .bankEmail, memberID: payment.memberID
        )
        XCTAssertNil(TransactionDeduplicator.findDuplicate(for: alert, in: [payment]))
        let sweep = TransactionDeduplicator.findExistingDuplicates(in: [payment, alert])
        XCTAssertFalse(sweep.hasChanges)
    }
}
