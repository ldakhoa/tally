@testable import BudgetKit
import TallyCore
import XCTest

/// Adviser figures against hand-checked numbers. Fixture (SGD, today 2026-11-24, a Tuesday):
///
/// | month | salary | other income | food | housing | bills | shopping | fun | spending | net |
/// |-------|--------|--------------|------|---------|-------|----------|-----|----------|-----|
/// | 08    | 5,000  |              | 400  | 2,000   |       | 100      |     | 2,500    | 2,500 (50.0%) |
/// | 09    | 5,000  |              | 600  | 2,000   | 150   |          |     | 2,750    | 2,250 (45.0%) |
/// | 10    | 5,000  | 500          | 800  | 2,000   | 150   |          | 250 | 3,200    | 2,300 (41.8%) |
/// | 11*   | 5,000  |              | 300  |         |       |          |     | 300      | month to date |
final class AdviserMetricsTests: XCTestCase {
    private let today = "2026-11-24"

    private func tx(_ day: String, _ major: Int64, _ category: CategoryID, name: String? = nil, member: String = "me", memberName: String = "Alex") -> TransactionRecord {
        TransactionRecord(
            name: name ?? category.rawValue, amountMinor: major * 100, type: category.transactionType,
            category: category, dayKey: day, memberID: member, memberName: memberName
        )
    }

    private var fixture: [TransactionRecord] {
        [
            tx("2026-08-01", 5_000, .salary), tx("2026-08-05", 400, .food), tx("2026-08-02", 2_000, .housing, name: "Rent"), tx("2026-08-20", 100, .shopping),
            tx("2026-09-01", 5_000, .salary), tx("2026-09-05", 600, .food), tx("2026-09-02", 2_000, .housing, name: "Rent"), tx("2026-09-10", 150, .bills),
            tx("2026-10-01", 5_000, .salary), tx("2026-10-15", 500, .freelance), tx("2026-10-05", 500, .food, name: "FairPrice"), tx("2026-10-06", 300, .food, name: "Grab Food", member: "p", memberName: "Sam"),
            tx("2026-10-02", 2_000, .housing, name: "Rent"), tx("2026-10-10", 150, .bills), tx("2026-10-20", 250, .entertainment),
            tx("2026-11-01", 5_000, .salary), tx("2026-11-10", 300, .food),
        ]
    }

    private func data(
        _ txs: [TransactionRecord]? = nil,
        budgets: [BudgetLimitRecord] = [],
        goals: [SavingsGoalRecord] = [],
        plans: [InstallmentPlanRecord] = [],
        currency: CurrencyCode = .sgd,
        hidden: Bool = false
    ) -> AdviserDataSet {
        AdviserDataSet(transactions: txs ?? fixture, budgets: budgets, goals: goals, plans: plans, currency: currency, todayKey: today, salaryHidden: hidden)
    }

    private func sgd(_ cents: Int64) -> AdviserFigure<Int64> { .value(cents) }

    // MARK: Cash flow

