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
    /// Images attached to a user message (display copies live in `ChatImageStore`). Optional so
    /// history written before images existed still decodes.
    public var attachments: [ChatImageAttachment]?
    /// Salary consent cards shown in this assistant reply (what was asked and how it ended, never
    /// a salary figure). Optional so history written before consent cards existed still decodes.
    public var consents: [SalaryConsentRecord]?

    public init(
        id: UUID = UUID(),
        role: ClaudeMessage.Role,
        text: String,
        actions: [AssistantActionReceipt] = [],
        timestamp: Date = Date(),
        attachments: [ChatImageAttachment]? = nil,
        consents: [SalaryConsentRecord]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.actions = actions
        self.timestamp = timestamp
        self.attachments = attachments
        self.consents = consents
    }

    public var hasAttachments: Bool { !(attachments ?? []).isEmpty }
    public var hasConsents: Bool { !(consents ?? []).isEmpty }

    /// Worth keeping in history: has text, receipts, images or consent cards.
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !actions.isEmpty || hasAttachments || hasConsents
    }

    /// Adds `record` or replaces the card with the same id.
    mutating func upsertConsent(_ record: SalaryConsentRecord) {
        var list = consents ?? []
        if let index = list.firstIndex(where: { $0.id == record.id }) {
            list[index] = record
        } else {
            list.append(record)
        }
        consents = list
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

struct PersistedChatHistory: Codable {
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

    /// Context resent to the model (earlier turns' images replaced by placeholders).
    @ObservationIgnored private(set) var wireHistory: [ClaudeMessage] = []
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var didUserCancel = false
    @ObservationIgnored private let persistEnabled: Bool
    @ObservationIgnored private let historyURL: URL?
    /// Display copies of attached images (device-only files beside the history JSON).
    @ObservationIgnored public let imageStore: ChatImageStore?
    /// Upload copies of the most recent user turn's images, kept in memory so Retry can resend
    /// them; never persisted.
    @ObservationIgnored private var lastTurnImages: (entryID: UUID, images: [ClaudeImageSource])?
    /// Salary consent cards: the model's `request_salary_access` waits here for the user.
    public let salaryAccess = SalaryAccessBroker()
    /// `false` where no chat screen can show a consent card (Siri one-shots): salary requests are
    /// answered "unavailable" without asking.
    @ObservationIgnored var presentsConsentCards = true
    /// Chat screens currently on screen; a consent card needs one to be answered.
    @ObservationIgnored private var visibleChatScreens = 0

    public init(persist: Bool = true, imageStore: ChatImageStore? = nil) {
        self.persistEnabled = persist
        self.historyURL = persist ? Self.defaultHistoryFileURL : nil
        self.imageStore = imageStore ?? (persist ? ChatImageStore.standard() : nil)
        if persist {
            loadHistoryFromDisk()
        }
    }

    /// History and images at explicit locations (tests).
    init(historyFileURL: URL, imageStore: ChatImageStore) {
        self.persistEnabled = true
        self.historyURL = historyFileURL
        self.imageStore = imageStore
        loadHistoryFromDisk()
    }

    /// `true` when the backend that would answer the next message can read images (Claude).
    /// The on-device Apple Intelligence path sends text-only prompts.
    public static func canAttachImages(settings: AppSettings) -> Bool {
        settings.resolvedBackend(for: .assistantChat) == .claude
    }

    /// Placeholder that replaces an earlier turn's images in the context resent to the model.
    static func imagePlaceholder(count: Int) -> String {
        count == 1
            ? "[The user attached 1 image here earlier; it is no longer included.]"
            : "[The user attached \(count) images here earlier; they are no longer included.]"
    }

    /// Display copy of an attached image, or `nil` when the file is missing or unreadable.
    public func imageData(for attachment: ChatImageAttachment) -> Data? {
        imageStore?.load(attachment.id)
    }

    public func send(_ text: String, images: [PreparedChatImage] = [], settings: AppSettings, store: BudgetStore) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty, !isStreaming else { return }
        if !images.isEmpty, !Self.canAttachImages(settings: settings) {
            errorMessage = Self.imagesUnsupportedMessage(in: settings.language)
            return
        }
        var attachments: [ChatImageAttachment] = []
        for image in images.prefix(ImageUploadPolicy.maxImagesPerMessage) {
            if let imageStore { try? imageStore.save(image.displayJPEG, for: image.id) }
            attachments.append(image.attachment)
        }
        submit(
            trimmed,
            images: images.prefix(ImageUploadPolicy.maxImagesPerMessage).map(\.claudeSource),
            attachments: attachments,
            settings: settings,
            store: store
        )
    }

    public static func imagesUnsupportedMessage(in language: AppLanguage) -> String {
        L10n.text(
            language,
            en: "Images need the Claude assistant. Apple Intelligence on this device reads text only — switch AI provider to Claude in Settings to attach photos.",
            vi: "Gửi ảnh cần trợ lý Claude. Apple Intelligence trên máy chỉ đọc được chữ — hãy chuyển nhà cung cấp AI sang Claude trong Cài đặt để đính kèm ảnh.",
            zh: "发送图片需要使用 Claude 助手。本机的 Apple 智能仅支持文字——请在设置中将 AI 提供方切换为 Claude 以附加图片。"
        )
    }

    private func submit(
        _ trimmed: String,
        images: [ClaudeImageSource],
        attachments: [ChatImageAttachment],
        settings: AppSettings,
        store: BudgetStore
    ) {
        let lang = settings.language
        guard !trimmed.isEmpty || !images.isEmpty else { return }
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
        let userEntry = ChatEntry(role: .user, text: trimmed, attachments: attachments.isEmpty ? nil : attachments)
        messages.append(userEntry)
        wireHistory.append(.user(trimmed, images: images))
        lastTurnImages = images.isEmpty ? nil : (userEntry.id, images)
        persistCurrentSession()

        let assistantID = UUID()
        messages.append(ChatEntry(id: assistantID, role: .assistant, text: ""))
        isStreaming = true

        activeTask?.cancel()
        activeTask = Task {
            defer {
                self.isStreaming = false
                self.statusLabel = nil
                // The images were sent with their turn; later requests only carry a placeholder.
                self.replaceImagesInWireHistory()
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
                    tempService.presentsConsentCards = false
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
            let formatted = MoneyFormat.masked(MoneyFormat.format(minor: record.amountMinor, currency: settings.currency, language: lang), hidden: record.isSalaryMasked(hidden: settings.hideSalary))
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
        // Room for: figure tools -> salary request -> figure tools again -> answer, plus actions.
        let maxToolRounds = 6
        var diagnostic = "claude no-rounds"
        for round in 0...maxToolRounds {
            let systemPrompt = BudgetAssistantPrompt.systemPrompt(
                snapshot: store.monthlySnapshot,
                goals: store.activeGoals,
                plans: store.plans,
                currency: settings.currency,
                language: lang,
                myName: settings.currentMember.name,
                partnerName: settings.partnerDisplayName,
                hideSalary: settings.hideSalary,
                adviserSnapshot: AdviserSnapshot.lines(data: Self.adviserData(settings: settings, store: store))
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
                    if toolUse.name == SalaryAccessTool.name {
                        let outcome = await self.requestSalaryAccess(toolUse, assistantID: assistantID, settings: settings)
                        toolResults.append((id: toolUse.id, content: outcome.toolResult, isError: outcome.isError))
                        continue
                    }
                    if AdviserToolCatalog.names.contains(toolUse.name) {
                        let output = AdviserToolCatalog.run(toolUse, context: AdviserToolContext(
                            data: Self.adviserData(settings: settings, store: store),
                            currentMemberID: settings.currentMember.id,
                            members: store.knownMembers(settings: settings),
                            salaryRequestAvailable: self.presentsConsentCards && !self.salaryAccess.hasRequested(turnID: assistantID)
                        ))
                        toolResults.append((id: toolUse.id, content: output.text, isError: output.isError))
                        continue
                    }
                    let outcome = Self.execute(toolUse: toolUse, settings: settings, store: store)
                    toolResults.append((id: toolUse.id, content: outcome.toolOutput, isError: outcome.isError))
                    receipts.append(contentsOf: outcome.receipts)
                }

                if !receipts.isEmpty,
                   let idx = self.messages.firstIndex(where: { $0.id == assistantID }) {
                    self.messages[idx].actions.append(contentsOf: receipts)
                }

                self.wireHistory.append(.toolResults(toolResults))
                self.statusLabel = nil
                // Stopped while a consent card was waiting: end here (the results are recorded).
                try Task.checkCancellation()
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
        if let last = messages.last, last.role == .assistant, last.text.isEmpty, last.actions.isEmpty, !last.hasConsents {
            messages.removeLast()
        }
        persistCurrentSession()
    }

    // MARK: - Salary consent

    /// Runs one `request_salary_access` call: a consent card in the reply `assistantID`, waiting
    /// for Allow / Not now, then the gate. The card's final state is saved with the chat.
    func requestSalaryAccess(_ toolUse: ClaudeToolUse, assistantID: UUID, settings: AppSettings) async -> SalaryAccessOutcome {
        // Nobody can answer a card (Siri, or the user left the chat while the reply was running):
        // treated as declined.
        guard presentsConsentCards, visibleChatScreens > 0 else { return .unavailable }
        let lang = settings.language
        let previousStatus = statusLabel
        let outcome = await salaryAccess.request(
            reason: SalaryAccessTool.reason(from: toolUse.input),
            turnID: assistantID,
            gate: settings.salaryGate,
            language: lang
        ) { record in
            if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                self.messages[index].upsertConsent(record)
            }
            self.statusLabel = record.status == .pending
                ? L10n.text(lang, en: "Waiting for your answer…", vi: "Đang chờ bạn trả lời…", zh: "正在等待您的回答…")
                : previousStatus
            self.persistCurrentSession()
        }
        return outcome
    }

    /// Allow on a consent card.
    public func allowSalaryRequest(_ id: UUID) {
        salaryAccess.allow(id)
    }

    /// Not now on a consent card.
    public func declineSalaryRequest(_ id: UUID) {
        salaryAccess.decline(id)
    }

    public func chatScreenDidAppear() {
        visibleChatScreens += 1
    }

    /// The chat screen went away: a card still waiting is treated as Not now.
    public func chatScreenDidDisappear() {
        visibleChatScreens = max(0, visibleChatScreens - 1)
        if visibleChatScreens == 0 {
            salaryAccess.declinePending()
        }
    }

    /// The data the adviser tools and snapshot are computed from.
    static func adviserData(settings: AppSettings, store: BudgetStore, now: Date = Date()) -> AdviserDataSet {
        AdviserDataSet(
            transactions: store.activeTransactions,
            budgets: store.activeBudgets,
            goals: store.activeGoals,
            plans: store.plans,
            currency: settings.currency,
            todayKey: DateKey.dayKey(from: now),
            salaryHidden: settings.hideSalary
        )
    }

    public func retryLast(settings: AppSettings, store: BudgetStore) {
        guard !isStreaming else { return }
        guard let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) else { return }
        let entry = messages[lastUserIdx]
        let attachments = entry.attachments ?? []
        var images: [ClaudeImageSource] = []
        if !attachments.isEmpty {
            guard Self.canAttachImages(settings: settings) else {
                errorMessage = Self.imagesUnsupportedMessage(in: settings.language)
                return
            }
            if let cached = lastTurnImages, cached.entryID == entry.id {
                images = cached.images
            } else {
                // After a relaunch only the display copies remain: re-encode those for upload.
                images = attachments.compactMap { attachment in
                    imageStore?.load(attachment.id)
                        .flatMap { ChatImageEncoder.prepareFromDisplayCopy($0, id: attachment.id) }?
                        .claudeSource
                }
            }
        }
        messages.removeSubrange(lastUserIdx...)
        if let wireIdx = wireHistory.lastIndex(where: \.isUserTurn) {
            wireHistory.removeSubrange(wireIdx...)
        }
        submit(entry.text, images: images, attachments: attachments, settings: settings, store: store)
    }

    /// Starts a fresh chat while preserving the current conversation in history.
    public func startNewChat() {
        persistCurrentSession()
        didUserCancel = true
        salaryAccess.reset()
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        statusLabel = nil
        errorMessage = nil
        activeSessionID = nil
        messages.removeAll()
        wireHistory.removeAll()
        lastTurnImages = nil
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
        var orphaned = sessions.filter { $0.id == id }.reduce(into: Set<UUID>()) { $0.formUnion($1.attachmentIDs) }
        if activeSessionID == id {
            orphaned.formUnion(messages.flatMap { $0.attachments ?? [] }.map(\.id))
        }
        sessions.removeAll { $0.id == id }
        imageStore?.delete(orphaned)
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
        salaryAccess.reset()
        activeTask?.cancel()
        activeTask = nil
        isStreaming = false
        statusLabel = nil
        errorMessage = nil
        activeSessionID = nil
        messages.removeAll()
        wireHistory.removeAll()
        sessions.removeAll()
        lastTurnImages = nil
        imageStore?.deleteAll()
        saveHistoryToDisk()
    }

    // MARK: - Local History Persistence

    private static var defaultHistoryFileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("Tally", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ask-tally-history.json")
    }

    private func loadHistoryFromDisk() {
        guard let url = historyURL else { return }
        guard let data = try? Data(contentsOf: url) else {
            // No history at all: any stored image is left over.
            if !FileManager.default.fileExists(atPath: url.path) { imageStore?.removeOrphans(keeping: []) }
            return
        }
        guard let decoded = try? JSONDecoder().decode(PersistedChatHistory.self, from: data) else {
            return
        }
        sessions = decoded.sessions.sorted { $0.updatedAt > $1.updatedAt }
        // Images whose message is gone (e.g. a crash between saving the image and the history).
        imageStore?.removeOrphans(keeping: sessions.reduce(into: Set<UUID>()) { $0.formUnion($1.attachmentIDs) })
        if let activeID = decoded.activeSessionID,
           let active = sessions.first(where: { $0.id == activeID }) {
            activeSessionID = active.id
            messages = active.messages
            rebuildWireHistory(from: active.messages)
        }
    }

    private func persistCurrentSession() {
        guard persistEnabled else { return }
        let cleaned = messages.filter(\.hasContent)
        guard !cleaned.isEmpty else { return }

        let sessionID = activeSessionID ?? UUID()
        activeSessionID = sessionID

        let firstUserText = cleaned.first(where: { $0.role == .user && !$0.text.isEmpty })?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = firstUserText.isEmpty ? "Chat" : String(firstUserText.prefix(56))
        let updated = ChatSession(id: sessionID, title: title, updatedAt: Date(), messages: cleaned)

        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx] = updated
        } else {
            sessions.insert(updated, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        if sessions.count > 40 {
            let dropped = sessions.dropFirst(40).reduce(into: Set<UUID>()) { $0.formUnion($1.attachmentIDs) }
            sessions = Array(sessions.prefix(40))
            imageStore?.delete(dropped)
        }
        saveHistoryToDisk()
    }

    private func saveHistoryToDisk() {
        guard persistEnabled, let url = historyURL else { return }
        let payload = PersistedChatHistory(activeSessionID: activeSessionID, sessions: sessions)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rebuildWireHistory(from entries: [ChatEntry]) {
        wireHistory = entries.suffix(24).compactMap { entry in
            var trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let imageCount = entry.attachments?.count ?? 0
            if entry.role == .user, imageCount > 0 {
                trimmed = trimmed.isEmpty ? Self.imagePlaceholder(count: imageCount) : Self.imagePlaceholder(count: imageCount) + "\n" + trimmed
            }
            guard !trimmed.isEmpty else { return nil }
            return entry.role == .user ? .user(trimmed) : .assistant(trimmed)
        }
    }

    /// Replaces the image blocks of every user turn in the resent context with a placeholder.
    private func replaceImagesInWireHistory() {
        wireHistory = wireHistory.map { message in
            message.imageCount > 0 ? message.replacingImages(withPlaceholder: Self.imagePlaceholder(count: message.imageCount)) : message
        }
    }

    private func dropEmptyAssistant(id: UUID) {
        if let idx = messages.firstIndex(where: { $0.id == id }),
           messages[idx].text.isEmpty,
           messages[idx].actions.isEmpty,
           !messages[idx].hasConsents {
            messages.remove(at: idx)
        }
    }

    private func popDanglingUserWireMessage() {
        if let last = wireHistory.last, last.isUserTurn {
            wireHistory.removeLast()
        }
    }

    // MARK: - Cross-App Tool Execution

    struct ToolExecutionOutcome {
        let toolOutput: String
        let isError: Bool
        let receipts: [AssistantActionReceipt]
    }

    static func execute(
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
                var touchedBudgets: [(CategoryID, String)] = []
                for item in items {
                    let member = resolveMember(hint: item.memberHint, settings: settings, store: store)
                    let amount = AssistantAmounts.storageMinor(
                        amountMajor: item.amountMajor,
                        stated: item.currency,
                        household: currency,
                        note: item.note,
                        language: lang
                    )
                    let minor = amount.minor
                    let record = TransactionRecord(
                        name: item.name,
                        amountMinor: minor,
                        type: item.type,
                        category: item.category,
                        dayKey: item.dayKey,
                        note: amount.note,
                        source: .aiQuickAdd,
                        memberID: member.id,
                        memberName: member.name,
                        needsReview: false
                    )
                    store.saveTransaction(record)
                    store.ensureVisible(dayKey: record.dayKey)

                    let signedMinor = item.type == .income ? minor : -minor
                    let amtStr = MoneyFormat.masked(MoneyFormat.format(minor: signedMinor, currency: currency, language: lang, signed: item.type == .income), hidden: record.isSalaryMasked(hidden: settings.hideSalary))
                    receipts.append(AssistantActionReceipt(
                        kind: .transactionAdded,
                        emoji: item.category.cuteEmoji,
                        title: record.name,
                        subtitle: "\(item.category.title(in: lang)) · \(DateKey.formatCompactDay(record.dayKey, language: lang))",
                        amountText: amtStr,
                        isPositive: item.type == .income
                    ))
                    let converted = item.currency.map { $0 != currency } ?? false
                    summaries.append("Added transaction [id:\(record.id)] \(record.name) \(amtStr) in \(item.category.rawValue) on \(record.dayKey)\(converted ? " (converted from \(item.currency!.rawValue); note: \(record.note))" : "")")
                    if record.type == .expense, !touchedBudgets.contains(where: { $0 == (record.category, record.monthKey) }) {
                        touchedBudgets.append((record.category, record.monthKey))
                    }
                }
                for (category, monthKey) in touchedBudgets {
                    if let line = AssistantBudgetStatus.line(category: category, monthKey: monthKey, transactions: store.activeTransactions, budgets: store.activeBudgets, currency: currency) {
                        summaries.append(line)
                    }
                }
                return ToolExecutionOutcome(toolOutput: summaries.joined(separator: "\n"), isError: false, receipts: receipts)

            case .updateTransaction(let id, let name, let amountMajor, let category, let dayKey, let note):
                guard var tx = store.activeTransactions.first(where: { $0.id == id }) else {
                    return ToolExecutionOutcome(toolOutput: "Transaction not found with id \(id).", isError: true, receipts: [])
                }
                // Judged by the stored transaction, before any mutation below.
                let stored = tx
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
                let amtStr = MoneyFormat.masked(MoneyFormat.format(minor: signedMinor, currency: currency, language: lang, signed: tx.type == .income), hidden: SalaryPrivacy.masksToolEcho(stored: stored, resulting: tx, hidden: settings.hideSalary))
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

            case .createPlan, .convertTransactionToPlan, .updatePlan, .settlePlan, .undoPlanSettlement, .deletePlan:
                return executePlan(command, todayKey: todayKey, settings: settings, store: store)
            }
        }
    }

    static func resolveMember(hint: String?, settings: AppSettings, store: BudgetStore) -> HouseholdMember {
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

    static func matchGoal(id: String?, name: String?, in goals: [SavingsGoalRecord]) -> SavingsGoalRecord? {
        AdviserToolCatalog.matchGoal(id: id, name: name, in: goals)
    }
}
