import ClaudeKit
import Foundation
import TallyCore

// MARK: - Queries

/// A read-only adviser tool call, decoded and validated. Amounts are already in storage minor
/// units of the household currency; dates are validated keys.
public enum AdviserQuery: Equatable, Sendable {
    public struct GoalPlanRequest: Equatable, Sendable {
        public var goalID: String?
        public var goalName: String?
        public var targetMinor: Int64?
        public var savedMinor: Int64?
        public var targetMonthKey: String?
        public var contributionMinor: Int64?

        public init(goalID: String? = nil, goalName: String? = nil, targetMinor: Int64? = nil, savedMinor: Int64? = nil, targetMonthKey: String? = nil, contributionMinor: Int64? = nil) {
            self.goalID = goalID
            self.goalName = goalName
            self.targetMinor = targetMinor
            self.savedMinor = savedMinor
            self.targetMonthKey = targetMonthKey
            self.contributionMinor = contributionMinor
        }
    }

    case cashFlow(months: Int)
    case debt
    case budgets(category: CategoryID?)
    case goals
    case goalPlan(GoalPlanRequest)
    case affordability(AffordabilityInput)
    case earlySettlement(planID: String, dayKey: String?)
    case runway(cashMinor: Int64)
    case period(startDayKey: String, endDayKey: String, category: CategoryID?, member: String?)
}

/// What the app tells the adviser tools besides the data (who "me" and "partner" are, and whether
/// the model may still ask for salary access in this message).
public struct AdviserToolContext: Sendable {
    public var data: AdviserDataSet
    public var currentMemberID: String
    public var members: [HouseholdMember]
    public var salaryRequestAvailable: Bool

    public init(data: AdviserDataSet, currentMemberID: String = HouseholdMember.defaultMeID, members: [HouseholdMember] = [], salaryRequestAvailable: Bool = true) {
        self.data = data
        self.currentMemberID = currentMemberID
        self.members = members
        self.salaryRequestAvailable = salaryRequestAvailable
    }
}

public struct AdviserToolOutput: Equatable, Sendable {
    public let text: String
    public let isError: Bool
    /// `true` when at least one figure was withheld because salary is hidden.
    public let salaryLocked: Bool
}

// MARK: - Catalog

public enum AdviserToolCatalog {
    public static let cashFlowName = "get_cash_flow_history"
    public static let debtName = "get_debt_overview"
    public static let budgetsName = "get_budget_adherence"
    public static let goalsName = "get_savings_goals"
    public static let goalPlanName = "plan_savings_goal"
    public static let affordabilityName = "check_affordability"
    public static let earlySettlementName = "early_settlement_saving"
    public static let runwayName = "emergency_runway"
    public static let periodName = "summarize_period"

    public static let names: Set<String> = [
        cashFlowName, debtName, budgetsName, goalsName, goalPlanName, affordabilityName, earlySettlementName, runwayName, periodName,
    ]

    private static func integer(_ description: String) -> JSONValue {
        ["type": "integer", "description": .string(description)]
    }

