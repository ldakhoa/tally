import BudgetKit
import TallyCore
import XCTest

final class CurrencyLedgerConverterTests: XCTestCase {
    private let fx = ExchangeRateTable(
        ratesPerSGD: [
            "SGD": 1.0,
            "VND": 19_000.0,
            "HKD": 5.85,
            "USD": 0.75,
        ],
        rateDate: "2026-11-25",
        fetchedAt: Date(timeIntervalSince1970: 1_764_000_000)
    )

    func testConvertSGDToVNDAndRoundTripLosslessly() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let t2 = Date(timeIntervalSince1970: 3_000)
        let todayKey = "2026-11-25"

        // 1. Domestic SGD transaction
        let coffee = TransactionRecord(
            id: "tx-coffee", name: "Coffee", amountMinor: 780, type: .expense, category: .food,
            dayKey: "2026-11-20", updatedAt: t0
        )
        // 2. Third-currency HKD transaction -> ~S$65.71
        let hkdShop = TransactionRecord(
            id: "tx-hkd", name: "PinDuoDuo", amountMinor: 6_820, type: .expense, category: .shopping,
            dayKey: "2026-11-21", updatedAt: t0,
            originalAmountMinor: 39_896, originalCurrencyCode: "HKD", exchangeRate: 6_820.0 / 39_896.0
        )
        // 3. Transaction whose original currency is ALREADY VND (should restore exact original on switch to VND)
        let vndLunch = TransactionRecord(
            id: "tx-vnd", name: "Pho", amountMinor: 526, type: .expense, category: .food,
            dayKey: "2026-11-22", updatedAt: t0,
            originalAmountMinor: 10_000_000, originalCurrencyCode: "VND", exchangeRate: 5.26 / 100_000.0
        )
        // 4. Deleted tombstone transaction (must remain untouched)
        let deletedTx = TransactionRecord(
            id: "tx-del", name: "Deleted", amountMinor: 900, type: .expense, category: .other,
            dayKey: "2026-11-19", updatedAt: t0, isDeleted: true
        )

        // Plan + schedule payment (not user-edited) + user-edited payment
        let plan = InstallmentPlanRecord(
            id: "plan-1", name: "Phone IPP", kind: .loan, totalMinor: 120_000, months: 12,
            firstPaymentDayKey: "2026-10-15", category: .shopping, currency: .sgd,
            monthlyPaymentMinor: 10_000, principalMinor: 110_000,
            createdAt: t0, updatedAt: t0
        )
        let autoPayment = plan.paymentTransaction(for: plan.fullSchedule[0])
        var editedPayment = plan.paymentTransaction(for: plan.fullSchedule[1])
        editedPayment.amountMinor = 11_500
        let userEditedPayment = editedPayment.recordingUserWrite(at: t0)

        let deletedPlan = InstallmentPlanRecord(
            id: "plan-del", name: "Old", totalMinor: 10_000, months: 2,
            firstPaymentDayKey: "2026-01-01", currency: .sgd,
            createdAt: t0, updatedAt: t0, isDeleted: true
        )

