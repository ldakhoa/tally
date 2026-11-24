import Foundation
import TallyCore

// MARK: - Debt picture

public struct DebtPlanFigures: Hashable, Sendable {
    public let planID: String
    public let name: String
    public let kind: InstallmentKind
    public let lender: String?
    public let currency: CurrencyCode
    /// The next scheduled payment (what this plan adds to monthly debt service).
    public let nextPaymentMinor: Int64
    public let nextPaymentDayKey: String?
    public let lastPaymentDayKey: String?
    public let remainingPayments: Int
    /// Scheduled payments still to come (principal + interest).
    public let remainingScheduledMinor: Int64
    public let outstandingPrincipalMinor: Int64
    /// Nominal annual rate on the reducing balance (12 x monthly), in percent with 2 decimals.
    public let effectiveAnnualRatePercent: Double
    public let interestRemainingMinor: Int64
    /// Settling today: principal to pay and interest saved. Insufficient before the first payment
    /// date (the app only records settlements on or after it).
    public let settleToday: AdviserFigure<EarlySettlement>
}

public struct EarlySettlement: Hashable, Sendable {
    public let settleDayKey: String
    public let payoffPrincipalMinor: Int64
    public let interestSavedMinor: Int64
    public let cancelledPaymentCount: Int
    public let cancelledPaymentsMinor: Int64

    public static func compute(plan: InstallmentPlanRecord, settleDayKey: String, todayKey: String) -> AdviserFigure<EarlySettlement> {
        guard settleDayKey >= plan.firstPaymentDayKey else {
            return .insufficient("a plan can only be settled on or after its first payment date \(plan.firstPaymentDayKey)")
        }
        let progress = plan.progress(todayKey: settleDayKey)
        guard !progress.isCompleted else {
            return .insufficient("the plan is already completed or settled by \(settleDayKey)")
        }
        let preview = InstallmentSettlementPreview(plan: plan, settleDayKey: settleDayKey, todayKey: todayKey)
        return .value(EarlySettlement(
            settleDayKey: settleDayKey,
            payoffPrincipalMinor: preview.payoffPrincipalMinor,
            interestSavedMinor: preview.interestSavedMinor,
            cancelledPaymentCount: preview.cancelledPaymentCount,
            cancelledPaymentsMinor: preview.cancelledPaymentsMinor
        ))
    }
}

public struct DebtOverview: Hashable, Sendable {
    /// Active (not completed, not settled) plans and loans, in the app's list order.
    public let plans: [DebtPlanFigures]
    public let totalRemainingScheduledMinor: Int64
    public let totalOutstandingPrincipalMinor: Int64
    public let totalInterestRemainingMinor: Int64
    public let monthlyDebtServiceMinor: Int64
    public let averageIncomeMinor: AdviserFigure<Int64>
    public let debtServiceToIncomePercent: AdviserFigure<Double>
    /// Plan IDs, best first.
    public let highestRateFirst: [String]
    public let smallestBalanceFirst: [String]
    public let notes: [String]

