import Foundation
import TallyCore

// MARK: - Plan editor draft (validation + record building)

/// Everything the plan editor collects, in storage minor units, with pure validation and record
/// building so the rules are unit-tested rather than living inside a SwiftUI view.
public struct InstallmentPlanDraft: Equatable, Sendable {
    public enum Issue: Equatable, Sendable {
        case missingName
        /// Total (installment) or amount borrowed (loan) is zero or negative.
        case invalidAmount
        /// Loans only: no monthly payment entered.
        case missingMonthlyPayment
        case invalidMonths
        case invalidFirstPaymentDay
        /// Loans only: `monthly × months` is below the amount borrowed. `shortfallMinor` is how
        /// much is missing.
        case paymentsBelowPrincipal(shortfallMinor: Int64)
        /// The amount cannot be split into `months` positive payments in the currency's smallest
        /// payable unit (e.g. ₫5 over 12 months). `minimumMinor` is the smallest amount that can.
        case amountTooSmallForMonths(minimumMinor: Int64)
        /// More payments marked as already paid than the plan has (`maxCount` = months), or a
        /// negative count.
        case alreadyPaidOutOfRange(maxCount: Int)
    }

    public static let maxMonths = InstallmentPlanRecord.maxMonths

    public var kind: InstallmentKind
    public var name: String
    public var lender: String
    /// Total price (installment) or amount borrowed (loan).
    public var amountMinor: Int64
    /// Regular monthly payment (loans only; ignored for installments).
    public var monthlyPaymentMinor: Int64
    public var months: Int?
    public var firstPaymentDayKey: String
    public var category: CategoryID
    public var memberID: String
    public var memberName: String
    /// Raw text typed into the link field (loans only).
    public var linkText: String
    public var note: String
    public var currency: CurrencyCode
    /// Leading payments already paid before the plan was added (or recorded in Tally another
    /// way); counted as paid but never booked as expenses by the plan. See
    /// `InstallmentPlanRecord.alreadyPaidPaymentCount`.
    public var alreadyPaidCount: Int

    public init(
        kind: InstallmentKind = .installment,
        name: String = "",
        lender: String = "",
        amountMinor: Int64 = 0,
        monthlyPaymentMinor: Int64 = 0,
        months: Int? = nil,
        firstPaymentDayKey: String,
        category: CategoryID = .shopping,
        memberID: String = HouseholdMember.defaultMeID,
        memberName: String = "",
        linkText: String = "",
        note: String = "",
        currency: CurrencyCode = .sgd,
        alreadyPaidCount: Int = 0
    ) {
        self.kind = kind
        self.name = name
        self.lender = lender
        self.amountMinor = amountMinor
        self.monthlyPaymentMinor = monthlyPaymentMinor
        self.months = months
        self.firstPaymentDayKey = firstPaymentDayKey
        self.category = category
        self.memberID = memberID
        self.memberName = memberName
        self.linkText = linkText
        self.note = note
        self.currency = currency
        self.alreadyPaidCount = alreadyPaidCount
    }

    /// Loads an existing plan into editable form.
    public init(plan: InstallmentPlanRecord) {
        let regular = plan.monthlyPaymentMinor ?? plan.fullSchedule.first?.amountMinor ?? 0
        self.init(
            kind: plan.kind,
            name: plan.name,
            lender: plan.lender ?? "",
            amountMinor: plan.kind == .loan ? plan.effectivePrincipalMinor : plan.totalMinor,
            monthlyPaymentMinor: plan.kind == .loan ? regular : 0,
            months: plan.months,
            firstPaymentDayKey: plan.firstPaymentDayKey,
            category: plan.category,
            memberID: plan.memberID,
            memberName: plan.memberName,
            linkText: plan.linkURL ?? "",
            note: plan.note,
            currency: plan.currency,
            alreadyPaidCount: max(0, plan.alreadyPaidPaymentCount ?? 0)
        )
    }

    // MARK: Validation

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var monthsAreValid: Bool {
        guard let months else { return false }
        return months >= 1 && months <= Self.maxMonths
    }

    /// Monthly payment rounded half-up to the currency's payable unit (whole đồng for VND).
    public var roundedMonthlyPaymentMinor: Int64 {
        InstallmentPlanRecord.roundHalfUp(monthlyPaymentMinor, step: InstallmentPlanRecord.roundingStep(for: currency))
    }

    /// Sum of all payments the loan fields describe (`monthly × months`, monthly rounded to the
    /// payable unit). 0 when months are invalid or the product overflows.
    public var loanTotalMinor: Int64 {
        guard monthsAreValid, let months else { return 0 }
        let (total, overflow) = roundedMonthlyPaymentMinor.multipliedReportingOverflow(by: Int64(months))
        return overflow ? 0 : total
    }

