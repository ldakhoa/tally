import Foundation
import TallyCore

// Deterministic "motivation" figures behind the Budgets, Goals and Commitments screens: pacing,
// streaks, levels, milestones and the debt-free date. The UI only formats and animates these.

// MARK: - Budgets: pace, daily allowance, streak

public struct BudgetMomentum: Hashable, Sendable {
    public enum Timing: Hashable, Sendable { case past, current, future }

    public enum Pace: Hashable, Sendable {
        /// No limits set for the month.
        case noBudget
        /// A month that has not started yet.
        case upcoming
        /// Spent clearly less than the even-spend line for today.
        case ahead
        case onTrack
        /// Still under the total limit, but spending faster than the even-spend line.
        case behind
        /// Total limit exceeded.
        case over
        /// A past month that closed at or under its total limit.
        case finishedUnder
    }

    /// A pace cushion within this share of the total limit (either way) counts as "on track".
    public static let onTrackBandPercent: Int64 = 5

    public let timing: Timing
    public let daysInMonth: Int
    /// Days of the month gone by, today included. `daysInMonth` for a past month, 0 for a future one.
    public let daysElapsed: Int
    /// Days still to cover, today included. 0 for a past month.
    public let daysLeft: Int
    public let totalMinor: Int64
    public let spentMinor: Int64
    public let leftMinor: Int64
    /// What can be spent per remaining day (today included) without breaking the total limit.
    public let safeToSpendPerDayMinor: Int64
    /// Even-spend line for today minus actual spending: positive means money ahead of plan.
    public let paceCushionMinor: Int64
    public let pace: Pace
    public let categoriesOnTrack: Int
    public let categoriesTotal: Int
    /// Consecutive months right before this one that closed at or under their total limit.
    public let underBudgetMonthStreak: Int

    /// Share of the total limit still unspent, clamped to 0...1.
    public var leftFraction: Double {
        guard totalMinor > 0 else { return 0 }
        return min(1, max(0, Double(leftMinor) / Double(totalMinor)))
    }

    public init(
        snapshot: MonthlySnapshot,
        todayKey: String,
        underBudgetMonthStreak: Int = 0
    ) {
        let monthKey = snapshot.monthKey
        let todayMonth = DateKey.monthKey(fromDayKey: todayKey)
        let days = max(1, DateKey.daysInMonth(monthKey))

        let timing: Timing
        let elapsed: Int
        if monthKey < todayMonth {
            timing = .past
            elapsed = days
        } else if monthKey > todayMonth {
            timing = .future
            elapsed = 0
        } else {
            timing = .current
            elapsed = min(days, max(1, DateKey.dayOfMonth(fromDayKey: todayKey)))
        }
        let left: Int
        switch timing {
        case .past: left = 0
        case .future: left = days
        case .current: left = days - elapsed + 1
        }

        let total = snapshot.budgetTotalMinor
        let spent = snapshot.budgetSpentMinor
        let remaining = total - spent
        let expectedByToday = total * Int64(elapsed) / Int64(days)
        let cushion = expectedByToday - spent

        self.timing = timing
        self.daysInMonth = days
        self.daysElapsed = elapsed
        self.daysLeft = left
        self.totalMinor = total
        self.spentMinor = spent
        self.leftMinor = remaining
        self.safeToSpendPerDayMinor = left > 0 ? max(0, remaining) / Int64(left) : 0
        self.paceCushionMinor = cushion
        self.categoriesTotal = snapshot.budgets.count
        self.categoriesOnTrack = snapshot.budgets.filter {
            (snapshot.expensesByCategory[$0.category] ?? 0) <= $0.limitMinor
        }.count
        self.underBudgetMonthStreak = underBudgetMonthStreak

        if total <= 0 {
            pace = .noBudget
        } else if remaining < 0 {
            pace = .over
        } else {
            switch timing {
            case .past:
                pace = .finishedUnder
            case .future:
                pace = .upcoming
            case .current:
                let band = total * Self.onTrackBandPercent / 100
                if cushion >= band, cushion > 0 {
                    pace = .ahead
                } else if cushion >= -band {
                    pace = .onTrack
                } else {
                    pace = .behind
                }
            }
        }
    }

