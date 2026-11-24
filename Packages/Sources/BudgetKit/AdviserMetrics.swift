import Foundation
import TallyCore

// MARK: - Figures & rules

/// A figure the adviser tools report, or the reason it is not reported. Every adviser function
/// returns this instead of a bare number so short history and hidden salary are explicit (never
/// a NaN or a misleading zero).
public enum AdviserFigure<Value: Hashable & Sendable>: Hashable, Sendable {
    case value(Value)
    /// Not enough data; the text says what is missing (written for the model).
    case insufficient(String)
    /// The figure would include salary while the user hides it on this device.
    case salaryLocked

    public var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    public var isSalaryLocked: Bool {
        if case .salaryLocked = self { return true }
        return false
    }

    public func map<T: Hashable & Sendable>(_ transform: (Value) -> T) -> AdviserFigure<T> {
        switch self {
        case .value(let value): return .value(transform(value))
        case .insufficient(let reason): return .insufficient(reason)
        case .salaryLocked: return .salaryLocked
        }
    }
}

/// The fixed rules the adviser figures follow. Stated here once so tool results, the report and
/// the tests agree.
public enum AdviserRules {
    /// Complete calendar months looked back over (the current month is reported separately).
    public static let historyMonths = 12
    /// Averages need at least this many complete months that have transactions.
    public static let minimumMonthsForAverage = 2
    /// Category movers compare the latest complete month with at least this many earlier months.
    public static let minimumBaselineMonthsForMovers = 2
    /// Suggested budget limits need at least this many complete months with transactions.
    public static let minimumMonthsForSuggestedLimit = 3
    public static let moversLimit = 5
    /// Spending in these categories counts as fixed, besides installment/loan payments.
    public static let fixedCategories: [CategoryID] = [.housing, .bills]
    /// Budget status "near" from this share of the limit.
    public static let nearLimitPercent = 80.0

    public static let averagesRule = "Averages use complete calendar months that have at least one transaction (months with none are listed but excluded); the current month is month-to-date and never averaged."
    public static let savingsRateRule = "Savings rate = net / income x 100. The average savings rate is total net / total income over the averaged months."
    public static let fixedRule = "Fixed spending = installment and loan payments plus housing and bills; everything else is variable."
    public static let moversRule = "Movers compare each category's spending in the latest complete month with its average over the earlier complete months with transactions, ranked by the size of the change."
    public static let debtServiceRule = "Monthly debt service = the next scheduled payment of every active plan or loan. Debt-service-to-income = monthly debt service / average monthly income."
    public static let payoffRule = "Highest rate first ranks by effective annual rate (ties: larger balance first). Smallest balance first ranks by outstanding principal (ties: higher rate first)."
    public static let suggestedLimitRule = "Statistic, not advice: median monthly spending over the complete months with transactions, rounded up to 2 significant figures."
    public static let projectionRule = "Linear projection: month-to-date spending / days elapsed x days in month."
    public static let goalPaceRule = "Pace = average monthly net (income - spending) of the household, counting saving from next month. It is the household's whole surplus, not money set aside for this goal."
    public static let runwayRule = "Runway = cash / average monthly spending, rounded down to 0.1 month."
}

/// Small integer-money helpers. Storage is always cents; `step` is the smallest payable unit
/// (100 for whole-dong VND, 1 otherwise).
public enum AdviserMath {
    public static func step(for currency: CurrencyCode) -> Int64 {
        InstallmentPlanRecord.roundingStep(for: currency)
    }

    /// `value` rounded half away from zero to a multiple of `step`.
    public static func round(_ value: Double, step: Int64) -> Int64 {
        let s = Double(max(1, step))
        return Int64((value / s).rounded()) * max(1, step)
    }

    /// `value` rounded up to a multiple of `step`.
    public static func roundUp(_ value: Double, step: Int64) -> Int64 {
        let s = Double(max(1, step))
        return Int64((value / s).rounded(.up)) * max(1, step)
    }

    public static func average(_ sum: Int64, count: Int, step: Int64) -> Int64 {
        guard count > 0 else { return 0 }
        return round(Double(sum) / Double(count), step: step)
    }