    func testMonthlySeriesAveragesAndChange() throws {
        let h = CashFlowHistory(data: data())
        XCTAssertEqual(h.months.map(\.monthKey), ["2026-08", "2026-09", "2026-10"])
        XCTAssertEqual(h.monthsWithData, 3)
        XCTAssertEqual(h.months.map(\.spendingMinor), [250_000, 275_000, 320_000])
        XCTAssertEqual(h.months.map(\.net), [sgd(250_000), sgd(225_000), sgd(230_000)])
        XCTAssertEqual(h.months.map(\.savingsRatePercent), [.value(50.0), .value(45.0), .value(41.8)])
        XCTAssertEqual(h.months.map(\.spendingChangeMinor), [nil, 25_000, 45_000])
        XCTAssertEqual(h.months[2].spendingByCategory[.food], 80_000)

        // 8,450 / 3 = 2,816.67; 15,500 / 3 = 5,166.67; 7,050 / 3 = 2,350; 7,050 / 15,500 = 45.48%.
        XCTAssertEqual(h.averageSpendingMinor, sgd(281_667))
        XCTAssertEqual(h.averageIncomeMinor, sgd(516_667))
        XCTAssertEqual(h.averageNonSalaryIncomeMinor, sgd(16_667))
        XCTAssertEqual(h.averageNetMinor, sgd(235_000))
        XCTAssertEqual(h.averageSavingsRatePercent, .value(45.5))
        XCTAssertEqual(h.averageSpendingByCategory.value?[.food], 60_000)

        let change = try XCTUnwrap(h.latestChange.value)
        XCTAssertEqual(change.fromMonthKey, "2026-09")
        XCTAssertEqual(change.spendingChangeMinor, 45_000)
        XCTAssertEqual(change.spendingChangePercent, 16.4) // 450 / 2,750
        XCTAssertEqual(change.incomeChange, sgd(50_000))
        XCTAssertEqual(change.netChange, sgd(5_000))

        // Current month is month-to-date, not averaged.
        XCTAssertEqual(h.currentMonth.monthKey, "2026-11")
        XCTAssertEqual(h.currentMonth.spendingMinor, 30_000)
        XCTAssertEqual(h.daysElapsedInCurrentMonth, 24)
        XCTAssertEqual(h.daysInCurrentMonth, 30)
    }

    func testMoversAgainstEarlierAverage() throws {
        let movers = try XCTUnwrap(CashFlowHistory(data: data()).movers.value)
        // Oct vs avg(Aug, Sep): food 800 vs 500, fun 250 vs 0, bills 150 vs 75, shopping 0 vs 50.
        XCTAssertEqual(movers.map(\.category), [.food, .entertainment, .bills, .shopping])
        XCTAssertEqual(movers.map(\.changeMinor), [30_000, 25_000, 7_500, -5_000])
        XCTAssertEqual(movers[0].changePercent, 60.0)
        XCTAssertNil(movers[1].changePercent, "no baseline")
        XCTAssertEqual(movers[3].changePercent, -100.0)
    }

    func testFixedVariableSplitCountsPlanPaymentsAndFixedCategories() throws {
        let split = try XCTUnwrap(CashFlowHistory(data: data()).fixedVariable.value)
        // Fixed: 2,000 + 2,150 + 2,150 = 6,300 over 3 months; variable 2,150 / 3.
        XCTAssertEqual(split.averageFixedMinor, 210_000)
        XCTAssertEqual(split.averageVariableMinor, 71_667)
        XCTAssertEqual(split.fixedSharePercent, 74.6)

        var withPlan = fixture
        var payment = tx("2026-10-15", 100, .shopping, name: "iPhone")
        payment.planID = "ipp"
        payment.planPaymentIndex = 0
        withPlan.append(payment)
        let split2 = try XCTUnwrap(CashFlowHistory(data: data(withPlan)).fixedVariable.value)
        XCTAssertEqual(split2.averagePlanPaymentsMinor, 3_333) // 100 / 3
        XCTAssertEqual(split2.averageFixedMinor, 213_333) // 6,400 / 3
        XCTAssertEqual(split2.averageVariableMinor, 71_667, "a plan payment counts as fixed even in a variable category")
    }

    func testHiddenSalaryLocksIncomeFiguresButNotSpending() {
        let h = CashFlowHistory(data: data(hidden: true))
        XCTAssertEqual(h.averageIncomeMinor, .salaryLocked)
        XCTAssertEqual(h.averageNetMinor, .salaryLocked)
        XCTAssertEqual(h.averageSavingsRatePercent, .salaryLocked)
        XCTAssertEqual(h.averageSpendingMinor, sgd(281_667))
        XCTAssertEqual(h.averageNonSalaryIncomeMinor, sgd(16_667), "other income is never hidden")
        XCTAssertTrue(h.months.allSatisfy { $0.income == .salaryLocked && $0.net == .salaryLocked && $0.savingsRatePercent == .salaryLocked })
        XCTAssertEqual(h.months[2].nonSalaryIncomeMinor, 50_000)
        XCTAssertEqual(h.latestChange.value?.incomeChange, .salaryLocked)
        XCTAssertEqual(h.latestChange.value?.spendingChangeMinor, 45_000)
    }