    /// Counts the consecutive months immediately before `monthKey` that had limits and closed with
    /// spending in the budgeted categories at or under the total limit. A month with no limits, or
    /// one that went over, ends the streak.
    public static func underBudgetMonthStreak(
        before monthKey: String,
        allTransactions: [TransactionRecord],
        allBudgets: [BudgetLimitRecord],
        memberFilter: String? = nil,
        maxMonths: Int = 36
    ) -> Int {
        var limits: [String: [CategoryID: Int64]] = [:]
        for budget in allBudgets where !budget.isDeleted {
            limits[budget.monthKey, default: [:]][budget.category, default: 0] += budget.limitMinor
        }
        guard !limits.isEmpty else { return 0 }

        var spent: [String: [CategoryID: Int64]] = [:]
        for tx in allTransactions where !tx.isDeleted && tx.type == .expense {
            if let memberFilter, tx.memberID != memberFilter { continue }
            let month = DateKey.monthKey(fromDayKey: tx.dayKey)
            guard limits[month] != nil else { continue }
            spent[month, default: [:]][tx.category, default: 0] += tx.amountMinor
        }

        var streak = 0
        var month = DateKey.shiftMonth(monthKey, by: -1)
        while streak < maxMonths, let monthLimits = limits[month] {
            let total = monthLimits.values.reduce(Int64(0), +)
            guard total > 0 else { break }
            let used = monthLimits.keys.reduce(Int64(0)) { $0 + (spent[month]?[$1] ?? 0) }
            guard used <= total else { break }
            streak += 1
            month = DateKey.shiftMonth(month, by: -1)
        }
        return streak
    }
}

// MARK: - Savings level (the "earn more, keep more" ladder)

public struct SavingsLevel: Hashable, Sendable {
    public enum Tier: Int, CaseIterable, Comparable, Hashable, Sendable {
        case starting, seed, sprout, bloom, golden, master

        /// Lowest savings rate (percent of income kept) that belongs to this tier.
        public var floorPercent: Int {
            switch self {
            case .starting: return Int.min
            case .seed: return 5
            case .sprout: return 10
            case .bloom: return 20
            case .golden: return 30
            case .master: return 50
            }
        }

        public var next: Tier? { Tier(rawValue: rawValue + 1) }

        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let tier: Tier
    public let nextTier: Tier?
    /// Kept income as a percent of income, rounded down.
    public let ratePercent: Int
    /// 0...1 position between this tier's floor and the next tier's floor.
    public let progressToNext: Double
    /// Extra income needed, with spending unchanged, to reach the next tier. 0 at the top tier.
    public let earnMoreMinor: Int64
    /// Spending to cut, with income unchanged, to reach the next tier. 0 at the top tier.
    public let spendLessMinor: Int64

    /// `nil` when there is no income to measure against.
    public init?(incomeMinor: Int64, netSavingsMinor: Int64) {
        guard incomeMinor > 0 else { return nil }
        let rate = Int((Double(netSavingsMinor) * 100 / Double(incomeMinor)).rounded(.down))
        let tier = Tier.allCases.last { $0 == .starting || Self.meets($0, income: incomeMinor, net: netSavingsMinor) } ?? .starting

        self.tier = tier
        self.nextTier = tier.next
        self.ratePercent = rate

        guard let next = tier.next else {
            progressToNext = 1
            earnMoreMinor = 0
            spendLessMinor = 0
            return
        }

        let target = Int64(next.floorPercent)
        // Keep `target`% of income: net + cut >= income * target / 100.
        let neededNet = (incomeMinor * target + 99) / 100
        spendLessMinor = max(0, neededNet - netSavingsMinor)
        // Earn E more: (net + E) / (income + E) >= target / 100.
        let numerator = incomeMinor * target - netSavingsMinor * 100
        earnMoreMinor = numerator <= 0 ? 0 : (numerator + (100 - target) - 1) / (100 - target)

        let floor = tier == .starting ? 0 : Double(tier.floorPercent)
        let span = Double(next.floorPercent) - floor
        let exactRate = Double(netSavingsMinor) * 100 / Double(incomeMinor)
        progressToNext = min(1, max(0, (exactRate - floor) / span))
    }