    /// `part / whole x 100` to one decimal, `nil` when `whole <= 0`.
    public static func percent(_ part: Int64, of whole: Int64) -> Double? {
        guard whole > 0 else { return nil }
        return oneDecimal(Double(part) / Double(whole) * 100)
    }

    public static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    public static func median(_ values: [Int64]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (Double(sorted[mid - 1]) + Double(sorted[mid])) / 2
        }
        return Double(sorted[mid])
    }

    /// Calendar months from `from` to `to` (`2026-11` to `2027-02` is 3; negative when earlier).
    public static func monthsBetween(_ from: String, _ to: String) -> Int? {
        guard let a = DateKey.yearAndMonth(fromMonthKey: from), let b = DateKey.yearAndMonth(fromMonthKey: to) else { return nil }
        return (b.year * 12 + b.month) - (a.year * 12 + a.month)
    }

    /// Rounds a positive storage amount up to 2 significant figures of its major value, with a
    /// step of at least one major unit (S$437.20 -> S$440, 1.234.000 ₫ -> 1.300.000 ₫).
    public static func roundUpToTwoSignificant(_ minor: Int64) -> Int64 {
        guard minor > 0 else { return 0 }
        let major = Double(minor) / 100
        let exponent = Int(floor(log10(major))) - 1
        let stepMajor = max(1, pow(10, Double(exponent)))
        let roundedMajor = (major / stepMajor).rounded(.up) * stepMajor
        return Int64((roundedMajor * 100).rounded())
    }
}

// MARK: - Input

/// The household data the adviser figures are computed from. Deleted records and transactions
/// dated after today are dropped.
public struct AdviserDataSet: Sendable {
    struct MonthTotals: Sendable {
        var count = 0
        var spendingMinor: Int64 = 0
        var incomeMinor: Int64 = 0
        var nonSalaryIncomeMinor: Int64 = 0
        var includesSalary = false
        var byCategory: [CategoryID: Int64] = [:]
        var planPaymentsMinor: Int64 = 0
        var fixedCategoryMinor: Int64 = 0

        var fixedMinor: Int64 { planPaymentsMinor + fixedCategoryMinor }
    }

    public let transactions: [TransactionRecord]
    public let budgets: [BudgetLimitRecord]
    public let goals: [SavingsGoalRecord]
    public let plans: [InstallmentPlanRecord]
    public let currency: CurrencyCode
    public let todayKey: String
    /// `true` while the user hides salary: salary-inclusive figures come back `.salaryLocked`.
    public let salaryHidden: Bool
    let monthTotals: [String: MonthTotals]

