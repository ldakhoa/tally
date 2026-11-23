import BudgetKit
import ClaudeKit
import Foundation
import Observation
import TallyCore

public struct ChatEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: ClaudeMessage.Role
    public var text: String
    public var actions: [AssistantActionReceipt]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: ClaudeMessage.Role,
        text: String,
        actions: [AssistantActionReceipt] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.actions = actions
        self.timestamp = timestamp
    }
}

/// Action-capable streaming Claude assistant with live cross-app access to
/// Transactions, Monthly Budgets, and Savings Goals.
@MainActor
@Observable
public final class AssistantService {
    public private(set) var messages: [ChatEntry] = []
    public private(set) var isStreaming = false
    public private(set) var statusLabel: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private var wireHistory: [ClaudeMessage] = []
    @ObservationIgnored private var activeTask: Task<Void, Never>?

    public init() {}

    public func send(_ text: String, settings: AppSettings, store: BudgetStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }
        guard let client = settings.makeAIClient() else {
            errorMessage = ClaudeError.missingAPIKey.localizedMessage(in: settings.language)
            return
        }

        errorMessage = nil
        statusLabel = nil
        messages.append(ChatEntry(role: .user, text: trimmed))
        wireHistory.append(.user(trimmed))

        let assistantID = UUID()
        messages.append(ChatEntry(role: .assistant, text: ""))
        isStreaming = true

        let lang = settings.language