    public static let tools: [ClaudeTool] = [
        ClaudeTool(
            name: cashFlowName,
            description: "Read-only. Month-by-month income, spending, net, savings rate and spending per category for the last complete months (up to 12), with averages, the latest month-over-month change, the categories that moved most against their average, and the fixed vs variable split. Use for trends, 'how are we doing', savings rate and where money goes over time.",
            inputSchema: .schemaObject([
                ("months", integer("How many complete months to look back (1-12, default 12).")),
            ], required: [])
        ),
        ClaudeTool(
            name: debtName,
            description: "Read-only. Every active installment plan and loan with monthly payment, payments left, outstanding balance, effective annual rate, interest still to pay and the saving from settling it today; totals, monthly debt service, debt-service-to-income ratio, and two payoff orders (highest rate first, smallest balance first).",
            inputSchema: .schemaObject([], required: [])
        ),
        ClaudeTool(
            name: budgetsName,
            description: "Read-only. This month's budget limit vs actual per category (remaining, % used, status, linear month-end projection), how often each category went over in recent months, and a suggested limit computed as a statistic of past spending.",
            inputSchema: .schemaObject([
                ("category", .schemaEnum(CategoryID.expenseCategories.map(\.rawValue), "Optional: only this expense category.")),
            ], required: [])
        ),
        ClaudeTool(
            name: goalsName,
            description: "Read-only. Every savings goal with amount still needed and months to reach it at the household's current average monthly net saving.",
            inputSchema: .schemaObject([], required: [])
        ),
        ClaudeTool(
            name: goalPlanName,
            description: "Calculator. For an existing goal (goal_id or goal_name) or a hypothetical one (target_amount, saved_amount): the monthly contribution needed to reach it by target_date, and/or how long it takes at a stated monthly_contribution, compared with the current saving pace.",
            inputSchema: .schemaObject([
                ("goal_id", .schemaString("ID of an existing goal.")),
                ("goal_name", .schemaString("Name of an existing goal if the id is not known.")),
                ("target_amount", .schemaNumber("Hypothetical goal: target amount in the household currency's major units.")),
                ("saved_amount", .schemaNumber("Hypothetical goal: amount already saved (default 0).")),
                ("target_date", .schemaString("Optional target month, YYYY-MM or YYYY-MM-DD.")),
                ("monthly_contribution", .schemaNumber("Optional monthly amount the user could set aside, in major units.")),
            ], required: [])
        ),
        ClaudeTool(
            name: affordabilityName,
            description: "Calculator. For a proposed new commitment (purchase in instalments or a loan): the monthly payment, total repaid and interest, the new monthly debt service and debt-service-to-income ratio, and the household's average monthly net after the payment. Pass monthly_payment if the lender quoted one, else annual_rate_percent (omit both for 0%).",
            inputSchema: .schemaObject([
                ("amount", .schemaNumber("Price or amount borrowed, in the household currency's major units.")),
                ("months", integer("Number of monthly payments.")),
                ("annual_rate_percent", .schemaNumber("Optional nominal annual interest rate in percent, e.g. 6.5.")),
                ("monthly_payment", .schemaNumber("Optional monthly payment quoted by the lender, in major units.")),
            ], required: ["amount", "months"])
        ),
        ClaudeTool(
            name: earlySettlementName,
            description: "Calculator. What settling an existing plan or loan early would cost and save: principal to pay off, interest saved and payments cancelled, on settle_date (default today). Does not change anything.",
            inputSchema: .schemaObject([
                ("plan_id", .schemaString("ID of the plan (from the plans list).")),
                ("settle_date", .schemaString("Optional payoff date, YYYY-MM-DD (default today).")),
            ], required: ["plan_id"])
        ),
        ClaudeTool(
            name: runwayName,
            description: "Calculator. How many months a cash amount the user states would cover the household's average monthly spending, and its fixed spending only. Tally does not know cash balances; only call with an amount the user gave.",
            inputSchema: .schemaObject([
                ("cash_amount", .schemaNumber("Cash or savings amount in the household currency's major units.")),
            ], required: ["cash_amount"])
        ),
        ClaudeTool(
            name: periodName,
            description: "Read-only. Totals for any date range: spending (by category with shares, by member, top merchants, per day), income and net, optionally for one category or member. Use this instead of adding up transactions yourself.",
            inputSchema: .schemaObject([
                ("month", .schemaString("A whole month, YYYY-MM (instead of start/end).")),
                ("start_date", .schemaString("First day, YYYY-MM-DD.")),
                ("end_date", .schemaString("Last day, YYYY-MM-DD (default: today, or start_date's day if it is in the future).")),
                ("category", .schemaEnum(CategoryID.allCases.map(\.rawValue), "Optional category filter.")),
                ("member", .schemaString("Optional member filter: 'me', 'partner', or a member's display name.")),
            ], required: [])
        ),
    ]

    // MARK: Decoding