    public init(
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord],
        plans: [InstallmentPlanRecord],
        currency: CurrencyCode,
        todayKey: String,
        salaryHidden: Bool
    ) {
        let live = transactions.filter { !$0.isDeleted && $0.dayKey <= todayKey && DateKey.date(fromDayKey: $0.dayKey) != nil }
        self.transactions = live
        self.budgets = budgets.filter { !$0.isDeleted }
        self.goals = goals.filter { !$0.isDeleted }
        self.plans = plans.filter { !$0.isDeleted }
        self.currency = currency
        self.todayKey = todayKey
        self.salaryHidden = salaryHidden

        var totals: [String: MonthTotals] = [:]
        for tx in live {
            var month = totals[tx.monthKey] ?? MonthTotals()
            month.count += 1
            if tx.type == .income {
                month.incomeMinor += tx.amountMinor
                if tx.includesSalary {
                    month.includesSalary = true
                } else {
                    month.nonSalaryIncomeMinor += tx.amountMinor
                }
            } else {
                month.spendingMinor += tx.amountMinor
                month.byCategory[tx.category, default: 0] += tx.amountMinor
                if tx.isPlanPayment {
                    month.planPaymentsMinor += tx.amountMinor
                } else if AdviserRules.fixedCategories.contains(tx.category) {
                    month.fixedCategoryMinor += tx.amountMinor
                }
            }
            totals[tx.monthKey] = month
        }
        self.monthTotals = totals
    }

    public var currentMonthKey: String { DateKey.monthKey(fromDayKey: todayKey) }
    public var step: Int64 { AdviserMath.step(for: currency) }
    public var firstDataMonthKey: String? { monthTotals.keys.min() }

    func totals(_ monthKey: String) -> MonthTotals { monthTotals[monthKey] ?? MonthTotals() }

    /// `.salaryLocked` when salary is hidden and the figure includes salary.
    func gate<T: Hashable & Sendable>(_ value: T, includesSalary: Bool) -> AdviserFigure<T> {
        salaryHidden && includesSalary ? .salaryLocked : .value(value)
    }

    /// Complete months (oldest first) in the last `count` months before the current month,
    /// starting no earlier than the first month with data.
    func completeMonthKeys(last count: Int = AdviserRules.historyMonths) -> [String] {
        guard let first = firstDataMonthKey else { return [] }
        let current = currentMonthKey
        let windowStart = DateKey.shiftMonth(current, by: -max(1, min(count, AdviserRules.historyMonths)))
        var key = max(windowStart, first)
        var keys: [String] = []
        while key < current, keys.count < AdviserRules.historyMonths {
            keys.append(key)
            let next = DateKey.shiftMonth(key, by: 1)
            guard next > key else { break }
            key = next
        }
        return keys
    }

    /// Complete months with at least one transaction (what averages use).
    func averagedMonthKeys(last count: Int = AdviserRules.historyMonths) -> [String] {
        completeMonthKeys(last: count).filter { totals($0).count > 0 }
    }
}

// MARK: - Monthly series

public struct AdviserMonth: Hashable, Sendable {
    public let monthKey: String
    public let transactionCount: Int
    public let spendingMinor: Int64
    public let income: AdviserFigure<Int64>
    /// Income that is not salary (never hidden).
    public let nonSalaryIncomeMinor: Int64
    public let net: AdviserFigure<Int64>
    public let savingsRatePercent: AdviserFigure<Double>
    public let spendingByCategory: [CategoryID: Int64]
    public let fixedMinor: Int64
    public let planPaymentsMinor: Int64
    public var variableMinor: Int64 { spendingMinor - fixedMinor }
    /// Spending change from the previous listed month (`nil` for the first or when either month has no data).
    public let spendingChangeMinor: Int64?
    public var hasData: Bool { transactionCount > 0 }

    init(monthKey: String, data: AdviserDataSet, previous: AdviserDataSet.MonthTotals? = nil) {
        let t = data.totals(monthKey)
        self.monthKey = monthKey
        transactionCount = t.count
        spendingMinor = t.spendingMinor
        nonSalaryIncomeMinor = t.nonSalaryIncomeMinor
        income = data.gate(t.incomeMinor, includesSalary: t.includesSalary)
        net = data.gate(t.incomeMinor - t.spendingMinor, includesSalary: t.includesSalary)
        if data.salaryHidden && t.includesSalary {
            savingsRatePercent = .salaryLocked
        } else if let rate = AdviserMath.percent(t.incomeMinor - t.spendingMinor, of: t.incomeMinor) {
            savingsRatePercent = .value(rate)
        } else {
            savingsRatePercent = .insufficient("no income recorded in \(monthKey)")
        }
        spendingByCategory = t.byCategory
        fixedMinor = t.fixedMinor
        planPaymentsMinor = t.planPaymentsMinor
        if let previous, previous.count > 0, t.count > 0 {
            spendingChangeMinor = t.spendingMinor - previous.spendingMinor
        } else {
            spendingChangeMinor = nil
        }
    }
}

public struct CategoryMover: Hashable, Sendable {
    public let category: CategoryID
    public let latestMinor: Int64
    public let baselineAverageMinor: Int64
    public var changeMinor: Int64 { latestMinor - baselineAverageMinor }
    /// `nil` when the baseline average is 0 (new category).
    public var changePercent: Double? { AdviserMath.percent(changeMinor, of: baselineAverageMinor) }
}

