import Foundation
import TallyCore

/// Per-day spending and income summary used to render daily money amounts directly in calendar cells.
public struct DailyCalendarTotal: Identifiable, Hashable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var spendingMinor: Int64
    public var incomeMinor: Int64
    public var count: Int

    public var netMinor: Int64 { incomeMinor - spendingMinor }
    public var hasActivity: Bool { count > 0 }

    public init(dayKey: String, spendingMinor: Int64 = 0, incomeMinor: Int64 = 0, count: Int = 0) {
        self.dayKey = dayKey
        self.spendingMinor = spendingMinor
        self.incomeMinor = incomeMinor
        self.count = count
    }
}

public struct MonthlyTrendPoint: Identifiable, Hashable, Sendable {
    public var id: String { monthKey }
    public var monthKey: String
    public var incomeMinor: Int64
    public var spendingMinor: Int64
    public var transactionCount: Int

    public var netMinor: Int64 { incomeMinor - spendingMinor }

    public init(monthKey: String, incomeMinor: Int64, spendingMinor: Int64, transactionCount: Int) {
        self.monthKey = monthKey
        self.incomeMinor = incomeMinor
        self.spendingMinor = spendingMinor
        self.transactionCount = transactionCount
    }
}

public struct MerchantSpend: Identifiable, Hashable, Sendable {
    public var id: String { normalizedKey }
    public var normalizedKey: String
    public var displayName: String
    public var category: CategoryID
    public var totalMinor: Int64
    public var count: Int
    public var share: Double

    public init(
        normalizedKey: String,
        displayName: String,
        category: CategoryID,
        totalMinor: Int64,
        count: Int,
        share: Double
    ) {
        self.normalizedKey = normalizedKey
        self.displayName = displayName
        self.category = category
        self.totalMinor = totalMinor
        self.count = count
        self.share = share
    }
}

public struct WeekdaySpend: Identifiable, Hashable, Sendable {
    public var id: Int { weekday }
    /// `1 = Sunday ... 7 = Saturday`.
    public var weekday: Int
    public var totalMinor: Int64
    public var averageMinor: Int64
    public var activeDays: Int
    public var transactionCount: Int

    public init(weekday: Int, totalMinor: Int64, averageMinor: Int64, activeDays: Int, transactionCount: Int) {
        self.weekday = weekday
        self.totalMinor = totalMinor
        self.averageMinor = averageMinor
        self.activeDays = activeDays
        self.transactionCount = transactionCount
    }
}

public struct DailySpendPoint: Identifiable, Hashable, Sendable {
    public var id: String { dayKey }
    public var dayKey: String
    public var dayIndex: Int
    public var spendingMinor: Int64
    public var incomeMinor: Int64
    public var cumulativeSpendingMinor: Int64

    public init(
        dayKey: String,
        dayIndex: Int,
        spendingMinor: Int64,
        incomeMinor: Int64,
        cumulativeSpendingMinor: Int64
    ) {
        self.dayKey = dayKey
        self.dayIndex = dayIndex
        self.spendingMinor = spendingMinor
        self.incomeMinor = incomeMinor
        self.cumulativeSpendingMinor = cumulativeSpendingMinor
    }
}

public struct StatisticsSnapshot: Hashable, Sendable {
    public var period: DatePeriod
    public var current: MonthlySnapshot
    public var previousPeriod: DatePeriod
    public var previousSpendingMinor: Int64
    public var previousIncomeMinor: Int64
    public var spendingChangePercent: Double?
    public var incomeChangePercent: Double?
    public var elapsedDaysCount: Int
    public var spendingDaysCount: Int
    public var averageDailySpendingMinor: Int64
    public var averageExpenseMinor: Int64
    public var largestExpenses: [TransactionRecord]
    public var highestSpendDay: DailyCalendarTotal?
    public var monthlyTrend: [MonthlyTrendPoint]
    public var dailySeries: [DailySpendPoint]
    public var weekdayBreakdown: [WeekdaySpend]
    public var topMerchants: [MerchantSpend]
    public var incomeBreakdown: [CategorySpend]