    public static func decode(_ toolUse: ClaudeToolUse, currency: CurrencyCode, todayKey: String) -> Result<AdviserQuery, AssistantToolDecodeError> {
        let input = toolUse.input
        func fail(_ text: String) -> Result<AdviserQuery, AssistantToolDecodeError> { .failure(.invalidArguments(text)) }

        switch toolUse.name {
        case cashFlowName:
            switch wholeNumber(input["months"], field: "months") {
            case .failure(let e): return .failure(e)
            case .success(let months):
                let n = months ?? AdviserRules.historyMonths
                guard (1...AdviserRules.historyMonths).contains(n) else { return fail("months must be 1-\(AdviserRules.historyMonths)") }
                return .success(.cashFlow(months: n))
            }

        case debtName:
            return .success(.debt)

        case budgetsName:
            guard let raw = text(input["category"]) else { return .success(.budgets(category: nil)) }
            guard let category = CategoryID(rawValue: raw), CategoryID.expenseCategories.contains(category) else {
                return fail("category must be one of \(CategoryID.expenseCategories.map(\.rawValue).joined(separator: ", "))")
            }
            return .success(.budgets(category: category))

        case goalsName:
            return .success(.goals)

        case goalPlanName:
            var request = AdviserQuery.GoalPlanRequest(goalID: text(input["goal_id"]), goalName: text(input["goal_name"]))
            switch (money(input["target_amount"], "target_amount", currency), money(input["saved_amount"], "saved_amount", currency, allowZero: true), money(input["monthly_contribution"], "monthly_contribution", currency)) {
            case (.failure(let e), _, _), (_, .failure(let e), _), (_, _, .failure(let e)): return .failure(e)
            case (.success(let target), .success(let saved), .success(let contribution)):
                request.targetMinor = target
                request.savedMinor = saved
                request.contributionMinor = contribution
            }
            if let raw = text(input["target_date"]) {
                guard let month = monthKey(from: raw) else { return fail("target_date must be YYYY-MM or YYYY-MM-DD") }
                request.targetMonthKey = month
            }
            guard request.goalID != nil || request.goalName != nil || request.targetMinor != nil else {
                return fail("give goal_id or goal_name for an existing goal, or target_amount for a hypothetical one")
            }
            return .success(.goalPlan(request))

        case affordabilityName:
            let amount: Int64?, payment: Int64?
            switch (money(input["amount"], "amount", currency), money(input["monthly_payment"], "monthly_payment", currency)) {
            case (.failure(let e), _), (_, .failure(let e)): return .failure(e)
            case (.success(let a), .success(let p)): (amount, payment) = (a, p)
            }
            guard let amount else { return fail("amount is required; ask the user for the price or amount borrowed") }
            let months: Int?
            switch wholeNumber(input["months"], field: "months") {
            case .failure(let e): return .failure(e)
            case .success(let value): months = value
            }
            guard let months, months >= 1 else { return fail("months is required; ask the user how many monthly payments") }
            var rate: Double?
            if let value = input["annual_rate_percent"], value != .null {
                guard let number = value.doubleValue, number.isFinite, number >= 0, number <= 100 else {
                    return fail("annual_rate_percent must be a number from 0 to 100")
                }
                rate = number
            }
            return .success(.affordability(AffordabilityInput(amountMinor: amount, months: months, annualRatePercent: rate, monthlyPaymentMinor: payment)))

        case earlySettlementName:
            guard let planID = text(input["plan_id"]) else { return fail("plan_id is required") }
            var day: String?
            if let raw = text(input["settle_date"]) {
                guard DateKey.date(fromDayKey: raw) != nil else { return fail("settle_date must be a valid date in YYYY-MM-DD format") }
                day = raw
            }
            return .success(.earlySettlement(planID: planID, dayKey: day))

        case runwayName:
            switch money(input["cash_amount"], "cash_amount", currency, allowZero: true) {
            case .failure(let e): return .failure(e)
            case .success(let cash):
                guard let cash else { return fail("cash_amount is required; ask the user how much cash or savings they mean") }
                return .success(.runway(cashMinor: cash))
            }

        case periodName:
            var start: String
            var end: String
            if let raw = text(input["month"]) {
                guard DateKey.yearAndMonth(fromMonthKey: raw) != nil, raw.count == 7 else { return fail("month must be YYYY-MM") }
                (start, end) = DateKey.dayRange(forMonth: raw)
            } else if let raw = text(input["start_date"]) {
                guard DateKey.date(fromDayKey: raw) != nil else { return fail("start_date must be a valid date in YYYY-MM-DD format") }
                start = raw
                end = raw > todayKey ? raw : todayKey
                if let rawEnd = text(input["end_date"]) {
                    guard DateKey.date(fromDayKey: rawEnd) != nil else { return fail("end_date must be a valid date in YYYY-MM-DD format") }
                    end = rawEnd
                }
            } else {
                return fail("give month (YYYY-MM) or start_date (YYYY-MM-DD)")
            }
            if end < start { swap(&start, &end) }
            var category: CategoryID?
            if let raw = text(input["category"]) {
                guard let parsed = CategoryID(rawValue: raw) else { return fail("unknown category \(raw)") }
                category = parsed
            }
            return .success(.period(startDayKey: start, endDayKey: end, category: category, member: text(input["member"])))

        default:
            return .failure(.unknownTool(toolUse.name))
        }
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard let s = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func wholeNumber(_ value: JSONValue?, field: String) -> Result<Int?, AssistantToolDecodeError> {
        guard let value, value != .null else { return .success(nil) }
        guard let number = value.doubleValue, number.isFinite, number.rounded() == number, number >= 0, number <= Double(Int32.max) else {
            return .failure(.invalidArguments("\(field) must be a whole number"))
        }
        return .success(Int(number))
    }

    private static func money(_ value: JSONValue?, _ field: String, _ currency: CurrencyCode, allowZero: Bool = false) -> Result<Int64?, AssistantToolDecodeError> {
        guard let value, value != .null else { return .success(nil) }
        guard let number = value.doubleValue, number.isFinite, allowZero ? number >= 0 : number > 0,
              number < Double(InstallmentPlanRecord.maxAmountMinor) / 100
        else { return .failure(.invalidArguments("\(field) must be a \(allowZero ? "non-negative" : "positive") number")) }
        return .success(currency.toStorageMinor(number))
    }

    /// `YYYY-MM` from `YYYY-MM` or `YYYY-MM-DD`.
    static func monthKey(from raw: String) -> String? {
        if raw.count == 7, DateKey.yearAndMonth(fromMonthKey: raw) != nil { return raw }
        if DateKey.date(fromDayKey: raw) != nil { return DateKey.monthKey(fromDayKey: raw) }
        return nil
    }

    // MARK: Running

    public static func run(_ toolUse: ClaudeToolUse, context: AdviserToolContext) -> AdviserToolOutput {
        switch decode(toolUse, currency: context.data.currency, todayKey: context.data.todayKey) {
        case .failure(let error):
            let message: String
            switch error {
            case .invalidArguments(let text): message = text
            case .unknownTool(let name): message = "unknown tool \(name)"
            }
            return AdviserToolOutput(text: "Error: \(message)", isError: true, salaryLocked: false)
        case .success(let query):
            return run(query, context: context)
        }
    }

    public static func run(_ query: AdviserQuery, context: AdviserToolContext) -> AdviserToolOutput {
        let renderer = AdviserRenderer(currency: context.data.currency)
        switch AdviserEvaluator.evaluate(query, context: context, renderer: renderer) {
        case .failure(let message):
            return AdviserToolOutput(text: "Error: \(message)", isError: true, salaryLocked: false)
        case .success(var object):
            if renderer.locked {
                object["salary_locked"] = .string(context.salaryRequestAvailable
                    ? "Figures marked 'locked' include salary, which the user hides on this device. Do not estimate them or work them out from other figures. If your answer needs them, call request_salary_access once with a one-sentence reason; otherwise answer with the unlocked figures only."
                    : "Figures marked 'locked' include salary, which stays hidden for this message (access was already requested). Do not estimate them or work them out from other figures; answer with the unlocked figures only.")
            }
            return AdviserToolOutput(text: renderer.encode(.object(object)), isError: false, salaryLocked: renderer.locked)
        }
    }

    /// Goal by id, then exact name, then a name containing (or contained in) the given one.
    public static func matchGoal(id: String?, name: String?, in goals: [SavingsGoalRecord]) -> SavingsGoalRecord? {
        let live = goals.filter { !$0.isDeleted }
        if let id, let exact = live.first(where: { $0.id == id }) { return exact }
        guard let name else { return nil }
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        if let exact = live.first(where: { $0.name.lowercased() == needle }) { return exact }
        return live.first { $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased()) }
    }
}

