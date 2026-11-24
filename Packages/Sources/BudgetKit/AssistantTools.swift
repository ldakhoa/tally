import ClaudeKit
import Foundation
import TallyCore

// MARK: - Action Confirmation Receipt (Rendered in AskTallyView)

public struct AssistantActionReceipt: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case transactionAdded
        case transactionUpdated
        case transactionDeleted
        case budgetSet
        case budgetDeleted
        case goalCreated
        case goalUpdated
        case goalDeleted
        case planCreated
        case planConverted
        case planUpdated
        case planSettled
        case planUnsettled
        case planDeleted

        public var isPlan: Bool {
            switch self {
            case .planCreated, .planConverted, .planUpdated, .planSettled, .planUnsettled, .planDeleted: return true
            default: return false
            }
        }
    }

    public let id: UUID
    public let kind: Kind
    public let emoji: String
    public let title: String
    public let subtitle: String
    public let amountText: String?
    public let isPositive: Bool
    /// Extra lines shown in full under the subtitle (plan receipts list the saved values here).
    /// Optional so receipts persisted before this field existed still decode.
    public let details: [String]?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        emoji: String,
        title: String,
        subtitle: String,
        amountText: String? = nil,
        isPositive: Bool = false,
        details: [String]? = nil
    ) {
        self.id = id
        self.kind = kind
        self.emoji = emoji
        self.title = title
        self.subtitle = subtitle
        self.amountText = amountText
        self.isPositive = isPositive
        self.details = details
    }
}

// MARK: - Decoded Cross-App Assistant Commands

public enum AssistantCommand: Equatable, Sendable {
    public struct NewTransactionItem: Equatable, Sendable {
        public let name: String
        public let amountMajor: Double
        public let type: TransactionType
        public let category: CategoryID
        public let dayKey: String
        public let note: String
        public let memberHint: String?
        /// Currency the amount was stated in when it is not the household's (converted by code).
        public let currency: CurrencyCode?

        public init(
            name: String,
            amountMajor: Double,
            type: TransactionType,
            category: CategoryID,
            dayKey: String,
            note: String = "",
            memberHint: String? = nil,
            currency: CurrencyCode? = nil
        ) {
            self.name = name
            self.amountMajor = amountMajor
            self.type = type
            self.category = category
            self.dayKey = dayKey
            self.note = note
            self.memberHint = memberHint
            self.currency = currency
        }
    }

    public struct BudgetItem: Equatable, Sendable {
        public let category: CategoryID
        public let limitMajor: Double

        public init(category: CategoryID, limitMajor: Double) {
            self.category = category
            self.limitMajor = limitMajor
        }
    }

    case addTransactions([NewTransactionItem])
    case updateTransaction(
        id: String,
        name: String?,
        amountMajor: Double?,
        category: CategoryID?,
        dayKey: String?,
        note: String?
    )
    case deleteTransaction(id: String)
    case setBudgets(monthKey: String, items: [BudgetItem])
    case deleteBudget(monthKey: String, category: CategoryID)
    case createSavingsGoal(
        name: String,
        targetMajor: Double,
        savedMajor: Double,
        icon: GoalIcon
    )
    case updateSavingsGoal(
        goalID: String?,
        goalName: String?,
        addMajor: Double?,
        newTargetMajor: Double?,
        newSavedMajor: Double?,
        newName: String?
    )
    case deleteSavingsGoal(goalID: String?, goalName: String?)
    case createPlan(PlanFields)
    case convertTransactionToPlan(transactionID: String, months: Int, firstPaymentDayKey: String)
    case updatePlan(planID: String, fields: PlanFields)
    case settlePlan(planID: String, dayKey: String)
    case undoPlanSettlement(planID: String)
    case deletePlan(planID: String, removePayments: Bool)
}

public enum AssistantToolDecodeError: Error, Equatable, Sendable {
    case unknownTool(String)
    case invalidArguments(String)
}

// MARK: - Tool Catalog & Decoder

public enum AssistantToolCatalog {
    public static let addTransactionsName = "add_transactions"
    public static let updateTransactionName = "update_transaction"
    public static let deleteTransactionName = "delete_transaction"
    public static let setBudgetsName = "set_budgets"
    public static let deleteBudgetName = "delete_budget"
    public static let createSavingsGoalName = "create_savings_goal"
    public static let updateSavingsGoalName = "update_savings_goal"
    public static let deleteSavingsGoalName = "delete_savings_goal"

    /// Every tool offered to Claude: transactions, budgets, goals, installment plans/loans, the
    /// read-only adviser figures and calculators, and the salary access request.
    public static let allTools: [ClaudeTool] = baseTools + planTools + AdviserToolCatalog.tools + [SalaryAccessTool.tool]

