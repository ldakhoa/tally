import BudgetKit
import ClaudeKit
import Foundation
import TallyCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Availability state of Apple's on-device Foundation Models (`SystemLanguageModel.default`).
public enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady
    case unsupportedOS

    public var isAvailable: Bool { self == .available }

    public static func current() -> AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .deviceNotEligible
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .modelNotReady
                @unknown default: return .modelNotReady
                }
            }
        }
        #endif
        return .unsupportedOS
    }

    public func headline(in language: AppLanguage) -> String {
        switch self {
        case .available:
            return L10n.text(language, en: "Apple Intelligence is ready", vi: "Apple Intelligence đã sẵn sàng", zh: "Apple 智能已就绪")
        case .notEnabled:
            return L10n.text(language, en: "Apple Intelligence is off", vi: "Chưa bật Apple Intelligence", zh: "未开启 Apple 智能")
        case .modelNotReady:
            return L10n.text(language, en: "Downloading on-device model…", vi: "Đang tải mô hình trên máy…", zh: "正在下载本地模型…")
        case .deviceNotEligible:
            return L10n.text(language, en: "Device not eligible", vi: "Thiết bị không hỗ trợ", zh: "设备不支持")
        case .unsupportedOS:
            return L10n.text(language, en: "Requires iOS 26 or newer", vi: "Cần iOS 26 trở lên", zh: "需要 iOS 26 或更高版本")
        }
    }

    public func detail(in language: AppLanguage) -> String {
        switch self {
        case .available:
            return L10n.text(
                language,
                en: "Free, private, on-device AI for Siri, bank alerts, and Tally Assistant.",
                vi: "AI chạy trên máy, miễn phí và riêng tư cho Siri, thông báo ngân hàng và Trợ lý Tally.",
                zh: "免费、私密的本地 AI，支持 Siri、银行通知解析与 Tally 助手。"
            )
        case .notEnabled:
            return L10n.text(
                language,
                en: "Turn on Apple Intelligence in iOS Settings → Apple Intelligence & Siri.",
                vi: "Bật trong Cài đặt iOS → Apple Intelligence & Siri.",
                zh: "请在 iOS 设置 → Apple 智能与 Siri 中开启。"
            )
        case .modelNotReady:
            return L10n.text(
                language,
                en: "iOS is preparing the on-device language model. Connect to Wi-Fi and try again shortly.",
                vi: "iOS đang tải mô hình ngôn ngữ về máy. Kết nối Wi-Fi và thử lại sau ít phút.",
                zh: "iOS 正在准备本地语言模型，请连接 Wi-Fi 稍后再试。"
            )
        case .deviceNotEligible:
            return L10n.text(
                language,
                en: "This device doesn't support Apple Intelligence. Use Claude API instead.",
                vi: "Thiết bị này không hỗ trợ Apple Intelligence. Hãy dùng Claude API.",
                zh: "此设备不支持 Apple 智能，请改用 Claude API。"
            )
        case .unsupportedOS:
            return L10n.text(
                language,
                en: "Update to iOS 26+ to use on-device Apple Foundation Models, or use Claude API.",
                vi: "Cập nhật iOS 26+ để dùng Apple Foundation Models, hoặc dùng Claude API.",
                zh: "升级至 iOS 26+ 即可使用本地 Apple 基础模型，或改用 Claude API。"
            )
        }
    }
}

// MARK: - AIClient Adapter for Apple Foundation Models (used by AITransactionParser & simple requests)

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
public struct AppleFoundationModelsClient: AIClient {
    public init() {}

    public func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard SystemLanguageModel.default.isAvailable else {
                        throw ClaudeError.malformedResponse("Apple Intelligence is not available on this device.")
                    }