// MARK: - Rendering

/// Turns adviser figures into compact JSON for the model. Money is formatted in the household
/// currency; a missing figure becomes "not enough data: …" or "locked (salary hidden)".
final class AdviserRenderer {
    let currency: CurrencyCode
    private(set) var locked = false
    static let lockedText = "locked (salary hidden)"

    init(currency: CurrencyCode) {
        self.currency = currency
    }

    func money(_ minor: Int64, currency: CurrencyCode? = nil) -> JSONValue {
        .string(MoneyFormat.format(minor: minor, currency: currency ?? self.currency, language: .english))
    }

    func percent(_ value: Double) -> JSONValue {
        .string(String(format: "%.1f%%", value))
    }

    func figure<T>(_ figure: AdviserFigure<T>, _ render: (T) -> JSONValue) -> JSONValue {
        switch figure {
        case .value(let value): return render(value)
        case .insufficient(let reason): return .string("not enough data: \(reason)")
        case .salaryLocked:
            locked = true
            return .string(Self.lockedText)
        }
    }

    func money(_ value: AdviserFigure<Int64>) -> JSONValue { figure(value) { self.money($0) } }
    func percent(_ value: AdviserFigure<Double>) -> JSONValue { figure(value) { self.percent($0) } }
    func optionalPercent(_ value: Double?) -> JSONValue { value.map { percent($0) } ?? .string("n/a (base is 0)") }

    func encode(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}

// MARK: - Evaluation

enum AdviserEvaluator {
    enum Outcome {
        case success([String: JSONValue])
        case failure(String)
    }

