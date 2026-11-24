import ClaudeKit
import Foundation
import TallyCore

// MARK: - Plan tool inputs

extension AssistantCommand {
    /// Plan fields as the model sent them (amounts in major units of the household currency).
    /// `nil` means "not given": on create the draft's validation reports what is missing, on
    /// update the plan keeps its current value.
    public struct PlanFields: Equatable, Sendable {
        public var kind: InstallmentKind?
        public var name: String?
        /// Total price (installment) or amount borrowed (loan).
        public var amountMajor: Double?
        /// Regular monthly payment (loans).
        public var monthlyPaymentMajor: Double?
        public var months: Int?
        public var firstPaymentDayKey: String?
        public var category: CategoryID?
        public var memberHint: String?
        public var lender: String?
        public var link: String?
        public var note: String?
        public var alreadyPaidPayments: Int?
        /// `true` when every payment due so far is already recorded (or paid outside Tally): code
        /// counts them from the schedule instead of the model doing the date arithmetic.
        public var allDuePaymentsAlreadyPaid: Bool?

        public init(
            kind: InstallmentKind? = nil,
            name: String? = nil,
            amountMajor: Double? = nil,
            monthlyPaymentMajor: Double? = nil,
            months: Int? = nil,
            firstPaymentDayKey: String? = nil,
            category: CategoryID? = nil,
            memberHint: String? = nil,
            lender: String? = nil,
            link: String? = nil,
            note: String? = nil,
            alreadyPaidPayments: Int? = nil,
            allDuePaymentsAlreadyPaid: Bool? = nil
        ) {
            self.kind = kind
            self.name = name
            self.amountMajor = amountMajor
            self.monthlyPaymentMajor = monthlyPaymentMajor
            self.months = months
            self.firstPaymentDayKey = firstPaymentDayKey
            self.category = category
            self.memberHint = memberHint
            self.lender = lender
            self.link = link
            self.note = note
            self.alreadyPaidPayments = alreadyPaidPayments
            self.allDuePaymentsAlreadyPaid = allDuePaymentsAlreadyPaid
        }
    }
}

// MARK: - Tool definitions

extension AssistantToolCatalog {
    public static let createPlanName = "create_installment_plan"
    public static let convertTransactionToPlanName = "convert_transaction_to_installment"
    public static let updatePlanName = "update_installment_plan"
    public static let settlePlanName = "settle_installment_plan"
    public static let undoPlanSettlementName = "undo_plan_settlement"
    public static let deletePlanName = "delete_installment_plan"

    static let planToolNames: Set<String> = [
        createPlanName, convertTransactionToPlanName, updatePlanName, settlePlanName, undoPlanSettlementName, deletePlanName,
    ]