    public static func compute(
        period: DatePeriod,
        allTransactions: [TransactionRecord],
        allBudgets: [BudgetLimitRecord],
        memberFilter: String? = nil,
        trendMonths: Int = 6,
        todayKey: String = DateKey.dayKey(from: Date())
    ) -> StatisticsSnapshot {
        let active = allTransactions
            .filter { !$0.isDeleted }
            .filter { memberFilter == nil || $0.memberID == memberFilter }

        let current = MonthlySnapshot.compute(
            period: period,
            allTransactions: allTransactions,
            allBudgets: allBudgets,
            memberFilter: memberFilter,
            todayKey: todayKey
        )

        let previousPeriod = period.shifted(by: -1)
        let previous = MonthlySnapshot.compute(
            period: previousPeriod,
            allTransactions: allTransactions,
            allBudgets: allBudgets,
            memberFilter: memberFilter,
            todayKey: todayKey
        )

        let spendingChangePercent: Double? = previous.spendingMinor > 0
            ? (Double(current.spendingMinor - previous.spendingMinor) * 100.0) / Double(previous.spendingMinor)
            : nil
        let incomeChangePercent: Double? = previous.incomeMinor > 0
            ? (Double(current.incomeMinor - previous.incomeMinor) * 100.0) / Double(previous.incomeMinor)
            : nil

        // Determine elapsed days in the selected period so current-month daily average reflects pace so far.
        let startKey = period.startDayKey
        let endKey = period.endDayKey
        let effectiveEndKey: String
        if todayKey >= startKey && todayKey <= endKey {
            effectiveEndKey = todayKey
        } else {
            effectiveEndKey = endKey
        }
        let elapsedDays = max(1, DateKey.daysBetween(startKey, effectiveEndKey) + 1)

        // Daily series & per-day aggregation within the active period.
        var periodDayMap: [String: DailyCalendarTotal] = [:]
        var expenseCount = 0
        var incomeByCat: [CategoryID: Int64] = [:]

        // Merchant buckets keyed by trimmed lowercase name.
        struct MerchantBucket {
            var displayName: String
            var categoryCounts: [CategoryID: Int]
            var totalMinor: Int64
            var count: Int
        }
        var merchantBuckets: [String: MerchantBucket] = [:]

        // Weekday buckets (1 = Sun ... 7 = Sat).
        var weekdayTotals: [Int: Int64] = [:]
        var weekdayCounts: [Int: Int] = [:]
        var weekdayDays: [Int: Set<String>] = [:]

        for tx in current.transactions {
            var day = periodDayMap[tx.dayKey] ?? DailyCalendarTotal(dayKey: tx.dayKey)
            day.count += 1
            if tx.type == .expense {
                day.spendingMinor += tx.amountMinor
                expenseCount += 1

                let wd = DateKey.weekday(fromDayKey: tx.dayKey)
                weekdayTotals[wd, default: 0] += tx.amountMinor
                weekdayCounts[wd, default: 0] += 1
                weekdayDays[wd, default: []].insert(tx.dayKey)

                let trimmed = tx.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.lowercased()
                if !normalized.isEmpty {
                    var bucket = merchantBuckets[normalized] ?? MerchantBucket(
                        displayName: trimmed,
                        categoryCounts: [:],
                        totalMinor: 0,
                        count: 0
                    )
                    bucket.totalMinor += tx.amountMinor
                    bucket.count += 1
                    bucket.categoryCounts[tx.category, default: 0] += 1
                    merchantBuckets[normalized] = bucket
                }
            } else {
                day.incomeMinor += tx.amountMinor
                incomeByCat[tx.category, default: 0] += tx.amountMinor
            }
            periodDayMap[tx.dayKey] = day
        }

        let spendingDaysCount = periodDayMap.values.filter { $0.spendingMinor > 0 }.count
        let averageDailySpendingMinor = current.spendingMinor / Int64(elapsedDays)
        let averageExpenseMinor = expenseCount > 0 ? current.spendingMinor / Int64(expenseCount) : 0

        let largestExpenses = current.transactions
            .filter { $0.type == .expense }
            .sorted { lhs, rhs in
                if lhs.amountMinor != rhs.amountMinor { return lhs.amountMinor > rhs.amountMinor }
                return lhs.dayKey > rhs.dayKey
            }
            .prefix(5)
            .map { $0 }

        let highestSpendDay = periodDayMap.values
            .filter { $0.spendingMinor > 0 }
            .max { lhs, rhs in
                if lhs.spendingMinor != rhs.spendingMinor { return lhs.spendingMinor < rhs.spendingMinor }
                return lhs.dayKey < rhs.dayKey
            }

        // Build continuous daily series across the selected period (capped sensibly at 62 days).
        let totalSpan = max(1, min(62, DateKey.daysBetween(startKey, effectiveEndKey) + 1))
        var cumulative: Int64 = 0
        let dailySeries: [DailySpendPoint] = (0..<totalSpan).map { offset in
            let key = DateKey.shiftDay(startKey, by: offset)
            let day = periodDayMap[key]
            let spent = day?.spendingMinor ?? 0
            let inc = day?.incomeMinor ?? 0
            cumulative += spent
            return DailySpendPoint(
                dayKey: key,
                dayIndex: offset + 1,
                spendingMinor: spent,
                incomeMinor: inc,
                cumulativeSpendingMinor: cumulative
            )
        }

        // Order weekdays Mon..Sun (2,3,4,5,6,7,1) for intuitive spending-pattern reading.
        let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        let weekdayBreakdown: [WeekdaySpend] = orderedWeekdays.map { wd in
            let total = weekdayTotals[wd] ?? 0
            let days = weekdayDays[wd]?.count ?? 0
            let avg = days > 0 ? total / Int64(days) : 0
            return WeekdaySpend(
                weekday: wd,
                totalMinor: total,
                averageMinor: avg,
                activeDays: days,
                transactionCount: weekdayCounts[wd] ?? 0
            )
        }

        let topMerchants: [MerchantSpend] = merchantBuckets
            .map { key, bucket in
                let primaryCategory = bucket.categoryCounts.max(by: { $0.value < $1.value })?.key ?? .other
                let share = current.spendingMinor > 0
                    ? Double(bucket.totalMinor) / Double(current.spendingMinor)
                    : 0
                return MerchantSpend(
                    normalizedKey: key,
                    displayName: bucket.displayName,
                    category: primaryCategory,
                    totalMinor: bucket.totalMinor,
                    count: bucket.count,
                    share: share
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
                return lhs.count > rhs.count
            }
            .prefix(8)
            .map { $0 }

        let incomeBreakdown = incomeByCat
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map {
                CategorySpend(
                    category: $0.key,
                    spentMinor: $0.value,
                    share: current.incomeMinor > 0 ? Double($0.value) / Double(current.incomeMinor) : 0
                )
            }

        // Build multi-month trend ending on `period.primaryMonthKey`.
        let anchorMonth = period.primaryMonthKey
        let monthCount = max(1, trendMonths)
        let monthKeys = (0..<monthCount).map { offset in
            DateKey.shiftMonth(anchorMonth, by: -(monthCount - 1 - offset))
        }
        let monthKeySet = Set(monthKeys)
        var monthIncome: [String: Int64] = [:]
        var monthSpending: [String: Int64] = [:]
        var monthTxCount: [String: Int] = [:]

        for tx in active {
            let mk = tx.monthKey
            guard monthKeySet.contains(mk) else { continue }
            monthTxCount[mk, default: 0] += 1
            if tx.type == .income {
                monthIncome[mk, default: 0] += tx.amountMinor
            } else {
                monthSpending[mk, default: 0] += tx.amountMinor
            }
        }

        let monthlyTrend = monthKeys.map { mk in
            MonthlyTrendPoint(
                monthKey: mk,
                incomeMinor: monthIncome[mk] ?? 0,
                spendingMinor: monthSpending[mk] ?? 0,
                transactionCount: monthTxCount[mk] ?? 0
            )
        }

        return StatisticsSnapshot(
            period: period,
            current: current,
            previousPeriod: previousPeriod,
            previousSpendingMinor: previous.spendingMinor,
            previousIncomeMinor: previous.incomeMinor,
            spendingChangePercent: spendingChangePercent,
            incomeChangePercent: incomeChangePercent,
            elapsedDaysCount: elapsedDays,
            spendingDaysCount: spendingDaysCount,
            averageDailySpendingMinor: averageDailySpendingMinor,
            averageExpenseMinor: averageExpenseMinor,
            largestExpenses: largestExpenses,
            highestSpendDay: highestSpendDay,
            monthlyTrend: monthlyTrend,
            dailySeries: dailySeries,
            weekdayBreakdown: weekdayBreakdown,
            topMerchants: topMerchants,
            incomeBreakdown: incomeBreakdown
        )
    }
}

public extension MonthlySnapshot {
    /// Aggregates active transactions by `YYYY-MM-DD` for calendar cell totals.
    static func dailyTotals(
        allTransactions: [TransactionRecord],
        memberFilter: String? = nil
    ) -> [String: DailyCalendarTotal] {
        var result: [String: DailyCalendarTotal] = [:]
        for tx in allTransactions where !tx.isDeleted {
            if let memberFilter, tx.memberID != memberFilter { continue }
            var day = result[tx.dayKey] ?? DailyCalendarTotal(dayKey: tx.dayKey)
            day.count += 1
            if tx.type == .income {
                day.incomeMinor += tx.amountMinor
            } else {
                day.spendingMinor += tx.amountMinor
            }
            result[tx.dayKey] = day
        }
        return result
    }

    /// Aggregates per-day totals into per-month (`YYYY-MM`) summaries for calendar month headers.
    static func monthlyTotals(from dailyTotals: [String: DailyCalendarTotal]) -> [String: DailyCalendarTotal] {
        var result: [String: DailyCalendarTotal] = [:]
        for (dayKey, summary) in dailyTotals {
            let monthKey = DateKey.monthKey(fromDayKey: dayKey)
            var month = result[monthKey] ?? DailyCalendarTotal(dayKey: monthKey)
            month.spendingMinor += summary.spendingMinor
            month.incomeMinor += summary.incomeMinor
            month.count += summary.count
            result[monthKey] = month
        }
        return result
    }

    /// Sums spending & income across all days within `period`.
    static func periodTotal(
        for period: DatePeriod,
        dailyTotals: [String: DailyCalendarTotal]
    ) -> DailyCalendarTotal {
        var total = DailyCalendarTotal(dayKey: period.startDayKey)
        for (dayKey, day) in dailyTotals where period.contains(dayKey: dayKey) {
            total.spendingMinor += day.spendingMinor
            total.incomeMinor += day.incomeMinor
            total.count += day.count
        }
        return total
    }
}