    public init(data: AdviserDataSet, history: CashFlowHistory? = nil) {
        let history = history ?? CashFlowHistory(data: data)
        let overview = CommitmentsOverview(plans: data.plans, todayKey: data.todayKey)
        let figures = overview.active.map { entry -> DebtPlanFigures in
            let plan = entry.plan
            let progress = entry.progress
            return DebtPlanFigures(
                planID: plan.id,
                name: plan.name,
                kind: plan.kind,
                lender: plan.lender?.isEmpty == false ? plan.lender : nil,
                currency: plan.currency,
                nextPaymentMinor: progress.nextPaymentMinor ?? 0,
                nextPaymentDayKey: progress.nextPaymentDayKey,
                lastPaymentDayKey: plan.schedule.last?.dayKey,
                remainingPayments: progress.paymentCount - progress.paidCount,
                remainingScheduledMinor: progress.remainingMinor,
                outstandingPrincipalMinor: progress.outstandingPrincipalMinor,
                effectiveAnnualRatePercent: (plan.effectiveAnnualRate * 10_000).rounded() / 100,
                interestRemainingMinor: progress.interestRemainingMinor,
                settleToday: EarlySettlement.compute(plan: plan, settleDayKey: data.todayKey, todayKey: data.todayKey)
            )
        }
        plans = figures
        totalRemainingScheduledMinor = figures.reduce(Int64(0)) { $0 + $1.remainingScheduledMinor }
        totalOutstandingPrincipalMinor = figures.reduce(Int64(0)) { $0 + $1.outstandingPrincipalMinor }
        totalInterestRemainingMinor = figures.reduce(Int64(0)) { $0 + $1.interestRemainingMinor }
        let service = figures.reduce(Int64(0)) { $0 + $1.nextPaymentMinor }
        monthlyDebtServiceMinor = service
        averageIncomeMinor = history.averageIncomeMinor
        debtServiceToIncomePercent = Self.ratio(service, income: history.averageIncomeMinor)

        highestRateFirst = figures.sorted { lhs, rhs in
            if lhs.effectiveAnnualRatePercent != rhs.effectiveAnnualRatePercent { return lhs.effectiveAnnualRatePercent > rhs.effectiveAnnualRatePercent }
            if lhs.outstandingPrincipalMinor != rhs.outstandingPrincipalMinor { return lhs.outstandingPrincipalMinor > rhs.outstandingPrincipalMinor }
            return lhs.name < rhs.name
        }.map(\.planID)
        smallestBalanceFirst = figures.sorted { lhs, rhs in
            if lhs.outstandingPrincipalMinor != rhs.outstandingPrincipalMinor { return lhs.outstandingPrincipalMinor < rhs.outstandingPrincipalMinor }
            if lhs.effectiveAnnualRatePercent != rhs.effectiveAnnualRatePercent { return lhs.effectiveAnnualRatePercent > rhs.effectiveAnnualRatePercent }
            return lhs.name < rhs.name
        }.map(\.planID)

        var notes = [AdviserRules.debtServiceRule, AdviserRules.payoffRule]
        if figures.isEmpty { notes.insert("No active installment plans or loans.", at: 0) }
        if figures.contains(where: { $0.currency != data.currency }) {
            notes.append("Some plans are in another currency; totals add their amounts as recorded.")
        }
        self.notes = notes
    }

    static func ratio(_ service: Int64, income: AdviserFigure<Int64>) -> AdviserFigure<Double> {
        switch income {
        case .value(let monthly):
            guard let percent = AdviserMath.percent(service, of: monthly) else {
                return .insufficient("average monthly income is 0")
            }
            return .value(percent)
        case .insufficient(let reason): return .insufficient(reason)
        case .salaryLocked: return .salaryLocked
        }
    }
}

// MARK: - Affordability of a new commitment

public struct AffordabilityInput: Equatable, Sendable {
    public var amountMinor: Int64
    public var months: Int
    /// Nominal annual rate in percent (e.g. 6 for 6% p.a.).
    public var annualRatePercent: Double?
    public var monthlyPaymentMinor: Int64?

    public init(amountMinor: Int64, months: Int, annualRatePercent: Double? = nil, monthlyPaymentMinor: Int64? = nil) {
        self.amountMinor = amountMinor
        self.months = months
        self.annualRatePercent = annualRatePercent
        self.monthlyPaymentMinor = monthlyPaymentMinor
    }
}

public struct AffordabilityCheck: Hashable, Sendable {
    public enum Basis: String, Hashable, Sendable {
        case givenMonthlyPayment = "monthly payment as given"
        case annuityAtRate = "annuity payment at the given nominal annual rate"
        case interestFree = "interest-free split of the amount"
    }

    public let basis: Basis
    public let monthlyPaymentMinor: Int64
    public let totalRepaidMinor: Int64
    public let totalInterestMinor: Int64
    public let annualRatePercent: Double
    public let currentDebtServiceMinor: Int64
    public let newDebtServiceMinor: Int64
    public let averageIncomeMinor: AdviserFigure<Int64>
    public let currentDebtServiceToIncomePercent: AdviserFigure<Double>
    public let newDebtServiceToIncomePercent: AdviserFigure<Double>
    public let averageNetMinor: AdviserFigure<Int64>
    /// Average monthly net minus the new payment.
    public let newMonthlyNetMinor: AdviserFigure<Int64>
    public let averageSpendingMinor: AdviserFigure<Int64>
    /// Average monthly spending plus the new payment.
    public let newMonthlySpendingMinor: AdviserFigure<Int64>
    public let notes: [String]

    public enum Failure: Error, Equatable, Sendable {
        case invalidAmount
        case invalidMonths
        case invalidRate
        /// Monthly payment x months is below the amount.
        case paymentTooSmall(totalMinor: Int64)