    private static func schemaInteger(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    private static var planFieldSchemas: [(String, JSONValue)] {
        [
            ("name", .schemaString("Short plan name, e.g. 'iPhone 17', 'Car loan', 'Vay mua xe'.")),
            ("total_amount", .schemaNumber("Installments only: total price being split, in the household currency's major units.")),
            ("amount_borrowed", .schemaNumber("Loans only: principal borrowed (not the total repaid), in major units.")),
            ("monthly_payment", .schemaNumber("Loans only: regular monthly payment as quoted by the lender, in major units.")),
            ("months", schemaInteger("Number of monthly payments in the whole term (1-\(InstallmentPlanRecord.maxMonths)).")),
            ("first_payment_date", .schemaString("Date of the FIRST payment of the whole term, YYYY-MM-DD (may be in the past for a plan already in progress).")),
            ("category", .schemaEnum(CategoryID.expenseCategories.map(\.rawValue), "Expense category for the monthly payments (installments default to 'shopping', loans to 'bills').")),
            ("member", .schemaString("Optional household member who pays: 'me', 'partner', or their display name.")),
            ("lender", .schemaString("Loans only: lender or bank, e.g. 'DBS', 'Trust'.")),
            ("link", .schemaString("Loans only: optional URL of the loan in the bank's app or website.")),
            ("note", .schemaString("Optional short note (card, account, reference).")),
            ("already_paid_payments", schemaInteger("How many of the first payments were already paid AND are already recorded in Tally (or were paid before the user started using Tally and should not count as spending). Tally marks them paid but does not add them as expenses. 0 means Tally adds every payment due so far as an expense in its month. Only when the user gave a number; if they said all payments so far are recorded, use all_due_payments_already_recorded instead.")),
            ("all_due_payments_already_recorded", .schemaBool("true when the user said every payment due up to today is already recorded in Tally (or was paid before using Tally): Tally counts them from the schedule. Do not count months yourself.")),
        ]
    }

    public static let planTools: [ClaudeTool] = [
        ClaudeTool(
            name: createPlanName,
            description: "Create an installment plan (a purchase split into monthly payments, usually 0%) or a loan (principal + monthly payment with interest). Tally books each monthly payment as an expense when it falls due. Only call with figures the user stated or that are clearly readable in an attached image; never guess the amount, the number of months or the first payment date.",
            inputSchema: .schemaObject(
                [("kind", .schemaEnum(InstallmentKind.allCases.map(\.rawValue), "'installment' or 'loan'."))] + planFieldSchemas,
                required: ["kind", "name", "months", "first_payment_date"]
            )
        ),
        ClaudeTool(
            name: convertTransactionToPlanName,
            description: "Turn an existing expense (listed in the recent transactions with its id, e.g. a card purchase paid by instalments) into an installment plan: the expense is replaced by monthly payments of its amount.",
            inputSchema: .schemaObject([
                ("transaction_id", .schemaString("ID of the expense to convert.")),
                ("months", schemaInteger("Number of monthly payments.")),
                ("first_payment_date", .schemaString("First payment date, YYYY-MM-DD.")),
            ], required: ["transaction_id", "months", "first_payment_date"])
        ),
        ClaudeTool(
            name: updatePlanName,
            description: "Change an existing installment plan or loan by its plan id. Only pass the fields that change; the kind cannot change.",
            inputSchema: .schemaObject(
                [("plan_id", .schemaString("ID of the plan (from the plans list)."))] + planFieldSchemas,
                required: ["plan_id"]
            )
        ),
        ClaudeTool(
            name: settlePlanName,
            description: "Mark a plan as paid off early (settled). Payments scheduled after the settlement date are cancelled.",
            inputSchema: .schemaObject([
                ("plan_id", .schemaString("ID of the plan.")),
                ("settled_date", .schemaString("Date it was paid off, YYYY-MM-DD. Defaults to today.")),
            ], required: ["plan_id"])
        ),
        ClaudeTool(
            name: undoPlanSettlementName,
            description: "Undo an early settlement so the plan's remaining payments are owed again.",
            inputSchema: .schemaObject([
                ("plan_id", .schemaString("ID of the plan.")),
            ], required: ["plan_id"])
        ),
        ClaudeTool(
            name: deletePlanName,
            description: "Delete a plan. The user must choose what happens to the payments already recorded as expenses: keep them as ordinary expenses (remove_payments false) or remove them too (true). If the user has not said which, ask before calling.",
            inputSchema: .schemaObject([
                ("plan_id", .schemaString("ID of the plan.")),
                ("remove_payments", .schemaBool("true to also delete the payments already recorded as expenses; false to keep them.")),
            ], required: ["plan_id", "remove_payments"])
        ),
    ]

    // MARK: Decoding

    static func decodePlanTool(_ toolUse: ClaudeToolUse, todayKey: String) -> Result<AssistantCommand, AssistantToolDecodeError> {
        let input = toolUse.input
        switch toolUse.name {
        case createPlanName:
            guard let rawKind = input["kind"]?.stringValue else {
                return .failure(.invalidArguments("kind is required: 'installment' or 'loan'"))
            }
            guard let kind = InstallmentKind(rawValue: rawKind.lowercased()) else {
                return .failure(.invalidArguments("kind must be 'installment' or 'loan'"))
            }
            return decodePlanFields(input, kind: kind).map(AssistantCommand.createPlan)

        case convertTransactionToPlanName:
            guard let id = trimmed(input["transaction_id"]) else {
                return .failure(.invalidArguments("transaction_id is required"))
            }
            let months: Int?
            switch integer(input["months"], field: "months") {
            case .failure(let error): return .failure(error)
            case .success(let value): months = value
            }
            guard let months else { return .failure(.invalidArguments("months is required; ask the user how many monthly payments")) }
            guard let day = trimmed(input["first_payment_date"]) else {
                return .failure(.invalidArguments("first_payment_date is required; ask the user when the first payment is due"))
            }
            guard DateKey.date(fromDayKey: day) != nil else {
                return .failure(.invalidArguments("first_payment_date must be a valid date in YYYY-MM-DD format"))
            }
            return .success(.convertTransactionToPlan(transactionID: id, months: months, firstPaymentDayKey: day))

        case updatePlanName:
            guard let planID = trimmed(input["plan_id"]) else {
                return .failure(.invalidArguments("plan_id is required"))
            }
            var kind: InstallmentKind?
            if let rawKind = input["kind"]?.stringValue {
                guard let parsed = InstallmentKind(rawValue: rawKind.lowercased()) else {
                    return .failure(.invalidArguments("kind must be 'installment' or 'loan'"))
                }
                kind = parsed
            }
            return decodePlanFields(input, kind: kind).flatMap { fields in
                fields == AssistantCommand.PlanFields(kind: kind)
                    ? .failure(.invalidArguments("No fields to change were provided"))
                    : .success(.updatePlan(planID: planID, fields: fields))
            }

        case settlePlanName:
            guard let planID = trimmed(input["plan_id"]) else {
                return .failure(.invalidArguments("plan_id is required"))
            }
            var day = todayKey
            if let raw = trimmed(input["settled_date"]) {
                guard DateKey.date(fromDayKey: raw) != nil else {
                    return .failure(.invalidArguments("settled_date must be a valid date in YYYY-MM-DD format"))
                }
                day = raw
            }
            return .success(.settlePlan(planID: planID, dayKey: day))

        case undoPlanSettlementName:
            guard let planID = trimmed(input["plan_id"]) else {
                return .failure(.invalidArguments("plan_id is required"))
            }
            return .success(.undoPlanSettlement(planID: planID))

        case deletePlanName:
            guard let planID = trimmed(input["plan_id"]) else {
                return .failure(.invalidArguments("plan_id is required"))
            }
            guard let remove = input["remove_payments"]?.boolValue else {
                return .failure(.invalidArguments("remove_payments is required. Ask the user whether to keep the payments already recorded as expenses or remove them too, then call again."))
            }
            return .success(.deletePlan(planID: planID, removePayments: remove))

        default:
            return .failure(.unknownTool(toolUse.name))
        }
    }

    private static func trimmed(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Whole number or `nil` when absent; an error for fractions, negatives or non-numbers.
    private static func integer(_ value: JSONValue?, field: String) -> Result<Int?, AssistantToolDecodeError> {
        guard let value, value != .null else { return .success(nil) }
        guard let number = value.doubleValue, number.isFinite, number.rounded() == number,
              number >= 0, number <= Double(Int32.max)
        else { return .failure(.invalidArguments("\(field) must be a whole number")) }
        return .success(Int(number))
    }

    /// Positive amount or `nil` when absent; an error for zero, negative or non-numbers.
    private static func amount(_ value: JSONValue?, field: String) -> Result<Double?, AssistantToolDecodeError> {
        guard let value, value != .null else { return .success(nil) }
        guard let number = value.doubleValue, number.isFinite, number > 0 else {
            return .failure(.invalidArguments("\(field) must be a positive number"))
        }
        return .success(number)
    }

    private static func decodePlanFields(_ input: JSONValue, kind: InstallmentKind?) -> Result<AssistantCommand.PlanFields, AssistantToolDecodeError> {
        var fields = AssistantCommand.PlanFields(kind: kind)
        fields.name = trimmed(input["name"])

        let total: Double?, borrowed: Double?, monthly: Double?
        switch (amount(input["total_amount"], field: "total_amount"), amount(input["amount_borrowed"], field: "amount_borrowed"), amount(input["monthly_payment"], field: "monthly_payment")) {
        case (.failure(let e), _, _), (_, .failure(let e), _), (_, _, .failure(let e)): return .failure(e)
        case (.success(let t), .success(let b), .success(let m)): (total, borrowed, monthly) = (t, b, m)
        }
        switch kind {
        case .loan?:
            if total != nil, borrowed == nil {
                return .failure(.invalidArguments("For a loan pass amount_borrowed (the principal), not total_amount. If only the total repaid is known, ask the user for the amount borrowed."))
            }
            fields.amountMajor = borrowed
            fields.monthlyPaymentMajor = monthly
        case .installment?:
            if borrowed != nil, total == nil {
                return .failure(.invalidArguments("For an installment pass total_amount (the price being split), not amount_borrowed."))
            }
            fields.amountMajor = total
            fields.monthlyPaymentMajor = monthly
        case nil:
            fields.amountMajor = total ?? borrowed
            fields.monthlyPaymentMajor = monthly
        }

        switch integer(input["months"], field: "months") {
        case .failure(let error): return .failure(error)
        case .success(let value): fields.months = value
        }
        switch integer(input["already_paid_payments"], field: "already_paid_payments") {
        case .failure(let error): return .failure(error)
        case .success(let value): fields.alreadyPaidPayments = value
        }
        if input["all_due_payments_already_recorded"]?.boolValue == true {
            fields.allDuePaymentsAlreadyPaid = true
        }
        if let day = trimmed(input["first_payment_date"]) {
            guard DateKey.date(fromDayKey: day) != nil else {
                return .failure(.invalidArguments("first_payment_date must be a valid date in YYYY-MM-DD format"))
            }
            fields.firstPaymentDayKey = day
        }
        if let raw = trimmed(input["category"]) {
            guard let category = CategoryID(rawValue: raw), CategoryID.expenseCategories.contains(category) else {
                return .failure(.invalidArguments("category must be one of \(CategoryID.expenseCategories.map(\.rawValue).joined(separator: ", "))"))
            }
            fields.category = category
        }
        fields.memberHint = trimmed(input["member"])
        fields.lender = input["lender"]?.stringValue
        fields.link = input["link"]?.stringValue
        fields.note = input["note"]?.stringValue
        return .success(fields)
    }
}

// MARK: - Draft building (shared validation with the manual editor)

public enum AssistantPlanDrafts {
    /// Draft for a new plan from the model's fields. Missing values stay empty so
    /// `InstallmentPlanDraft.issues` reports them.
    public static func newDraft(
        _ fields: AssistantCommand.PlanFields,
        currency: CurrencyCode,
        member: HouseholdMember
    ) -> InstallmentPlanDraft {
        let kind = fields.kind ?? .installment
        var draft = InstallmentPlanDraft(
            kind: kind,
            firstPaymentDayKey: fields.firstPaymentDayKey ?? "",
            category: kind == .loan ? .bills : .shopping,
            memberID: member.id,
            memberName: member.name,
            currency: currency
        )
        apply(fields, to: &draft, currency: currency, member: nil)
        return draft
    }

    /// Draft for editing `plan` with the model's fields applied over its current values.
    public static func updatedDraft(
        _ fields: AssistantCommand.PlanFields,
        plan: InstallmentPlanRecord,
        member: HouseholdMember?
    ) -> InstallmentPlanDraft {
        var draft = InstallmentPlanDraft(plan: plan)
        apply(fields, to: &draft, currency: plan.currency, member: member)
        return draft
    }

    private static func apply(
        _ fields: AssistantCommand.PlanFields,
        to draft: inout InstallmentPlanDraft,
        currency: CurrencyCode,
        member: HouseholdMember?
    ) {
        if let name = fields.name { draft.name = name }
        if let amount = fields.amountMajor { draft.amountMinor = currency.toStorageMinor(amount) }
        if let monthly = fields.monthlyPaymentMajor { draft.monthlyPaymentMinor = currency.toStorageMinor(monthly) }
        if let months = fields.months { draft.months = months }
        if let day = fields.firstPaymentDayKey { draft.firstPaymentDayKey = day }
        if let category = fields.category { draft.category = category }
        if let member {
            draft.memberID = member.id
            draft.memberName = member.name
        }
        if let lender = fields.lender { draft.lender = lender }
        if let link = fields.link { draft.linkText = link }
        if let note = fields.note { draft.note = note }
        if let alreadyPaid = fields.alreadyPaidPayments { draft.alreadyPaidCount = alreadyPaid }
    }

    /// Why the draft cannot be saved, written for the model so it can ask the user for the
    /// missing or inconsistent value instead of guessing.
    public static func issuesDescription(_ draft: InstallmentPlanDraft) -> String {
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: draft.currency, language: .english) }
        let lines = draft.issues.map { issue -> String in
            switch issue {
            case .missingName:
                return "The plan needs a name."
            case .invalidAmount:
                return draft.kind == .loan
                    ? "The amount borrowed (principal) is missing or not positive."
                    : "The total amount is missing or not positive."
            case .missingMonthlyPayment:
                return "The monthly payment of the loan is missing."
            case .invalidMonths:
                return "The number of monthly payments is missing or outside 1-\(InstallmentPlanDraft.maxMonths)."
            case .invalidFirstPaymentDay:
                return "The first payment date is missing or invalid."
            case .paymentsBelowPrincipal(let shortfall):
                return "Monthly payment x months is \(money(draft.loanTotalMinor)), \(money(shortfall)) less than the amount borrowed, so these figures are inconsistent."
            case .amountTooSmallForMonths(let minimum):
                return "The amount is too small to split into that many payments (minimum \(money(minimum)))."
            case .alreadyPaidOutOfRange(let maxCount):
                return "already_paid_payments must be between 0 and the number of months (\(maxCount))."
            }
        }
        return "Not saved. " + lines.joined(separator: " ")
            + " Ask the user for the missing or correct value; do not guess or invent figures."
    }
}

