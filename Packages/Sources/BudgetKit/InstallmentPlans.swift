import Foundation
import TallyCore

// MARK: - Plan record

public enum InstallmentKind: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    /// Card instalment plan (usually 0%, e.g. DBS "IPP").
    case installment
    /// Loan with interest (personal loan, car loan, ...).
    case loan

    public var id: String { rawValue }

    public func title(in language: AppLanguage) -> String {
        switch self {
        case .installment: return L10n.text(language, en: "Installment", vi: "Trả góp", zh: "分期付款")
        case .loan: return L10n.text(language, en: "Loan", vi: "Khoản vay", zh: "贷款")
        }
    }
}

/// An installment purchase or loan. The plan itself never counts as spending: each monthly
/// payment is materialized as an ordinary expense `TransactionRecord` (id `"<planID>#<index>"`,
/// `planID`/`planPaymentIndex` set) once its due date arrives, so analytics stay cash-basis.
public struct InstallmentPlanRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: InstallmentKind
    /// Sum of all scheduled payments (storage minor units, i.e. cents; see `CurrencyCode.toStorageMinor`).
    public var totalMinor: Int64
    public var months: Int
    /// `YYYY-MM-DD` of the first payment. Later payments fall on the same day of month,
    /// clamped to the month's length.
    public var firstPaymentDayKey: String
    /// Expense category used for the payment transactions.
    public var category: CategoryID
    public var memberID: String
    public var memberName: String
    public var note: String
    /// Currency the amounts were entered in. Payments are rounded to this currency's smallest
    /// unit (whole dong for VND) so every device computes the identical schedule.
    public var currency: CurrencyCode
    /// Regular monthly payment as quoted by the bank. When set, the first `months - 1`
    /// payments use it and the last payment takes the remainder of `totalMinor`. When `nil`,
    /// the regular payment is `totalMinor / months` rounded half-up.
    public var monthlyPaymentMinor: Int64?
    /// Amount borrowed (loans). `nil` means no interest (principal == total).
    public var principalMinor: Int64?
    /// Expense this plan was converted from (tombstoned on conversion).
    public var sourceTransactionID: String?
    /// Free-text lender, e.g. "DBS", "Trust".
    public var lender: String?
    /// URL that opens the loan in the bank's own app or website.
    public var linkURL: String?
    /// `YYYY-MM-DD` the plan was settled early. Payments due after this day are never
    /// materialized, and the plan counts as completed from that day on.
    public var settledDayKey: String?
    /// Set when the plan is deleted: `true` means the deletion also removed its booked payments,
    /// `false`/`nil` means they stay as ordinary expenses. Synced so every device applies the
    /// same choice to payments it booked or receives later.
    public var deletionRemovesPayments: Bool?
    /// `YYYY-MM-DD` the plan was deleted. Payments due after it are withdrawn on every device
    /// even when booked payments are kept. Falls back to the tombstone's `updatedAt` day.
    public var deletedDayKey: String?
    /// Number of leading payments (indexes `0..<n`) that were already paid before the plan was
    /// added to Tally or are recorded in Tally some other way (e.g. imported from bank emails).
    /// They count as paid for the schedule, progress and debt figures, but the plan never books
    /// them as expenses, so they are not counted twice. `nil`/0 means every due payment is booked
    /// by the plan (the behaviour before this field existed). Clamped to `0...months` when used.
    public var alreadyPaidPaymentCount: Int?
    public var createdAt: Date
    public var updatedAt: Date
    public var isDeleted: Bool

    /// Upper bound on the number of monthly payments (50 years). Single source of truth for
    /// validation in the editor, backup import and CloudKit payloads.
    public static let maxMonths = 600

    /// Upper bound on any plan amount in storage minor units (10 trillion in cents; far above
    /// what the amount keypad accepts). Keeps every schedule, sum and amortization overflow-free.
    public static let maxAmountMinor: Int64 = 1_000_000_000_000_000

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: InstallmentKind = .installment,
        totalMinor: Int64,
        months: Int,
        firstPaymentDayKey: String,
        category: CategoryID = .shopping,
        memberID: String = HouseholdMember.defaultMeID,
        memberName: String = "",
        note: String = "",
        currency: CurrencyCode = .sgd,
        monthlyPaymentMinor: Int64? = nil,
        principalMinor: Int64? = nil,
        sourceTransactionID: String? = nil,
        lender: String? = nil,
        linkURL: String? = nil,
        settledDayKey: String? = nil,
        deletionRemovesPayments: Bool? = nil,
        deletedDayKey: String? = nil,
        alreadyPaidPaymentCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.totalMinor = totalMinor
        self.months = months
        self.firstPaymentDayKey = firstPaymentDayKey
        self.category = category
        self.memberID = memberID
        self.memberName = memberName
        self.note = note
        self.currency = currency
        self.monthlyPaymentMinor = monthlyPaymentMinor
        self.principalMinor = principalMinor
        self.sourceTransactionID = sourceTransactionID
        self.lender = lender
        self.linkURL = linkURL
        self.settledDayKey = settledDayKey
        self.deletionRemovesPayments = deletionRemovesPayments
        self.deletedDayKey = deletedDayKey
        self.alreadyPaidPaymentCount = alreadyPaidPaymentCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
    }

    /// Builds a loan from the figures shown in the bank's app: principal, regular monthly
    /// payment, number of months and first payment date. `totalMinor` defaults to
    /// `monthlyPaymentMinor * months`; pass it explicitly when the final payment differs.
    public static func loan(
        id: String = UUID().uuidString,
        name: String,
        principalMinor: Int64,
        monthlyPaymentMinor: Int64,
        months: Int,
        firstPaymentDayKey: String,
        totalMinor: Int64? = nil,
        category: CategoryID = .bills,
        memberID: String = HouseholdMember.defaultMeID,
        memberName: String = "",
        note: String = "",
        currency: CurrencyCode = .sgd,
        lender: String? = nil,
        linkURL: String? = nil,
        alreadyPaidPaymentCount: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: id,
            name: name,
            kind: .loan,
            totalMinor: totalMinor ?? monthlyPaymentMinor * Int64(max(0, months)),
            months: months,
            firstPaymentDayKey: firstPaymentDayKey,
            category: category,
            memberID: memberID,
            memberName: memberName,
            note: note,
            currency: currency,
            monthlyPaymentMinor: monthlyPaymentMinor,
            principalMinor: principalMinor,
            lender: lender,
            linkURL: linkURL,
            alreadyPaidPaymentCount: alreadyPaidPaymentCount,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: Already-paid payments

    /// `alreadyPaidPaymentCount` clamped to `0...months`.
    public var effectiveAlreadyPaidCount: Int {
        min(max(0, alreadyPaidPaymentCount ?? 0), max(0, months))
    }

    /// `true` when payment `index` counts as paid without being booked by this plan.
    public func isPaidOutsidePlan(index: Int) -> Bool {
        index >= 0 && index < effectiveAlreadyPaidCount
    }

    // MARK: Payment identity

    public static func paymentIDPrefix(planID: String) -> String { "\(planID)#" }

    /// Deterministic payment transaction id so devices syncing over CloudKit converge on the
    /// same record instead of duplicating it.
    public static func paymentTransactionID(planID: String, index: Int) -> String {
        "\(paymentIDPrefix(planID: planID))\(index)"
    }

    /// Id of the plan created by converting transaction `sourceTransactionID`. Deterministic so
    /// converting the same expense on two devices yields revisions of one plan (sharing payment
    /// ids) instead of two plans that double the payments after sync.
    public static func convertedPlanID(sourceTransactionID: String) -> String {
        "conv-\(sourceTransactionID)"
    }

    /// Where converting expense `sourceTransactionID` goes, given the plans this device knows.
    public enum ConversionTarget: Equatable, Sendable {
        /// A live plan already holds a conversion of this expense: reuse it.
        case existing(InstallmentPlanRecord)
        /// Create a plan with this id.
        case new(String)
    }

    /// Walks the deterministic conversion ids of `sourceTransactionID` (`conv-<id>`, then
    /// `conv-<id>-2`, `conv-<id>-3`, ...): the first live plan is reused; past deleted ones a new
    /// plan gets the first free id. Devices that know the same plans pick the same id.
    public static func conversionTarget(
        sourceTransactionID: String,
        existingPlans: [String: InstallmentPlanRecord]
    ) -> ConversionTarget {
        var generation = 1
        while true {
            let base = convertedPlanID(sourceTransactionID: sourceTransactionID)
            let id = generation == 1 ? base : "\(base)-\(generation)"
            guard let plan = existingPlans[id] else { return .new(id) }
            if !plan.isDeleted { return .existing(plan) }
            generation += 1
        }
    }

    // MARK: Validation

    /// `true` when the terms describe a schedule of exactly `months` positive payments in
    /// payable units: months within `1...maxMonths`, a positive total, a valid first payment day,
    /// non-negative optional amounts and no overflow. Records failing this are rejected on save,
    /// skipped on backup import and ignored when they arrive from CloudKit.
    public var hasValidTerms: Bool {
        guard months >= 1, months <= Self.maxMonths,
              totalMinor > 0, totalMinor <= Self.maxAmountMinor,
              DateKey.date(fromDayKey: firstPaymentDayKey) != nil
        else { return false }
        if let monthlyPaymentMinor, !(0...Self.maxAmountMinor).contains(monthlyPaymentMinor) { return false }
        if let principalMinor, !(0...Self.maxAmountMinor).contains(principalMinor) { return false }
        if let alreadyPaidPaymentCount, !(0...months).contains(alreadyPaidPaymentCount) { return false }
        return fullSchedule.count == months
    }

    /// Day of the month the payment at `index` falls due (schedule length not required, so
    /// indexes past a shortened term still resolve). `nil` for a negative index or invalid day.
    public func paymentDayKey(index: Int) -> String? {
        guard index >= 0, index < Self.maxMonths,
              DateKey.date(fromDayKey: firstPaymentDayKey) != nil,
              let ym = DateKey.yearAndMonth(fromMonthKey: DateKey.monthKey(fromDayKey: firstPaymentDayKey))
        else { return nil }
        let monthIndex = (ym.month - 1) + index
        let year = ym.year + monthIndex / 12
        let month = monthIndex % 12 + 1
        let monthKey = DateKey.monthKey(year: year, month: month)
        let day = min(DateKey.dayOfMonth(fromDayKey: firstPaymentDayKey), DateKey.daysInMonth(monthKey))
        return DateKey.dayKey(year: year, month: month, day: day)
    }

    /// Payments due after this day stop belonging to a deleted plan (see `deletedDayKey`).
    public var deletionCutoffDayKey: String {
        deletedDayKey ?? DateKey.dayKey(from: updatedAt)
    }

    // MARK: Schedule

    /// Smallest payable step in storage minor units (storage is always cents, so whole-dong
    /// currencies such as VND step by 100).
    public static func roundingStep(for currency: CurrencyCode) -> Int64 {
        currency.isZeroDecimal ? 100 : 1
    }

    /// Full payment schedule ignoring early settlement. Empty for `months < 1`, a non-positive
    /// total or an invalid first payment day.
    public var fullSchedule: [InstallmentPayment] {
        guard months >= 1, months <= Self.maxMonths, totalMinor > 0,
              DateKey.date(fromDayKey: firstPaymentDayKey) != nil
        else { return [] }

        let amounts = Self.paymentAmounts(
            totalMinor: totalMinor,
            months: months,
            regularMinor: monthlyPaymentMinor,
            step: Self.roundingStep(for: currency)
        )
        return amounts.enumerated().compactMap { index, amount in
            guard let dayKey = paymentDayKey(index: index) else { return nil }
            return InstallmentPayment(planID: id, index: index, dayKey: dayKey, amountMinor: amount)
        }
    }

    /// Payments that are actually owed: the full schedule cut off at `settledDayKey`.
    public var schedule: [InstallmentPayment] {
        let all = fullSchedule
        guard let settledDayKey else { return all }
        return all.filter { $0.dayKey <= settledDayKey }
    }

    /// Splits `totalMinor` into `months` payments: the regular payment for the first
    /// `months - 1` and the remainder last (515.00 / 12 -> 42.92 x 11 + 42.88). An explicit
    /// `regularMinor` is rounded half-up to `step` first. Every returned payment is positive;
    /// terms that cannot produce `months` positive payments in payable units (e.g. ₫5 over 12
    /// months), or more than `maxMonths` payments, return `[]`. Never traps on overflow.
    public static func paymentAmounts(
        totalMinor: Int64,
        months: Int,
        regularMinor: Int64? = nil,
        step: Int64 = 1
    ) -> [Int64] {
        guard months >= 1, months <= maxMonths, totalMinor > 0 else { return [] }
        let step = max(1, step)
        if months == 1 { return [totalMinor] }
        let count = Int64(months)
        let others = count - 1

        var regular: Int64 = 0
        if let regularMinor, regularMinor > 0 {
            let rounded = roundHalfUp(regularMinor, step: step)
            let (product, overflow) = rounded.multipliedReportingOverflow(by: others)
            if rounded > 0, !overflow, product < totalMinor { regular = rounded }
        }
        if regular == 0 {
            // Half-up rounding of total / months to a multiple of `step`, without overflow.
            let (divisor, overflow) = count.multipliedReportingOverflow(by: step)
            guard !overflow else { return [] }
            let quotient = totalMinor / divisor
            let remainder = totalMinor % divisor
            regular = quotient * step
            if remainder >= divisor - remainder { regular += step }
            // Rounding up must never push the last payment to zero or below.
            let (product, productOverflow) = regular.multipliedReportingOverflow(by: others)
            if productOverflow || product >= totalMinor {
                regular = quotient * step
            }
        }
        guard regular > 0 else { return [] }
        let last = totalMinor - regular * others
        guard last > 0 else { return [] }
        return Array(repeating: regular, count: months - 1) + [last]
    }

    /// `value` rounded half-up to a multiple of `step` (saturating instead of overflowing).
    public static func roundHalfUp(_ value: Int64, step: Int64) -> Int64 {
        let step = max(1, step)
        let quotient = value / step
        let remainder = value % step
        let base = quotient * step
        guard remainder > 0, remainder >= step - remainder else { return base }
        let (rounded, overflow) = base.addingReportingOverflow(step)
        return overflow ? base : rounded
    }

    /// The expense transaction a schedule entry materializes into: booked by the schedule of
    /// this plan revision (`updatedAt`).
    public func paymentTransaction(for payment: InstallmentPayment) -> TransactionRecord {
        let content = scheduledContent(dayKey: payment.dayKey, amountMinor: payment.amountMinor, isDeleted: false)
        return Self.paymentRecord(planID: id, index: payment.index)
            .applying(PlanPaymentState(schedule: PlanPaymentScheduleWrite(planRevision: updatedAt, content: content)))
    }

    /// Content this plan revision gives a payment (name, category, member and note from the plan).
    public func scheduledContent(dayKey: String, amountMinor: Int64, isDeleted: Bool) -> PlanPaymentContent {
        PlanPaymentContent(
            name: name,
            amountMinor: amountMinor,
            type: .expense,
            category: category,
            dayKey: dayKey,
            createdAt: DateKey.date(fromDayKey: dayKey) ?? createdAt,
            note: note,
            source: .manual,
            rawSourceText: nil,
            memberID: memberID,
            memberName: memberName,
            needsReview: false,
            isDeleted: isDeleted
        )
    }

    /// Empty payment record carrying only identity (`id`, `planID`, `planPaymentIndex`); the
    /// visible fields are filled in by `applying(_:)`.
    public static func paymentRecord(planID: String, index: Int) -> TransactionRecord {
        TransactionRecord(
            id: paymentTransactionID(planID: planID, index: index),
            name: "",
            amountMinor: 0,
            type: .expense,
            category: .other,
            dayKey: "",
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            updatedAt: Date(timeIntervalSinceReferenceDate: 0),
            planID: planID,
            planPaymentIndex: index
        )
    }

    /// Schedule index encoded in a payment transaction id `"<planID>#<index>"`.
    public static func paymentIndex(transactionID: String, planID: String) -> Int? {
        let prefix = paymentIDPrefix(planID: planID)
        guard transactionID.hasPrefix(prefix) else { return nil }
        return Int(transactionID.dropFirst(prefix.count))
    }

    // MARK: Interest & amortization

    /// Principal used for amortization (falls back to the total, i.e. 0% interest).
    public var effectivePrincipalMinor: Int64 {
        guard let principalMinor, principalMinor > 0 else { return totalMinor }
        return min(principalMinor, totalMinor)
    }

    /// Total interest over the full (unsettled) schedule: total - principal, never negative.
    public var totalInterestMinor: Int64 {
        max(0, totalMinor - effectivePrincipalMinor)
    }

    /// Monthly rate `r` solving `principal = sum(payment_i / (1 + r)^(i + 1))` for the full
    /// schedule. 0 when there is no interest.
    public var effectiveMonthlyRate: Double {
        InstallmentMath.solveMonthlyRate(
            principalMinor: effectivePrincipalMinor,
            payments: fullSchedule.map(\.amountMinor)
        )
    }

    /// Nominal annual rate on the reducing balance (`12 x monthly`), the figure Singapore banks
    /// publish as "EIR". 0.0542 means 5.42% p.a.
    public var effectiveAnnualRate: Double { effectiveMonthlyRate * 12 }

    /// Annual rate with monthly compounding: `(1 + r)^12 - 1`.
    public var compoundedAnnualRate: Double { pow(1 + effectiveMonthlyRate, 12) - 1 }

    /// Per-payment interest/principal split over the full schedule. Integer minor units; the
    /// last row closes the outstanding principal at exactly 0, so interest sums to
    /// `totalInterestMinor` and principal sums to `effectivePrincipalMinor`.
    public var amortizationSchedule: [AmortizationRow] {
        let payments = fullSchedule
        guard !payments.isEmpty else { return [] }
        let rate = effectiveMonthlyRate
        var outstanding = effectivePrincipalMinor
        var rows: [AmortizationRow] = []
        rows.reserveCapacity(payments.count)
        for (offset, payment) in payments.enumerated() {
            let isLast = offset == payments.count - 1
            var interest: Int64
            var principalPart: Int64
            if isLast {
                principalPart = outstanding
                interest = payment.amountMinor - principalPart
            } else {
                interest = rate > 0 ? Int64((Double(outstanding) * rate).rounded()) : 0
                interest = min(max(0, interest), payment.amountMinor)
                principalPart = min(payment.amountMinor - interest, outstanding)
                interest = payment.amountMinor - principalPart
            }
            outstanding -= principalPart
            rows.append(AmortizationRow(
                index: payment.index,
                dayKey: payment.dayKey,
                paymentMinor: payment.amountMinor,
                interestMinor: interest,
                principalMinor: principalPart,
                outstandingPrincipalMinor: outstanding
            ))
        }
        // Per-row interest rounding can leave more principal than the last payment covers
        // (e.g. 240 x 32.12 on 6,270.21 ends at -0.03 interest). Move the deficit back onto
        // the latest rows' principal, so every row keeps non-negative interest while payment,
        // principal and interest totals stay exact.
        if var deficit = rows.last.map({ -$0.interestMinor }), deficit > 0 {
            for offset in stride(from: rows.count - 2, through: 0, by: -1) where deficit > 0 {
                let take = min(rows[offset].interestMinor, deficit)
                rows[offset].interestMinor -= take
                rows[offset].principalMinor += take
                deficit -= take
            }
            var remaining = effectivePrincipalMinor
            for offset in rows.indices {
                if offset == rows.count - 1 {
                    rows[offset].principalMinor = remaining
                    rows[offset].interestMinor = rows[offset].paymentMinor - remaining
                }
                remaining -= rows[offset].principalMinor
                rows[offset].outstandingPrincipalMinor = remaining
            }
        }
        return rows
    }

    // MARK: Progress

    public func progress(todayKey: String) -> InstallmentProgress {
        InstallmentProgress(plan: self, todayKey: todayKey)
    }

    /// Payments falling in `monthKey` across non-deleted plans (settled tails excluded).
    public static func committedMinor(inMonth monthKey: String, plans: [InstallmentPlanRecord]) -> Int64 {
        plans.filter { !$0.isDeleted }.reduce(Int64(0)) { sum, plan in
            sum + plan.schedule.filter { $0.monthKey == monthKey }.reduce(Int64(0)) { $0 + $1.amountMinor }
        }
    }

    /// Scheduled payments still to come after `todayKey` across non-deleted plans.
    public static func remainingDebtMinor(plans: [InstallmentPlanRecord], todayKey: String) -> Int64 {
        plans.filter { !$0.isDeleted }.reduce(Int64(0)) { $0 + $1.progress(todayKey: todayKey).remainingMinor }
    }

    /// Principal still owed after `todayKey` across non-deleted plans (excludes future interest).
    public static func outstandingPrincipalMinor(plans: [InstallmentPlanRecord], todayKey: String) -> Int64 {
        plans.filter { !$0.isDeleted }.reduce(Int64(0)) { $0 + $1.progress(todayKey: todayKey).outstandingPrincipalMinor }
    }
}