        public var message: String {
            switch self {
            case .invalidAmount: return "amount must be a positive number"
            case .invalidMonths: return "months must be a whole number from 1 to \(InstallmentPlanRecord.maxMonths)"
            case .invalidRate: return "annual_rate_percent must be between 0 and 100"
            case .paymentTooSmall: return "monthly_payment x months is less than the amount, so the figures are inconsistent; ask the user to check them"
            }
        }
    }

    public static func evaluate(_ input: AffordabilityInput, data: AdviserDataSet, history: CashFlowHistory? = nil, debt: DebtOverview? = nil) -> Result<AffordabilityCheck, Failure> {
        guard input.amountMinor > 0, input.amountMinor <= InstallmentPlanRecord.maxAmountMinor else { return .failure(.invalidAmount) }
        guard input.months >= 1, input.months <= InstallmentPlanRecord.maxMonths else { return .failure(.invalidMonths) }
        let step = data.step
        var notes: [String] = []
        let basis: Basis
        let payment: Int64
        let totalRepaid: Int64
        let rate: Double

        if let given = input.monthlyPaymentMinor, given > 0 {
            let rounded = InstallmentPlanRecord.roundHalfUp(given, step: step)
            let (total, overflow) = rounded.multipliedReportingOverflow(by: Int64(input.months))
            guard !overflow, total >= input.amountMinor else { return .failure(.paymentTooSmall(totalMinor: overflow ? .max : total)) }
            basis = .givenMonthlyPayment
            payment = rounded
            totalRepaid = total
            let monthly = InstallmentMath.solveMonthlyRate(principalMinor: input.amountMinor, payments: Array(repeating: rounded, count: input.months))
            rate = (monthly * 12 * 10_000).rounded() / 100
            if input.annualRatePercent != nil {
                notes.append("annual_rate_percent was ignored because monthly_payment was given; the rate shown is the one implied by the payment.")
            }
        } else if let percent = input.annualRatePercent, percent > 0 {
            guard percent.isFinite, percent <= 100 else { return .failure(.invalidRate) }
            let r = percent / 100 / 12
            let n = Double(input.months)
            let exact = Double(input.amountMinor) * r / (1 - pow(1 + r, -n))
            basis = .annuityAtRate
            payment = AdviserMath.round(exact, step: step)
            totalRepaid = payment * Int64(input.months)
            rate = percent
            notes.append("Total repaid = monthly payment x months; a lender's last payment may differ slightly.")
        } else {
            if let percent = input.annualRatePercent, !(percent.isFinite && percent >= 0) { return .failure(.invalidRate) }
            let amounts = InstallmentPlanRecord.paymentAmounts(totalMinor: input.amountMinor, months: input.months, step: step)
            guard let first = amounts.first else { return .failure(.invalidAmount) }
            basis = .interestFree
            payment = first
            totalRepaid = input.amountMinor
            rate = 0
            if let last = amounts.last, amounts.count > 1, last != first {
                notes.append("The last payment is \(MoneyFormat.format(minor: last, currency: data.currency, language: .english)).")
            }
        }

        let history = history ?? CashFlowHistory(data: data)
        let debt = debt ?? DebtOverview(data: data, history: history)
        let current = debt.monthlyDebtServiceMinor
        let newService = current + payment
        let check = AffordabilityCheck(
            basis: basis,
            monthlyPaymentMinor: payment,
            totalRepaidMinor: totalRepaid,
            totalInterestMinor: max(0, totalRepaid - input.amountMinor),
            annualRatePercent: rate,
            currentDebtServiceMinor: current,
            newDebtServiceMinor: newService,
            averageIncomeMinor: history.averageIncomeMinor,
            currentDebtServiceToIncomePercent: DebtOverview.ratio(current, income: history.averageIncomeMinor),
            newDebtServiceToIncomePercent: DebtOverview.ratio(newService, income: history.averageIncomeMinor),
            averageNetMinor: history.averageNetMinor,
            newMonthlyNetMinor: history.averageNetMinor.map { $0 - payment },
            averageSpendingMinor: history.averageSpendingMinor,
            newMonthlySpendingMinor: history.averageSpendingMinor.map { $0 + payment },
            notes: notes + [AdviserRules.debtServiceRule, AdviserRules.averagesRule]
        )
        return .success(check)
    }
}

// MARK: - Savings goals

public struct GoalOutlook: Hashable, Sendable {
    public let goalID: String?
    public let name: String
    public let targetMinor: Int64
    public let savedMinor: Int64
    public let neededMinor: Int64
    public let percent: Int
    /// Monthly saving pace used (household average net).
    public let paceMinor: AdviserFigure<Int64>
    /// Months to reach the target at the pace, counting from next month; 0 when reached.
    public let monthsToTarget: AdviserFigure<Int>
    public let projectedMonthKey: AdviserFigure<String>