public struct MonthChange: Hashable, Sendable {
    public let fromMonthKey: String
    public let toMonthKey: String
    public let spendingChangeMinor: Int64
    public let spendingChangePercent: Double?
    public let incomeChange: AdviserFigure<Int64>
    public let netChange: AdviserFigure<Int64>
}

public struct FixedVariableSplit: Hashable, Sendable {
    public let averageFixedMinor: Int64
    public let averagePlanPaymentsMinor: Int64
    public let averageFixedCategoryMinor: Int64
    public let averageVariableMinor: Int64
    public let fixedSharePercent: Double?
}

public struct CashFlowHistory: Hashable, Sendable {
    /// Complete months, oldest first (months without transactions included).
    public let months: [AdviserMonth]
    public let monthsWithData: Int
    public let currentMonth: AdviserMonth
    public let daysElapsedInCurrentMonth: Int
    public let daysInCurrentMonth: Int
    public let averageSpendingMinor: AdviserFigure<Int64>
    public let averageIncomeMinor: AdviserFigure<Int64>
    public let averageNonSalaryIncomeMinor: AdviserFigure<Int64>
    public let averageNetMinor: AdviserFigure<Int64>
    public let averageSavingsRatePercent: AdviserFigure<Double>
    public let averageSpendingByCategory: AdviserFigure<[CategoryID: Int64]>
    public let latestChange: AdviserFigure<MonthChange>
    public let movers: AdviserFigure<[CategoryMover]>
    public let fixedVariable: AdviserFigure<FixedVariableSplit>
    public let notes: [String]

