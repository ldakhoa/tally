import BudgetKit
import TallyCore
import XCTest

final class MotivationMetricsTests: XCTestCase {
    private func expense(_ amount: Int64, _ category: CategoryID, _ dayKey: String, member: String = "me") -> TransactionRecord {
        TransactionRecord(name: "x", amountMinor: amount, type: .expense, category: category, dayKey: dayKey, memberID: member)
    }

    private func snapshot(
        month: String = "2026-11",
        budgets: [BudgetLimitRecord],
        transactions: [TransactionRecord]
    ) -> MonthlySnapshot {
        MonthlySnapshot.compute(monthKey: month, allTransactions: transactions, allBudgets: budgets, todayKey: "2026-11-10")
    }

    // MARK: Budget momentum

    func testCurrentMonthAheadOfPace() {
        // 30-day month, day 10: even-spend line = 300,000 * 10 / 30 = 100,000.
        let snap = snapshot(
            budgets: [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 300_000)],
            transactions: [expense(40_000, .food, "2026-11-03")]
        )
        let m = BudgetMomentum(snapshot: snap, todayKey: "2026-11-10")
        XCTAssertEqual(m.timing, .current)
        XCTAssertEqual(m.daysElapsed, 10)
        XCTAssertEqual(m.daysLeft, 21)
        XCTAssertEqual(m.leftMinor, 260_000)
        XCTAssertEqual(m.paceCushionMinor, 60_000)
        XCTAssertEqual(m.safeToSpendPerDayMinor, 260_000 / 21)
        XCTAssertEqual(m.pace, .ahead)
        XCTAssertEqual(m.categoriesOnTrack, 1)
        XCTAssertEqual(m.categoriesTotal, 1)
    }

    func testOnTrackBandAndBehind() {
        let budgets = [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 300_000)]
        // Line is 100,000; band is 5% of 300,000 = 15,000.
        let near = BudgetMomentum(
            snapshot: snapshot(budgets: budgets, transactions: [expense(110_000, .food, "2026-11-02")]),
            todayKey: "2026-11-10"
        )
        XCTAssertEqual(near.pace, .onTrack)

        let fast = BudgetMomentum(
            snapshot: snapshot(budgets: budgets, transactions: [expense(200_000, .food, "2026-11-02")]),
            todayKey: "2026-11-10"
        )
        XCTAssertEqual(fast.pace, .behind)
        XCTAssertEqual(fast.paceCushionMinor, -100_000)
    }

    func testOverBudgetCountsCategoriesAndStopsAllowance() {
        let snap = snapshot(
            budgets: [
                BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 100_000),
                BudgetLimitRecord(monthKey: "2026-11", category: .shopping, limitMinor: 50_000),
            ],
            transactions: [expense(190_000, .food, "2026-11-02"), expense(10_000, .shopping, "2026-11-02")]
        )
        let m = BudgetMomentum(snapshot: snap, todayKey: "2026-11-10")
        XCTAssertEqual(m.pace, .over)
        XCTAssertEqual(m.safeToSpendPerDayMinor, 0)
        XCTAssertEqual(m.categoriesOnTrack, 1)
        XCTAssertEqual(m.categoriesTotal, 2)
        XCTAssertEqual(m.leftFraction, 0)
    }

    func testPastFutureAndNoBudget() {
        let budgets = [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 300_000)]
        let snap = snapshot(budgets: budgets, transactions: [expense(40_000, .food, "2026-11-03")])

        let past = BudgetMomentum(snapshot: snap, todayKey: "2026-12-04")
        XCTAssertEqual(past.timing, .past)
        XCTAssertEqual(past.pace, .finishedUnder)
        XCTAssertEqual(past.daysLeft, 0)
        XCTAssertEqual(past.safeToSpendPerDayMinor, 0)

        let future = BudgetMomentum(snapshot: snap, todayKey: "2026-10-20")
        XCTAssertEqual(future.timing, .future)
        XCTAssertEqual(future.pace, .upcoming)
        XCTAssertEqual(future.daysLeft, 30)

        let none = BudgetMomentum(snapshot: snapshot(budgets: [], transactions: []), todayKey: "2026-11-10")
        XCTAssertEqual(none.pace, .noBudget)
    }

    func testUnderBudgetMonthStreak() {
        let budgets = ["2026-07", "2026-08", "2026-09", "2026-10"].map {
            BudgetLimitRecord(monthKey: $0, category: .food, limitMinor: 100_000)
        }
        let transactions = [
            expense(150_000, .food, "2026-07-05"), // over: ends the streak
            expense(90_000, .food, "2026-08-05"),
            expense(100_000, .food, "2026-09-05"), // exactly at the limit still counts
            expense(10_000, .food, "2026-10-05"),
            expense(999_000, .shopping, "2026-10-06"), // not a budgeted category
        ]
        XCTAssertEqual(
            BudgetMomentum.underBudgetMonthStreak(before: "2026-11", allTransactions: transactions, allBudgets: budgets),
            3
        )
        // A month with no limits breaks the chain.
        XCTAssertEqual(
            BudgetMomentum.underBudgetMonthStreak(before: "2026-12", allTransactions: transactions, allBudgets: budgets),
            0
        )
    }

    func testStreakRespectsMemberFilterAndDeletedRows() {
        let budgets = [
            BudgetLimitRecord(monthKey: "2026-10", category: .food, limitMinor: 100_000),
            BudgetLimitRecord(monthKey: "2026-09", category: .food, limitMinor: 100_000, isDeleted: true),
        ]
        let transactions = [
            expense(80_000, .food, "2026-10-05", member: "me"),
            expense(80_000, .food, "2026-10-06", member: "partner"),
        ]
        XCTAssertEqual(BudgetMomentum.underBudgetMonthStreak(before: "2026-11", allTransactions: transactions, allBudgets: budgets), 0)
        XCTAssertEqual(
            BudgetMomentum.underBudgetMonthStreak(before: "2026-11", allTransactions: transactions, allBudgets: budgets, memberFilter: "me"),
            1
        )
    }

    // MARK: Savings level

    func testSavingsLevelTiersAndTargets() throws {
        XCTAssertNil(SavingsLevel(incomeMinor: 0, netSavingsMinor: 0))

        // 15% kept -> sprout, next is bloom at 20%.
        let level = try XCTUnwrap(SavingsLevel(incomeMinor: 1_000_000, netSavingsMinor: 150_000))
        XCTAssertEqual(level.tier, .sprout)
        XCTAssertEqual(level.nextTier, .bloom)
        XCTAssertEqual(level.ratePercent, 15)
        XCTAssertEqual(level.progressToNext, 0.5, accuracy: 0.0001)
        XCTAssertEqual(level.spendLessMinor, 50_000)
        // (150,000 + E) / (1,000,000 + E) >= 0.2  ->  E >= 62,500
        XCTAssertEqual(level.earnMoreMinor, 62_500)
        let reached = try XCTUnwrap(SavingsLevel(
            incomeMinor: 1_000_000 + level.earnMoreMinor,
            netSavingsMinor: 150_000 + level.earnMoreMinor
        ))
        XCTAssertEqual(reached.tier, .bloom)
    }

    func testSavingsLevelEdges() throws {
        let negative = try XCTUnwrap(SavingsLevel(incomeMinor: 1_000_000, netSavingsMinor: -200_000))
        XCTAssertEqual(negative.tier, .starting)
        XCTAssertEqual(negative.progressToNext, 0)
        XCTAssertEqual(negative.spendLessMinor, 250_000)

        let exact = try XCTUnwrap(SavingsLevel(incomeMinor: 1_000_000, netSavingsMinor: 300_000))
        XCTAssertEqual(exact.tier, .golden)

        let top = try XCTUnwrap(SavingsLevel(incomeMinor: 1_000_000, netSavingsMinor: 700_000))
        XCTAssertEqual(top.tier, .master)
        XCTAssertNil(top.nextTier)
        XCTAssertEqual(top.earnMoreMinor, 0)
        XCTAssertEqual(top.progressToNext, 1)
    }

    // MARK: Goals

    func testGoalMilestones() {
        let none = GoalMilestones(savedMinor: 0, targetMinor: 1_000)
        XCTAssertEqual(none.reachedCount, 0)
        XCTAssertEqual(none.nextStepPercent, 25)
        XCTAssertEqual(none.toNextMinor, 250)
        XCTAssertNil(none.lastReachedPercent)

        let half = GoalMilestones(savedMinor: 500, targetMinor: 1_000)
        XCTAssertEqual(half.reachedCount, 2)
        XCTAssertEqual(half.lastReachedPercent, 50)
        XCTAssertEqual(half.nextStepPercent, 75)
        XCTAssertEqual(half.toNextMinor, 250)
        XCTAssertEqual(half.remainingMinor, 500)

        let almost = GoalMilestones(savedMinor: 249, targetMinor: 1_000)
        XCTAssertEqual(almost.reachedCount, 0)
        XCTAssertEqual(almost.toNextMinor, 1)

        let done = GoalMilestones(savedMinor: 1_200, targetMinor: 1_000)
        XCTAssertTrue(done.isComplete)
        XCTAssertNil(done.nextStepPercent)
        XCTAssertEqual(done.remainingMinor, 0)

        XCTAssertEqual(GoalMilestones(savedMinor: 10, targetMinor: 0).reachedCount, 0)
    }

    func testGoalsJourney() {
        let goals = [
            SavingsGoalRecord(id: "a", name: "Trip", targetMinor: 1_000, savedMinor: 800),
            SavingsGoalRecord(id: "b", name: "Fund", targetMinor: 2_000, savedMinor: 2_000),
            SavingsGoalRecord(id: "c", name: "Laptop", targetMinor: 4_000, savedMinor: 1_000),
            SavingsGoalRecord(id: "d", name: "Gone", targetMinor: 9_000, savedMinor: 9_000, isDeleted: true),
        ]
        let journey = GoalsJourney(goals: goals)
        XCTAssertEqual(journey.totalSavedMinor, 3_800)
        XCTAssertEqual(journey.totalTargetMinor, 7_000)
        XCTAssertEqual(journey.completedCount, 1)
        XCTAssertEqual(journey.inProgressCount, 2)
        XCTAssertEqual(journey.starsEarned, 3 + 4 + 1)
        XCTAssertEqual(journey.starsTotal, 12)
        XCTAssertEqual(journey.closest?.id, "a")
        XCTAssertNil(GoalsJourney(goals: [goals[1]]).closest)
    }

    // MARK: Debt freedom

    func testDebtFreedom() {
        // 12 payments from 2026-08-05: 4 due by 2026-11-10, last on 2027-07-05.
        let phone = InstallmentPlanRecord(id: "phone", name: "Phone", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2026-08-05")
        // 3 payments from 2026-10-01: 2 due, last on 2026-12-01.
        let sofa = InstallmentPlanRecord(id: "sofa", name: "Sofa", totalMinor: 30_000, months: 3, firstPaymentDayKey: "2026-10-01")
        // Finished long ago.
        let done = InstallmentPlanRecord(id: "done", name: "Done", totalMinor: 20_000, months: 2, firstPaymentDayKey: "2026-01-01")

        let today = "2026-11-10"
        let freedom = DebtFreedom(overview: CommitmentsOverview(plans: [phone, sofa, done], todayKey: today), todayKey: today)

        XCTAssertEqual(freedom.paidMinor, 40_000 + 20_000)
        XCTAssertEqual(freedom.remainingMinor, 80_000 + 10_000)
        XCTAssertEqual(freedom.fraction, 0.4, accuracy: 0.0001)
        XCTAssertEqual(freedom.debtFreeDayKey, "2027-07-05")
        XCTAssertEqual(freedom.monthsUntilDebtFree, 8)
        XCTAssertEqual(freedom.freedMonthlyMinor, 20_000)
        XCTAssertEqual(freedom.paymentsLeft, 9)
        XCTAssertEqual(freedom.nextToFinish?.planID, "sofa")
        XCTAssertEqual(freedom.nextToFinish?.paymentsLeft, 1)
        XCTAssertEqual(freedom.completedCount, 1)
        XCTAssertEqual(freedom.releasedMonthlyMinor, 10_000)
        XCTAssertEqual(freedom.nextPayoffMilestone?.monthKey, "2026-12")
        XCTAssertEqual(freedom.nextPayoffMilestone?.monthlyReliefMinor, 10_000)
    }

    func testMonthlyReliefGroupsPayoffsAndUsesRegularPayment() {
        let loan = InstallmentPlanRecord(
            name: "Loan", totalMinor: 32_000, months: 3, firstPaymentDayKey: "2026-10-01", monthlyPaymentMinor: 10_000
        )
        let installment = InstallmentPlanRecord(
            name: "Installment", totalMinor: 10_000, months: 2, firstPaymentDayKey: "2026-11-08"
        )
        let oneOff = InstallmentPlanRecord(
            name: "One-off", totalMinor: 7_000, months: 1, firstPaymentDayKey: "2026-11-15"
        )
        let plans = [loan, installment, oneOff]

        let today = "2026-11-24"
        let forecast = DebtFreedom(overview: CommitmentsOverview(plans: plans, todayKey: today), todayKey: today)
        XCTAssertEqual(forecast.releasedMonthlyMinor, 0)
        XCTAssertEqual(forecast.nextPayoffMilestone?.monthKey, "2026-12")
        XCTAssertEqual(forecast.nextPayoffMilestone?.planNames, ["Loan", "Installment"])
        XCTAssertEqual(forecast.nextPayoffMilestone?.monthlyReliefMinor, 15_000)

        let afterPayoffs = "2026-12-09"
        let achieved = DebtFreedom(
            overview: CommitmentsOverview(plans: plans, todayKey: afterPayoffs), todayKey: afterPayoffs
        )
        XCTAssertEqual(achieved.releasedMonthlyMinor, 15_000)
        XCTAssertNil(achieved.nextPayoffMilestone)
    }

    func testEarlySettlementReleasesRegularPayment() {
        let plan = InstallmentPlanRecord(
            name: "Early payoff", totalMinor: 60_000, months: 6,
            firstPaymentDayKey: "2026-09-01", settledDayKey: "2026-12-18"
        )
        let beforeSettlement = "2026-12-10"
        let forecast = DebtFreedom(
            overview: CommitmentsOverview(plans: [plan], todayKey: beforeSettlement), todayKey: beforeSettlement
        )
        XCTAssertEqual(forecast.releasedMonthlyMinor, 0)
        XCTAssertEqual(forecast.nextPayoffMilestone?.monthKey, "2026-12")
        XCTAssertEqual(forecast.nextPayoffMilestone?.monthlyReliefMinor, 10_000)

        let settled = "2026-12-18"
        let achieved = DebtFreedom(
            overview: CommitmentsOverview(plans: [plan], todayKey: settled), todayKey: settled
        )
        XCTAssertEqual(achieved.releasedMonthlyMinor, 10_000)
        XCTAssertNil(achieved.nextPayoffMilestone)
    }

    func testDebtFreedomWithNothingOwed() {
        let freedom = DebtFreedom(overview: CommitmentsOverview(plans: [], todayKey: "2026-11-10"), todayKey: "2026-11-10")
        XCTAssertNil(freedom.debtFreeDayKey)
        XCTAssertEqual(freedom.fraction, 0)
        XCTAssertNil(freedom.nextToFinish)
    }
}