// MARK: - Receipts & summaries

public enum AssistantPlanSummary {
    /// Localized lines describing exactly what was saved, shown under the plan receipt in chat.
    public static func detailLines(for plan: InstallmentPlanRecord, todayKey: String, language: AppLanguage) -> [String] {
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: plan.currency, language: language) }
        let schedule = plan.fullSchedule
        let regular = schedule.first?.amountMinor ?? 0
        var lines: [String] = []

        lines.append(L10n.text(
            language,
            en: "\(money(regular)) / month × \(plan.months) months · total \(money(plan.totalMinor))",
            vi: "\(money(regular)) / tháng × \(plan.months) tháng · tổng \(money(plan.totalMinor))",
            zh: "每月 \(money(regular)) × \(plan.months) 期 · 合计 \(money(plan.totalMinor))"
        ))
        if let last = schedule.last, schedule.count > 1, last.amountMinor != regular {
            lines.append(L10n.text(language, en: "Last payment \(money(last.amountMinor))", vi: "Kỳ cuối \(money(last.amountMinor))", zh: "末期 \(money(last.amountMinor))"))
        }
        let first = DateKey.formatAbsoluteDay(plan.firstPaymentDayKey, language: language)
        let end = schedule.last.map { DateKey.formatAbsoluteDay($0.dayKey, language: language) } ?? first
        lines.append(L10n.text(language, en: "First payment \(first) · last \(end)", vi: "Kỳ đầu \(first) · kỳ cuối \(end)", zh: "首期 \(first) · 末期 \(end)"))
        if plan.kind == .loan || plan.totalInterestMinor > 0 {
            let rate = InstallmentRateFormat.percent(plan.effectiveAnnualRate, language: language)
            lines.append(L10n.text(
                language,
                en: "Borrowed \(money(plan.effectivePrincipalMinor)) · effective rate \(rate) p.a. · interest \(money(plan.totalInterestMinor))",
                vi: "Vay \(money(plan.effectivePrincipalMinor)) · lãi suất thực \(rate)/năm · tiền lãi \(money(plan.totalInterestMinor))",
                zh: "借款 \(money(plan.effectivePrincipalMinor)) · 实际年利率 \(rate) · 利息 \(money(plan.totalInterestMinor))"
            ))
        }
        if plan.effectiveAlreadyPaidCount > 0 {
            let n = plan.effectiveAlreadyPaidCount
            lines.append(L10n.text(
                language,
                en: "\(n) payments already paid (not added as expenses)",
                vi: "\(n) kỳ đã trả (không ghi thành khoản chi)",
                zh: "已支付 \(n) 期（不计入支出）"
            ))
        }
        if let settled = plan.settledDayKey {
            let day = DateKey.formatAbsoluteDay(settled, language: language)
            lines.append(L10n.text(language, en: "Settled early on \(day)", vi: "Tất toán sớm ngày \(day)", zh: "已于 \(day) 提前结清"))
        }
        if let lender = plan.lender, !lender.isEmpty {
            lines.append(L10n.text(language, en: "Lender: \(lender)", vi: "Bên cho vay: \(lender)", zh: "贷款机构：\(lender)"))
        }
        return lines
    }

    /// Short English summary of the saved values for the tool result (so the model reports what
    /// was actually recorded).
    public static func modelSummary(for plan: InstallmentPlanRecord, todayKey: String) -> String {
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: plan.currency, language: .english) }
        let schedule = plan.fullSchedule
        let progress = plan.progress(todayKey: todayKey)
        var parts = [
            "[id:\(plan.id)] \(plan.kind.rawValue) '\(plan.name)'",
            "monthly payment \(money(schedule.first?.amountMinor ?? 0))",
            "\(plan.months) months",
            "first payment \(plan.firstPaymentDayKey)",
            "last payment \(schedule.last?.dayKey ?? plan.firstPaymentDayKey)",
            "total \(money(plan.totalMinor))",
            "category \(plan.category.rawValue)",
        ]
        if plan.kind == .loan || plan.totalInterestMinor > 0 {
            parts.append("borrowed \(money(plan.effectivePrincipalMinor))")
            parts.append(String(format: "effective annual rate %.2f%%", plan.effectiveAnnualRate * 100))
            parts.append("total interest \(money(plan.totalInterestMinor))")
        }
        if let lender = plan.lender { parts.append("lender \(lender)") }
        if plan.effectiveAlreadyPaidCount > 0 {
            parts.append("\(plan.effectiveAlreadyPaidCount) payments already paid (not booked as expenses)")
        }
        if let settled = plan.settledDayKey { parts.append("settled \(settled)") }
        parts.append("paid \(progress.paidCount)/\(progress.paymentCount)")
        parts.append("remaining \(money(progress.remainingMinor))")
        return parts.joined(separator: ", ")
    }
}