    func testHiddenSalaryWithoutSalaryInWindowShowsIncome() {
        let noSalary = fixture.filter { $0.category != .salary }
        let h = CashFlowHistory(data: data(noSalary, hidden: true))
        XCTAssertEqual(h.averageIncomeMinor, sgd(16_667))
    }

    func testEmptyAndShortHistoryAreExplicit() {
        let empty = CashFlowHistory(data: data([]))
        XCTAssertTrue(empty.months.isEmpty)
        XCTAssertEqual(empty.monthsWithData, 0)
        XCTAssertTrue(empty.notes.contains("No transactions recorded yet."))
        for figure in [empty.averageSpendingMinor, empty.averageIncomeMinor, empty.averageNetMinor] {
            guard case .insufficient = figure else { return XCTFail("\(figure)") }
        }
        guard case .insufficient = empty.movers, case .insufficient = empty.latestChange, case .insufficient = empty.fixedVariable else {
            return XCTFail("short history must be explicit")
        }

        let currentOnly = CashFlowHistory(data: data([tx("2026-11-03", 20, .food)]))
        XCTAssertTrue(currentOnly.months.isEmpty)
        XCTAssertTrue(currentOnly.notes.contains { $0.contains("No complete month yet") })
        XCTAssertEqual(currentOnly.currentMonth.spendingMinor, 2_000)
        XCTAssertEqual(currentOnly.currentMonth.savingsRatePercent, .insufficient("no income recorded in 2026-11"))

        let oneMonth = CashFlowHistory(data: data([tx("2026-10-03", 20, .food)]))
        XCTAssertEqual(oneMonth.monthsWithData, 1)
        XCTAssertEqual(oneMonth.averageSpendingMinor, .insufficient("only 1 complete month(s) with transactions; averages need at least 2"))
    }

    func testMonthsWithoutTransactionsAreListedButNotAveraged() {
        let h = CashFlowHistory(data: data([tx("2026-07-03", 100, .food), tx("2026-10-03", 300, .food)]))
        XCTAssertEqual(h.months.map(\.monthKey), ["2026-07", "2026-08", "2026-09", "2026-10"])
        XCTAssertEqual(h.monthsWithData, 2)
        XCTAssertEqual(h.averageSpendingMinor, sgd(20_000), "(100 + 300) / 2, not / 4")
        XCTAssertEqual(h.months[3].spendingChangeMinor, nil, "previous month has no data")
        XCTAssertTrue(h.notes.contains { $0.contains("2026-08, 2026-09") })
    }

    func testWindowIsTwelveCompleteMonthsAndFutureEntriesAreIgnored() {
        var txs = (0..<18).map { offset in tx(DateKey.shiftMonth("2025-05", by: offset) + "-10", 10, .food) }
        txs.append(tx("2026-12-01", 999, .food))
        let h = CashFlowHistory(data: data(txs))
        XCTAssertEqual(h.months.count, 12)
        XCTAssertEqual(h.months.first?.monthKey, "2025-11")
        XCTAssertEqual(h.months.last?.monthKey, "2026-10")
        XCTAssertEqual(CashFlowHistory(data: data(txs), months: 3).months.map(\.monthKey), ["2026-08", "2026-09", "2026-10"])
        XCTAssertEqual(h.currentMonth.spendingMinor, 0, "the December entry is after today")
    }

