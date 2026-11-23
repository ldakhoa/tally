import Foundation
import TallyCore

public struct WeeklyCashFlowBin: Identifiable, Hashable, Sendable {
    public var id: Int
    public var label: String
    public var incomeMinor: Int64
    public var spendingMinor: Int64

    public init(id: Int, label: String, incomeMinor: Int64, spendingMinor: Int64) {
        self.id = id
        self.label = label
        self.incomeMinor = incomeMinor
        self.spendingMinor = spendingMinor
    }
}

public struct CategorySpend: Identifiable, Hashable, Sendable {
    public var id: CategoryID { category }
    public var category: CategoryID
    public var spentMinor: Int64
    public var share: Double

    public init(category: CategoryID, spentMinor: Int64, share: Double) {
        self.category = category
        self.spentMinor = spentMinor
        self.share = share
    }
}

public struct MemberSpend: Identifiable, Hashable, Sendable {
    public var id: String { memberID }
    public var memberID: String
    public var memberName: String
    public var spendingMinor: Int64
    public var incomeMinor: Int64
    public var count: Int
}

public struct DailyTransactionGroup: Identifiable, Hashable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var transactions: [TransactionRecord]
    public var totalSpendingMinor: Int64
    public var totalIncomeMinor: Int64
}

public struct MonthlySnapshot: Hashable, Sendable {
    public var period: DatePeriod
    public var monthKey: String
    public var transactions: [TransactionRecord]
    public var budgets: [BudgetLimitRecord]
    public var incomeMinor: Int64
    public var spendingMinor: Int64
    public var netSavingsMinor: Int64
    public var budgetTotalMinor: Int64
    public var budgetSpentMinor: Int64
    public var budgetLeftMinor: Int64
    public var todaySpendingMinor: Int64
    public var pendingReviewCount: Int
    public var expensesByCategory: [CategoryID: Int64]
    public var categoryBreakdown: [CategorySpend]
    public var weeklyCashFlow: [WeeklyCashFlowBin]
    public var memberBreakdown: [MemberSpend]

    public var savingsRatePercent: Int? {
        guard incomeMinor > 0 else { return nil }
        return Int((Double(netSavingsMinor) * 100.0 / Double(incomeMinor)).rounded())
    }

    public static func compute(
        monthKey: String,
        allTransactions: [TransactionRecord],
        allBudgets: [BudgetLimitRecord],
        memberFilter: String? = nil,
        todayKey: String = DateKey.dayKey(from: Date())
    ) -> MonthlySnapshot {
        compute(
            period: .month(monthKey),
            allTransactions: allTransactions,
            allBudgets: allBudgets,
            memberFilter: memberFilter,
            todayKey: todayKey
        )
    }