// MARK: - Plan context for the system prompt

extension BudgetAssistantPrompt {
    /// Compact plan lines for the model: id, name, kind, monthly payment, paid/total, remaining,
    /// next payment, lender and status. Deleted plans are omitted.
    public static func planContextLines(
        plans: [InstallmentPlanRecord],
        todayKey: String,
        currency: CurrencyCode,
        limit: Int = 30
    ) -> [String] {
        let live = plans.filter { !$0.isDeleted }
        let overview = CommitmentsOverview(plans: live, todayKey: todayKey)
        let ordered = (overview.active + overview.completed).prefix(limit)
        return ordered.map { entry in
            let plan = entry.plan
            let progress = entry.progress
            let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: plan.currency, language: .english) }
            var parts = [
                "[id:\(plan.id)] \(plan.name)",
                plan.kind.rawValue,
                "monthly \(money(plan.fullSchedule.first?.amountMinor ?? 0))",
                "paid \(progress.paidCount)/\(progress.paymentCount)",
            ]
            if plan.effectiveAlreadyPaidCount > 0 {
                parts.append("\(plan.effectiveAlreadyPaidCount) paid before/outside Tally")
            }
            parts.append("remaining \(money(progress.remainingMinor))")
            if plan.kind == .loan || plan.totalInterestMinor > 0, !progress.isCompleted {
                parts.append("principal owed \(money(progress.outstandingPrincipalMinor))")
                parts.append(String(format: "rate %.2f%% p.a.", plan.effectiveAnnualRate * 100))
            }
            if let next = progress.nextPayment {
                parts.append("next \(next.dayKey) \(money(next.amountMinor))")
            }
            if let lender = plan.lender, !lender.isEmpty { parts.append("lender \(lender)") }
            if progress.isSettled, let day = plan.settledDayKey {
                parts.append("settled \(day)")
            } else if let day = plan.settledDayKey {
                parts.append("settles \(day)")
            } else if progress.isCompleted {
                parts.append("completed")
            } else {
                parts.append("active")
            }
            return "- " + parts.joined(separator: " · ")
        } + (live.count > limit ? ["- … \(live.count - limit) more plans not listed"] : [])
            + (overview.active.isEmpty ? [] : [
                "Total still to pay on active plans: \(MoneyFormat.format(minor: overview.remainingDebtMinor, currency: currency, language: .english)); due this month: \(MoneyFormat.format(minor: overview.committedThisMonthMinor, currency: currency, language: .english))"
            ])
    }
}