public struct InstallmentPayment: Codable, Hashable, Sendable, Identifiable {
    public var planID: String
    /// 0-based position in the schedule.
    public var index: Int
    public var dayKey: String
    public var amountMinor: Int64

    public init(planID: String, index: Int, dayKey: String, amountMinor: Int64) {
        self.planID = planID
        self.index = index
        self.dayKey = dayKey
        self.amountMinor = amountMinor
    }

    public var id: String { transactionID }
    public var transactionID: String { InstallmentPlanRecord.paymentTransactionID(planID: planID, index: index) }
    public var monthKey: String { DateKey.monthKey(fromDayKey: dayKey) }
}

public struct AmortizationRow: Hashable, Sendable, Identifiable {
    public var index: Int
    public var dayKey: String
    public var paymentMinor: Int64
    public var interestMinor: Int64
    public var principalMinor: Int64
    /// Principal still owed after this payment.
    public var outstandingPrincipalMinor: Int64

    public var id: Int { index }
}

/// Schedule-based progress of a plan as of `todayKey` (payments with `dayKey <= todayKey`, and the
/// plan's already-paid leading payments, count as paid). For installments without interest the
/// interest fields are 0.
public struct InstallmentProgress: Hashable, Sendable {
    /// Payments owed (after cutting off at settlement).
    public let paymentCount: Int
    public let paidCount: Int
    public let paidMinor: Int64
    /// Scheduled payments still to come. 0 once completed or settled.
    public let remainingMinor: Int64
    public let nextPayment: InstallmentPayment?
    public let isCompleted: Bool
    /// `true` once `settledDayKey <= todayKey`.
    public let isSettled: Bool
    public let principalMinor: Int64
    /// Principal still owed after the paid payments (0 when completed or settled).
    public let outstandingPrincipalMinor: Int64
    public let interestPaidMinor: Int64
    /// Interest still to pay under the schedule (0 when completed or settled).
    public let interestRemainingMinor: Int64
    /// Principal paid off in the early settlement (outstanding principal on the settlement
    /// day). `nil` unless settled.
    public let settlementPrincipalMinor: Int64?
    /// Interest of the full schedule not paid because of early settlement. 0 unless settled.
    public let interestSavedMinor: Int64