    private var amountIsInRange: Bool {
        amountMinor > 0 && amountMinor <= InstallmentPlanRecord.maxAmountMinor
    }

    public var issues: [Issue] {
        var result: [Issue] = []
        if trimmedName.isEmpty { result.append(.missingName) }
        if !amountIsInRange { result.append(.invalidAmount) }
        if !monthsAreValid { result.append(.invalidMonths) }
        if DateKey.date(fromDayKey: firstPaymentDayKey) == nil { result.append(.invalidFirstPaymentDay) }
        switch kind {
        case .loan:
            if roundedMonthlyPaymentMinor <= 0 || roundedMonthlyPaymentMinor > InstallmentPlanRecord.maxAmountMinor {
                result.append(.missingMonthlyPayment)
            } else if monthsAreValid, amountIsInRange, loanTotalMinor < amountMinor {
                result.append(.paymentsBelowPrincipal(shortfallMinor: amountMinor - loanTotalMinor))
            }
        case .installment:
            if monthsAreValid, amountIsInRange, let months {
                let step = InstallmentPlanRecord.roundingStep(for: currency)
                if InstallmentPlanRecord.paymentAmounts(totalMinor: amountMinor, months: months, step: step).isEmpty {
                    result.append(.amountTooSmallForMonths(minimumMinor: step * Int64(months)))
                }
            }
        }
        if alreadyPaidCount < 0 || (monthsAreValid && alreadyPaidCount > (months ?? 0)) {
            result.append(.alreadyPaidOutOfRange(maxCount: monthsAreValid ? (months ?? 0) : 0))
        }
        // Defensive: whatever the fields say, never save terms that cannot build a schedule.
        if result.isEmpty, buildRecord(existing: nil, id: "draft-check", now: Date(timeIntervalSince1970: 0)).hasValidTerms == false {
            result.append(.invalidAmount)
        }
        return result
    }

    public var isValid: Bool { issues.isEmpty }

    /// `true` when the first payment falls on or before `todayKey`, i.e. the plan has already
    /// started and some payments may have been paid before it was added to Tally.
    public func startsOnOrBefore(_ todayKey: String) -> Bool {
        DateKey.date(fromDayKey: firstPaymentDayKey) != nil && firstPaymentDayKey <= todayKey
    }

    /// Scheduled payments due on or before `todayKey` under these terms (0 while invalid).
    public func duePaymentCount(todayKey: String) -> Int {
        guard let record = previewRecord() else { return 0 }
        return record.fullSchedule.filter { $0.dayKey <= todayKey }.count
    }

    /// `true` when the link field has text that is not an openable link (it is dropped on save).
    public var linkIsUnrecognized: Bool {
        guard kind == .loan else { return false }
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && InstallmentLink.normalized(trimmed) == nil
    }

    // MARK: Records

    /// Transient plan used to show effective rate / interest live while typing. `nil` until the
    /// amount, months and (for loans) payment are usable. Never persisted.
    public func previewRecord() -> InstallmentPlanRecord? {
        guard amountIsInRange, monthsAreValid,
              DateKey.date(fromDayKey: firstPaymentDayKey) != nil
        else { return nil }
        if kind == .loan, roundedMonthlyPaymentMinor <= 0 { return nil }
        let record = buildRecord(existing: nil, id: "draft-preview", now: Date(timeIntervalSince1970: 0))
        return record.hasValidTerms ? record : nil
    }

    /// The record to save, or `nil` while the draft is invalid. Editing keeps the plan's id,
    /// creation date, early-settlement day and source transaction.
    public func makeRecord(existing: InstallmentPlanRecord? = nil, now: Date = Date()) -> InstallmentPlanRecord? {
        guard isValid else { return nil }
        let record = buildRecord(existing: existing, id: existing?.id ?? UUID().uuidString, now: now)
        return record.hasValidTerms ? record : nil
    }