    static func evaluate(_ query: AdviserQuery, context: AdviserToolContext, renderer r: AdviserRenderer) -> Outcome {
        let data = context.data
        switch query {
        case .cashFlow(let months):
            return .success(cashFlow(CashFlowHistory(data: data, months: months), renderer: r))

        case .debt:
            return .success(debt(DebtOverview(data: data), renderer: r))

        case .budgets(let category):
            return .success(budgets(BudgetAdherence(data: data, only: category), renderer: r))

        case .goals:
            let history = CashFlowHistory(data: data)
            let outlooks = data.goals.map {
                GoalOutlook(goalID: $0.id, name: $0.name, targetMinor: $0.targetMinor, savedMinor: $0.savedMinor, data: data, history: history)
            }
            var object: [String: JSONValue] = [
                "goals": .array(outlooks.map { goal($0, renderer: r) }),
                "average_monthly_net_saving": r.money(history.averageNetMinor),
                "notes": .array([AdviserRules.goalPaceRule, AdviserRules.averagesRule].map(JSONValue.string)),
            ]
            if outlooks.isEmpty { object["goals"] = .string("no savings goals") }
            return .success(object)

        case .goalPlan(let request):
            let history = CashFlowHistory(data: data)
            let outlook: GoalOutlook
            if request.goalID != nil || request.goalName != nil {
                guard let goal = AdviserToolCatalog.matchGoal(id: request.goalID, name: request.goalName, in: data.goals) else {
                    return .failure("no savings goal matches; use an id from the goals list, or pass target_amount for a hypothetical goal")
                }
                outlook = GoalOutlook(goalID: goal.id, name: goal.name, targetMinor: request.targetMinor ?? goal.targetMinor, savedMinor: request.savedMinor ?? goal.savedMinor, data: data, history: history)
            } else {
                guard let target = request.targetMinor else { return .failure("target_amount is required for a hypothetical goal") }
                outlook = GoalOutlook(goalID: nil, name: "hypothetical goal", targetMinor: target, savedMinor: request.savedMinor ?? 0, data: data, history: history)
            }
            switch GoalPlan.evaluate(outlook: outlook, targetMonthKey: request.targetMonthKey, contributionMinor: request.contributionMinor, data: data) {
            case .failure(let failure): return .failure(failure.message)
            case .success(let plan): return .success(goalPlan(plan, renderer: r))
            }

        case .affordability(let input):
            switch AffordabilityCheck.evaluate(input, data: data) {
            case .failure(let failure): return .failure(failure.message)
            case .success(let check): return .success(affordability(check, input: input, renderer: r))
            }

        case .earlySettlement(let planID, let day):
            guard let plan = data.plans.first(where: { $0.id == planID }) else {
                return .failure("no installment plan or loan with id \(planID); use an id from the plans list")
            }
            let settleDay = day ?? data.todayKey
            let progress = plan.progress(todayKey: data.todayKey)
            var object: [String: JSONValue] = [
                "plan_id": .string(plan.id),
                "name": .string(plan.name),
                "settle_date": .string(settleDay),
                "if_not_settled": .object([
                    "payments_left": .int(progress.paymentCount - progress.paidCount),
                    "scheduled_payments_left": r.money(progress.remainingMinor, currency: plan.currency),
                    "interest_still_to_pay": r.money(progress.interestRemainingMinor, currency: plan.currency),
                ]),
                "effective_annual_rate": r.percent((plan.effectiveAnnualRate * 10_000).rounded() / 100),
            ]
            object["settlement"] = r.figure(EarlySettlement.compute(plan: plan, settleDayKey: settleDay, todayKey: data.todayKey)) { s in
                .object([
                    "principal_to_pay_off": r.money(s.payoffPrincipalMinor, currency: plan.currency),
                    "interest_saved": r.money(s.interestSavedMinor, currency: plan.currency),
                    "payments_cancelled": .int(s.cancelledPaymentCount),
                    "scheduled_amount_cancelled": r.money(s.cancelledPaymentsMinor, currency: plan.currency),
                ])
            }
            object["notes"] = .array([.string("Settling is not recorded by this calculator; settle_installment_plan does that when the user asks.")])
            return .success(object)

        case .runway(let cash):
            let estimate = RunwayEstimate(cashMinor: cash, history: CashFlowHistory(data: data))
            return .success([
                "cash": r.money(cash),
                "average_monthly_spending": r.money(estimate.averageSpendingMinor),
                "months_of_spending_covered": r.figure(estimate.monthsOfSpending) { .string(String(format: "%.1f", $0)) },
                "average_monthly_fixed_spending": r.money(estimate.averageFixedMinor),
                "months_of_fixed_spending_covered": r.figure(estimate.monthsOfFixedCosts) { .string(String(format: "%.1f", $0)) },
                "notes": .array([AdviserRules.runwayRule, AdviserRules.fixedRule, AdviserRules.averagesRule].map(JSONValue.string)),
            ])

        case .period(let start, let end, let category, let member):
            var memberID: String?
            if let member {
                guard let resolved = resolveMember(member, context: context) else {
                    return .failure("no household member matches '\(member)'")
                }
                memberID = resolved
            }
            return .success(period(PeriodSummary(data: data, startDayKey: start, endDayKey: end, category: category, memberID: memberID), category: category, member: member, renderer: r))
        }
    }

    static func resolveMember(_ hint: String, context: AdviserToolContext) -> String? {
        let lowered = hint.lowercased()
        if lowered == "me" { return context.currentMemberID }
        if lowered == "partner" {
            return context.members.first { $0.id != context.currentMemberID }?.id
        }
        if let match = context.members.first(where: { $0.name.lowercased() == lowered || $0.id.lowercased() == lowered }) {
            return match.id
        }
        return context.data.transactions.first { $0.memberName.lowercased() == lowered }?.memberID
    }

    // MARK: Pieces

    static func month(_ m: AdviserMonth, renderer r: AdviserRenderer) -> JSONValue {
        var object: [String: JSONValue] = [
            "month": .string(m.monthKey),
            "transactions": .int(m.transactionCount),
        ]
        guard m.hasData else {
            object["note"] = .string("no transactions")
            return .object(object)
        }
        object["spending"] = r.money(m.spendingMinor)
        object["income"] = r.money(m.income)
        object["income_excluding_salary"] = r.money(m.nonSalaryIncomeMinor)
        object["net"] = r.money(m.net)
        object["savings_rate"] = r.percent(m.savingsRatePercent)
        object["fixed"] = r.money(m.fixedMinor)
        object["variable"] = r.money(m.variableMinor)
        if let change = m.spendingChangeMinor { object["spending_change_vs_previous_month"] = signed(change, r) }
        let categories = m.spendingByCategory.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        object["spending_by_category"] = .object(Dictionary(uniqueKeysWithValues: categories.map { ($0.key.rawValue, r.money($0.value)) }))
        return .object(object)
    }

    static func signed(_ minor: Int64, _ r: AdviserRenderer, currency: CurrencyCode? = nil) -> JSONValue {
        .string(MoneyFormat.format(minor: minor, currency: currency ?? r.currency, language: .english, signed: true))
    }