    private static func meets(_ tier: Tier, income: Int64, net: Int64) -> Bool {
        net * 100 >= income * Int64(tier.floorPercent)
    }
}

// MARK: - Goals: milestones and the overall journey

public struct GoalMilestones: Hashable, Sendable {
    /// Percent marks celebrated on every goal.
    public static let steps: [Int] = [25, 50, 75, 100]

    public let reachedCount: Int
    /// The next mark to hit, `nil` once the goal is complete.
    public let nextStepPercent: Int?
    /// Amount still needed to hit `nextStepPercent`.
    public let toNextMinor: Int64
    /// Amount still needed to finish the goal.
    public let remainingMinor: Int64

    public var isComplete: Bool { reachedCount == Self.steps.count }
    /// The highest mark already reached, `nil` before the first one.
    public var lastReachedPercent: Int? { reachedCount > 0 ? Self.steps[reachedCount - 1] : nil }

    public init(savedMinor: Int64, targetMinor: Int64) {
        let reached = Self.reachedCount(savedMinor: savedMinor, targetMinor: targetMinor)
        reachedCount = reached
        remainingMinor = max(0, targetMinor - savedMinor)
        if reached < Self.steps.count, targetMinor > 0 {
            let step = Self.steps[reached]
            nextStepPercent = step
            let needed = (targetMinor * Int64(step) + 99) / 100
            toNextMinor = max(0, needed - savedMinor)
        } else {
            nextStepPercent = nil
            toNextMinor = 0
        }
    }

    public init(goal: SavingsGoalRecord) {
        self.init(savedMinor: goal.savedMinor, targetMinor: goal.targetMinor)
    }

    public static func reachedCount(savedMinor: Int64, targetMinor: Int64) -> Int {
        guard targetMinor > 0, savedMinor > 0 else { return 0 }
        return steps.filter { savedMinor * 100 >= targetMinor * Int64($0) }.count
    }
}

public struct GoalsJourney: Hashable, Sendable {
    public let totalSavedMinor: Int64
    public let totalTargetMinor: Int64
    public let completedCount: Int
    public let inProgressCount: Int
    /// Stars earned across all goals (one per milestone reached).
    public let starsEarned: Int
    public let starsTotal: Int
    /// The unfinished goal closest to done (highest progress, then smallest amount left).
    public let closest: SavingsGoalRecord?

    public var fraction: Double {
        guard totalTargetMinor > 0 else { return 0 }
        return min(1, max(0, Double(totalSavedMinor) / Double(totalTargetMinor)))
    }

    public init(goals: [SavingsGoalRecord]) {
        let live = goals.filter { !$0.isDeleted }
        totalSavedMinor = live.reduce(Int64(0)) { $0 + $1.savedMinor }
        totalTargetMinor = live.reduce(Int64(0)) { $0 + $1.targetMinor }
        let milestones = live.map { GoalMilestones(goal: $0) }
        completedCount = milestones.filter(\.isComplete).count
        inProgressCount = live.count - completedCount
        starsEarned = milestones.reduce(0) { $0 + $1.reachedCount }
        starsTotal = live.count * GoalMilestones.steps.count

        closest = zip(live, milestones)
            .filter { !$0.1.isComplete && $0.0.targetMinor > 0 }
            .min { lhs, rhs in
                if lhs.0.progress != rhs.0.progress { return lhs.0.progress > rhs.0.progress }
                if lhs.1.remainingMinor != rhs.1.remainingMinor { return lhs.1.remainingMinor < rhs.1.remainingMinor }
                return lhs.0.name < rhs.0.name
            }?.0
    }
}

// MARK: - Commitments: the road to debt-free

public struct DebtFreedom: Hashable, Sendable {
    public struct Finisher: Hashable, Sendable {
        public let planID: String
        public let name: String
        public let paymentsLeft: Int
    }