                    var instructions = request.system ?? ""
                    if let schema = request.jsonSchema {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.sortedKeys]
                        if let data = try? encoder.encode(schema),
                           let schemaText = String(data: data, encoding: .utf8) {
                            instructions += "\n\nRespond ONLY with a single valid JSON object (no markdown fences, no extra prose) conforming to this JSON Schema:\n\(schemaText)"
                        }
                    }

                    let session = LanguageModelSession(
                        model: SystemLanguageModel.default,
                        instructions: instructions.isEmpty ? nil : instructions
                    )

                    let promptText = Self.flattenPrompt(from: request.messages)
                    if request.jsonSchema != nil {
                        let response = try await session.respond(to: promptText)
                        let cleaned = Self.extractJSONObject(from: response.content)
                        continuation.yield(.text(cleaned))
                        continuation.yield(.finished(ClaudeCompletion(
                            text: cleaned,
                            stopReason: "end_turn",
                            model: "apple-foundation-model"
                        )))
                    } else {
                        var emitted = ""
                        for try await snapshot in session.streamResponse(to: promptText) {
                            let full = snapshot.content
                            if full.hasPrefix(emitted) {
                                let delta = String(full.dropFirst(emitted.count))
                                if !delta.isEmpty {
                                    continuation.yield(.text(delta))
                                }
                                emitted = full
                            }
                        }
                        continuation.yield(.finished(ClaudeCompletion(
                            text: emitted,
                            stopReason: "end_turn",
                            model: "apple-foundation-model"
                        )))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: ClaudeError.malformedResponse(error.localizedDescription))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private static func flattenPrompt(from messages: [ClaudeMessage]) -> String {
        if messages.count == 1 {
            return messages[0].content
        }
        return messages.map { msg in
            let prefix = msg.role == .user ? "User" : "Assistant"
            return "\(prefix): \(msg.content)"
        }.joined(separator: "\n\n")
    }

    static func extractJSONObject(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return trimmed
    }
}

// MARK: - Native FoundationModels Cross-App Tools (Transactions, Budgets, Savings Goals)

