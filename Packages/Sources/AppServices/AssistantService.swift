import BudgetKit
import ClaudeKit
import Foundation
import Observation
import TallyCore

public struct ChatEntry: Identifiable, Codable, Hashable, Sendable {
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

public struct ChatSession: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var updatedAt: Date
    public var messages: [ChatEntry]

    public init(
        id: UUID = UUID(),
        title: String,
        updatedAt: Date = Date(),
        messages: [ChatEntry]
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

private struct PersistedChatHistory: Codable {
    var activeSessionID: UUID?
    var sessions: [ChatSession]
}

/// Action-capable streaming Claude assistant with live cross-app access to
/// Transactions, Monthly Budgets, and Savings Goals.
@MainActor
@Observable
public final class AssistantService {
    public private(set) var messages: [ChatEntry] = []
    public private(set) var sessions: [ChatSession] = []
    public private(set) var activeSessionID: UUID?
    public private(set) var isStreaming = false
    public private(set) var statusLabel: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private var wireHistory: [ClaudeMessage] = []
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var didUserCancel = false
    @ObservationIgnored private let persistEnabled: Bool

    public init(persist: Bool = true) {
        self.persistEnabled = persist
        if persist {
            loadHistoryFromDisk()
        }
    }

    public func send(_ text: String, settings: AppSettings, store: BudgetStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let lang = settings.language
        guard let backend = settings.resolvedBackend(for: .assistantChat) else {
            errorMessage = settings.aiProvider == .appleIntelligence
                ? settings.appleIntelligenceStatus.detail(in: lang)
                : ClaudeError.missingAPIKey.localizedMessage(in: lang)
            return
        }

        errorMessage = nil
        statusLabel = nil
        didUserCancel = false
        let priorHistory = messages
        if activeSessionID == nil {
            activeSessionID = UUID()
        }
        messages.append(ChatEntry(role: .user, text: trimmed))
        wireHistory.append(.user(trimmed))
        persistCurrentSession()

        let assistantID = UUID()
        messages.append(ChatEntry(id: assistantID, role: .assistant, text: ""))
        isStreaming = true

        activeTask?.cancel()
        activeTask = Task {
            defer {
                self.isStreaming = false
                self.statusLabel = nil
                self.persistCurrentSession()
            }
            do {
                var lastDiagnostic = "backend=\(backend.rawValue)"

                switch backend {
                case .appleIntelligence:
                    #if canImport(FoundationModels)
                    if #available(iOS 26.0, macOS 26.0, *) {
                        let result = try await AppleAssistantRunner.run(
                            message: trimmed,
                            recentHistory: priorHistory,
                            settings: settings,
                            store: store
                        ) { partialText in
                            if let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                                self.messages[idx].text = partialText
                            }
                        }
                        lastDiagnostic = "apple text=\(result.text.count) receipts=\(result.receipts.count)"
                        if let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                            self.messages[idx].actions = result.receipts
                            let replyText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !replyText.isEmpty {
                                self.messages[idx].text = replyText
                            } else if !result.receipts.isEmpty {
                                self.messages[idx].text = Self.spokenSummary(for: result.receipts, language: lang)
                            }
                            if !self.messages[idx].text.isEmpty {
                                self.wireHistory.append(.assistant(self.messages[idx].text))
                            }
                        }
                    } else {
                        throw ClaudeError.malformedResponse(settings.appleIntelligenceStatus.detail(in: lang))
                    }
                    #else
                    throw ClaudeError.malformedResponse(settings.appleIntelligenceStatus.detail(in: lang))
                    #endif

                case .claude:
                    guard let client = settings.makeClaudeClient() else {
                        throw ClaudeError.missingAPIKey
                    }
                    lastDiagnostic = try await self.runClaudeLoop(client: client, assistantID: assistantID, settings: settings, store: store)
                }

                // If Apple Intelligence returned empty with no actions, transparently fall back to Claude if available.
                if backend == .appleIntelligence,
                   let idx = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   self.messages[idx].actions.isEmpty,
                   let claude = settings.makeClaudeClient() {
                    lastDiagnostic = try await self.runClaudeLoop(client: claude, assistantID: assistantID, settings: settings, store: store)
                }

                // Final safety net: NEVER leave a silent empty assistant bubble!
                if let idx = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !self.messages[idx].actions.isEmpty {
                        let fallback = Self.spokenSummary(for: self.messages[idx].actions, language: lang)
                        self.messages[idx].text = fallback
                        self.wireHistory.append(.assistant(fallback))
                    } else {
                        self.errorMessage = L10n.text(
                            lang,
                            en: "No reply received (\(lastDiagnostic)). Tap Retry.",
                            vi: "Không nhận được phản hồi (\(lastDiagnostic)). Hãy bấm Thử lại.",
                            zh: "未收到回复（\(lastDiagnostic)），请点击重试。"
                        )
                        self.dropEmptyAssistant(id: assistantID)
                        self.popDanglingUserWireMessage()
                    }
                }
            } catch is CancellationError {
                self.dropEmptyAssistant(id: assistantID)
                self.popDanglingUserWireMessage()
                if !self.didUserCancel {
                    self.errorMessage = L10n.text(
                        lang,
                        en: "Request was cancelled (\(backend.rawValue)). Tap Retry.",
                        vi: "Yêu cầu bị huỷ (\(backend.rawValue)). Hãy bấm Thử lại.",
                        zh: "请求被取消（\(backend.rawValue)），请点击重试。"
                    )
                }
                return
            } catch let err as ClaudeError {
                if let idx = self.messages.firstIndex(where: { $0.id == assistantID }),
                   !self.messages[idx].actions.isEmpty {
                    if self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.messages[idx].text = Self.spokenSummary(for: self.messages[idx].actions, language: lang)
                    }
                } else {
                    self.errorMessage = err.localizedMessage(in: lang)
                    self.dropEmptyAssistant(id: assistantID)
                    self.popDanglingUserWireMessage()
                }
            } catch {
                if let idx = self.messages.firstIndex(where: { $0.id == assistantID }),
                   !self.messages[idx].actions.isEmpty {
                    if self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.messages[idx].text = Self.spokenSummary(for: self.messages[idx].actions, language: lang)
                    }
                } else {
                    self.errorMessage = error.localizedDescription
                    self.dropEmptyAssistant(id: assistantID)
                    self.popDanglingUserWireMessage()
                }
            }
        }
    }

    /// One-shot cross-app assistant execution for Apple Siri (`TellTallyIntent`).
    /// Uses Apple Intelligence (on-device) or Claude based on `settings.aiProvider`,
    /// and falls back to offline transaction parsing if no AI backend is available.
    public static func runOneShot(
        message: String,
        settings: AppSettings,
        store: BudgetStore
    ) async -> (reply: String, receipts: [AssistantActionReceipt]) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang = settings.language
        guard !trimmed.isEmpty else {
            return (
                L10n.text(lang, en: "Tell me what you'd like to log or update.", vi: "Hãy nói khoản chi, ngân sách hoặc mục tiêu bạn muốn lưu.", zh: "请告诉我您想记录或更新的内容。"),
                []
            )
        }

        if let backend = settings.resolvedBackend(for: .siri) {
            switch backend {
            case .appleIntelligence:
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *) {
                    if let result = try? await AppleAssistantRunner.run(
                        message: trimmed,
                        recentHistory: [],
                        settings: settings,
                        store: store,
                        onTextUpdate: { _ in }
                    ) {
                        let spoken = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !spoken.isEmpty {
                            return (spoken, result.receipts)
                        }
                        if !result.receipts.isEmpty {
                            return (Self.spokenSummary(for: result.receipts, language: lang), result.receipts)
                        }
                    }
                }
                #endif

            case .claude:
                if let client = settings.makeClaudeClient() {
                    let tempService = AssistantService(persist: false)
                    tempService.wireHistory = [.user(trimmed)]
                    let tempID = UUID()
                    tempService.messages = [ChatEntry(id: tempID, role: .assistant, text: "")]
                    do {
                        try await tempService.runClaudeLoop(client: client, assistantID: tempID, settings: settings, store: store)
                        if let entry = tempService.messages.first(where: { $0.id == tempID }) {
                            let spoken = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !spoken.isEmpty {
                                return (spoken, entry.actions)
                            }
                            if !entry.actions.isEmpty {
                                return (Self.spokenSummary(for: entry.actions, language: lang), entry.actions)
                            }
                        }
                    } catch {
                        // Fall through to local parser fallback below.
                    }
                }
            }
        }

        // Offline fallback: parse as a transaction with LocalTransactionParser so Siri still works!
        if let parsed = LocalTransactionParser.parse(trimmed, defaultCurrency: settings.currency) {
            let member = settings.currentMember
            let resolved = AITransactionParser.resolvedAmountAndNote(
                for: parsed,
                targetCurrency: settings.currency,
                language: lang
            )
            let record = TransactionRecord(
                name: parsed.name,
                amountMinor: max(1, resolved.amountMinor),
                type: parsed.type,
                category: parsed.category,
                dayKey: parsed.dayKey,
                note: resolved.note,
                source: .shortcut,
                rawSourceText: trimmed,
                memberID: member.id,
                memberName: member.name,
                needsReview: false
            )
            store.saveTransaction(record)
            let formatted = MoneyFormat.format(minor: record.amountMinor, currency: settings.currency, language: lang)
            let reply = L10n.text(
                lang,
                en: "Logged \(record.name): \(formatted) in \(record.category.title(in: lang)).",
                vi: "Đã lưu \(record.name): \(formatted) vào mục \(record.category.title(in: lang)).",
                zh: "已记录 \(record.name)：\(formatted)（\(record.category.title(in: lang))）。"
            )
            return (reply, [])
        }

        return (
            L10n.text(
                lang,
                en: "I couldn't understand that yet. Enable Apple Intelligence or add a Claude API key in Tally Settings.",
                vi: "Mình chưa hiểu rõ yêu cầu này. Hãy bật Apple Intelligence hoặc thêm Claude API key trong Cài đặt Tally.",
                zh: "暂时无法理解这条内容。请在 Tally 设置中开启 Apple 智能或添加 Claude API 密钥。"
            ),
            []
        )
    }

    private static func spokenSummary(for receipts: [AssistantActionReceipt], language: AppLanguage) -> String {
        let items = receipts.map { r in
            if let amt = r.amountText { return "\(r.title) (\(amt))" }
            return r.title
        }.joined(separator: ", ")
        return L10n.text(
            language,
            en: "Done! Updated Tally: \(items).",
            vi: "Xong! Đã cập nhật Tally: \(items).",
            zh: "已完成！已更新 Tally：\(items)。"
        )
    }

    @discardableResult
    private func runClaudeLoop(
        client: any AIClient,
        assistantID: UUID,
        settings: AppSettings,
        store: BudgetStore
    ) async throws -> String {
        let lang = settings.language
        let maxToolRounds = 4
        var diagnostic = "claude no-rounds"
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

            guard let completion else {
                diagnostic = "claude r\(round) nil-completion"
                break
            }
            diagnostic = "claude r\(round) stop=\(completion.stopReason ?? "nil") text=\(completion.text.count) tools=\(completion.toolUses.count)"

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
            } else if let idx = self.messages.firstIndex(where: { $0.id == assistantID }),
                      self.messages[idx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !self.messages[idx].actions.isEmpty {
                let fallback = Self.spokenSummary(for: self.messages[idx].actions, language: lang)
                self.messages[idx].text = fallback
                self.wireHistory.append(.assistant(fallback))
            }
            break
        }
        return diagnostic
    }

    public func stop() {
        didUserCancel = true
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        statusLabel = nil
        if let last = messages.last, last.role == .assistant, last.text.isEmpty, last.actions.isEmpty {
            messages.removeLast()
        }
        persistCurrentSession()
    }

    public func retryLast(settings: AppSettings, store: BudgetStore) {
        guard !isStreaming else { return }
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let lastUserText = messages[lastUserIdx].text
        messages.removeSubrange(lastUserIdx...)
        if let wireIdx = wireHistory.lastIndex(where: { $0.role == .user && $0.blocks == nil }) {
            wireHistory.removeSubrange(wireIdx...)
        }
        send(lastUserText, settings: settings, store: store)
    }

    /// Starts a fresh chat while preserving the current conversation in history.
    public func startNewChat() {
        persistCurrentSession()
        didUserCancel = true
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        statusLabel = nil
        errorMessage = nil
        activeSessionID = nil
        messages.removeAll()
        wireHistory.removeAll()
        saveHistoryToDisk()
    }

    public func clear() {
        startNewChat()
    }

    public func selectSession(_ session: ChatSession) {
        guard !isStreaming else { return }
        persistCurrentSession()
        errorMessage = nil
        statusLabel = nil
        activeSessionID = session.id
        messages = session.messages
        rebuildWireHistory(from: session.messages)
        saveHistoryToDisk()
    }

    public func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = nil
            messages.removeAll()
            wireHistory.removeAll()
            errorMessage = nil
        }
        saveHistoryToDisk()
    }

    public func clearAllHistory() {
        didUserCancel = true
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        statusLabel = nil
        errorMessage = nil
        activeSessionID = nil
        messages.removeAll()
        wireHistory.removeAll()
        sessions.removeAll()
        saveHistoryToDisk()
    }

    // MARK: - Local History Persistence

    private static var historyFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Tally", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ask-tally-history.json")
    }

    private func loadHistoryFromDisk() {
        guard let url = Self.historyFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PersistedChatHistory.self, from: data) else {
            return
        }
        sessions = decoded.sessions.sorted { $0.updatedAt > $1.updatedAt }
        if let activeID = decoded.activeSessionID,
           let active = sessions.first(where: { $0.id == activeID }) {
            activeSessionID = active.id
            messages = active.messages
            rebuildWireHistory(from: active.messages)
        }
    }

    private func persistCurrentSession() {
        guard persistEnabled else { return }
        let cleaned = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.actions.isEmpty }
        guard !cleaned.isEmpty else { return }

        let sessionID = activeSessionID ?? UUID()
        activeSessionID = sessionID

        let firstUserText = cleaned.first(where: { $0.role == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Chat"
        let title = String(firstUserText.prefix(56))
        let updated = ChatSession(id: sessionID, title: title, updatedAt: Date(), messages: cleaned)

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx] = updated
        } else {
            sessions.insert(updated, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        if sessions.count > 40 {
            sessions = Array(sessions.prefix(40))
        }
        saveHistoryToDisk()
    }

    private func saveHistoryToDisk() {
        guard persistEnabled, let url = Self.historyFileURL else { return }
        let payload = PersistedChatHistory(activeSessionID: activeSessionID, sessions: sessions)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rebuildWireHistory(from entries: [ChatEntry]) {
        wireHistory = entries.suffix(24).compactMap { entry in
            let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return entry.role == .user ? .user(trimmed) : .assistant(trimmed)
        }
    }

    private func dropEmptyAssistant(id: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == id }),
           messages[idx].text.isEmpty,
           messages[idx].actions.isEmpty {
            messages.remove(at: idx)
        }
    }

    private func popDanglingUserWireMessage() {
        if let last = wireHistory.last, last.role == .user, last.blocks == nil {
            wireHistory.removeLast()
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