    private func buildRecord(existing: InstallmentPlanRecord?, id: String, now: Date) -> InstallmentPlanRecord {
        let months = months ?? 0
        var record = existing ?? InstallmentPlanRecord(
            id: id,
            name: trimmedName,
            kind: kind,
            totalMinor: amountMinor,
            months: months,
            firstPaymentDayKey: firstPaymentDayKey,
            currency: currency,
            createdAt: now,
            updatedAt: now
        )
        record.kind = kind
        record.name = trimmedName
        record.months = months
        record.firstPaymentDayKey = firstPaymentDayKey
        record.category = category
        record.memberID = memberID
        record.memberName = memberName
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.currency = currency
        record.alreadyPaidPaymentCount = alreadyPaidCount > 0 ? alreadyPaidCount : nil
        record.updatedAt = now

        switch kind {
        case .installment:
            let unchanged = existing.map { $0.totalMinor == amountMinor && $0.months == months } ?? false
            record.totalMinor = amountMinor
            if !unchanged {
                // Bank-quoted regular payment / principal only describe the old schedule.
                record.monthlyPaymentMinor = nil
                record.principalMinor = nil
            }
            record.lender = nil
            record.linkURL = nil
        case .loan:
            // Keep an explicit final-payment total (bank rounding) while the schedule inputs
            // are untouched; otherwise the schedule is exactly `monthly × months`.
            let monthly = roundedMonthlyPaymentMinor
            let untouched = existing.map {
                $0.kind == .loan
                    && $0.months == months
                    && ($0.monthlyPaymentMinor ?? $0.fullSchedule.first?.amountMinor) == monthly
            } ?? false
            record.totalMinor = untouched ? (existing?.totalMinor ?? loanTotalMinor) : loanTotalMinor
            record.monthlyPaymentMinor = monthly
            record.principalMinor = amountMinor
            let trimmedLender = lender.trimmingCharacters(in: .whitespacesAndNewlines)
            record.lender = trimmedLender.isEmpty ? nil : trimmedLender
            record.linkURL = InstallmentLink.normalized(linkText)
        }
        return record
    }
}

// MARK: - Bank-app link

public enum InstallmentLink {
    /// Schemes that must never be opened from a stored link.
    private static let blockedSchemes: Set<String> = ["javascript", "data", "file", "vbscript", "about", "blob"]

    /// Returns a storable, openable link: http(s) with a host, or a custom app scheme
    /// (`dbsdigibank://`). Bare domains such as `dbs.com.sg/loans` get `https://`. Returns `nil`
    /// for empty, unparseable or dangerous input.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        var candidate = trimmed
        if scheme(of: candidate) == nil {
            // "dbs.com.sg/loans" -> https; anything without a dot is not a link.
            guard candidate.contains("."), !candidate.hasPrefix("."), !candidate.hasPrefix("/") else { return nil }
            candidate = "https://" + candidate
        }
        guard let scheme = scheme(of: candidate), !blockedSchemes.contains(scheme),
              let components = URLComponents(string: candidate),
              components.url != nil
        else { return nil }

        if scheme == "http" || scheme == "https" {
            guard let host = components.host, !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
        }
        return candidate
    }

    /// URL to hand to `openURL`; `nil` when the stored string is not openable.
    public static func url(from text: String?) -> URL? {
        guard let text, let normalized = normalized(text) else { return nil }
        return URL(string: normalized)
    }

    private static func scheme(of text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = String(text[text.startIndex..<colon])
        guard let first = scheme.unicodeScalars.first,
              CharacterSet.letters.contains(first), first.isASCII,
              scheme.unicodeScalars.allSatisfy({
                  $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "+-.".unicodeScalars.contains($0))
              })
        else { return nil }
        // "host:8080/path" without "//" is a port, not a scheme.
        let rest = text[text.index(after: colon)...]
        if !rest.hasPrefix("//"), rest.first?.isNumber == true { return nil }
        return scheme.lowercased()
    }
}

// MARK: - Rate formatting

public enum InstallmentRateFormat {
    /// `0.0542` -> "5.42%" ("5,42%" in Vietnamese). Zero shows as "0%".
    public static func percent(_ rate: Double, language: AppLanguage) -> String {
        guard rate.isFinite, rate > 0 else { return "0%" }
        var text = String(format: "%.2f", rate * 100)
        if language.resolved == .vietnamese {
            text = text.replacingOccurrences(of: ".", with: ",")
        }
        return text + "%"
    }
}

// MARK: - Commitments overview (list grouping + summary)