    public struct PayoffMilestone: Hashable, Sendable {
        public let monthKey: String
        public let planNames: [String]
        public let monthlyReliefMinor: Int64
    }

    /// Paid so far across plans still being repaid.
    public let paidMinor: Int64
    public let remainingMinor: Int64
    /// Day of the last scheduled payment across active plans; `nil` when nothing is owed.
    public let debtFreeDayKey: String?
    /// Whole calendar months from today's month to the debt-free month.
    public let monthsUntilDebtFree: Int
    /// Monthly cash that comes back once every active plan is finished.
    public let freedMonthlyMinor: Int64
    public let paymentsLeft: Int
    /// The active plan with the fewest payments left.
    public let nextToFinish: Finisher?
    public let completedCount: Int
    /// Regular monthly payments freed up by completed plans.
    public let releasedMonthlyMinor: Int64
    /// Additional monthly room after all payoffs in the nearest scheduled payoff month.
    public let nextPayoffMilestone: PayoffMilestone?

    public var fraction: Double {
        let total = paidMinor + remainingMinor
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(paidMinor) / Double(total)))
    }

    public init(overview: CommitmentsOverview, todayKey: String) {
        let active = overview.active
        paidMinor = active.reduce(Int64(0)) { $0 + $1.progress.paidMinor }
        remainingMinor = overview.remainingDebtMinor
        completedCount = overview.completed.count

        let payoffs = (active + overview.completed).compactMap {
            entry -> (month: String, name: String, monthly: Int64, completed: Bool)? in
            let plan = entry.plan
            let schedule = plan.fullSchedule
            guard schedule.count > 1, let first = schedule.first, let last = schedule.last else { return nil }
            let payoffDay = min(plan.settledDayKey ?? last.dayKey, last.dayKey)
            let waitingForSettlement = plan.settledDayKey == payoffDay && payoffDay > todayKey
            return (
                DateKey.monthKey(fromDayKey: payoffDay),
                plan.name,
                first.amountMinor,
                entry.progress.isCompleted && !waitingForSettlement
            )
        }
        let upcomingPayoffs = payoffs.filter { !$0.completed }
        freedMonthlyMinor = upcomingPayoffs.reduce(0) { $0 + $1.monthly }
        if let month = upcomingPayoffs.map(\.month).min() {
            let monthlyPayoffs = upcomingPayoffs.filter { $0.month == month }
            nextPayoffMilestone = PayoffMilestone(
                monthKey: month,
                planNames: monthlyPayoffs.map(\.name),
                monthlyReliefMinor: monthlyPayoffs.reduce(0) { $0 + $1.monthly }
            )
        } else {
            nextPayoffMilestone = nil
        }
        releasedMonthlyMinor = payoffs.filter(\.completed).reduce(0) { $0 + $1.monthly }

        let lefts = active.map { ($0, Self.paymentsLeft($0.progress)) }
        paymentsLeft = lefts.reduce(0) { $0 + $1.1 }
        nextToFinish = lefts
            .filter { $0.1 > 0 }
            .min { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.plan.name < rhs.0.plan.name
            }
            .map { Finisher(planID: $0.0.plan.id, name: $0.0.plan.name, paymentsLeft: $0.1) }

        let lastDay = active.compactMap { $0.plan.schedule.last?.dayKey }.max()
        debtFreeDayKey = lastDay
        if let lastDay {
            monthsUntilDebtFree = max(0, Self.monthsBetween(
                DateKey.monthKey(fromDayKey: todayKey),
                DateKey.monthKey(fromDayKey: lastDay)
            ))
        } else {
            monthsUntilDebtFree = 0
        }
    }

    public static func paymentsLeft(_ progress: InstallmentProgress) -> Int {
        progress.isCompleted ? 0 : max(0, progress.paymentCount - progress.paidCount)
    }

    private static func monthsBetween(_ from: String, _ to: String) -> Int {
        guard let a = DateKey.yearAndMonth(fromMonthKey: from),
              let b = DateKey.yearAndMonth(fromMonthKey: to)
        else { return 0 }
        return (b.year - a.year) * 12 + (b.month - a.month)
    }
}