@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class AppleToolContext {
    let settings: AppSettings
    let store: BudgetStore
    var receipts: [AssistantActionReceipt] = []

    init(settings: AppSettings, store: BudgetStore) {
        self.settings = settings
        self.store = store
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct FMAddTransactionArgs: Sendable {
    @Guide(description: "Short merchant or description, e.g. 'PayNow to friend', 'Rent', 'Coffee', 'Tiền nhà', '房租'")
    var name: String

    @Guide(description: "Positive numeric amount in the household's currency")
    var amount: Double

    @Guide(description: "Either 'expense' or 'income'")
    var type: String

    @Guide(description: "Category ID: food, housing, transport, shopping, bills, health, entertainment, other, salary, freelance, or income")
    var category: String

    @Guide(description: "Optional date in YYYY-MM-DD format; leave empty for today")
    var dayKey: String

    @Guide(description: "Optional short note or reason (e.g. 'lunch split', 'PayNow')")
    var note: String
}

@available(iOS 26.0, macOS 26.0, *)
struct FMAddTransactionTool: Tool {
    let name = "add_transaction"
    let description = "Record an expense or income transaction into Tally (e.g. PayNow transfer, rent, credit card payment, coffee, salary)."
    let context: AppleToolContext

    func call(arguments: FMAddTransactionArgs) async throws -> String {
        await MainActor.run {
            let lang = context.settings.language
            let currency = context.settings.currency
            let todayKey = DateKey.dayKey(from: Date())
            let txType = TransactionType(rawValue: arguments.type.lowercased()) ?? .expense
            var cat = CategoryID(rawValue: arguments.category.lowercased()) ?? (txType == .income ? .income : .other)
            if cat.transactionType != txType {
                cat = txType == .income ? .income : .other
            }
            let day = DateKey.date(fromDayKey: arguments.dayKey) != nil ? arguments.dayKey : todayKey
            let cleanedName = arguments.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = cleanedName.isEmpty ? cat.title(in: lang) : cleanedName
            let minor = max(1, currency.toStorageMinor(abs(arguments.amount)))
            let member = context.settings.currentMember

            let record = TransactionRecord(
                name: finalName,
                amountMinor: minor,
                type: txType,
                category: cat,
                dayKey: day,
                note: arguments.note.trimmingCharacters(in: .whitespacesAndNewlines),
                source: .aiQuickAdd,
                memberID: member.id,
                memberName: member.name,
                needsReview: false
            )
            context.store.saveTransaction(record)
            context.store.ensureVisible(dayKey: record.dayKey)

            let signedMinor = txType == .income ? minor : -minor
            let amtStr = MoneyFormat.format(minor: signedMinor, currency: currency, language: lang, signed: txType == .income)
            context.receipts.append(AssistantActionReceipt(
                kind: .transactionAdded,
                emoji: cat.cuteEmoji,
                title: record.name,
                subtitle: "\(cat.title(in: lang)) · \(DateKey.formatCompactDay(record.dayKey, language: lang))",
                amountText: amtStr,
                isPositive: txType == .income
            ))
            return "Saved \(record.name): \(amtStr) in \(cat.title(in: lang)) on \(record.dayKey)."
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct FMSetBudgetArgs: Sendable {
    @Guide(description: "Expense category ID: food, housing, transport, shopping, bills, health, entertainment, or other")
    var category: String

    @Guide(description: "Positive monthly limit amount in the household's currency")
    var limit: Double
}

@available(iOS 26.0, macOS 26.0, *)
struct FMSetBudgetTool: Tool {
    let name = "set_budget"
    let description = "Set or update a monthly spending budget limit for an expense category."
    let context: AppleToolContext

    func call(arguments: FMSetBudgetArgs) async throws -> String {
        await MainActor.run {
            let lang = context.settings.language
            let currency = context.settings.currency
            guard let cat = CategoryID(rawValue: arguments.category.lowercased()),
                  CategoryID.expenseCategories.contains(cat),
                  arguments.limit > 0
            else {
                return "Invalid budget category or amount."
            }
            let monthKey = context.store.selectedMonth
            let limitMinor = max(1, currency.toStorageMinor(arguments.limit))
            let record = BudgetLimitRecord(monthKey: monthKey, category: cat, limitMinor: limitMinor)
            context.store.saveBudget(record)

            let limitStr = MoneyFormat.format(minor: limitMinor, currency: currency, language: lang)
            let monthLabel = DateKey.formatMonth(monthKey, language: lang)
            context.receipts.append(AssistantActionReceipt(
                kind: .budgetSet,
                emoji: cat.cuteEmoji,
                title: cat.title(in: lang),
                subtitle: L10n.text(lang, en: "Budget · \(monthLabel)", vi: "Ngân sách · \(monthLabel)", zh: "预算 · \(monthLabel)"),
                amountText: limitStr
            ))
            return "Set \(cat.title(in: lang)) budget for \(monthLabel) to \(limitStr)."
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct FMCreateGoalArgs: Sendable {
    @Guide(description: "Savings goal name, e.g. 'Japan trip', 'Emergency fund', 'Mua xe'")
    var name: String

    @Guide(description: "Positive target amount to save")
    var targetAmount: Double

    @Guide(description: "Amount already saved, or 0 if starting fresh")
    var savedAmount: Double

    @Guide(description: "Icon: target, shield, plane, laptop, house, or heart")
    var icon: String
}

@available(iOS 26.0, macOS 26.0, *)
struct FMCreateGoalTool: Tool {
    let name = "create_savings_goal"
    let description = "Create a new savings goal when the user wants to save money for something."
    let context: AppleToolContext

    func call(arguments: FMCreateGoalArgs) async throws -> String {
        await MainActor.run {
            let lang = context.settings.language
            let currency = context.settings.currency
            let trimmed = arguments.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, arguments.targetAmount > 0 else {
                return "Goal name and positive target amount are required."
            }
            let icon = GoalIcon(rawValue: arguments.icon.lowercased()) ?? .target
            let targetMinor = max(1, currency.toStorageMinor(arguments.targetAmount))
            let savedMinor = max(0, currency.toStorageMinor(arguments.savedAmount))
            let goal = SavingsGoalRecord(name: trimmed, icon: icon, targetMinor: targetMinor, savedMinor: savedMinor)
            context.store.saveGoal(goal)

            let targetStr = MoneyFormat.format(minor: targetMinor, currency: currency, language: lang)
            let savedStr = MoneyFormat.format(minor: savedMinor, currency: currency, language: lang)
            context.receipts.append(AssistantActionReceipt(
                kind: .goalCreated,
                emoji: icon.cuteEmoji,
                title: goal.name,
                subtitle: L10n.text(lang, en: "Savings goal · \(savedStr) / \(targetStr)", vi: "Mục tiêu · \(savedStr) / \(targetStr)", zh: "存钱目标 · \(savedStr) / \(targetStr)"),
                amountText: targetStr,
                isPositive: true
            ))
            return "Created savings goal '\(goal.name)' with target \(targetStr)."
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct FMContributeGoalArgs: Sendable {
    @Guide(description: "Name of the existing savings goal")
    var goalName: String

    @Guide(description: "Positive amount to add to the goal's saved total")
    var addAmount: Double
}

@available(iOS 26.0, macOS 26.0, *)
struct FMContributeGoalTool: Tool {
    let name = "contribute_savings_goal"
    let description = "Add a savings contribution to an existing savings goal."
    let context: AppleToolContext

    func call(arguments: FMContributeGoalArgs) async throws -> String {
        await MainActor.run {
            let lang = context.settings.language
            let currency = context.settings.currency
            let needle = arguments.goalName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard arguments.addAmount > 0,
                  let goal = context.store.activeGoals.first(where: {
                      $0.name.lowercased() == needle || $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased())
                  })
            else {
                return "Could not find a matching savings goal."
            }
            let addMinor = max(1, currency.toStorageMinor(arguments.addAmount))
            context.store.addContribution(goalID: goal.id, amountMinor: addMinor)
            let updated = context.store.activeGoals.first(where: { $0.id == goal.id }) ?? goal
            let addStr = MoneyFormat.format(minor: addMinor, currency: currency, language: lang, signed: true)
            let savedStr = MoneyFormat.format(minor: updated.savedMinor, currency: currency, language: lang)
            let targetStr = MoneyFormat.format(minor: updated.targetMinor, currency: currency, language: lang)
            context.receipts.append(AssistantActionReceipt(
                kind: .goalUpdated,
                emoji: updated.icon.cuteEmoji,
                title: updated.name,
                subtitle: "\(savedStr) / \(targetStr) (\(updated.percent)%)",
                amountText: addStr,
                isPositive: true
            ))
            return "Added \(addStr) to '\(updated.name)' (now \(savedStr) / \(targetStr))."
        }
    }
}

/// Runs Tally's cross-app assistant on Apple's on-device Foundation Model with native tool calling.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public enum AppleAssistantRunner {
    public static func run(
        message: String,
        recentHistory: [ChatEntry],
        settings: AppSettings,
        store: BudgetStore,
        onTextUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> (text: String, receipts: [AssistantActionReceipt]) {
        guard SystemLanguageModel.default.isAvailable else {
            throw ClaudeError.malformedResponse(AppleIntelligenceStatus.current().detail(in: settings.language))
        }

        let toolContext = AppleToolContext(settings: settings, store: store)
        let tools: [any Tool] = [
            FMAddTransactionTool(context: toolContext),
            FMSetBudgetTool(context: toolContext),
            FMCreateGoalTool(context: toolContext),
            FMContributeGoalTool(context: toolContext),
        ]

        // Keep instructions compact so we stay comfortably inside the on-device context window.
        let instructions = compactSystemInstructions(settings: settings, store: store)
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: tools,
            instructions: instructions
        )

        var prompt = message
        let recentTurns = recentHistory.suffix(4)
        if !recentTurns.isEmpty {
            let transcript = recentTurns.map { entry in
                let who = entry.role == .user ? "User" : "Tally"
                return "\(who): \(entry.text)"
            }.joined(separator: "\n")
            prompt = "Recent context:\n\(transcript)\n\nUser now says: \(message)"
        }

        let stream = session.streamResponse(to: prompt)
        var latestText = ""
        for try await snapshot in stream {
            let text = snapshot.content
            if !text.isEmpty {
                latestText = text
                onTextUpdate(latestText)
            }
        }
        if latestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let finalResponse = try? await stream.collect(),
               !finalResponse.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                latestText = finalResponse.content
                onTextUpdate(latestText)
            }
        }
        return (latestText, toolContext.receipts)
    }

    private static func compactSystemInstructions(settings: AppSettings, store: BudgetStore) -> String {
        let lang = settings.language
        let currency = settings.currency
        let snapshot = store.monthlySnapshot
        let todayKey = DateKey.dayKey(from: Date())

        let spent = MoneyFormat.format(minor: snapshot.spendingMinor, currency: currency, language: lang)
        let income = MoneyFormat.format(minor: snapshot.incomeMinor, currency: currency, language: lang)
        let goalsSummary = store.activeGoals.prefix(5).map { "\($0.name) (\($0.percent)%)" }.joined(separator: ", ")
        let budgetsSummary = snapshot.budgets.prefix(6).map {
            "\($0.category.rawValue): \(MoneyFormat.format(minor: $0.limitMinor, currency: currency, language: lang))"
        }.joined(separator: ", ")

        return """
        You are Tally, a practical household budget assistant.
        \(lang.aiInstruction)
        Today is \(todayKey). Currency: \(currency.rawValue).
        This month (\(snapshot.monthKey)): income \(income), spending \(spent).
        Budgets: \(budgetsSummary.isEmpty ? "none" : budgetsSummary).
        Goals: \(goalsSummary.isEmpty ? "none" : goalsSummary).

        RULES:
        - When the user mentions spending, paying (e.g. PayNow, rent, credit card, meal), or receiving income: ALWAYS call `add_transaction` (call once per item).
        - When the user sets a monthly budget: ALWAYS call `set_budget`.
        - When the user wants to save for a goal: ALWAYS call `create_savings_goal` or `contribute_savings_goal`.
        - Translate generic transaction/goal names into the app's language (\(lang.resolved.rawValue)) while keeping brand names (FairPrice, Grab, PayNow) unchanged.
        - ALWAYS write a brief, friendly confirmation reply after calling a tool.
        """
    }
}
#endif