    public init(data: AdviserDataSet, months requested: Int = AdviserRules.historyMonths) {
        let keys = data.completeMonthKeys(last: requested)
        var rows: [AdviserMonth] = []
        for (offset, key) in keys.enumerated() {
            let previous = offset > 0 ? data.totals(keys[offset - 1]) : nil
            rows.append(AdviserMonth(monthKey: key, data: data, previous: previous))
        }
        months = rows
        let averaged = keys.filter { data.totals($0).count > 0 }
        monthsWithData = averaged.count
        currentMonth = AdviserMonth(monthKey: data.currentMonthKey, data: data)
        daysElapsedInCurrentMonth = DateKey.dayOfMonth(fromDayKey: data.todayKey)
        daysInCurrentMonth = DateKey.daysInMonth(data.currentMonthKey)

        let step = data.step
        let totals = averaged.map { data.totals($0) }
        let anySalary = totals.contains { $0.includesSalary }
        let shortHistory = "only \(averaged.count) complete month(s) with transactions; averages need at least \(AdviserRules.minimumMonthsForAverage)"
        let enough = averaged.count >= AdviserRules.minimumMonthsForAverage

        if enough {
            let n = totals.count
            let spending = totals.reduce(Int64(0)) { $0 + $1.spendingMinor }
            let income = totals.reduce(Int64(0)) { $0 + $1.incomeMinor }
            let nonSalary = totals.reduce(Int64(0)) { $0 + $1.nonSalaryIncomeMinor }
            averageSpendingMinor = .value(AdviserMath.average(spending, count: n, step: step))
            averageNonSalaryIncomeMinor = .value(AdviserMath.average(nonSalary, count: n, step: step))
            averageIncomeMinor = data.gate(AdviserMath.average(income, count: n, step: step), includesSalary: anySalary)
            averageNetMinor = data.gate(AdviserMath.average(income - spending, count: n, step: step), includesSalary: anySalary)
            if data.salaryHidden && anySalary {
                averageSavingsRatePercent = .salaryLocked
            } else if let rate = AdviserMath.percent(income - spending, of: income) {
                averageSavingsRatePercent = .value(rate)
            } else {
                averageSavingsRatePercent = .insufficient("no income recorded in the averaged months")
            }
            var byCategory: [CategoryID: Int64] = [:]
            for category in CategoryID.expenseCategories {
                let sum = totals.reduce(Int64(0)) { $0 + ($1.byCategory[category] ?? 0) }
                if sum > 0 { byCategory[category] = AdviserMath.average(sum, count: n, step: step) }
            }
            averageSpendingByCategory = .value(byCategory)
            let fixed = totals.reduce(Int64(0)) { $0 + $1.fixedMinor }
            let plan = totals.reduce(Int64(0)) { $0 + $1.planPaymentsMinor }
            let fixedCategory = totals.reduce(Int64(0)) { $0 + $1.fixedCategoryMinor }
            fixedVariable = .value(FixedVariableSplit(
                averageFixedMinor: AdviserMath.average(fixed, count: n, step: step),
                averagePlanPaymentsMinor: AdviserMath.average(plan, count: n, step: step),
                averageFixedCategoryMinor: AdviserMath.average(fixedCategory, count: n, step: step),
                averageVariableMinor: AdviserMath.average(spending - fixed, count: n, step: step),
                fixedSharePercent: AdviserMath.percent(fixed, of: spending)
            ))
        } else {
            averageSpendingMinor = .insufficient(shortHistory)
            averageNonSalaryIncomeMinor = .insufficient(shortHistory)
            averageIncomeMinor = data.salaryHidden && anySalary ? .salaryLocked : .insufficient(shortHistory)
            averageNetMinor = data.salaryHidden && anySalary ? .salaryLocked : .insufficient(shortHistory)
            averageSavingsRatePercent = data.salaryHidden && anySalary ? .salaryLocked : .insufficient(shortHistory)
            averageSpendingByCategory = .insufficient(shortHistory)
            fixedVariable = .insufficient(shortHistory)
        }

        // Latest complete month against the one before it.
        if keys.count >= 2, let last = keys.last {
            let prior = keys[keys.count - 2]
            let a = data.totals(prior)
            let b = data.totals(last)
            if a.count > 0, b.count > 0 {
                let locked = a.includesSalary || b.includesSalary
                latestChange = .value(MonthChange(
                    fromMonthKey: prior,
                    toMonthKey: last,
                    spendingChangeMinor: b.spendingMinor - a.spendingMinor,
                    spendingChangePercent: AdviserMath.percent(b.spendingMinor - a.spendingMinor, of: a.spendingMinor),
                    incomeChange: data.gate(b.incomeMinor - a.incomeMinor, includesSalary: locked),
                    netChange: data.gate((b.incomeMinor - b.spendingMinor) - (a.incomeMinor - a.spendingMinor), includesSalary: locked)
                ))
            } else {
                latestChange = .insufficient("\(a.count == 0 ? prior : last) has no transactions")
            }
        } else {
            latestChange = .insufficient("needs two complete months; \(keys.count) available")
        }

        movers = Self.movers(data: data, averagedKeys: averaged)

        var notes: [String] = []
        if data.firstDataMonthKey == nil {
            notes.append("No transactions recorded yet.")
        } else if keys.isEmpty {
            notes.append("No complete month yet: history starts in the current month \(data.currentMonthKey).")
        } else {
            notes.append("History: \(averaged.count) complete month(s) with transactions between \(keys.first!) and \(keys.last!).")
        }
        let empty = keys.filter { data.totals($0).count == 0 }
        if !empty.isEmpty {
            notes.append("Months with no transactions (excluded from averages): \(empty.joined(separator: ", ")).")
        }
        notes.append("Current month \(data.currentMonthKey) is month-to-date (day \(daysElapsedInCurrentMonth) of \(daysInCurrentMonth)) and not averaged.")
        notes = notes + [AdviserRules.averagesRule]
        self.notes = notes
    }