        activeTask?.cancel()
        activeTask = Task {
            defer {
                self.isStreaming = false
                self.statusLabel = nil
            }
            do {
                let maxToolRounds = 4
                for round in 0...maxToolRounds {
                    let systemPrompt = BudgetAssistantPrompt.systemPrompt(
                        snapshot: store.monthlySnapshot,
                        goals: store.activeGoals,
                        currency: settings.currency,
                        language: lang,
                        myName: settings.currentMember.name,
                        partnerName: settings.partnerDisplayName
                    )

                    let request = ClaudeRequest(
                        system: systemPrompt,
                        messages: self.wireHistory,
                        maxTokens: 2_048,
                        effort: .low,
                        tools: AssistantToolCatalog.allTools,
                        cacheConversation: true
                    )

                    var completion: ClaudeCompletion?
                    var streamedPrefix = false
                    for try await event in client.stream(request) {
                        switch event {
                        case .text(let chunk):
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                                if round > 0 && !streamedPrefix && !self.messages[idx].text.isEmpty {
                                    self.messages[idx].text += "\n\n"
                                }
                                streamedPrefix = true
                                self.messages[idx].text += chunk
                            }
                        case .finished(let done):
                            completion = done
                        }
                    }

                    guard let completion else { break }

                    if completion.needsToolExecution && round < maxToolRounds {
                        self.wireHistory.append(.assistant(blocks: completion.assistantBlocks))
                        self.statusLabel = L10n.text(
                            lang,
                            en: "Updating your Tally data…",
                            vi: "Đang cập nhật dữ liệu Tally…",
                            zh: "正在更新您的 Tally 数据…"
                        )

                        var toolResults: [(id: String, content: String, isError: Bool)] = []
                        var receipts: [AssistantActionReceipt] = []

                        for toolUse in completion.toolUses {
                            let outcome = self.execute(toolUse: toolUse, settings: settings, store: store)
                            toolResults.append((id: toolUse.id, content: outcome.toolOutput, isError: outcome.isError))
                            receipts.append(contentsOf: outcome.receipts)
                        }

                        if !receipts.isEmpty,
                           let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                            self.messages[idx].actions.append(contentsOf: receipts)
                        }

                        self.wireHistory.append(.toolResults(toolResults))
                        self.statusLabel = nil
                        continue
                    }

                    if !completion.text.isEmpty {
                        self.wireHistory.append(.assistant(completion.text))
                    }
                    break
                }
            } catch is CancellationError {
                return
            } catch let err as ClaudeError {
                self.errorMessage = err.localizedMessage(in: lang)
                self.dropEmptyAssistant(id: assistantID)
            } catch {
                self.errorMessage = error.localizedDescription
                self.dropEmptyAssistant(id: assistantID)
            }
        }
    }

    public func clear() {
        activeTask?.cancel()
        isStreaming = false
        statusLabel = nil
        errorMessage = nil
        messages.removeAll()
        wireHistory.removeAll()
    }

    private func dropEmptyAssistant(id: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == id }),
           messages[idx].text.isEmpty,
           messages[idx].actions.isEmpty {
            messages.remove(at: idx)
        }
    }

    // MARK: - Cross-App Tool Execution

    private struct ToolExecutionOutcome {
        let toolOutput: String
        let isError: Bool
        let receipts: [AssistantActionReceipt]
    }

    private func execute(
        toolUse: ClaudeToolUse,
        settings: AppSettings,
        store: BudgetStore
    ) -> ToolExecutionOutcome {
        let lang = settings.language
        let currency = settings.currency
        let todayKey = DateKey.dayKey(from: Date())
        let activeMonth = store.selectedMonth

        switch AssistantToolCatalog.decode(toolUse, defaultDayKey: todayKey, defaultMonthKey: activeMonth) {
        case .failure(let error):
            return ToolExecutionOutcome(
                toolOutput: "Error: \(error)",
                isError: true,
                receipts: []
            )

        case .success(let command):
            switch command {
            case .addTransactions(let items):
                var receipts: [AssistantActionReceipt] = []
                var summaries: [String] = []
                for item in items {
                    let member = resolveMember(hint: item.memberHint, settings: settings, store: store)
                    let minor = max(1, currency.toStorageMinor(item.amountMajor))
                    let record = TransactionRecord(
                        name: item.name,
                        amountMinor: minor,
                        type: item.type,
                        category: item.category,
                        dayKey: item.dayKey,
                        note: item.note,
                        source: .aiQuickAdd,
                        memberID: member.id,
                        memberName: member.name,
                        needsReview: false
                    )
                    store.saveTransaction(record)
                    store.ensureVisible(dayKey: record.dayKey)

                    let signedMinor = item.type == .income ? minor : -minor
                    let amtStr = MoneyFormat.format(minor: signedMinor, currency: currency, language: lang, signed: item.type == .income)
                    receipts.append(AssistantActionReceipt(
                        kind: .transactionAdded,
                        emoji: item.category.cuteEmoji,
                        title: record.name,
                        subtitle: "\(item.category.title(in: lang)) · \(DateKey.formatCompactDay(record.dayKey, language: lang))",
                        amountText: amtStr,
                        isPositive: item.type == .income
                    ))
                    summaries.append("Added transaction [id:\(record.id)] \(record.name) \(amtStr) in \(item.category.rawValue) on \(record.dayKey)")
                }
                return ToolExecutionOutcome(toolOutput: summaries.joined(separator: "\n"), isError: false, receipts: receipts)

            case .updateTransaction(let id, let name, let amountMajor, let category, let dayKey, let note):
                guard var tx = store.activeTransactions.first(where: { $0.id == id }) else {
                    return ToolExecutionOutcome(toolOutput: "Transaction not found with id \(id).", isError: true, receipts: [])
                }
                if let name { tx.name = name }
                if let amountMajor { tx.amountMinor = max(1, currency.toStorageMinor(amountMajor)) }
                if let category {
                    tx.category = category
                    tx.type = category.transactionType
                }
                if let dayKey { tx.dayKey = dayKey }
                if let note { tx.note = note }
                store.saveTransaction(tx)
                let signedMinor = tx.type == .income ? tx.amountMinor : -tx.amountMinor
                let amtStr = MoneyFormat.format(minor: signedMinor, currency: currency, language: lang, signed: tx.type == .income)
                let receipt = AssistantActionReceipt(
                    kind: .transactionUpdated,
                    emoji: tx.category.cuteEmoji,
                    title: tx.name,
                    subtitle: L10n.text(lang, en: "Updated · \(tx.category.title(in: lang))", vi: "Đã cập nhật · \(tx.category.title(in: lang))", zh: "已更新 · \(tx.category.title(in: lang))"),
                    amountText: amtStr,
                    isPositive: tx.type == .income
                )
                return ToolExecutionOutcome(toolOutput: "Updated transaction \(tx.id): \(tx.name) \(amtStr).", isError: false, receipts: [receipt])

            case .deleteTransaction(let id):
                guard let tx = store.activeTransactions.first(where: { $0.id == id }) else {
                    return ToolExecutionOutcome(toolOutput: "Transaction not found with id \(id).", isError: true, receipts: [])
                }
                store.deleteTransaction(id: id)
                let receipt = AssistantActionReceipt(
                    kind: .transactionDeleted,
                    emoji: "🗑️",
                    title: tx.name,
                    subtitle: L10n.text(lang, en: "Deleted transaction", vi: "Đã xoá giao dịch", zh: "已删除账单")
                )
                return ToolExecutionOutcome(toolOutput: "Deleted transaction \(tx.name) (\(id)).", isError: false, receipts: [receipt])

            case .setBudgets(let monthKey, let items):
                var receipts: [AssistantActionReceipt] = []
                var summaries: [String] = []
                let monthLabel = DateKey.formatMonth(monthKey, language: lang)
                for item in items {
                    let limitMinor = max(1, currency.toStorageMinor(item.limitMajor))
                    let record = BudgetLimitRecord(monthKey: monthKey, category: item.category, limitMinor: limitMinor)
                    store.saveBudget(record)
                    let limitStr = MoneyFormat.format(minor: limitMinor, currency: currency, language: lang)
                    receipts.append(AssistantActionReceipt(
                        kind: .budgetSet,
                        emoji: item.category.cuteEmoji,
                        title: item.category.title(in: lang),
                        subtitle: L10n.text(lang, en: "Budget · \(monthLabel)", vi: "Ngân sách · \(monthLabel)", zh: "预算 · \(monthLabel)"),
                        amountText: limitStr
                    ))
                    summaries.append("Set budget for \(item.category.rawValue) in \(monthKey) to \(limitStr)")
                }
                return ToolExecutionOutcome(toolOutput: summaries.joined(separator: "\n"), isError: false, receipts: receipts)

            case .deleteBudget(let monthKey, let category):
                let budgetID = "\(monthKey)/\(category.rawValue)"
                guard store.activeBudgets.contains(where: { $0.id == budgetID }) else {
                    return ToolExecutionOutcome(toolOutput: "No budget found for \(category.rawValue) in \(monthKey).", isError: true, receipts: [])
                }
                store.deleteBudget(id: budgetID)
                let receipt = AssistantActionReceipt(
                    kind: .budgetDeleted,
                    emoji: "🗑️",
                    title: category.title(in: lang),
                    subtitle: L10n.text(lang, en: "Removed budget", vi: "Đã xoá ngân sách", zh: "已删除预算")
                )
                return ToolExecutionOutcome(toolOutput: "Deleted budget \(budgetID).", isError: false, receipts: [receipt])

            case .createSavingsGoal(let name, let targetMajor, let savedMajor, let icon):
                let targetMinor = max(1, currency.toStorageMinor(targetMajor))
                let savedMinor = max(0, currency.toStorageMinor(savedMajor))
                let goal = SavingsGoalRecord(
                    name: name,
                    icon: icon,
                    targetMinor: targetMinor,
                    savedMinor: savedMinor
                )
                store.saveGoal(goal)
                let targetStr = MoneyFormat.format(minor: targetMinor, currency: currency, language: lang)
                let savedStr = MoneyFormat.format(minor: savedMinor, currency: currency, language: lang)
                let receipt = AssistantActionReceipt(
                    kind: .goalCreated,
                    emoji: icon.cuteEmoji,
                    title: goal.name,
                    subtitle: L10n.text(lang, en: "Savings goal · \(savedStr) / \(targetStr)", vi: "Mục tiêu · \(savedStr) / \(targetStr)", zh: "存钱目标 · \(savedStr) / \(targetStr)"),
                    amountText: targetStr,
                    isPositive: true
                )
                return ToolExecutionOutcome(toolOutput: "Created savings goal [id:\(goal.id)] '\(goal.name)' target \(targetStr), saved \(savedStr).", isError: false, receipts: [receipt])

            case .updateSavingsGoal(let goalID, let goalName, let addMajor, let newTargetMajor, let newSavedMajor, let newName):
                guard var goal = matchGoal(id: goalID, name: goalName, in: store.activeGoals) else {
                    return ToolExecutionOutcome(toolOutput: "Could not find matching savings goal.", isError: true, receipts: [])
                }
                if let newName { goal.name = newName }
                if let newTargetMajor { goal.targetMinor = max(1, currency.toStorageMinor(newTargetMajor)) }
                if let newSavedMajor { goal.savedMinor = max(0, currency.toStorageMinor(newSavedMajor)) }
                if let addMajor { goal.savedMinor += max(1, currency.toStorageMinor(addMajor)) }
                store.saveGoal(goal)

                let targetStr = MoneyFormat.format(minor: goal.targetMinor, currency: currency, language: lang)
                let savedStr = MoneyFormat.format(minor: goal.savedMinor, currency: currency, language: lang)
                let badgeAmount: String? = addMajor.map {
                    MoneyFormat.format(minor: currency.toStorageMinor($0), currency: currency, language: lang, signed: true)
                } ?? "\(goal.percent)%"
                let receipt = AssistantActionReceipt(
                    kind: .goalUpdated,
                    emoji: goal.icon.cuteEmoji,
                    title: goal.name,
                    subtitle: "\(savedStr) / \(targetStr) (\(goal.percent)%)",
                    amountText: badgeAmount,
                    isPositive: true
                )
                return ToolExecutionOutcome(toolOutput: "Updated goal '\(goal.name)': \(savedStr) / \(targetStr) (\(goal.percent)%).", isError: false, receipts: [receipt])

            case .deleteSavingsGoal(let goalID, let goalName):
                guard let goal = matchGoal(id: goalID, name: goalName, in: store.activeGoals) else {
                    return ToolExecutionOutcome(toolOutput: "Could not find matching savings goal.", isError: true, receipts: [])
                }
                store.deleteGoal(id: goal.id)
                let receipt = AssistantActionReceipt(
                    kind: .goalDeleted,
                    emoji: "🗑️",
                    title: goal.name,
                    subtitle: L10n.text(lang, en: "Deleted savings goal", vi: "Đã xoá mục tiêu", zh: "已删除存钱目标")
                )
                return ToolExecutionOutcome(toolOutput: "Deleted savings goal '\(goal.name)'.", isError: false, receipts: [receipt])
            }
        }
    }

    private func resolveMember(hint: String?, settings: AppSettings, store: BudgetStore) -> HouseholdMember {
        guard let raw = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return settings.currentMember
        }
        let lowered = raw.lowercased()
        let partnerTokens: Set<String> = ["partner", "wife", "husband", "spouse", "vợ", "vo", "chồng", "chong", "老婆", "妻子", "老公", "伴侣"]
        let partnerName = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if partnerTokens.contains(lowered) || (!partnerName.isEmpty && lowered == partnerName.lowercased()) {
            let known = store.knownMembers(settings: settings)
            if let existingPartner = known.first(where: { $0.id != settings.currentMember.id }) {
                return existingPartner
            }
            let fallback = partnerName.isEmpty
                ? L10n.text(settings.language, en: "Partner", vi: "Vợ", zh: "伴侣")
                : partnerName
            return HouseholdMember(id: HouseholdMember.defaultPartnerID, name: fallback)
        }

        if let matched = store.knownMembers(settings: settings).first(where: { $0.name.lowercased() == lowered }) {
            return matched
        }
        return settings.currentMember
    }

    private func matchGoal(id: String?, name: String?, in goals: [SavingsGoalRecord]) -> SavingsGoalRecord? {
        if let id, let exact = goals.first(where: { $0.id == id }) {
            return exact
        }
        if let name {
            let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let exact = goals.first(where: { $0.name.lowercased() == needle }) {
                return exact
            }
            if let partial = goals.first(where: { $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased()) }) {
                return partial
            }
        }
        return nil
    }
}
