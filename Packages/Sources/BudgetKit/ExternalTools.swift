import ClaudeKit
import Foundation
import TallyCore

/// Tools for assistants outside the app (MCP clients such as Claude Code or Codex).
///
/// Ask Tally gets the household's context in its system prompt; an outside assistant has none,
/// so two read tools stand in for it: `get_overview` (what the prompt would have said) and
/// `list_transactions` (individual rows). Everything else is the same deterministic adviser
/// and action tools Ask Tally uses. Salary hiding applies exactly as in the app.
public enum ExternalToolCatalog {
    public static let overviewName = "get_overview"
    public static let transactionsName = "list_transactions"

    public static let defaultLimit = 50
    public static let maxLimit = 500

    static let ownNames: Set<String> = [overviewName, transactionsName]

    static let ownTools: [ClaudeTool] = [
        ClaudeTool(
            name: overviewName,
            description: "Read-only. Start here. Today's date and useful date ranges, the household currency and members, the category ids, a short computed financial snapshot, savings goals and installment plans & loans with their ids, and how much history is on record.",
            inputSchema: .schemaObject([], required: [])
        ),
        ClaudeTool(
            name: transactionsName,
            description: "Read-only. Individual transactions, newest first, with their ids. Filter by month or date range, category, type, member, or text in the name or note. For totals, averages and breakdowns use summarize_period or get_cash_flow_history instead of adding rows up.",
            inputSchema: .schemaObject([
                ("month", .schemaString("A whole month, YYYY-MM (instead of start_date/end_date).")),
                ("start_date", .schemaString("First day, YYYY-MM-DD.")),
                ("end_date", .schemaString("Last day, YYYY-MM-DD.")),
                ("category", .schemaEnum(CategoryID.allCases.map(\.rawValue), "Optional category filter.")),
                ("type", .schemaEnum(TransactionType.allCases.map(\.rawValue), "Optional: only expenses or only income.")),
                ("member", .schemaString("Optional member filter: 'me', 'partner', or a member's display name.")),
                ("search", .schemaString("Optional text to find in the name or note (case-insensitive).")),
                ("limit", ["type": "integer", "description": .string("Rows to return (default \(defaultLimit), max \(maxLimit)).")]),
                ("offset", ["type": "integer", "description": "Rows to skip, for paging (default 0)."]),
            ], required: [])
        ),
    ]

    /// Tools that only read.
    public static var readTools: [ClaudeTool] { ownTools + AdviserToolCatalog.tools }

    /// Tools that add, change or delete records.
    public static var writeTools: [ClaudeTool] { AssistantToolCatalog.baseTools + AssistantToolCatalog.planTools }

    public static var readNames: Set<String> { ownNames.union(AdviserToolCatalog.names) }
    public static let writeNames: Set<String> = Set((AssistantToolCatalog.baseTools + AssistantToolCatalog.planTools).map(\.name))

    public static func isDestructive(_ name: String) -> Bool { name.hasPrefix("delete_") }

    /// Guidance sent to the connecting assistant when it initializes.
    public static func instructions(currency: CurrencyCode, allowsChanges: Bool) -> String {
        """
        Tally is a household budget tracker for a couple. These tools read the live data in the Tally app on this Mac\(allowsChanges ? " and can change it" : " (read-only: changes are turned off in Tally's settings)").
        - Call get_overview first: it gives today's date, the members, category ids and the ids of goals and plans.
        - Amounts are in \(currency.rawValue) unless a figure says otherwise.
        - Tally computes the figures. Take totals, averages, percentages, date ranges, loan maths and goal timelines from the tools (summarize_period, get_cash_flow_history, get_budget_adherence, get_debt_overview, get_savings_goals, plan_savings_goal, check_affordability, early_settlement_saving, emergency_runway) rather than adding up transactions yourself.
        - Figures shown as "locked (salary hidden)" include salary, which the user is hiding. Do not estimate them or work them out from other figures. Only the user can reveal them, with the eye button in the Tally app.
        - "not enough data" means Tally lacks the history for that figure; say so instead of guessing.\(allowsChanges ? "\n- Changes are saved immediately and sync to the household's other devices. Confirm with the user before deleting anything." : "")
        """
    }

    // MARK: Running