    static let baseTools: [ClaudeTool] = [
        ClaudeTool(
            name: addTransactionsName,
            description: "Record one or more completed expenses or income transactions into Tally. Use this whenever the user says they paid for something, spent money, paid a bill/credit card/rent, or received salary/income.",
            inputSchema: .schemaObject([
                ("items", .schemaArray(
                    of: .schemaObject([
                        ("name", .schemaString("Short, clear merchant or description (e.g. 'Rent', 'Credit card payment', 'Tiền nhà', '房租').")),
                        ("amount", .schemaNumber("Positive amount in major units, exactly as stated (do not convert currencies yourself).")),
                        ("currency", .schemaEnum(CurrencyCode.allCases.map(\.rawValue), "Only when the amount was stated in a currency other than the household's: that currency. Tally converts it and keeps the original in the note.")),
                        ("type", .schemaEnum(["expense", "income"], "Whether this is an expense or income.")),
                        ("category", .schemaEnum(CategoryID.allCases.map(\.rawValue), "Best matching category ID. Use 'housing' for rent, 'bills' for utilities/credit card payments/subscriptions, 'food' for meals/groceries, 'transport' for rides/MRT, 'shopping' for purchases, 'health' for medical/gym, 'entertainment' for fun, 'salary'/'freelance'/'income' for income.")),
                        ("day_key", .schemaString("Optional transaction date in YYYY-MM-DD format, taken from the dates listed in the context (e.g. yesterday). Defaults to today if omitted.")),
                        ("note", .schemaString("Optional short note.")),
                        ("member", .schemaString("Optional household member: 'me', 'partner', or their display name.")),
                    ], required: ["name", "amount", "type", "category"]),
                    "List of one or more transactions to add."
                )),
            ], required: ["items"])
        ),

        ClaudeTool(
            name: updateTransactionName,
            description: "Update an existing transaction's amount, name, category, date, or note by its ID.",
            inputSchema: .schemaObject([
                ("transaction_id", .schemaString("ID of the transaction to update.")),
                ("name", .schemaString("Optional new name.")),
                ("amount", .schemaNumber("Optional new positive amount in active currency major units.")),
                ("category", .schemaEnum(CategoryID.allCases.map(\.rawValue), "Optional new category ID.")),
                ("day_key", .schemaString("Optional new date in YYYY-MM-DD format.")),
                ("note", .schemaString("Optional new note.")),
            ], required: ["transaction_id"])
        ),

        ClaudeTool(
            name: deleteTransactionName,
            description: "Delete an existing transaction by its ID.",
            inputSchema: .schemaObject([
                ("transaction_id", .schemaString("ID of the transaction to delete.")),
            ], required: ["transaction_id"])
        ),

        ClaudeTool(
            name: setBudgetsName,
            description: "Set or update one or more monthly spending budget limits by category. Use this whenever the user specifies monthly budget targets (e.g. 'budget tháng này ăn uống 800, nhà ở 3000' or 'set food budget to 600').",
            inputSchema: .schemaObject([
                ("month_key", .schemaString("Optional YYYY-MM month key. Defaults to the currently viewed month.")),
                ("items", .schemaArray(
                    of: .schemaObject([
                        ("category", .schemaEnum(CategoryID.expenseCategories.map(\.rawValue), "Expense category ID.")),
                        ("limit", .schemaNumber("Positive monthly limit amount in active currency major units.")),
                    ], required: ["category", "limit"]),
                    "One or more category budget limits to set."
                )),
            ], required: ["items"])
        ),

        ClaudeTool(
            name: deleteBudgetName,
            description: "Remove a monthly budget limit for a specific expense category.",
            inputSchema: .schemaObject([
                ("month_key", .schemaString("Optional YYYY-MM month key. Defaults to the currently viewed month.")),
                ("category", .schemaEnum(CategoryID.expenseCategories.map(\.rawValue), "Expense category ID to remove.")),
            ], required: ["category"])
        ),

        ClaudeTool(
            name: createSavingsGoalName,
            description: "Create a new savings goal. Use this whenever the user talks about saving money for a target (e.g. emergency fund, buying a car/house, trip, baby fund, etc.).",
            inputSchema: .schemaObject([
                ("name", .schemaString("Clear goal name (e.g. 'Japan trip', 'Mua xe', '日本旅行').")),
                ("target_amount", .schemaNumber("Positive target amount to save in active currency major units.")),
                ("saved_amount", .schemaNumber("Optional amount already saved (defaults to 0).")),
                ("icon", .schemaEnum(GoalIcon.allCases.map(\.rawValue), "Best fitting icon: target, shield (emergency), plane (travel), laptop (tech), house (home), heart (family).")),
            ], required: ["name", "target_amount"])
        ),

        ClaudeTool(
            name: updateSavingsGoalName,
            description: "Contribute money to an existing savings goal or update its target/saved amount or name.",
            inputSchema: .schemaObject([
                ("goal_id", .schemaString("Optional ID of the goal if known.")),
                ("goal_name", .schemaString("Name of the goal to match if goal_id is omitted.")),
                ("add_amount", .schemaNumber("Optional positive amount to add/contribute to the goal's saved total.")),
                ("new_target_amount", .schemaNumber("Optional new target amount.")),
                ("new_saved_amount", .schemaNumber("Optional absolute new saved amount.")),
                ("new_name", .schemaString("Optional renamed goal title.")),
            ], required: [])
        ),

        ClaudeTool(
            name: deleteSavingsGoalName,
            description: "Delete an existing savings goal by ID or name.",
            inputSchema: .schemaObject([
                ("goal_id", .schemaString("Optional ID of the goal.")),
                ("goal_name", .schemaString("Optional name of the goal to delete.")),
            ], required: [])
        ),
    ]