    public var nextPaymentDayKey: String? { nextPayment?.dayKey }
    public var nextPaymentMinor: Int64? { nextPayment?.amountMinor }
    public var fraction: Double {
        guard paymentCount > 0 else { return isCompleted ? 1 : 0 }
        return isSettled ? 1 : Double(paidCount) / Double(paymentCount)
    }

    public init(plan: InstallmentPlanRecord, todayKey: String) {
        let owed = plan.schedule
        let rows = plan.amortizationSchedule
        // Payments due by today, plus the leading payments already paid outside the plan (which
        // may run ahead of the calendar). The schedule is in index order, so paid is a prefix.
        let dueCount = owed.filter { $0.dayKey <= todayKey }.count
        let paidPrefix = max(dueCount, min(plan.effectiveAlreadyPaidCount, owed.count))
        let paid = Array(owed.prefix(paidPrefix))
        let settled = plan.settledDayKey.map { $0 <= todayKey } ?? false

        paymentCount = owed.count
        paidCount = paid.count
        paidMinor = paid.reduce(Int64(0)) { $0 + $1.amountMinor }
        principalMinor = plan.effectivePrincipalMinor

        let paidRows = rows.prefix(paid.count)
        interestPaidMinor = paidRows.reduce(Int64(0)) { $0 + $1.interestMinor }
        let outstandingAfterPaid = paidRows.last?.outstandingPrincipalMinor ?? plan.effectivePrincipalMinor

        if settled {
            remainingMinor = 0
            nextPayment = nil
            isCompleted = true
            isSettled = true
            outstandingPrincipalMinor = 0
            interestRemainingMinor = 0
            settlementPrincipalMinor = rows.isEmpty ? 0 : outstandingAfterPaid
            interestSavedMinor = max(0, plan.totalInterestMinor - interestPaidMinor)
        } else {
            let upcoming = Array(owed.dropFirst(paid.count))
            remainingMinor = upcoming.reduce(Int64(0)) { $0 + $1.amountMinor }
            nextPayment = upcoming.first
            isCompleted = !owed.isEmpty && upcoming.isEmpty
            isSettled = false
            if isCompleted && plan.settledDayKey == nil {
                outstandingPrincipalMinor = 0
                interestRemainingMinor = 0
            } else {
                // A future settlement still owes the scheduled payments up to it.
                outstandingPrincipalMinor = rows.isEmpty ? 0 : outstandingAfterPaid
                interestRemainingMinor = rows.prefix(owed.count).dropFirst(paid.count)
                    .reduce(Int64(0)) { $0 + $1.interestMinor }
            }
            settlementPrincipalMinor = nil
            interestSavedMinor = 0
        }
    }
}

