import BudgetKit
import TallyCore
import XCTest

/// The "hide salary" rule: only salary transactions are masked, but so is every aggregate that
/// includes one; the same aggregate without salary shows normally.
final class SalaryPrivacyTests: XCTestCase {
    private let today = "2026-11-24"

    private func tx(
        _ id: String,
        _ amount: Int64,
        _ type: TransactionType,
        _ category: CategoryID,
        day: String,
        member: String = "a"
    ) -> TransactionRecord {
        TransactionRecord(
            id: id, name: id, amountMinor: amount, type: type, category: category,
            dayKey: day, memberID: member, memberName: member.uppercased()
        )
    }

    private var salary: TransactionRecord { tx("salary", 5_000_00, .income, .salary, day: "2026-11-02") }
    private var freelance: TransactionRecord { tx("freelance", 800_00, .income, .freelance, day: "2026-11-10") }
    private var refund: TransactionRecord { tx("refund", 40_00, .income, .income, day: "2026-11-12") }
    private var lunch: TransactionRecord { tx("lunch", 12_00, .expense, .food, day: "2026-11-03") }

    // MARK: Transactions & categories

    func testOnlySalaryTransactionsAreMasked() {
        XCTAssertTrue(salary.isSalaryMasked(hidden: true))
        XCTAssertFalse(salary.isSalaryMasked(hidden: false))
        XCTAssertFalse(freelance.isSalaryMasked(hidden: true))
        XCTAssertFalse(refund.isSalaryMasked(hidden: true))
        XCTAssertFalse(lunch.isSalaryMasked(hidden: true))
    }

    func testOnlyTheSalaryCategoryFigureIsMasked() {
        for category in CategoryID.allCases {
            XCTAssertEqual(category.isSalaryMasked(hidden: true), category == .salary, "\(category)")
            XCTAssertFalse(category.isSalaryMasked(hidden: false))
        }
        let rows = [
            CategorySpend(category: .salary, spentMinor: 5_000_00, share: 0.86),
            CategorySpend(category: .freelance, spentMinor: 800_00, share: 0.14),
        ]
        XCTAssertEqual(rows.map { $0.isSalaryMasked(hidden: true) }, [true, false])
    }

    func testAggregateMaskingFollowsItsTransactions() {
        XCTAssertTrue(SalaryPrivacy.masksAggregate(of: [salary, freelance, lunch], hidden: true))
        XCTAssertFalse(SalaryPrivacy.masksAggregate(of: [salary, freelance, lunch], hidden: false))
        XCTAssertFalse(SalaryPrivacy.masksAggregate(of: [freelance, refund, lunch], hidden: true))
        XCTAssertFalse(SalaryPrivacy.masksAggregate(of: [TransactionRecord](), hidden: true))
    }

    func testVisibleTransactionsDropOnlySalaryWhileHidden() {
        let all = [salary, freelance, refund, lunch]
        XCTAssertEqual(SalaryPrivacy.visibleTransactions(all, hidden: true).map(\.id), ["freelance", "refund", "lunch"])
        XCTAssertEqual(SalaryPrivacy.visibleTransactions(all, hidden: false).map(\.id), all.map(\.id))
    }

    // MARK: Snapshots

    func testSnapshotWithSalaryIsMaskedAndMixedIncomeStaysInTheNumbers() {
        let snapshot = MonthlySnapshot.compute(
            monthKey: "2026-11", allTransactions: [salary, freelance, lunch], allBudgets: [], todayKey: today
        )
        XCTAssertTrue(snapshot.includesSalary)
        XCTAssertTrue(snapshot.isSalaryMasked(hidden: true))
        XCTAssertFalse(snapshot.isSalaryMasked(hidden: false))
        XCTAssertEqual(snapshot.incomeMinor, 5_800_00)
    }

    func testSnapshotWithoutSalaryShowsNormallyEvenWhenHidingIsOn() {
        let snapshot = MonthlySnapshot.compute(
            monthKey: "2026-11", allTransactions: [freelance, refund, lunch], allBudgets: [], todayKey: today
        )
        XCTAssertFalse(snapshot.includesSalary)
        XCTAssertFalse(snapshot.isSalaryMasked(hidden: true))
        XCTAssertEqual(snapshot.incomeMinor, 840_00)
        XCTAssertEqual(snapshot.netSavingsMinor, 828_00)
        XCTAssertEqual(snapshot.savingsRatePercent, 99)
    }