    public init(goalID: String?, name: String, targetMinor: Int64, savedMinor: Int64, data: AdviserDataSet, history: CashFlowHistory) {
        self.goalID = goalID
        self.name = name
        self.targetMinor = targetMinor
        self.savedMinor = savedMinor
        let needed = max(0, targetMinor - savedMinor)
        neededMinor = needed
        percent = targetMinor > 0 ? Int((Double(savedMinor) * 100 / Double(targetMinor)).rounded(.down)) : 0
        paceMinor = history.averageNetMinor
        let months = Self.monthsToCover(needed, monthly: history.averageNetMinor, label: "average monthly net saving")
        monthsToTarget = months
        projectedMonthKey = months.map { DateKey.shiftMonth(data.currentMonthKey, by: $0) }
    }

    /// Whole months of `monthly` needed to cover `needed` (0 when nothing is needed).
    static func monthsToCover(_ needed: Int64, monthly: AdviserFigure<Int64>, label: String) -> AdviserFigure<Int> {
        if needed == 0 { return .value(0) }
        switch monthly {
        case .value(let pace):
            guard pace > 0 else { return .insufficient("\(label) is not positive, so the target is not reached at this pace") }
            return .value(Int((Double(needed) / Double(pace)).rounded(.up)))
        case .insufficient(let reason): return .insufficient(reason)
        case .salaryLocked: return .salaryLocked
        }
    }
}

public struct GoalPlan: Hashable, Sendable {
    public let outlook: GoalOutlook
    /// Target month and the monthly contribution it needs, counting from next month through the
    /// target month.
    public let targetMonthKey: String?
    public let contributionMonths: Int?
    public let requiredMonthlyMinor: Int64?
    /// Required contribution minus the household's average net (positive = short each month).
    public let shortfallVersusPaceMinor: AdviserFigure<Int64>?
    /// With a stated monthly contribution: months needed and the month reached.
    public let contributionMinor: Int64?
    public let monthsAtContribution: Int?
    public let monthKeyAtContribution: String?
    public let notes: [String]

    public enum Failure: Error, Equatable, Sendable {
        case targetDateNotInFuture(currentMonthKey: String)
        case invalidContribution

        public var message: String {
            switch self {
            case .targetDateNotInFuture(let current): return "target_date must be in a later month than the current month \(current)"
            case .invalidContribution: return "monthly_contribution must be a positive number"
            }
        }
    }

    public static func evaluate(
        outlook: GoalOutlook,
        targetMonthKey: String?,
        contributionMinor: Int64?,
        data: AdviserDataSet
    ) -> Result<GoalPlan, Failure> {
        var months: Int?
        var required: Int64?
        var shortfall: AdviserFigure<Int64>?
        if let targetMonthKey {
            guard let n = AdviserMath.monthsBetween(data.currentMonthKey, targetMonthKey), n >= 1 else {
                return .failure(.targetDateNotInFuture(currentMonthKey: data.currentMonthKey))
            }
            months = n
            let perMonth = AdviserMath.roundUp(Double(outlook.neededMinor) / Double(n), step: data.step)
            required = perMonth
            shortfall = outlook.paceMinor.map { perMonth - $0 }
        }
        var atContributionMonths: Int?
        var atContributionKey: String?
        if let contributionMinor {
            guard contributionMinor > 0 else { return .failure(.invalidContribution) }
            let m = outlook.neededMinor == 0 ? 0 : Int((Double(outlook.neededMinor) / Double(contributionMinor)).rounded(.up))
            atContributionMonths = m
            atContributionKey = DateKey.shiftMonth(data.currentMonthKey, by: m)
        }
        return .success(GoalPlan(
            outlook: outlook,
            targetMonthKey: targetMonthKey,
            contributionMonths: months,
            requiredMonthlyMinor: required,
            shortfallVersusPaceMinor: shortfall,
            contributionMinor: contributionMinor,
            monthsAtContribution: atContributionMonths,
            monthKeyAtContribution: atContributionKey,
            notes: [
                "Contributions are counted from next month (\(DateKey.shiftMonth(data.currentMonthKey, by: 1))) through the target month; the required amount is rounded up.",
                AdviserRules.goalPaceRule,
            ]
        ))
    }
}