    public static func compute(
        period: DatePeriod,
        allTransactions: [TransactionRecord],
        allBudgets: [BudgetLimitRecord],
        memberFilter: String? = nil,
        todayKey: String = DateKey.dayKey(from: Date())
    ) -> MonthlySnapshot {
        let monthKey = period.primaryMonthKey
        let activeTransactions = allTransactions.filter { !$0.isDeleted }
        let pendingReviewCount = activeTransactions.filter(\.needsReview).count

        let filtered = activeTransactions
            .filter { period.contains(dayKey: $0.dayKey) }
            .filter { memberFilter == nil || $0.memberID == memberFilter }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey > rhs.dayKey }
                return lhs.createdAt > rhs.createdAt
            }

        var income: Int64 = 0
        var spending: Int64 = 0
        var todaySpending: Int64 = 0
        var expenses: [CategoryID: Int64] = [:]
        var members: [String: MemberSpend] = [:]

        var bins = makeCashFlowBins(for: period)

        for tx in filtered {
            let binIndex = cashFlowBinIndex(for: tx.dayKey, period: period, binCount: bins.count)
            var m = members[tx.memberID] ?? MemberSpend(
                memberID: tx.memberID,
                memberName: tx.memberName,
                spendingMinor: 0,
                incomeMinor: 0,
                count: 0
            )
            if m.memberName.isEmpty && !tx.memberName.isEmpty { m.memberName = tx.memberName }
            m.count += 1

            if tx.type == .income {
                income += tx.amountMinor
                bins[binIndex].incomeMinor += tx.amountMinor
                m.incomeMinor += tx.amountMinor
            } else {
                spending += tx.amountMinor
                bins[binIndex].spendingMinor += tx.amountMinor
                expenses[tx.category, default: 0] += tx.amountMinor
                m.spendingMinor += tx.amountMinor
                if tx.dayKey == todayKey {
                    todaySpending += tx.amountMinor
                }
            }
            members[tx.memberID] = m
        }

        let monthBudgets = allBudgets
            .filter { !$0.isDeleted && $0.monthKey == monthKey }
            .sorted { $0.category.rawValue < $1.category.rawValue }
        let budgetTotal = monthBudgets.reduce(Int64(0)) { $0 + $1.limitMinor }
        let budgetSpent = monthBudgets.reduce(Int64(0)) { $0 + (expenses[$1.category] ?? 0) }

        let breakdown = expenses
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { CategorySpend(category: $0.key, spentMinor: $0.value, share: spending > 0 ? Double($0.value) / Double(spending) : 0) }

        return MonthlySnapshot(
            period: period,
            monthKey: monthKey,
            transactions: filtered,
            budgets: monthBudgets,
            incomeMinor: income,
            spendingMinor: spending,
            netSavingsMinor: income - spending,
            budgetTotalMinor: budgetTotal,
            budgetSpentMinor: budgetSpent,
            budgetLeftMinor: budgetTotal - budgetSpent,
            todaySpendingMinor: todaySpending,
            pendingReviewCount: pendingReviewCount,
            expensesByCategory: expenses,
            categoryBreakdown: breakdown,
            weeklyCashFlow: bins,
            memberBreakdown: members.values.sorted { $0.spendingMinor > $1.spendingMinor }
        )
    }

    private static func makeCashFlowBins(for period: DatePeriod) -> [WeeklyCashFlowBin] {
        switch period {
        case .month(let monthKey):
            let totalDays = DateKey.daysInMonth(monthKey)
            let weekCount = max(1, (totalDays + 6) / 7)
            return (0..<weekCount).map { index in
                let start = index * 7 + 1
                let end = min(start + 6, totalDays)
                return WeeklyCashFlowBin(id: index, label: "\(start)–\(end)", incomeMinor: 0, spendingMinor: 0)
            }
        case .day(let dayKey):
            let day = DateKey.dayOfMonth(fromDayKey: dayKey)
            return [WeeklyCashFlowBin(id: 0, label: "\(day)", incomeMinor: 0, spendingMinor: 0)]
        case .range(let start, let end):
            let lo = min(start, end)
            let hi = max(start, end)
            let span = max(1, DateKey.daysBetween(lo, hi) + 1)
            if span <= 7 {
                return (0..<span).map { offset in
                    let key = DateKey.shiftDay(lo, by: offset)
                    let day = DateKey.dayOfMonth(fromDayKey: key)
                    return WeeklyCashFlowBin(id: offset, label: "\(day)", incomeMinor: 0, spendingMinor: 0)
                }
            }
            let bucketCount = min(5, max(2, (span + 6) / 7))
            let bucketSize = (span + bucketCount - 1) / bucketCount
            return (0..<bucketCount).map { idx in
                let bStart = DateKey.shiftDay(lo, by: idx * bucketSize)
                let bEndOffset = min(span - 1, (idx + 1) * bucketSize - 1)
                let bEnd = DateKey.shiftDay(lo, by: bEndOffset)
                let sDay = DateKey.dayOfMonth(fromDayKey: bStart)
                let eDay = DateKey.dayOfMonth(fromDayKey: bEnd)
                let label = sDay == eDay ? "\(sDay)" : "\(sDay)–\(eDay)"
                return WeeklyCashFlowBin(id: idx, label: label, incomeMinor: 0, spendingMinor: 0)
            }
        }
    }

    private static func cashFlowBinIndex(for dayKey: String, period: DatePeriod, binCount: Int) -> Int {
        guard binCount > 1 else { return 0 }
        switch period {
        case .month:
            return min(binCount - 1, max(0, (DateKey.dayOfMonth(fromDayKey: dayKey) - 1) / 7))
        case .day:
            return 0
        case .range(let start, let end):
            let lo = min(start, end)
            let hi = max(start, end)
            let span = max(1, DateKey.daysBetween(lo, hi) + 1)
            let offset = max(0, DateKey.daysBetween(lo, dayKey))
            if span <= 7 {
                return min(binCount - 1, offset)
            }
            let bucketSize = max(1, (span + binCount - 1) / binCount)
            return min(binCount - 1, offset / bucketSize)
        }
    }

    public static func groupByDay(_ transactions: [TransactionRecord]) -> [DailyTransactionGroup] {
        var buckets: [String: [TransactionRecord]] = [:]
        for tx in transactions {
            buckets[tx.dayKey, default: []].append(tx)
        }
        return buckets.keys.sorted(by: >).map { day in
            let items = (buckets[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            let spent = items.filter { $0.type == .expense }.reduce(Int64(0)) { $0 + $1.amountMinor }
            let inc = items.filter { $0.type == .income }.reduce(Int64(0)) { $0 + $1.amountMinor }
            return DailyTransactionGroup(dayKey: day, transactions: items, totalSpendingMinor: spent, totalIncomeMinor: inc)
        }
    }
}