    private static func movers(data: AdviserDataSet, averagedKeys: [String]) -> AdviserFigure<[CategoryMover]> {
        guard let latestKey = averagedKeys.last else {
            return .insufficient("no complete month with transactions")
        }
        let baselineKeys = Array(averagedKeys.dropLast())
        guard baselineKeys.count >= AdviserRules.minimumBaselineMonthsForMovers else {
            return .insufficient("needs \(AdviserRules.minimumBaselineMonthsForMovers) earlier complete months with transactions before \(latestKey); \(baselineKeys.count) available")
        }
        let latest = data.totals(latestKey).byCategory
        let baseline = baselineKeys.map { data.totals($0).byCategory }
        var result: [CategoryMover] = []
        for category in CategoryID.expenseCategories {
            let sum = baseline.reduce(Int64(0)) { $0 + ($1[category] ?? 0) }
            let mover = CategoryMover(
                category: category,
                latestMinor: latest[category] ?? 0,
                baselineAverageMinor: AdviserMath.average(sum, count: baseline.count, step: data.step)
            )
            if mover.changeMinor != 0 { result.append(mover) }
        }
        result.sort { lhs, rhs in
            let l = abs(lhs.changeMinor), r = abs(rhs.changeMinor)
            if l != r { return l > r }
            return (CategoryID.expenseCategories.firstIndex(of: lhs.category) ?? 0) < (CategoryID.expenseCategories.firstIndex(of: rhs.category) ?? 0)
        }
        return .value(Array(result.prefix(AdviserRules.moversLimit)))
    }
}

// MARK: - Budget adherence

public struct SuggestedLimit: Hashable, Sendable {
    public let limitMinor: Int64
    public let medianMinor: Int64
    public let monthsUsed: Int
}

public struct BudgetCategoryAdherence: Hashable, Sendable {
    public enum Status: String, Hashable, Sendable {
        case under, near, over
    }

    public let category: CategoryID
    /// This month's limit, `nil` when the category has no budget this month.
    public let limitMinor: Int64?
    public let spentMinor: Int64
    public let remainingMinor: Int64?
    public let percentUsed: Double?
    public let status: Status?
    public let projectedMonthEndMinor: Int64
    public let projectedOverLimit: Bool?
    /// Complete months (with transactions) in which this category had a budget, and in how many
    /// of them spending exceeded that month's budget.
    public let monthsWithBudget: Int
    public let monthsOverItsBudget: Int
    /// Complete months with transactions, and in how many spending was above this month's limit.
    public let monthsCompared: Int
    public let monthsAboveCurrentLimit: Int?
    public let suggestedLimit: AdviserFigure<SuggestedLimit>
}

public struct BudgetAdherence: Hashable, Sendable {
    public let monthKey: String
    public let daysElapsed: Int
    public let daysInMonth: Int
    public let categories: [BudgetCategoryAdherence]
    public let totalLimitMinor: Int64
    public let totalSpentInBudgetedMinor: Int64
    public let notes: [String]