        let budget = BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 100_000, updatedAt: t0)
        let deletedBudget = BudgetLimitRecord(monthKey: "2026-10", category: .food, limitMinor: 50_000, updatedAt: t0, isDeleted: true)

        let goal = SavingsGoalRecord(id: "g-1", name: "Japan", targetMinor: 500_000, savedMinor: 200_000, updatedAt: t0)
        let zeroSavedGoal = SavingsGoalRecord(id: "g-0", name: "Empty", targetMinor: 100_000, savedMinor: 0, updatedAt: t0)
        let deletedGoal = SavingsGoalRecord(id: "g-del", name: "Gone", targetMinor: 100_000, savedMinor: 50_000, updatedAt: t0, isDeleted: true)

        let forward = CurrencyLedgerConverter.convert(
            from: .sgd,
            to: .vnd,
            rates: fx,
            transactions: [coffee, hkdShop, vndLunch, deletedTx, autoPayment, userEditedPayment],
            budgets: [budget, deletedBudget],
            goals: [goal, zeroSavedGoal, deletedGoal],
            plans: [plan, deletedPlan],
            todayKey: todayKey,
            now: t1
        )
        XCTAssertNotNil(forward)
        guard let forward else { return }

        // Domestic Coffee: S$7.80 -> 148,200 VND, original SGD preserved
        let vndCoffee = forward.transactions.first { $0.id == "tx-coffee" }!
        XCTAssertEqual(vndCoffee.amountMinor, 14_820_000)
        XCTAssertEqual(vndCoffee.amountMinor % 100, 0)
        XCTAssertEqual(vndCoffee.originalCurrencyCode, "SGD")
        XCTAssertEqual(vndCoffee.originalAmountMinor, 780)
        XCTAssertEqual(vndCoffee.updatedAt, t1)

        // Third-currency HKD stays HKD, amount converted to VND, rate updated
        let vndHKD = forward.transactions.first { $0.id == "tx-hkd" }!
        XCTAssertEqual(vndHKD.amountMinor, 129_580_000) // 68.20 * 19000 = 1,295,800 VND
        XCTAssertEqual(vndHKD.originalCurrencyCode, "HKD")
        XCTAssertEqual(vndHKD.originalAmountMinor, 39_896)
        XCTAssertEqual(vndHKD.exchangeRate ?? 0, 1_295_800.0 / 398.96, accuracy: 0.01)

        // Already-VND original transaction restores exact original 100,000 VND and clears foreign metadata
        let vndRestored = forward.transactions.first { $0.id == "tx-vnd" }!
        XCTAssertEqual(vndRestored.amountMinor, 10_000_000)
        XCTAssertFalse(vndRestored.isForeignCurrency)
        XCTAssertNil(vndRestored.originalCurrencyCode)
        XCTAssertNil(vndRestored.originalAmountMinor)
        XCTAssertNil(vndRestored.exchangeRate)

        // Deleted transaction left completely untouched
        let untouchedDelTx = forward.transactions.first { $0.id == "tx-del" }!
        XCTAssertEqual(untouchedDelTx.amountMinor, 900)
        XCTAssertEqual(untouchedDelTx.updatedAt, t0)
        XCTAssertFalse(forward.changedTransactionIDs.contains("tx-del"))

        // Plan & payments
        let vndPlan = forward.plans.first { $0.id == "plan-1" }!
        XCTAssertEqual(vndPlan.currency, .vnd)
        XCTAssertEqual(vndPlan.totalMinor, 2_280_000_000)
        XCTAssertEqual(vndPlan.monthlyPaymentMinor, 190_000_000)
        XCTAssertEqual(vndPlan.principalMinor, 2_090_000_000)
        XCTAssertTrue(vndPlan.hasValidTerms)

        let vndAutoPay = forward.transactions.first { $0.id == autoPayment.id }!
        XCTAssertEqual(vndAutoPay.amountMinor, 190_000_000)
        XCTAssertFalse(vndAutoPay.hasUserPaymentWrite)
        XCTAssertEqual(vndAutoPay.paymentState?.schedule?.planRevision, t1)

        let vndUserPay = forward.transactions.first { $0.id == userEditedPayment.id }!
        XCTAssertEqual(vndUserPay.amountMinor, 218_500_000)
        XCTAssertTrue(vndUserPay.hasUserPaymentWrite)

        XCTAssertEqual(forward.plans.first { $0.id == "plan-del" }?.currency, .sgd)
        XCTAssertFalse(forward.changedPlanIDs.contains("plan-del"))

        // Budgets & Goals
        XCTAssertEqual(forward.budgets.first { $0.id == budget.id }?.limitMinor, 1_900_000_000)
        XCTAssertEqual(forward.budgets.first { $0.id == deletedBudget.id }?.limitMinor, 50_000)
        XCTAssertEqual(forward.goals.first { $0.id == "g-1" }?.targetMinor, 9_500_000_000)
        XCTAssertEqual(forward.goals.first { $0.id == "g-1" }?.savedMinor, 3_800_000_000)
        XCTAssertEqual(forward.goals.first { $0.id == "g-0" }?.savedMinor, 0)
        XCTAssertEqual(forward.goals.first { $0.id == "g-del" }?.savedMinor, 50_000)

        // Round-trip VND -> SGD restores Coffee exact 780 cents with no foreign metadata
        let roundTrip = CurrencyLedgerConverter.convert(
            from: .vnd,
            to: .sgd,
            rates: fx,
            transactions: forward.transactions,
            budgets: forward.budgets,
            goals: forward.goals,
            plans: forward.plans,
            todayKey: todayKey,
            now: t2
        )
        XCTAssertNotNil(roundTrip)
        guard let roundTrip else { return }

        let restoredCoffee = roundTrip.transactions.first { $0.id == "tx-coffee" }!
        XCTAssertEqual(restoredCoffee.amountMinor, 780)
        XCTAssertNil(restoredCoffee.originalCurrencyCode)
        XCTAssertNil(restoredCoffee.originalAmountMinor)
        XCTAssertNil(restoredCoffee.exchangeRate)

        let restoredPlan = roundTrip.plans.first { $0.id == "plan-1" }!
        XCTAssertEqual(restoredPlan.currency, .sgd)
        XCTAssertEqual(restoredPlan.totalMinor, 120_000)
        XCTAssertTrue(restoredPlan.hasValidTerms)
    }

    func testTinyVNDPlanConvertedToSGDClampsToValidMinimum() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        // 600 VND over 12 months would convert to < S$0.12 (12 cents); must clamp to minTotal = 12 cents
        let tinyPlan = InstallmentPlanRecord(
            id: "tiny", name: "Tiny", totalMinor: 60_000, months: 12,
            firstPaymentDayKey: "2026-01-15", currency: .vnd,
            monthlyPaymentMinor: 5_000, createdAt: t0, updatedAt: t0
        )

        let result = CurrencyLedgerConverter.convert(
            from: .vnd,
            to: .sgd,
            rates: fx,
            transactions: [],
            budgets: [],
            goals: [],
            plans: [tinyPlan],
            todayKey: "2026-11-25",
            now: t1
        )
        XCTAssertNotNil(result)
        let converted = result!.plans[0]
        XCTAssertEqual(converted.currency, .sgd)
        XCTAssertGreaterThanOrEqual(converted.totalMinor, 12)
        XCTAssertTrue(converted.hasValidTerms)
    }

    func testSameCurrencyReturnsNil() {
        XCTAssertNil(CurrencyLedgerConverter.convert(
            from: .sgd, to: .sgd, rates: fx, transactions: [], budgets: [], goals: [], plans: [], todayKey: "2026-11-25"
        ))
    }
}