// MARK: - Rate solving

public enum InstallmentMath {
    /// Present value of `payments` (paid at the end of months 1...n) at monthly rate `rate`.
    public static func presentValue(payments: [Int64], rate: Double) -> Double {
        var discount = 1.0
        var pv = 0.0
        for payment in payments {
            discount /= (1 + rate)
            pv += Double(payment) * discount
        }
        return pv
    }

    /// Solves the annuity equation `principal = PV(payments, r)` for the monthly rate `r` by
    /// bisection. Returns 0 when the payments do not exceed the principal.
    public static func solveMonthlyRate(principalMinor: Int64, payments: [Int64]) -> Double {
        let total = payments.reduce(Int64(0), +)
        guard principalMinor > 0, !payments.isEmpty, total > principalMinor else { return 0 }
        let target = Double(principalMinor)
        var low = 0.0
        var high = 0.05
        // PV decreases monotonically towards 0 as the rate rises; widen until PV(high) is at or
        // below the principal so [low, high] brackets the root. PV(0) = total > principal, and
        // total <= Int64.max, so a rate of ~1e19 always brackets.
        while presentValue(payments: payments, rate: high) > target {
            low = high
            high *= 2
            guard high.isFinite, high < 1e20 else { return low }
        }
        for _ in 0..<400 {
            let mid = (low + high) / 2
            if presentValue(payments: payments, rate: mid) > target {
                low = mid
            } else {
                high = mid
            }
            if high - low <= 1e-13 * max(1, high) { break }
        }
        return (low + high) / 2
    }
}

// MARK: - Installment hint

/// Heuristic that flags transactions that look like an instalment purchase so the UI can
/// suggest converting them into a plan (e.g. DBS merchant "SHOPEEPAY SG IPP").
public enum InstallmentHint {
    public static func looksLikeInstallment(_ transaction: TransactionRecord) -> Bool {
        guard transaction.type == .expense, !transaction.isPlanPayment else { return false }
        return looksLikeInstallment(name: transaction.name, rawSourceText: transaction.rawSourceText)
    }

    public static func looksLikeInstallment(name: String, rawSourceText: String? = nil) -> Bool {
        matches(name) || (rawSourceText.map(matches) ?? false)
    }

    private static func matches(_ text: String) -> Bool {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d")
            .lowercased()
        if folded.contains("instalment") || folded.contains("installment") { return true }
        let words = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let tokens = String(words).split(separator: " ").map(String.init)
        if tokens.contains("ipp") { return true }
        // Vietnamese "trả góp" (folded to "tra gop"), also written "tragop".
        if tokens.contains("tragop") { return true }
        for (a, b) in zip(tokens, tokens.dropFirst()) where a == "tra" && b == "gop" {
            return true
        }
        return false
    }
}