    static func cashFlow(_ h: CashFlowHistory, renderer r: AdviserRenderer) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "complete_months_listed": .int(h.months.count),
            "complete_months_with_transactions": .int(h.monthsWithData),
            "months": .array(h.months.map { month($0, renderer: r) }),
        ]
        var current = month(h.currentMonth, renderer: r).objectValue ?? [:]
        current["days_elapsed"] = .string("\(h.daysElapsedInCurrentMonth) of \(h.daysInCurrentMonth)")
        current.removeValue(forKey: "spending_change_vs_previous_month")
        object["current_month_to_date"] = .object(current)
        object["averages"] = .object([
            "spending": r.money(h.averageSpendingMinor),
            "income": r.money(h.averageIncomeMinor),
            "income_excluding_salary": r.money(h.averageNonSalaryIncomeMinor),
            "net": r.money(h.averageNetMinor),
            "savings_rate": r.percent(h.averageSavingsRatePercent),
            "spending_by_category": r.figure(h.averageSpendingByCategory) { dict in
                .object(Dictionary(uniqueKeysWithValues: dict.map { ($0.key.rawValue, r.money($0.value)) }))
            },
        ])
        object["latest_month_change"] = r.figure(h.latestChange) { c in
            .object([
                "from": .string(c.fromMonthKey),
                "to": .string(c.toMonthKey),
                "spending_change": signed(c.spendingChangeMinor, r),
                "spending_change_percent": r.optionalPercent(c.spendingChangePercent),
                "income_change": r.figure(c.incomeChange) { signed($0, r) },
                "net_change": r.figure(c.netChange) { signed($0, r) },
            ])
        }
        object["top_category_movers"] = r.figure(h.movers) { movers in
            movers.isEmpty ? .string("no category changed") : .array(movers.map { m in
                .object([
                    "category": .string(m.category.rawValue),
                    "latest_month": r.money(m.latestMinor),
                    "earlier_average": r.money(m.baselineAverageMinor),
                    "change": signed(m.changeMinor, r),
                    "change_percent": r.optionalPercent(m.changePercent),
                ])
            })
        }
        object["fixed_vs_variable"] = r.figure(h.fixedVariable) { s in
            .object([
                "average_fixed": r.money(s.averageFixedMinor),
                "of_which_plan_payments": r.money(s.averagePlanPaymentsMinor),
                "of_which_housing_and_bills": r.money(s.averageFixedCategoryMinor),
                "average_variable": r.money(s.averageVariableMinor),
                "fixed_share_of_spending": r.optionalPercent(s.fixedSharePercent),
            ])
        }
        object["notes"] = .array((h.notes + [AdviserRules.savingsRateRule, AdviserRules.fixedRule, AdviserRules.moversRule]).map(JSONValue.string))
        return object
    }

    static func debt(_ d: DebtOverview, renderer r: AdviserRenderer) -> [String: JSONValue] {
        let byID = Dictionary(uniqueKeysWithValues: d.plans.map { ($0.planID, $0) })
        func ranking(_ ids: [String]) -> JSONValue {
            .array(ids.enumerated().compactMap { index, id in
                guard let plan = byID[id] else { return nil }
                return .string("\(index + 1). [id:\(id)] \(plan.name): rate \(String(format: "%.2f%%", plan.effectiveAnnualRatePercent)), outstanding principal \(MoneyFormat.format(minor: plan.outstandingPrincipalMinor, currency: plan.currency, language: .english))")
            })
        }
        return [
            "active_plans": .array(d.plans.map { p in
                var object: [String: JSONValue] = [
                    "plan_id": .string(p.planID),
                    "name": .string(p.name),
                    "kind": .string(p.kind.rawValue),
                    "monthly_payment": r.money(p.nextPaymentMinor, currency: p.currency),
                    "payments_left": .int(p.remainingPayments),
                    "scheduled_payments_left": r.money(p.remainingScheduledMinor, currency: p.currency),
                    "outstanding_principal": r.money(p.outstandingPrincipalMinor, currency: p.currency),
                    "effective_annual_rate": .string(String(format: "%.2f%%", p.effectiveAnnualRatePercent)),
                    "interest_still_to_pay": r.money(p.interestRemainingMinor, currency: p.currency),
                ]
                if let next = p.nextPaymentDayKey { object["next_payment_date"] = .string(next) }
                if let last = p.lastPaymentDayKey { object["last_payment_date"] = .string(last) }
                if let lender = p.lender { object["lender"] = .string(lender) }
                object["settle_today"] = r.figure(p.settleToday) { s in
                    .object([
                        "principal_to_pay_off": r.money(s.payoffPrincipalMinor, currency: p.currency),
                        "interest_saved": r.money(s.interestSavedMinor, currency: p.currency),
                    ])
                }
                return .object(object)
            }),
            "totals": .object([
                "scheduled_payments_left": r.money(d.totalRemainingScheduledMinor),
                "outstanding_principal": r.money(d.totalOutstandingPrincipalMinor),
                "interest_still_to_pay": r.money(d.totalInterestRemainingMinor),
                "monthly_debt_service": r.money(d.monthlyDebtServiceMinor),
            ]),
            "average_monthly_income": r.money(d.averageIncomeMinor),
            "debt_service_to_income": r.percent(d.debtServiceToIncomePercent),
            "payoff_order_highest_rate_first": ranking(d.highestRateFirst),
            "payoff_order_smallest_balance_first": ranking(d.smallestBalanceFirst),
            "notes": .array(d.notes.map(JSONValue.string)),
        ]
    }

    static func budgets(_ b: BudgetAdherence, renderer r: AdviserRenderer) -> [String: JSONValue] {
        [
            "month": .string(b.monthKey),
            "days_elapsed": .string("\(b.daysElapsed) of \(b.daysInMonth)"),
            "categories": .array(b.categories.map { c in
                var object: [String: JSONValue] = [
                    "category": .string(c.category.rawValue),
                    "spent_this_month": r.money(c.spentMinor),
                    "projected_month_end": r.money(c.projectedMonthEndMinor),
                    "suggested_limit_statistic": r.figure(c.suggestedLimit) { s in
                        .string("\(MoneyFormat.format(minor: s.limitMinor, currency: r.currency, language: .english)) (median \(MoneyFormat.format(minor: s.medianMinor, currency: r.currency, language: .english)) over \(s.monthsUsed) months)")
                    },
                ]
                if let limit = c.limitMinor {
                    object["limit"] = r.money(limit)
                    object["remaining"] = r.money(c.remainingMinor ?? 0)
                    object["percent_used"] = r.optionalPercent(c.percentUsed)
                    object["status"] = .string(c.status?.rawValue ?? "under")
                    object["projected_over_limit"] = .bool(c.projectedOverLimit ?? false)
                    object["recent_months_above_this_limit"] = .string("\(c.monthsAboveCurrentLimit ?? 0) of \(c.monthsCompared)")
                } else {
                    object["limit"] = .string("no budget this month")
                }
                if c.monthsWithBudget > 0 {
                    object["recent_months_over_their_budget"] = .string("\(c.monthsOverItsBudget) of \(c.monthsWithBudget) months that had a budget")
                }
                return .object(object)
            }),
            "total_limit": r.money(b.totalLimitMinor),
            "total_spent_in_budgeted_categories": r.money(b.totalSpentInBudgetedMinor),
            "notes": .array(b.notes.map(JSONValue.string)),
        ]
    }

    static func goal(_ g: GoalOutlook, renderer r: AdviserRenderer) -> JSONValue {
        var object: [String: JSONValue] = [
            "name": .string(g.name),
            "target": r.money(g.targetMinor),
            "saved": r.money(g.savedMinor),
            "still_needed": r.money(g.neededMinor),
            "percent_saved": .string("\(g.percent)%"),
            "months_to_target_at_current_pace": r.figure(g.monthsToTarget) { .int($0) },
            "projected_month_at_current_pace": r.figure(g.projectedMonthKey) { .string($0) },
        ]
        if let id = g.goalID { object["goal_id"] = .string(id) }
        return .object(object)
    }

    static func goalPlan(_ p: GoalPlan, renderer r: AdviserRenderer) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "goal": goal(p.outlook, renderer: r),
            "current_pace_average_monthly_net": r.money(p.outlook.paceMinor),
            "notes": .array(p.notes.map(JSONValue.string)),
        ]
        if let target = p.targetMonthKey, let months = p.contributionMonths, let required = p.requiredMonthlyMinor {
            var byDate: [String: JSONValue] = [
                "target_month": .string(target),
                "monthly_contributions": .int(months),
                "required_monthly_contribution": r.money(required),
            ]
            if let shortfall = p.shortfallVersusPaceMinor {
                byDate["required_minus_current_pace"] = r.figure(shortfall) { signed($0, r) }
            }
            object["by_target_date"] = .object(byDate)
        }
        if let contribution = p.contributionMinor, let months = p.monthsAtContribution, let key = p.monthKeyAtContribution {
            object["at_stated_contribution"] = .object([
                "monthly_contribution": r.money(contribution),
                "months_needed": .int(months),
                "reached_in_month": .string(key),
            ])
        }
        return object
    }

    static func affordability(_ c: AffordabilityCheck, input: AffordabilityInput, renderer r: AdviserRenderer) -> [String: JSONValue] {
        [
            "amount": r.money(input.amountMinor),
            "months": .int(input.months),
            "payment_basis": .string(c.basis.rawValue),
            "monthly_payment": r.money(c.monthlyPaymentMinor),
            "total_repaid": r.money(c.totalRepaidMinor),
            "total_interest": r.money(c.totalInterestMinor),
            "annual_rate": .string(String(format: "%.2f%%", c.annualRatePercent)),
            "monthly_debt_service_now": r.money(c.currentDebtServiceMinor),
            "monthly_debt_service_after": r.money(c.newDebtServiceMinor),
            "average_monthly_income": r.money(c.averageIncomeMinor),
            "debt_service_to_income_now": r.percent(c.currentDebtServiceToIncomePercent),
            "debt_service_to_income_after": r.percent(c.newDebtServiceToIncomePercent),
            "average_monthly_net_now": r.money(c.averageNetMinor),
            "average_monthly_net_after_payment": r.money(c.newMonthlyNetMinor),
            "average_monthly_spending_now": r.money(c.averageSpendingMinor),
            "average_monthly_spending_with_payment": r.money(c.newMonthlySpendingMinor),
            "notes": .array(c.notes.map(JSONValue.string)),
        ]
    }

    static func period(_ s: PeriodSummary, category: CategoryID?, member: String?, renderer r: AdviserRenderer) -> [String: JSONValue] {
        var object: [String: JSONValue] = [
            "from": .string(s.startDayKey),
            "to": .string(s.endDayKey),
            "days": .int(s.dayCount),
            "transactions": .int(s.transactionCount),
            "spending": r.money(s.spendingMinor),
            "spending_per_day": r.money(s.averagePerDayMinor),
            "income": r.money(s.income),
            "income_excluding_salary": r.money(s.nonSalaryIncomeMinor),
            "net": r.money(s.net),
            "spending_by_category": .array(s.spendingByCategory.map { c in
                .string("\(c.category.rawValue): \(MoneyFormat.format(minor: c.minor, currency: r.currency, language: .english)) (\(c.sharePercent.map { String(format: "%.1f%%", $0) } ?? "n/a"))")
            }),
            "spending_by_member": .array(s.members.map { m in
                .string("\(m.name): \(MoneyFormat.format(minor: m.spendingMinor, currency: r.currency, language: .english)) (\(m.count) tx)")
            }),
            "top_merchants": .array(s.topMerchants.map { m in
                .string("\(m.name): \(MoneyFormat.format(minor: m.totalMinor, currency: r.currency, language: .english)) (\(m.count) tx)")
            }),
        ]
        var filters: [String] = []
        if let category { filters.append("category \(category.rawValue)") }
        if let member { filters.append("member \(member)") }
        if !filters.isEmpty { object["filters"] = .string(filters.joined(separator: ", ")) }
        if s.transactionCount == 0 { object["note"] = .string("no transactions in this range") }
        return object
    }
}