    func testVNDAveragesRoundToWholeDong() {
        let txs = [
            TransactionRecord(name: "a", amountMinor: 100_000_00, type: .expense, category: .food, dayKey: "2026-09-02"),
            TransactionRecord(name: "b", amountMinor: 100_000_00, type: .expense, category: .food, dayKey: "2026-10-02"),
            TransactionRecord(name: "c", amountMinor: 100_001_00, type: .expense, category: .food, dayKey: "2026-08-02"),
        ]
        let h = CashFlowHistory(data: data(txs, currency: .vnd))
        // 300,001 ₫ / 3 = 100,000.33 ₫ -> 100,000 ₫ (storage is whole hundreds).
        XCTAssertEqual(h.averageSpendingMinor, .value(100_000_00))
    }

    // MARK: Budgets

    func testBudgetAdherenceHistoryAndSuggestedLimit() throws {
        let budgets = [
            BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 50_000),
            BudgetLimitRecord(monthKey: "2026-09", category: .food, limitMinor: 55_000),
        ]
        let b = BudgetAdherence(data: data(budgets: budgets))
        XCTAssertEqual(b.monthKey, "2026-11")
        let food = try XCTUnwrap(b.categories.first)
        XCTAssertEqual(food.category, .food)
        XCTAssertEqual(food.limitMinor, 50_000)
        XCTAssertEqual(food.spentMinor, 30_000)
        XCTAssertEqual(food.remainingMinor, 20_000)
        XCTAssertEqual(food.percentUsed, 60.0)
        XCTAssertEqual(food.status, .under)
        XCTAssertEqual(food.projectedMonthEndMinor, 37_500) // 300 x 30 / 24
        XCTAssertEqual(food.projectedOverLimit, false)
        XCTAssertEqual(food.monthsAboveCurrentLimit, 2) // Sep 600, Oct 800 > 500
        XCTAssertEqual(food.monthsCompared, 3)
        XCTAssertEqual(food.monthsWithBudget, 1)
        XCTAssertEqual(food.monthsOverItsBudget, 1) // Sep 600 > 550
        XCTAssertEqual(food.suggestedLimit, .value(SuggestedLimit(limitMinor: 60_000, medianMinor: 60_000, monthsUsed: 3)))