    /// Budgeted categories first (this month), then other expense categories with spending in the
    /// window. `only` limits the result to one category.
    public init(data: AdviserDataSet, only: CategoryID? = nil) {
        let monthKey = data.currentMonthKey
        self.monthKey = monthKey
        let daysElapsed = DateKey.dayOfMonth(fromDayKey: data.todayKey)
        let daysInMonth = DateKey.daysInMonth(monthKey)
        self.daysElapsed = daysElapsed
        self.daysInMonth = daysInMonth
        let step = data.step

        let current = data.totals(monthKey)
        let thisMonthBudgets = Dictionary(
            data.budgets.filter { $0.monthKey == monthKey }.map { ($0.category, $0.limitMinor) },
            uniquingKeysWith: { a, _ in a }
        )
        let averaged = data.averagedMonthKeys()
        let budgetsByMonth = Dictionary(grouping: data.budgets, by: \.monthKey)

        var rows: [BudgetCategoryAdherence] = []
        for category in CategoryID.expenseCategories {
            if let only, only != category { continue }
            let limit = thisMonthBudgets[category]
            let spent = current.byCategory[category] ?? 0
            let history = averaged.map { data.totals($0).byCategory[category] ?? 0 }
            let hasHistory = history.contains { $0 > 0 }
            guard limit != nil || spent > 0 || hasHistory || only != nil else { continue }

            var monthsWithBudget = 0
            var monthsOver = 0
            for key in averaged {
                guard let budget = budgetsByMonth[key]?.first(where: { $0.category == category }) else { continue }
                monthsWithBudget += 1
                if (data.totals(key).byCategory[category] ?? 0) > budget.limitMinor { monthsOver += 1 }
            }
            let projected = daysElapsed > 0
                ? AdviserMath.round(Double(spent) * Double(daysInMonth) / Double(daysElapsed), step: step)
                : spent

            let suggestion: AdviserFigure<SuggestedLimit>
            if averaged.count >= AdviserRules.minimumMonthsForSuggestedLimit {
                let median = AdviserMath.round(AdviserMath.median(history), step: step)
                suggestion = median > 0
                    ? .value(SuggestedLimit(limitMinor: AdviserMath.roundUpToTwoSignificant(median), medianMinor: median, monthsUsed: averaged.count))
                    : .insufficient("median monthly spending in \(category.rawValue) is 0")
            } else {
                suggestion = .insufficient("needs \(AdviserRules.minimumMonthsForSuggestedLimit) complete months with transactions; \(averaged.count) available")
            }

            var status: BudgetCategoryAdherence.Status?
            var percent: Double?
            if let limit {
                percent = AdviserMath.percent(spent, of: limit)
                if spent > limit {
                    status = .over
                } else if let percent, percent >= AdviserRules.nearLimitPercent {
                    status = .near
                } else {
                    status = .under
                }
            }
            rows.append(BudgetCategoryAdherence(
                category: category,
                limitMinor: limit,
                spentMinor: spent,
                remainingMinor: limit.map { $0 - spent },
                percentUsed: percent,
                status: status,
                projectedMonthEndMinor: projected,
                projectedOverLimit: limit.map { projected > $0 },
                monthsWithBudget: monthsWithBudget,
                monthsOverItsBudget: monthsOver,
                monthsCompared: averaged.count,
                monthsAboveCurrentLimit: limit.map { l in history.filter { $0 > l }.count },
                suggestedLimit: suggestion
            ))
        }
        rows.sort { lhs, rhs in
            if (lhs.limitMinor != nil) != (rhs.limitMinor != nil) { return lhs.limitMinor != nil }
            return lhs.spentMinor > rhs.spentMinor
        }
        categories = rows
        totalLimitMinor = rows.compactMap(\.limitMinor).reduce(0, +)
        totalSpentInBudgetedMinor = rows.filter { $0.limitMinor != nil }.reduce(Int64(0)) { $0 + $1.spentMinor }

        var notes = ["Month-to-date for \(monthKey): day \(daysElapsed) of \(daysInMonth).", AdviserRules.projectionRule, AdviserRules.suggestedLimitRule]
        if thisMonthBudgets.isEmpty { notes.insert("No budgets are set for \(monthKey).", at: 0) }
        if averaged.count < AdviserRules.minimumMonthsForSuggestedLimit {
            notes.append("Only \(averaged.count) complete month(s) with transactions, so history-based figures are limited.")
        }
        self.notes = notes
    }
}

// MARK: - Runway

public struct RunwayEstimate: Hashable, Sendable {
    public let cashMinor: Int64
    public let averageSpendingMinor: AdviserFigure<Int64>
    public let monthsOfSpending: AdviserFigure<Double>
    public let averageFixedMinor: AdviserFigure<Int64>
    public let monthsOfFixedCosts: AdviserFigure<Double>

    public init(cashMinor: Int64, history: CashFlowHistory) {
        self.cashMinor = cashMinor
        averageSpendingMinor = history.averageSpendingMinor
        averageFixedMinor = history.fixedVariable.map(\.averageFixedMinor)
        monthsOfSpending = Self.months(cash: cashMinor, per: history.averageSpendingMinor, label: "average monthly spending")
        monthsOfFixedCosts = Self.months(cash: cashMinor, per: averageFixedMinor, label: "average monthly fixed spending")
    }

    private static func months(cash: Int64, per figure: AdviserFigure<Int64>, label: String) -> AdviserFigure<Double> {
        switch figure {
        case .value(let monthly):
            guard monthly > 0 else { return .insufficient("\(label) is 0") }
            return .value((Double(cash) / Double(monthly) * 10).rounded(.down) / 10)
        case .insufficient(let reason): return .insufficient(reason)
        case .salaryLocked: return .salaryLocked
        }
    }
}