// MARK: - Always-on context

/// The short adviser snapshot that is always in the system prompt (details come from tools).
public enum AdviserSnapshot {
    public static func lines(data: AdviserDataSet) -> [String] {
        let history = CashFlowHistory(data: data)
        let debt = DebtOverview(data: data, history: history)
        let r = AdviserRenderer(currency: data.currency)
        func show(_ value: JSONValue) -> String { value.stringValue ?? r.encode(value) }

        var lines: [String] = []
        if history.monthsWithData == 0 {
            lines.append("- History: no complete month with transactions yet.")
        } else {
            lines.append("- History: \(history.monthsWithData) complete month(s) with transactions; current month day \(history.daysElapsedInCurrentMonth) of \(history.daysInCurrentMonth).")
        }
        lines.append("- Average monthly spending: \(show(r.money(history.averageSpendingMinor))); average income: \(show(r.money(history.averageIncomeMinor))); average net: \(show(r.money(history.averageNetMinor))); average savings rate: \(show(r.percent(history.averageSavingsRatePercent))).")
        if debt.plans.isEmpty {
            lines.append("- Active plans & loans: none.")
        } else {
            lines.append("- Active plans & loans: \(debt.plans.count); monthly debt service \(show(r.money(debt.monthlyDebtServiceMinor))); debt-service-to-income \(show(r.percent(debt.debtServiceToIncomePercent))).")
        }
        if r.locked {
            lines.append("- Figures marked locked include salary, which the user hides on this device (see the salary rules).")
        }
        return lines
    }
}