    public static func decode(
        _ toolUse: ClaudeToolUse,
        defaultDayKey: String,
        defaultMonthKey: String
    ) -> Result<AssistantCommand, AssistantToolDecodeError> {
        let input = toolUse.input
        if planToolNames.contains(toolUse.name) {
            return decodePlanTool(toolUse, todayKey: defaultDayKey)
        }
        switch toolUse.name {
        case addTransactionsName:
            guard let rawItems = input["items"]?.arrayValue, !rawItems.isEmpty else {
                return .failure(.invalidArguments("items must be a non-empty array"))
            }
            var parsed: [AssistantCommand.NewTransactionItem] = []
            for item in rawItems {
                guard let rawName = item["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !rawName.isEmpty,
                      let amount = item["amount"]?.doubleValue,
                      amount > 0
                else { continue }
                let type = item["type"]?.stringValue.flatMap(TransactionType.init(rawValue:)) ?? .expense
                var category = item["category"]?.stringValue.flatMap(CategoryID.init(rawValue:))
                    ?? (type == .income ? .income : .other)
                if category.transactionType != type {
                    category = type == .income ? .income : .other
                }
                let rawDay = item["day_key"]?.stringValue
                let dayKey = rawDay.flatMap { DateKey.date(fromDayKey: $0) != nil ? $0 : nil } ?? defaultDayKey
                let note = item["note"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let member = item["member"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                let currency = item["currency"]?.stringValue.flatMap { CurrencyCode(rawValue: $0.uppercased()) }
                parsed.append(.init(
                    name: rawName,
                    amountMajor: amount,
                    type: type,
                    category: category,
                    dayKey: dayKey,
                    note: note,
                    memberHint: member?.isEmpty == false ? member : nil,
                    currency: currency
                ))
            }
            guard !parsed.isEmpty else {
                return .failure(.invalidArguments("No valid transaction items provided"))
            }
            return .success(.addTransactions(parsed))

        case updateTransactionName:
            guard let id = input["transaction_id"]?.stringValue, !id.isEmpty else {
                return .failure(.invalidArguments("transaction_id is required"))
            }
            let name = input["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = input["amount"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
            let category = input["category"]?.stringValue.flatMap(CategoryID.init(rawValue:))
            let dayKey = input["day_key"]?.stringValue.flatMap { DateKey.date(fromDayKey: $0) != nil ? $0 : nil }
            let note = input["note"]?.stringValue
            return .success(.updateTransaction(
                id: id,
                name: name?.isEmpty == false ? name : nil,
                amountMajor: amount,
                category: category,
                dayKey: dayKey,
                note: note
            ))

        case deleteTransactionName:
            guard let id = input["transaction_id"]?.stringValue, !id.isEmpty else {
                return .failure(.invalidArguments("transaction_id is required"))
            }
            return .success(.deleteTransaction(id: id))

        case setBudgetsName:
            guard let rawItems = input["items"]?.arrayValue, !rawItems.isEmpty else {
                return .failure(.invalidArguments("items must be a non-empty array"))
            }
            let rawMonth = input["month_key"]?.stringValue
            let monthKey = rawMonth.flatMap { DateKey.date(fromMonthKey: $0) != nil ? $0 : nil } ?? defaultMonthKey
            var parsed: [AssistantCommand.BudgetItem] = []
            for item in rawItems {
                guard let catRaw = item["category"]?.stringValue,
                      let cat = CategoryID(rawValue: catRaw),
                      CategoryID.expenseCategories.contains(cat),
                      let limit = item["limit"]?.doubleValue,
                      limit > 0
                else { continue }
                parsed.append(.init(category: cat, limitMajor: limit))
            }
            guard !parsed.isEmpty else {
                return .failure(.invalidArguments("No valid budget items provided"))
            }
            return .success(.setBudgets(monthKey: monthKey, items: parsed))

        case deleteBudgetName:
            guard let catRaw = input["category"]?.stringValue,
                  let cat = CategoryID(rawValue: catRaw),
                  CategoryID.expenseCategories.contains(cat)
            else {
                return .failure(.invalidArguments("Valid expense category is required"))
            }
            let rawMonth = input["month_key"]?.stringValue
            let monthKey = rawMonth.flatMap { DateKey.date(fromMonthKey: $0) != nil ? $0 : nil } ?? defaultMonthKey
            return .success(.deleteBudget(monthKey: monthKey, category: cat))

        case createSavingsGoalName:
            guard let rawName = input["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawName.isEmpty,
                  let target = input["target_amount"]?.doubleValue,
                  target > 0
            else {
                return .failure(.invalidArguments("name and positive target_amount are required"))
            }
            let saved = max(0, input["saved_amount"]?.doubleValue ?? 0)
            let icon = input["icon"]?.stringValue.flatMap(GoalIcon.init(rawValue:)) ?? .target
            return .success(.createSavingsGoal(name: rawName, targetMajor: target, savedMajor: saved, icon: icon))

        case updateSavingsGoalName:
            let goalID = input["goal_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let goalName = input["goal_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (goalID?.isEmpty == false) || (goalName?.isEmpty == false) else {
                return .failure(.invalidArguments("Either goal_id or goal_name is required"))
            }
            let addAmount = input["add_amount"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
            let newTarget = input["new_target_amount"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
            let newSaved = input["new_saved_amount"]?.doubleValue.flatMap { $0 >= 0 ? $0 : nil }
            let newName = input["new_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(.updateSavingsGoal(
                goalID: goalID?.isEmpty == false ? goalID : nil,
                goalName: goalName?.isEmpty == false ? goalName : nil,
                addMajor: addAmount,
                newTargetMajor: newTarget,
                newSavedMajor: newSaved,
                newName: newName?.isEmpty == false ? newName : nil
            ))

        case deleteSavingsGoalName:
            let goalID = input["goal_id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let goalName = input["goal_name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (goalID?.isEmpty == false) || (goalName?.isEmpty == false) else {
                return .failure(.invalidArguments("Either goal_id or goal_name is required"))
            }
            return .success(.deleteSavingsGoal(
                goalID: goalID?.isEmpty == false ? goalID : nil,
                goalName: goalName?.isEmpty == false ? goalName : nil
            ))

        default:
            return .failure(.unknownTool(toolUse.name))
        }
    }
}

// MARK: - Deterministic helpers for tool execution

public enum AssistantAmounts {
    /// Storage amount in `household` currency for an amount the user stated in `stated` currency
    /// (approximate conversion via `CurrencyConverter`), and the note with the original amount
    /// appended when converted. Never below one payable unit.
    public static func storageMinor(
        amountMajor: Double,
        stated: CurrencyCode?,
        household: CurrencyCode,
        note: String,
        language: AppLanguage
    ) -> (minor: Int64, note: String) {
        let draft = ParsedTransactionDraft(name: "", amountMajor: amountMajor, currency: stated, note: note)
        let resolved = AITransactionParser.resolvedAmountAndNote(for: draft, targetCurrency: household, language: language)
        return (max(AdviserMath.step(for: household), resolved.amountMinor), resolved.note)
    }
}

public enum AssistantBudgetStatus {
    /// After an expense is saved: that category's budget for the month, computed (spent, limit,
    /// remaining or over, % used), so the model reports it without doing the sums. `nil` when the
    /// category has no budget that month.
    public static func line(
        category: CategoryID,
        monthKey: String,
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        currency: CurrencyCode
    ) -> String? {
        guard let budget = budgets.first(where: { !$0.isDeleted && $0.monthKey == monthKey && $0.category == category }) else { return nil }
        let spent = transactions
            .filter { !$0.isDeleted && $0.type == .expense && $0.category == category && $0.monthKey == monthKey }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: currency, language: .english) }
        let percent = AdviserMath.percent(spent, of: budget.limitMinor).map { String(format: "%.1f%%", $0) } ?? "n/a"
        let left = budget.limitMinor - spent
        let tail = left >= 0 ? "\(money(left)) left" : "over by \(money(-left))"
        return "Budget \(category.rawValue) \(monthKey): spent \(money(spent)) of \(money(budget.limitMinor)) (\(percent) used), \(tail)."
    }
}