    func testSalaryInAnotherMonthDoesNotMaskThisMonth() {
        let october = tx("oct-salary", 5_000_00, .income, .salary, day: "2026-10-02")
        let snapshot = MonthlySnapshot.compute(
            monthKey: "2026-11", allTransactions: [october, freelance], allBudgets: [], todayKey: today
        )
        XCTAssertFalse(snapshot.includesSalary)
    }

    func testDeletedSalaryDoesNotMask() {
        var deleted = salary
        deleted.isDeleted = true
        let snapshot = MonthlySnapshot.compute(
            monthKey: "2026-11", allTransactions: [deleted, freelance], allBudgets: [], todayKey: today
        )
        XCTAssertFalse(snapshot.includesSalary)
    }

    func testMemberFilterScopesTheMask() {
        let partnerFreelance = tx("pf", 300_00, .income, .freelance, day: "2026-11-05", member: "b")
        let all = [salary, partnerFreelance, lunch]
        let mine = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: all, allBudgets: [], memberFilter: "a", todayKey: today)
        let partner = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: all, allBudgets: [], memberFilter: "b", todayKey: today)
        XCTAssertTrue(mine.isSalaryMasked(hidden: true))
        XCTAssertFalse(partner.isSalaryMasked(hidden: true))
    }

    func testPerMemberAndPerBinIncomeMaskOnlyWhereSalaryIs() {
        let partnerFreelance = tx("pf", 300_00, .income, .freelance, day: "2026-11-20", member: "b")
        let snapshot = MonthlySnapshot.compute(
            monthKey: "2026-11", allTransactions: [salary, partnerFreelance, freelance], allBudgets: [], todayKey: today
        )
        let byMember = Dictionary(uniqueKeysWithValues: snapshot.memberBreakdown.map { ($0.memberID, $0) })
        XCTAssertTrue(byMember["a"]?.isSalaryMasked(hidden: true) == true)
        XCTAssertTrue(byMember["b"]?.isSalaryMasked(hidden: true) == false)

        // Salary on the 2nd is in week 1 (1–7); freelance on the 10th (week 2) and 20th (week 3).
        let bins = snapshot.weeklyCashFlow
        XCTAssertEqual(bins.map { $0.isSalaryMasked(hidden: true) }, [true, false, false, false, false])
        XCTAssertEqual(bins[1].incomeMinor, 800_00)
    }

    func testDailyGroupsMaskOnlyTheDayWithSalary() {
        let groups = MonthlySnapshot.groupByDay([salary, freelance, lunch])
        let byDay = Dictionary(uniqueKeysWithValues: groups.map { ($0.dayKey, $0) })
        XCTAssertTrue(byDay["2026-11-02"]?.isSalaryMasked(hidden: true) == true)
        XCTAssertTrue(byDay["2026-11-10"]?.isSalaryMasked(hidden: true) == false)
        XCTAssertTrue(byDay["2026-11-03"]?.isSalaryMasked(hidden: true) == false)
    }

    func testCalendarTotalsCarrySalaryUpToDayMonthAndPeriod() {
        let daily = MonthlySnapshot.dailyTotals(allTransactions: [salary, freelance, lunch])
        XCTAssertTrue(daily["2026-11-02"]?.isSalaryMasked(hidden: true) == true)
        XCTAssertTrue(daily["2026-11-10"]?.isSalaryMasked(hidden: true) == false)

        let monthly = MonthlySnapshot.monthlyTotals(from: daily)
        XCTAssertTrue(monthly["2026-11"]?.isSalaryMasked(hidden: true) == true)

        let weekAfterSalary = MonthlySnapshot.periodTotal(for: .range(start: "2026-11-08", end: "2026-11-14"), dailyTotals: daily)
        XCTAssertFalse(weekAfterSalary.isSalaryMasked(hidden: true))
        XCTAssertEqual(weekAfterSalary.incomeMinor, 800_00)
        let wholeMonth = MonthlySnapshot.periodTotal(for: .month("2026-11"), dailyTotals: daily)
        XCTAssertTrue(wholeMonth.isSalaryMasked(hidden: true))
    }

    // MARK: Statistics

    func testStatisticsTrendMasksOnlyMonthsWithSalary() {
        let oct = tx("oct-salary", 5_000_00, .income, .salary, day: "2026-10-02")
        let octFreelance = tx("oct-free", 100_00, .income, .freelance, day: "2026-10-09")
        let sep = tx("sep-free", 700_00, .income, .freelance, day: "2026-09-09")
        // November has no salary.
        let stats = StatisticsSnapshot.compute(
            period: .month("2026-11"),
            allTransactions: [oct, octFreelance, sep, freelance, lunch],
            allBudgets: [],
            trendMonths: 3,
            todayKey: today
        )
        XCTAssertEqual(stats.monthlyTrend.map(\.monthKey), ["2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(stats.monthlyTrend.map { $0.isSalaryMasked(hidden: true) }, [false, true, false])

        // Chart bars: the October income bar is gone, September's and November's are drawn.
        let bars = TrendChartBar.bars(for: stats.monthlyTrend, hideSalary: true)
        XCTAssertEqual(bars.filter { $0.kind == .income }.map(\.monthKey), ["2026-09", "2026-11"])
        XCTAssertEqual(bars.filter { $0.kind == .spending }.count, 3)
        // Income bars are all drawn when hiding is off.
        XCTAssertEqual(TrendChartBar.bars(for: stats.monthlyTrend, hideSalary: false).filter { $0.kind == .income }.count, 3)
        // The hidden October income (5,100.00) cannot force the axis scale.
        XCTAssertLessThan(bars.map(\.amountMinor).max() ?? 0, 5_000_00)
    }

    func testStatisticsCurrentAndPreviousPeriodMasking() {
        let oct = tx("oct-salary", 5_000_00, .income, .salary, day: "2026-10-02")
        let stats = StatisticsSnapshot.compute(
            period: .month("2026-11"), allTransactions: [oct, freelance], allBudgets: [], todayKey: today
        )
        XCTAssertFalse(stats.isSalaryMasked(hidden: true), "this month has no salary")
        XCTAssertTrue(stats.previousIncludesSalary)
        XCTAssertTrue(stats.incomeChangeIncludesSalary, "the change vs. last month reveals last month's salary")

        let withSalary = StatisticsSnapshot.compute(
            period: .month("2026-11"), allTransactions: [salary, freelance], allBudgets: [], todayKey: today
        )
        XCTAssertTrue(withSalary.isSalaryMasked(hidden: true))
    }

    func testStatisticsDailySeriesAndIncomeBreakdown() {
        let stats = StatisticsSnapshot.compute(
            period: .month("2026-11"), allTransactions: [salary, freelance, lunch], allBudgets: [], todayKey: today
        )
        let byDay = Dictionary(uniqueKeysWithValues: stats.dailySeries.map { ($0.dayKey, $0) })
        XCTAssertTrue(byDay["2026-11-02"]?.isSalaryMasked(hidden: true) == true)
        XCTAssertTrue(byDay["2026-11-10"]?.isSalaryMasked(hidden: true) == false)

        let breakdown = Dictionary(uniqueKeysWithValues: stats.incomeBreakdown.map { ($0.category, $0) })
        XCTAssertTrue(breakdown[.salary]?.isSalaryMasked(hidden: true) == true)
        XCTAssertTrue(breakdown[.freelance]?.isSalaryMasked(hidden: true) == false)
    }

    // MARK: Assistant context

    private func prompt(_ txs: [TransactionRecord], hideSalary: Bool) -> String {
        let snapshot = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: txs, allBudgets: [], todayKey: today)
        return BudgetAssistantPrompt.systemPrompt(
            snapshot: snapshot, goals: [], currency: .usd, language: .english,
            now: DateKey.date(fromDayKey: today) ?? Date(), hideSalary: hideSalary
        )
    }

    func testAssistantContextKeepsNonSalaryIncomeAndDropsSalary() {
        let hidden = prompt([salary, freelance, refund, lunch], hideSalary: true)
        // Salary transaction and every aggregate that includes it are left out.
        XCTAssertFalse(hidden.contains("[id:salary]"))
        XCTAssertFalse(hidden.contains("$5,000.00"))
        XCTAssertFalse(hidden.contains("$5,840.00"), "total income")
        XCTAssertFalse(hidden.contains("Monthly income:"))
        XCTAssertFalse(hidden.contains("Net savings:"))
        XCTAssertTrue(hidden.contains("hidden salary figures"))
        // Non-salary income is still given, as transactions and as a subtotal.
        XCTAssertTrue(hidden.contains("[id:freelance]"))
        XCTAssertTrue(hidden.contains("[id:refund]"))
        XCTAssertTrue(hidden.contains("Monthly income excluding salary: $840.00"), hidden)
        XCTAssertTrue(hidden.contains("Monthly spending: $12.00"))
    }

    func testAssistantContextForPeriodWithoutSalaryIsUnchanged() {
        let hidden = prompt([freelance, refund, lunch], hideSalary: true)
        let visible = prompt([freelance, refund, lunch], hideSalary: false)
        XCTAssertEqual(hidden, visible)
        XCTAssertTrue(hidden.contains("Monthly income: $840.00"))
        XCTAssertTrue(hidden.contains("Net savings: $828.00"))
        XCTAssertFalse(hidden.contains("hidden salary figures"))
    }

    func testAssistantContextShowsEverythingWhenNotHidden() {
        let shown = prompt([salary, freelance, lunch], hideSalary: false)
        XCTAssertTrue(shown.contains("[id:salary]"))
        XCTAssertTrue(shown.contains("Monthly income: $5,800.00"))
    }

    func testCompactMonthLineForOnDeviceModel() {
        let snapshot = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: [salary, freelance, lunch], allBudgets: [], todayKey: today)
        let hidden = BudgetAssistantPrompt.compactMonthLine(snapshot: snapshot, hideSalary: true, currency: .usd, language: .english)
        XCTAssertFalse(hidden.contains("5,800"))
        XCTAssertFalse(hidden.contains("5,000"))
        XCTAssertTrue(hidden.contains("income excluding salary $800.00"))
        let shown = BudgetAssistantPrompt.compactMonthLine(snapshot: snapshot, hideSalary: false, currency: .usd, language: .english)
        XCTAssertTrue(shown.contains("income $5,800.00"))
    }

    // MARK: Tool results

    func testToolEchoIsJudgedByTheStoredTransactionAndTheResult() {
        // Editing a stored salary row, even into another category, must not echo its amount.
        var movedAway = salary
        movedAway.category = .freelance
        XCTAssertTrue(SalaryPrivacy.masksToolEcho(stored: salary, resulting: movedAway, hidden: true))
        // Moving a visible row into salary must not echo the new amount.
        var movedIn = freelance
        movedIn.category = .salary
        XCTAssertTrue(SalaryPrivacy.masksToolEcho(stored: freelance, resulting: movedIn, hidden: true))
        // Plain salary edit.
        XCTAssertTrue(SalaryPrivacy.masksToolEcho(stored: salary, resulting: salary, hidden: true))
        // Non-salary rows and spending are echoed normally; nothing is masked when not hiding.
        XCTAssertFalse(SalaryPrivacy.masksToolEcho(stored: freelance, resulting: freelance, hidden: true))
        XCTAssertFalse(SalaryPrivacy.masksToolEcho(stored: lunch, resulting: lunch, hidden: true))
        XCTAssertFalse(SalaryPrivacy.masksToolEcho(stored: salary, resulting: salary, hidden: false))
        // A brand-new transaction has no stored row; only its own category counts.
        XCTAssertTrue(SalaryPrivacy.masksToolEcho(stored: nil, resulting: salary, hidden: true))
        XCTAssertFalse(SalaryPrivacy.masksToolEcho(stored: nil, resulting: freelance, hidden: true))
    }

    func testSalaryCategoryExpenseIsNotSalary() {
        // Salary is income; an expense that somehow carries the salary category is spending.
        let odd = tx("odd", 10_00, .expense, .salary, day: "2026-11-04")
        XCTAssertFalse(odd.isSalaryMasked(hidden: true))
    }
}