/// Resolved calendar facts for the prompt, so the model looks dates up instead of working them out.
public enum AssistantDateContext {
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public static func weekdayName(_ dayKey: String) -> String {
        weekdayNames[max(0, min(6, DateKey.weekday(fromDayKey: dayKey) - 1))]
    }

    /// Monday of the week containing `dayKey`.
    public static func weekStart(_ dayKey: String) -> String {
        let weekday = DateKey.weekday(fromDayKey: dayKey) // 1 = Sunday
        return DateKey.shiftDay(dayKey, by: -((weekday + 5) % 7))
    }

    public static func lines(todayKey: String) -> [String] {
        let recent = (1...14).map { offset -> String in
            let key = DateKey.shiftDay(todayKey, by: -offset)
            return "\(key) \(weekdayName(key))\(offset == 1 ? " (yesterday)" : "")"
        }
        let thisWeek = weekStart(todayKey)
        let lastWeek = DateKey.shiftDay(thisWeek, by: -7)
        let month = DateKey.monthKey(fromDayKey: todayKey)
        let lastMonth = DateKey.shiftMonth(month, by: -1)
        let thisRange = DateKey.dayRange(forMonth: month)
        let lastRange = DateKey.dayRange(forMonth: lastMonth)
        return [
            "Today: \(todayKey) (\(weekdayName(todayKey))). Tomorrow: \(DateKey.shiftDay(todayKey, by: 1)). Weeks start on Monday.",
            "Previous 14 days: " + recent.joined(separator: ", ") + ".",
            "This week: \(thisWeek) to \(DateKey.shiftDay(thisWeek, by: 6)); last week: \(lastWeek) to \(DateKey.shiftDay(lastWeek, by: 6)).",
            "This month: \(month) (\(thisRange.start) to \(thisRange.end)); last month: \(lastMonth) (\(lastRange.start) to \(lastRange.end)); next month: \(DateKey.shiftMonth(month, by: 1)).",
        ]
    }
}