public struct CommitmentsOverview: Sendable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let plan: InstallmentPlanRecord
        public let progress: InstallmentProgress
        public var id: String { plan.id }
    }

    /// Plans still being paid, soonest next payment first.
    public let active: [Entry]
    /// Fully paid or settled plans, most recently finished first.
    public let completed: [Entry]
    /// Payments falling in the current calendar month across active plans.
    public let committedThisMonthMinor: Int64
    /// Scheduled payments still to come across active plans.
    public let remainingDebtMinor: Int64
    /// The soonest upcoming payment across active plans.
    public let nextPayment: (plan: InstallmentPlanRecord, payment: InstallmentPayment)?

    public init(plans: [InstallmentPlanRecord], todayKey: String) {
        let live = plans.filter { !$0.isDeleted }
        let entries = live.map { Entry(plan: $0, progress: $0.progress(todayKey: todayKey)) }

        let open = entries.filter { !$0.progress.isCompleted }
        active = open.sorted { lhs, rhs in
            switch (lhs.progress.nextPaymentDayKey, rhs.progress.nextPaymentDayKey) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.plan.name.localizedCaseInsensitiveCompare(rhs.plan.name) == .orderedAscending
            }
        }
        completed = entries.filter { $0.progress.isCompleted }.sorted {
            Self.finishDayKey($0.plan) > Self.finishDayKey($1.plan)
        }

        let openPlans = open.map(\.plan)
        committedThisMonthMinor = InstallmentPlanRecord.committedMinor(
            inMonth: DateKey.monthKey(fromDayKey: todayKey),
            plans: openPlans
        )
        remainingDebtMinor = open.reduce(Int64(0)) { $0 + $1.progress.remainingMinor }

        if let soonest = active.first(where: { $0.progress.nextPayment != nil }),
           let payment = soonest.progress.nextPayment {
            nextPayment = (soonest.plan, payment)
        } else {
            nextPayment = nil
        }
    }

    public var isEmpty: Bool { active.isEmpty && completed.isEmpty }

    private static func finishDayKey(_ plan: InstallmentPlanRecord) -> String {
        plan.settledDayKey ?? plan.schedule.last?.dayKey ?? plan.firstPaymentDayKey
    }
}

// MARK: - Early settlement preview

public struct InstallmentSettlementPreview: Hashable, Sendable {
    /// Principal still owed on the settlement day: what the user would pay to close the plan.
    public let payoffPrincipalMinor: Int64
    /// Interest of the full schedule that is never paid. 0 for interest-free installments.
    public let interestSavedMinor: Int64
    /// Scheduled payments after the settlement day that are cancelled.
    public let cancelledPaymentCount: Int
    public let cancelledPaymentsMinor: Int64
    /// Cancelled payments already booked as expenses (due on or before today); settling removes them.
    public let bookedPaymentsRemovedCount: Int

    public init(plan: InstallmentPlanRecord, settleDayKey: String, todayKey: String) {
        var settled = plan
        settled.settledDayKey = settleDayKey
        let progress = InstallmentProgress(plan: settled, todayKey: settleDayKey)
        let cancelled = plan.fullSchedule.filter { $0.dayKey > settleDayKey }

        payoffPrincipalMinor = progress.settlementPrincipalMinor ?? 0
        interestSavedMinor = progress.interestSavedMinor
        cancelledPaymentCount = cancelled.count
        cancelledPaymentsMinor = cancelled.reduce(Int64(0)) { $0 + $1.amountMinor }
        bookedPaymentsRemovedCount = cancelled.filter { $0.dayKey <= todayKey && !plan.isPaidOutsidePlan(index: $0.index) }.count
    }
}

// MARK: - Schedule rows for the detail screen

public struct InstallmentScheduleRow: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case paid
        /// Counted as paid but not booked as an expense by this plan (paid before the plan was
        /// added to Tally, or recorded in Tally another way).
        case paidOutsidePlan
        case upcoming
        /// After an early settlement: never owed.
        case cancelled
    }

    public let index: Int
    public let dayKey: String
    public let paymentMinor: Int64
    /// Loans only (`nil` for plain installments).
    public let interestMinor: Int64?
    public let principalMinor: Int64?
    public let outstandingPrincipalMinor: Int64?
    public let state: State
    public var id: Int { index }

    /// Full schedule with each row's state as of `todayKey`. Loans (or any plan with interest)
    /// carry the interest/principal split from the amortization schedule.
    public static func rows(for plan: InstallmentPlanRecord, todayKey: String) -> [InstallmentScheduleRow] {
        let hasInterest = plan.totalInterestMinor > 0
        let amortization = hasInterest ? plan.amortizationSchedule : []
        return plan.fullSchedule.enumerated().map { offset, payment in
            let state: State
            if let settled = plan.settledDayKey, payment.dayKey > settled {
                state = .cancelled
            } else if plan.isPaidOutsidePlan(index: payment.index) {
                state = .paidOutsidePlan
            } else if payment.dayKey <= todayKey {
                state = .paid
            } else {
                state = .upcoming
            }
            let row = amortization.indices.contains(offset) ? amortization[offset] : nil
            return InstallmentScheduleRow(
                index: payment.index,
                dayKey: payment.dayKey,
                paymentMinor: payment.amountMinor,
                interestMinor: row?.interestMinor,
                principalMinor: row?.principalMinor,
                outstandingPrincipalMinor: row?.outstandingPrincipalMinor,
                state: state
            )
        }
    }
}