        let housing = try XCTUnwrap(b.categories.first { $0.category == .housing })
        XCTAssertNil(housing.limitMinor)
        XCTAssertEqual(housing.suggestedLimit.value?.limitMinor, 200_000)
        let fun = try XCTUnwrap(b.categories.first { $0.category == .entertainment })
        XCTAssertEqual(fun.suggestedLimit, .insufficient("median monthly spending in entertainment is 0"))
    }

    func testBudgetStatusOverAndNear() throws {
        let over = BudgetAdherence(data: data(budgets: [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 25_000)]), only: .food)
        XCTAssertEqual(over.categories.first?.status, .over)
        XCTAssertEqual(over.categories.first?.remainingMinor, -5_000)
        let near = BudgetAdherence(data: data(budgets: [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 35_000)]), only: .food)
        XCTAssertEqual(near.categories.first?.status, .near) // 85.7%
        XCTAssertEqual(near.categories.first?.projectedOverLimit, true)
        let short = BudgetAdherence(data: data([tx("2026-11-02", 10, .food)]))
        guard case .insufficient = short.categories.first?.suggestedLimit else { return XCTFail() }
    }

    func testRoundUpToTwoSignificantFigures() {
        XCTAssertEqual(AdviserMath.roundUpToTwoSignificant(43_720), 44_000)
        XCTAssertEqual(AdviserMath.roundUpToTwoSignificant(123_400_000), 130_000_000)
        XCTAssertEqual(AdviserMath.roundUpToTwoSignificant(850), 900, "8.50 -> 9 (step at least one unit)")
        XCTAssertEqual(AdviserMath.roundUpToTwoSignificant(200_000), 200_000)
        XCTAssertEqual(AdviserMath.roundUpToTwoSignificant(0), 0)
    }

    // MARK: Debt

    private var phone: InstallmentPlanRecord {
        InstallmentPlanRecord(id: "phone", name: "iPhone", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2026-06-15")
    }

    private var loan: InstallmentPlanRecord {
        .loan(id: "car", name: "Car loan", principalMinor: 1_000_000, monthlyPaymentMinor: 86_066, months: 12, firstPaymentDayKey: "2026-10-05")
    }

    func testDebtOverviewTotalsRatioAndOrders() throws {
        let d = DebtOverview(data: data(plans: [phone, loan]))
        XCTAssertEqual(d.plans.count, 2)
        let car = try XCTUnwrap(d.plans.first { $0.planID == "car" })
        XCTAssertEqual(car.nextPaymentMinor, 86_066)
        XCTAssertEqual(car.nextPaymentDayKey, "2026-12-05")
        XCTAssertEqual(car.remainingPayments, 10)
        XCTAssertEqual(car.remainingScheduledMinor, 860_660)
        XCTAssertEqual(car.effectiveAnnualRatePercent, 6.0, accuracy: 0.01)
        // Hand amortization at 0.5%/month: 10,000 -> 9,189.34 -> 8,374.63.
        XCTAssertEqual(Double(car.outstandingPrincipalMinor), 837_463, accuracy: 2)
        let iphone = try XCTUnwrap(d.plans.first { $0.planID == "phone" })
        XCTAssertEqual(iphone.remainingPayments, 6)
        XCTAssertEqual(iphone.outstandingPrincipalMinor, 60_000)
        XCTAssertEqual(iphone.settleToday, .value(EarlySettlement(settleDayKey: today, payoffPrincipalMinor: 60_000, interestSavedMinor: 0, cancelledPaymentCount: 6, cancelledPaymentsMinor: 60_000)))
        let carSettle = try XCTUnwrap(car.settleToday.value)
        // Total interest 327.92 minus interest paid (50.00 + 45.95).
        XCTAssertEqual(Double(carSettle.interestSavedMinor), 23_197, accuracy: 2)

        XCTAssertEqual(d.monthlyDebtServiceMinor, 96_066)
        XCTAssertEqual(d.debtServiceToIncomePercent, .value(18.6)) // 960.66 / 5,166.67
        XCTAssertEqual(d.highestRateFirst, ["car", "phone"])
        XCTAssertEqual(d.smallestBalanceFirst, ["phone", "car"])

        XCTAssertEqual(DebtOverview(data: data(plans: [phone, loan], hidden: true)).debtServiceToIncomePercent, .salaryLocked)
        let none = DebtOverview(data: data())
        XCTAssertTrue(none.plans.isEmpty)
        XCTAssertEqual(none.monthlyDebtServiceMinor, 0)
        XCTAssertTrue(none.notes.first?.contains("No active") == true)
    }

    func testEarlySettlementBeforeFirstPaymentIsNotAvailable() {
        let future = InstallmentPlanRecord(id: "f", name: "Sofa", totalMinor: 60_000, months: 6, firstPaymentDayKey: "2027-01-10")
        guard case .insufficient(let reason) = EarlySettlement.compute(plan: future, settleDayKey: today, todayKey: today) else { return XCTFail() }
        XCTAssertTrue(reason.contains("2027-01-10"))
    }

    // MARK: Affordability

    func testAffordabilityAtRate() throws {
        let check = try AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 1_000_000, months: 12, annualRatePercent: 6), data: data()).get()
        XCTAssertEqual(check.basis, .annuityAtRate)
        XCTAssertEqual(check.monthlyPaymentMinor, 86_066) // 10,000 x 0.005 / (1 - 1.005^-12)
        XCTAssertEqual(check.totalRepaidMinor, 1_032_792)
        XCTAssertEqual(check.totalInterestMinor, 32_792)
        XCTAssertEqual(check.currentDebtServiceMinor, 0)
        XCTAssertEqual(check.newDebtServiceToIncomePercent, .value(16.7)) // 860.66 / 5,166.67
        XCTAssertEqual(check.newMonthlyNetMinor, sgd(148_934)) // 2,350 - 860.66
        XCTAssertEqual(check.newMonthlySpendingMinor, sgd(367_733)) // 2,816.67 + 860.66

        let hidden = try AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 1_000_000, months: 12, annualRatePercent: 6), data: data(hidden: true)).get()
        XCTAssertEqual(hidden.newDebtServiceToIncomePercent, .salaryLocked)
        XCTAssertEqual(hidden.newMonthlyNetMinor, .salaryLocked)
        XCTAssertEqual(hidden.newMonthlySpendingMinor, sgd(367_733))
    }

    func testAffordabilityGivenPaymentInterestFreeAndErrors() throws {
        let given = try AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 1_000_000, months: 12, monthlyPaymentMinor: 86_066), data: data(plans: [phone])).get()
        XCTAssertEqual(given.basis, .givenMonthlyPayment)
        XCTAssertEqual(given.annualRatePercent, 6.0, accuracy: 0.01)
        XCTAssertEqual(given.currentDebtServiceMinor, 10_000)
        XCTAssertEqual(given.newDebtServiceMinor, 96_066)

        let free = try AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 100_000, months: 3), data: data()).get()
        XCTAssertEqual(free.basis, .interestFree)
        XCTAssertEqual(free.monthlyPaymentMinor, 33_333)
        XCTAssertEqual(free.totalRepaidMinor, 100_000)
        XCTAssertTrue(free.notes.contains { $0.contains(MoneyFormat.format(minor: 33_334, currency: .sgd)) })

        // VND: whole-dong payments (storage step 100).
        let vnd = try AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 1_200_000_000, months: 7), data: data([], currency: .vnd)).get()
        XCTAssertEqual(vnd.monthlyPaymentMinor, 171_428_600)
        XCTAssertEqual(vnd.monthlyPaymentMinor % 100, 0)
        guard case .insufficient = vnd.newDebtServiceToIncomePercent else { return XCTFail("no history") }

        XCTAssertEqual(AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 1_000_000, months: 12, monthlyPaymentMinor: 50_000), data: data()).failureValue, .paymentTooSmall(totalMinor: 600_000))
        XCTAssertEqual(AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 0, months: 12), data: data()).failureValue, .invalidAmount)
        XCTAssertEqual(AffordabilityCheck.evaluate(AffordabilityInput(amountMinor: 100, months: 0), data: data()).failureValue, .invalidMonths)
    }

    // MARK: Goals & runway

    func testGoalOutlookAndPlan() throws {
        let goal = SavingsGoalRecord(id: "jp", name: "Japan trip", targetMinor: 1_000_000, savedMinor: 295_000)
        let d = data(goals: [goal])
        let history = CashFlowHistory(data: d)
        let outlook = GoalOutlook(goalID: goal.id, name: goal.name, targetMinor: goal.targetMinor, savedMinor: goal.savedMinor, data: d, history: history)
        XCTAssertEqual(outlook.neededMinor, 705_000)
        XCTAssertEqual(outlook.monthsToTarget, .value(3)) // 7,050 / 2,350
        XCTAssertEqual(outlook.projectedMonthKey, .value("2027-02"))

        let plan = try GoalPlan.evaluate(outlook: outlook, targetMonthKey: "2027-05", contributionMinor: 100_000, data: d).get()
        XCTAssertEqual(plan.contributionMonths, 6)
        XCTAssertEqual(plan.requiredMonthlyMinor, 117_500)
        XCTAssertEqual(plan.shortfallVersusPaceMinor, sgd(-117_500))
        XCTAssertEqual(plan.monthsAtContribution, 8) // 7,050 / 1,000 rounded up
        XCTAssertEqual(plan.monthKeyAtContribution, "2027-07")

        XCTAssertEqual(GoalPlan.evaluate(outlook: outlook, targetMonthKey: "2026-11", contributionMinor: nil, data: d).failureValue, .targetDateNotInFuture(currentMonthKey: "2026-11"))

        let hidden = data(goals: [goal], hidden: true)
        let locked = GoalOutlook(goalID: goal.id, name: goal.name, targetMinor: goal.targetMinor, savedMinor: goal.savedMinor, data: hidden, history: CashFlowHistory(data: hidden))
        XCTAssertEqual(locked.monthsToTarget, .salaryLocked)
        let lockedPlan = try GoalPlan.evaluate(outlook: locked, targetMonthKey: "2027-05", contributionMinor: nil, data: hidden).get()
        XCTAssertEqual(lockedPlan.requiredMonthlyMinor, 117_500, "the required contribution does not need income")
        XCTAssertEqual(lockedPlan.shortfallVersusPaceMinor, .salaryLocked)

        let reached = GoalOutlook(goalID: nil, name: "x", targetMinor: 100, savedMinor: 200, data: d, history: history)
        XCTAssertEqual(reached.neededMinor, 0)
        XCTAssertEqual(reached.monthsToTarget, .value(0))

        let spendingOnly = data([tx("2026-09-02", 100, .food), tx("2026-10-02", 100, .food)])
        let negative = GoalOutlook(goalID: nil, name: "x", targetMinor: 1_000, savedMinor: 0, data: spendingOnly, history: CashFlowHistory(data: spendingOnly))
        guard case .insufficient = negative.monthsToTarget else { return XCTFail("non-positive pace") }
    }

    func testRunway() {
        let estimate = RunwayEstimate(cashMinor: 1_000_000, history: CashFlowHistory(data: data(hidden: true)))
        XCTAssertEqual(estimate.monthsOfSpending, .value(3.5)) // 10,000 / 2,816.67 = 3.55 -> 3.5
        XCTAssertEqual(estimate.monthsOfFixedCosts, .value(4.7)) // 10,000 / 2,100 = 4.76 -> 4.7
        guard case .insufficient = RunwayEstimate(cashMinor: 1_000_000, history: CashFlowHistory(data: data([]))).monthsOfSpending else { return XCTFail() }
    }

    // MARK: Period summary

    func testPeriodSummary() {
        let s = PeriodSummary(data: data(), startDayKey: "2026-10-01", endDayKey: "2026-10-31")
        XCTAssertEqual(s.dayCount, 31)
        XCTAssertEqual(s.spendingMinor, 320_000)
        XCTAssertEqual(s.spendingByCategory.map(\.category), [.housing, .food, .entertainment, .bills])
        XCTAssertEqual(s.spendingByCategory.map(\.sharePercent), [62.5, 25.0, 7.8, 4.7])
        XCTAssertEqual(s.income, sgd(550_000))
        XCTAssertEqual(s.net, sgd(230_000))
        XCTAssertEqual(s.averagePerDayMinor, 10_323) // 3,200 / 31
        XCTAssertEqual(s.members.map(\.name), ["Alex", "Sam"])
        XCTAssertEqual(s.topMerchants.first?.name, "Rent")

        let hidden = PeriodSummary(data: data(hidden: true), startDayKey: "2026-10-01", endDayKey: "2026-10-31")
        XCTAssertEqual(hidden.income, .salaryLocked)
        XCTAssertEqual(hidden.net, .salaryLocked)
        XCTAssertEqual(hidden.nonSalaryIncomeMinor, 50_000)

        let samFood = PeriodSummary(data: data(), startDayKey: "2026-10-01", endDayKey: "2026-10-31", category: .food, memberID: "p")
        XCTAssertEqual(samFood.spendingMinor, 30_000)
        XCTAssertEqual(samFood.income, sgd(0))
    }
}

extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