// MARK: - Period summary

/// Totals for an arbitrary date range, so the model never adds up transaction lists itself.
public struct PeriodSummary: Hashable, Sendable {
    public struct Merchant: Hashable, Sendable {
        public let name: String
        public let totalMinor: Int64
        public let count: Int
    }

    public struct CategoryShare: Hashable, Sendable {
        public let category: CategoryID
        public let minor: Int64
        public let sharePercent: Double?
    }

    public struct Member: Hashable, Sendable {
        public let name: String
        public let spendingMinor: Int64
        public let count: Int
    }

    public let startDayKey: String
    public let endDayKey: String
    public let dayCount: Int
    public let transactionCount: Int
    public let spendingMinor: Int64
    public let spendingByCategory: [CategoryShare]
    public let income: AdviserFigure<Int64>
    public let nonSalaryIncomeMinor: Int64
    public let net: AdviserFigure<Int64>
    public let members: [Member]
    public let topMerchants: [Merchant]
    public let averagePerDayMinor: Int64

    /// `category` / `memberID` filter the transactions first. Future-dated transactions are not in
    /// the data set (it stops at today).
    public init(data: AdviserDataSet, startDayKey: String, endDayKey: String, category: CategoryID? = nil, memberID: String? = nil) {
        let lo = min(startDayKey, endDayKey)
        let hi = max(startDayKey, endDayKey)
        self.startDayKey = lo
        self.endDayKey = hi
        dayCount = DateKey.daysBetween(lo, hi) + 1
        let txs = data.transactions.filter {
            $0.dayKey >= lo && $0.dayKey <= hi
                && (category == nil || $0.category == category)
                && (memberID == nil || $0.memberID == memberID)
        }
        transactionCount = txs.count
        let expenses = txs.filter { $0.type == .expense }
        let spending = expenses.reduce(Int64(0)) { $0 + $1.amountMinor }
        spendingMinor = spending
        var byCategory: [CategoryID: Int64] = [:]
        for tx in expenses { byCategory[tx.category, default: 0] += tx.amountMinor }
        spendingByCategory = byCategory
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
            .map { CategoryShare(category: $0.key, minor: $0.value, sharePercent: AdviserMath.percent($0.value, of: spending)) }
        let incomeTxs = txs.filter { $0.type == .income }
        let income = incomeTxs.reduce(Int64(0)) { $0 + $1.amountMinor }
        let hasSalary = SalaryPrivacy.containsSalary(incomeTxs)
        self.income = data.gate(income, includesSalary: hasSalary)
        nonSalaryIncomeMinor = incomeTxs.filter { !$0.includesSalary }.reduce(Int64(0)) { $0 + $1.amountMinor }
        net = data.gate(income - spending, includesSalary: hasSalary)

        var members: [String: Member] = [:]
        for tx in expenses {
            let old = members[tx.memberID]
            let name = (old?.name.isEmpty == false ? old?.name : nil) ?? (tx.memberName.isEmpty ? tx.memberID : tx.memberName)
            members[tx.memberID] = Member(name: name, spendingMinor: (old?.spendingMinor ?? 0) + tx.amountMinor, count: (old?.count ?? 0) + 1)
        }
        self.members = members.values.sorted { $0.spendingMinor > $1.spendingMinor }

        var merchants: [String: Merchant] = [:]
        for tx in expenses {
            let key = tx.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let old = merchants[key]
            merchants[key] = Merchant(name: old?.name ?? tx.name, totalMinor: (old?.totalMinor ?? 0) + tx.amountMinor, count: (old?.count ?? 0) + 1)
        }
        topMerchants = Array(merchants.values.sorted {
            $0.totalMinor != $1.totalMinor ? $0.totalMinor > $1.totalMinor : $0.name < $1.name
        }.prefix(5))
        averagePerDayMinor = AdviserMath.average(spending, count: max(1, dayCount), step: data.step)
    }
}