    /// Runs `get_overview` or `list_transactions`; `nil` for any other tool.
    public static func run(_ toolUse: ClaudeToolUse, context: AdviserToolContext) -> AdviserToolOutput? {
        switch toolUse.name {
        case overviewName:
            return AdviserToolOutput(text: overview(context: context), isError: false, salaryLocked: false)
        case transactionsName:
            switch decodeTransactionQuery(toolUse.input, context: context) {
            case .failure(let message):
                return AdviserToolOutput(text: "Error: \(message)", isError: true, salaryLocked: false)
            case .success(let query):
                return listTransactions(query, context: context)
            }
        default:
            return nil
        }
    }

    // MARK: Overview

    static func overview(context: AdviserToolContext) -> String {
        let data = context.data
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: data.currency, language: .english) }
        var sections: [String] = []

        sections.append("Tally household budget. Currency: \(data.currency.rawValue).")
        sections.append(AssistantDateContext.lines(todayKey: data.todayKey).joined(separator: "\n"))

        let members = context.members.map { member in
            "- \(member.name)\(member.id == context.currentMemberID ? " (\"me\": the person using this Mac)" : "")"
        }
        sections.append("Household members:\n" + (members.isEmpty ? "- none recorded" : members.joined(separator: "\n")))

        sections.append(
            "Categories (ids):\n- expense: " + CategoryID.expenseCategories.map(\.rawValue).joined(separator: ", ")
                + "\n- income: " + CategoryID.incomeCategories.map(\.rawValue).joined(separator: ", ")
        )

        sections.append("Snapshot (computed by Tally; call the tools for details):\n" + AdviserSnapshot.lines(data: data).joined(separator: "\n"))

        let goals = data.goals.map { goal in
            "- [id:\(goal.id)] \(goal.name): \(money(goal.savedMinor)) / \(money(goal.targetMinor)) (\(goal.percent)%), still needed \(money(max(0, goal.targetMinor - goal.savedMinor)))"
        }
        sections.append("Savings goals:\n" + (goals.isEmpty ? "- none" : goals.joined(separator: "\n")))

        let plans = BudgetAssistantPrompt.planContextLines(plans: data.plans, todayKey: data.todayKey, currency: data.currency)
        sections.append("Installment plans & loans (paid = payments made so far, remaining = scheduled payments still to come):\n" + (plans.isEmpty ? "- none" : plans.joined(separator: "\n")))

        let days = data.transactions.map(\.dayKey)
        if let first = days.min(), let last = days.max() {
            sections.append("Transactions on record: \(data.transactions.count), from \(first) to \(last).")
        } else {
            sections.append("Transactions on record: none.")
        }

        sections.append(data.salaryHidden
            ? "Salary: hidden by the user. Salary transactions are left out of list_transactions and figures that include salary read \"\(AdviserRenderer.lockedText)\"."
            : "Salary: visible.")
        return sections.joined(separator: "\n\n")
    }

    // MARK: Transactions

    struct TransactionQuery: Equatable {
        var startDayKey: String?
        var endDayKey: String?
        var category: CategoryID?
        var type: TransactionType?
        var memberID: String?
        var search: String?
        var limit = ExternalToolCatalog.defaultLimit
        var offset = 0
    }

    enum QueryResult: Equatable {
        case success(TransactionQuery)
        case failure(String)
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    /// A whole number given as a JSON number or numeric string. `valid` is `false` when the
    /// value is present but not a whole number.
    private static func wholeNumber(_ value: JSONValue?) -> (valid: Bool, value: Int?) {
        guard let value, value != .null else { return (true, nil) }
        guard let number = value.doubleValue, number == number.rounded(), abs(number) < 1_000_000_000 else { return (false, nil) }
        return (true, Int(number))
    }

    static func decodeTransactionQuery(_ input: JSONValue, context: AdviserToolContext) -> QueryResult {
        var query = TransactionQuery()

        if let month = text(input["month"]) {
            guard month.count == 7, DateKey.yearAndMonth(fromMonthKey: month) != nil else { return .failure("month must be YYYY-MM") }
            (query.startDayKey, query.endDayKey) = DateKey.dayRange(forMonth: month)
        } else {
            if let start = text(input["start_date"]) {
                guard DateKey.date(fromDayKey: start) != nil else { return .failure("start_date must be a valid date in YYYY-MM-DD format") }
                query.startDayKey = start
            }
            if let end = text(input["end_date"]) {
                guard DateKey.date(fromDayKey: end) != nil else { return .failure("end_date must be a valid date in YYYY-MM-DD format") }
                query.endDayKey = end
            }
            if let start = query.startDayKey, let end = query.endDayKey, start > end {
                return .failure("start_date must not be after end_date")
            }
        }

        if let raw = text(input["category"]) {
            guard let category = CategoryID(rawValue: raw.lowercased()) else {
                return .failure("category must be one of: \(CategoryID.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            query.category = category
        }
        if let raw = text(input["type"]) {
            guard let type = TransactionType(rawValue: raw.lowercased()) else { return .failure("type must be expense or income") }
            query.type = type
        }
        if let member = text(input["member"]) {
            guard let resolved = AdviserEvaluator.resolveMember(member, context: context) else {
                return .failure("no household member matches '\(member)'")
            }
            query.memberID = resolved
        }
        query.search = text(input["search"])

        let limit = wholeNumber(input["limit"])
        guard limit.valid, (limit.value ?? 1) >= 1 else {
            return .failure("limit must be a whole number from 1 to \(maxLimit)")
        }
        query.limit = min(limit.value ?? defaultLimit, maxLimit)
        let offset = wholeNumber(input["offset"])
        guard offset.valid, (offset.value ?? 0) >= 0 else {
            return .failure("offset must be a whole number, 0 or more")
        }
        query.offset = offset.value ?? 0
        return .success(query)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func listTransactions(_ query: TransactionQuery, context: AdviserToolContext) -> AdviserToolOutput {
        let data = context.data
        let needle = query.search.map(folded)
        let matching = data.transactions.filter { tx in
            if let start = query.startDayKey, tx.dayKey < start { return false }
            if let end = query.endDayKey, tx.dayKey > end { return false }
            if let category = query.category, tx.category != category { return false }
            if let type = query.type, tx.type != type { return false }
            if let memberID = query.memberID, tx.memberID != memberID { return false }
            if let needle,
               !folded(tx.name).contains(needle),
               !folded(tx.note).contains(needle),
               !folded(tx.originalCurrencyCode ?? "").contains(needle),
               !folded(tx.formattedOriginalAmount(language: .english) ?? "").contains(needle) {
                return false
            }
            return true
        }
        let visible = SalaryPrivacy.visibleTransactions(matching, hidden: data.salaryHidden)
            .sorted { ($0.dayKey, $0.createdAt) > ($1.dayKey, $1.createdAt) }
        let page = visible.dropFirst(query.offset).prefix(query.limit)

        let rows = page.map { tx -> JSONValue in
            let signedMinor = tx.type == .income ? tx.amountMinor : -tx.amountMinor
            var row: [String: JSONValue] = [
                "id": .string(tx.id),
                "date": .string(tx.dayKey),
                "name": .string(tx.name),
                "amount": .string(MoneyFormat.format(minor: signedMinor, currency: data.currency, language: .english, signed: tx.type == .income)),
                "amount_value": .double(data.currency.toMajor(tx.amountMinor)),
                "type": .string(tx.type.rawValue),
                "category": .string(tx.category.rawValue),
            ]
            if !tx.memberName.isEmpty { row["member"] = .string(tx.memberName) }
            if !tx.note.isEmpty { row["note"] = .string(tx.note) }
            if tx.isForeignCurrency,
               let origCode = tx.originalCurrencyCode,
               let origMinor = tx.originalAmountMinor,
               let origFormatted = tx.formattedOriginalAmount(language: .english) {
                row["original_currency"] = .string(origCode)
                row["original_amount"] = .string(origFormatted)
                row["original_amount_value"] = .double(CurrencyCode.toMajor(origMinor))
                if let rate = tx.exchangeRate {
                    row["exchange_rate"] = .double(rate)
                }
            }
            if tx.needsReview { row["needs_review"] = true }
            if let planID = tx.planID { row["plan_id"] = .string(planID) }
            return .object(row)
        }

        var object: [String: JSONValue] = [
            "total_matching": .int(visible.count),
            "returned": .int(rows.count),
            "offset": .int(query.offset),
            "transactions": .array(rows),
        ]
        let nextOffset = query.offset + rows.count
        if nextOffset < visible.count { object["next_offset"] = .int(nextOffset) }
        let salaryOmitted = visible.count != matching.count
        if salaryOmitted {
            object["salary_hidden"] = "Salary transactions in this range are left out because the user hides salary. Do not estimate them; only the user can reveal them, with the eye button in the Tally app."
        }
        return AdviserToolOutput(text: AdviserRenderer(currency: data.currency).encode(.object(object)), isError: false, salaryLocked: salaryOmitted)
    }
}
