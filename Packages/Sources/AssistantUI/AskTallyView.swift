import AppServices
import BudgetKit
import ClaudeKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore
import UniformTypeIdentifiers
#if os(iOS)
import PhotosUI
import UIKit
#else
import AppKit
#endif

public struct AskTallyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(AssistantService.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("tally.dictation.language") private var dictationLanguageID = ""
    @State private var draft = ""
    @State private var draftBeforeDictation = ""
    @State private var dictation = VoiceDictationManager()
    @State private var copiedMessageID: UUID?
    @State private var celebrationTrigger = 0
    @State private var path: [Route] = []
    @State private var didRestoreRoute = false
    @State private var pendingImages: [PreparedChatImage] = []
    @State private var preparingCount = 0
    @State private var attachmentBatchID = UUID()
    @State private var attachNote: String?
    @State private var viewerItem: ChatImageViewerItem?
    @State private var editingTransaction: TransactionRecord?
    @State private var hasScrolled = false
    @State private var lastMessageIsOffscreen = false
    @State private var isAtBottom = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @State private var photoSelection: [PhotosPickerItem] = []
    #else
    @State private var isShowingFileImporter = false
    #endif
    @FocusState private var isComposerFocused: Bool

    private let bottomAnchorID = "ask-tally-bottom-anchor"

    private enum Route: Hashable { case conversation }

    public init() {}

    public var body: some View {
        let lang = settings.language
        NavigationStack(path: $path) {
            chatHistory(lang: lang)
                .navigationDestination(for: Route.self) { _ in
                    conversation(lang: lang)
                }
        }
        .onAppear {
            guard !didRestoreRoute else { return }
            didRestoreRoute = true
            if assistant.activeSessionID != nil {
                path = [.conversation]
            }
        }
        .cozySheetFrame(minWidth: 540, idealWidth: 640, minHeight: 600, idealHeight: 700)
        .interactiveDismissDisabled(
            !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !pendingImages.isEmpty
                || dictation.isRecording
                || assistant.isStreaming
        )
    }

    private func conversation(lang: AppLanguage) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !settings.isAIReady {
                            setupEmptyState(lang: lang)
                        } else if assistant.messages.isEmpty {
                            welcomeEmptyState(lang: lang)
                        } else {
                            ForEach(assistant.messages) { msg in
                                messageRow(for: msg, lang: lang)
                                    .background {
                                        if msg.id == assistant.messages.last?.id {
                                            Color.clear.onGeometryChange(for: Bool.self) { geometry in
                                                guard let viewport = geometry.bounds(of: .scrollView) else { return false }
                                                return !viewport.intersects(CGRect(origin: .zero, size: geometry.size))
                                            } action: { lastMessageIsOffscreen = $0 }
                                        }
                                    }
                                    .id(msg.id)
                            }

                            if let status = assistant.statusLabel {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(status)
                                        .font(.appCaption.weight(.medium))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.softFill, in: Capsule())
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }

                        if let err = assistant.errorMessage {
                            errorBanner(err, lang: lang)
                        }

                        if let micErr = dictation.errorMessage {
                            Text(micErr)
                                .font(.appCaption)
                                .foregroundStyle(Color.negative)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.negative.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        Color.clear
                            .frame(height: 6)
                            .onGeometryChange(for: Bool.self) { geometry in
                                guard let viewport = geometry.bounds(of: .scrollView) else { return true }
                                return viewport.maxY >= 0
                            } action: { atBottom in
                                isAtBottom = atBottom
                                if atBottom { hasScrolled = false }
                            }
                            .id(bottomAnchorID)
                    }
                    .documentColumn()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isComposerFocused {
                            isComposerFocused = false
                        }
                    }
                    #if os(macOS)
                    .modifier(LegacyChatScrollIntent { hasScrolled = true })
                    #endif
                }
                .modifier(ChatScrollIntent { hasScrolled = true })
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: assistant.messages.count) { _, _ in
                    followLatestMessage(proxy: proxy, animated: true)
                }
                .onChange(of: assistant.messages.last?.text) { _, _ in
                    followLatestMessage(proxy: proxy, animated: false)
                }
                .onChange(of: assistant.messages.last?.actions.count) { oldCount, newCount in
                    followLatestMessage(proxy: proxy, animated: true)
                    if let newCount, newCount > (oldCount ?? 0) {
                        celebrationTrigger += 1
                    }
                }
                .onChange(of: assistant.salaryAccess.pending?.id) { _, _ in
                    followLatestMessage(proxy: proxy, animated: true)
                }
                .onChange(of: isComposerFocused) { _, focused in
                    if focused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            followLatestMessage(proxy: proxy, animated: true)
                        }
                    }
                }
                .task(id: assistant.activeSessionID) {
                    hasScrolled = false
                    scrollToBottom(proxy: proxy, animated: false)
                }
                .overlay(alignment: .bottomTrailing) {
                    if hasScrolled && lastMessageIsOffscreen && !assistant.messages.isEmpty {
                        Button {
                            scrollToBottom(proxy: proxy, animated: true)
                        } label: {
                            CozyUIIcon(.chevronDown, size: 18, color: Color.onInk)
                                .frame(width: 44, height: 44)
                                .background(Color.ink, in: Circle())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text(lang, en: "Scroll to latest message", vi: "Cuộn đến tin nhắn mới nhất", zh: "滚动到最新消息"))
                        .padding(12)
                    }
                }
            }

            // Live voice dictation bar (appears smoothly when recording)
            if dictation.isRecording {
                liveDictationBanner(lang: lang)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Cozy floating chat composer bar (swipe down to dismiss keyboard)
            composerBar(lang: lang)
        }
        .overlay(alignment: .bottom) {
            CozyCelebrationOverlay(trigger: celebrationTrigger)
                .padding(.bottom, 92)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: dictation.isRecording)
        .pageBackground()
        .onAppear { assistant.chatScreenDidAppear() }
        // A consent card still waiting when the chat goes away counts as Not now.
        .onDisappear { assistant.chatScreenDidDisappear() }
        #if os(iOS)
        .navigationTitle(conversationTitle(lang: lang))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { doneButton(lang: lang) }
        }
        .modifier(ChatHistorySwipe(onSwipe: showHistory))
        #else
        .navigationBarBackButtonHidden(true)
        .cozySheetToolbar(title: conversationTitle(lang: lang)) {
            Button(action: showHistory) {
                Label(L10n.text(lang, en: "Chats", vi: "Danh sách chat", zh: "对话列表"), systemImage: "chevron.left")
            }
        } trailing: {
            doneButton(lang: lang)
        }
        #endif
        .onDisappear {
            dictation.stop()
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            guard canAttachImages else {
                attachNote = AssistantService.imagesUnsupportedMessage(in: lang)
                return false
            }
            return attachImages(from: providers)
        }
        #if os(macOS)
        .onPasteCommand(of: [.image, .fileURL]) { providers in
            guard canAttachImages else { return }
            _ = attachImages(from: providers)
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let slots = ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount)
            prepareImages(urls.prefix(slots).map { url in
                { @Sendable in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try? Data(contentsOf: url)
                }
            })
        }
        #else
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            let slots = ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount)
            prepareImages(items.prefix(slots).map { item in
                { @Sendable in try? await item.loadTransferable(type: Data.self) }
            })
        }
        #endif
        #if os(iOS)
        .fullScreenCover(item: $viewerItem) { item in
            ChatImageViewer(attachment: item.attachment, data: imageLoader(for: item.attachment), language: lang)
        }
        #else
        .sheet(item: $viewerItem) { item in
            ChatImageViewer(attachment: item.attachment, data: imageLoader(for: item.attachment), language: lang)
        }
        #endif
        .sheet(item: $editingTransaction) { tx in
            TransactionEditorSheet(existing: tx)
        }
    }

    private func conversationTitle(lang: AppLanguage) -> String {
        assistant.sessions.first { $0.id == assistant.activeSessionID }?.title
            ?? L10n.text(lang, en: "New Chat", vi: "Chat mới", zh: "新对话")
    }

    private func doneButton(lang: AppLanguage) -> some View {
        Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
            dictation.stop()
            dismiss()
        }
    }

    private func chatHistory(lang: AppLanguage) -> some View {
        ChatHistoryList(
            sessions: assistant.sessions,
            activeSessionID: assistant.activeSessionID,
            isStreaming: assistant.isStreaming,
            language: lang,
            onSelect: { session in
                if session.id != assistant.activeSessionID {
                    guard !assistant.isStreaming else { return }
                    resetComposer()
                    assistant.selectSession(session)
                }
                CozyHaptics.selection()
                path = [.conversation]
            },
            onDelete: { id in
                guard !assistant.isStreaming || id != assistant.activeSessionID else { return }
                if id == assistant.activeSessionID { resetComposer() }
                CozyHaptics.light()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    assistant.deleteSession(id: id)
                }
            }
        )
        .cozySheetToolbar(title: "Ask Tally") {
            Button(L10n.text(lang, en: "Close", vi: "Đóng", zh: "关闭")) { dismiss() }
        } trailing: {
            Button(action: startNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.text(lang, en: "New chat", vi: "Chat mới", zh: "新对话"))
        }
    }

    private func showHistory() {
        CozyHaptics.light()
        isComposerFocused = false
        path.removeAll()
    }

    private func startNewChat() {
        CozyHaptics.light()
        resetComposer()
        assistant.startNewChat()
        path = [.conversation]
    }

    private func resetComposer() {
        dictation.stop()
        isComposerFocused = false
        draft = ""
        draftBeforeDictation = ""
        pendingImages = []
        preparingCount = 0
        attachmentBatchID = UUID()
        attachNote = nil
    }

    // MARK: - Empty States

    private func setupEmptyState(lang: AppLanguage) -> some View {
        EmptyStateCard(
            symbol: "sparkles",
            title: L10n.text(lang, en: "Set up AI Assistant", vi: "Thiết lập Trợ lý AI", zh: "设置 AI 助手"),
            message: L10n.text(
                lang,
                en: "Enable on-device Apple Intelligence or add your Anthropic API key in Settings to log expenses, set budgets, create savings goals, and chat about spending.",
                vi: "Bật Apple Intelligence trên máy hoặc thêm Anthropic API key trong Cài đặt để chat ghi chi tiêu, đặt ngân sách, tạo mục tiêu tiết kiệm và hỏi đáp.",
                zh: "开启本地 Apple 智能或在设置中添加 Anthropic API 密钥，即可通过对话记账、设置预算、创建存钱目标并分析家庭收支。"
            ),
            actionTitle: L10n.text(lang, en: "Open Settings", vi: "Mở Cài đặt", zh: "打开设置")
        ) {
            dismiss()
            settings.isShowingSettings = true
        }
    }

    private func welcomeEmptyState(lang: AppLanguage) -> some View {
        let prompts = BudgetAssistantPrompt.suggestedPrompts(in: lang)
        let tints: [Color] = [
            Color(hex: 0xF0944D),
            Color(hex: 0x5B9EC9),
            Color(hex: 0xD97CA6),
            Color(hex: 0x459E6E)
        ]
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let heroColors: [Color] = isDark
            ? [Color(hex: 0x3A2A25), Color(hex: 0x2F2224)]
            : [Color(hex: 0xFFE9D8), Color(hex: 0xFFF6EA)]

        return VStack(alignment: .leading, spacing: 14) {
            // Cozy Paws & Cream assistant hero header
            ZStack {
                PawPrintBackdrop(tint: .accent)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                CoupleAvatarsBadge(avatarSize: 22, showHeart: true)
                                Text(L10n.text(lang, en: "Hi! How can Tally help?", vi: "Chào hai bạn! Tally giúp gì nhé?", zh: "你好！有什么可以帮你？"))
                                    .font(.appHeading)
                            }
                            HStack(spacing: 6) {
                                Text(DateKey.formatMonth(store.selectedMonth, language: lang))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                if let backend = settings.resolvedBackend(for: .assistantChat) {
                                    Text("·")
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Tag(
                                        text: backend == .appleIntelligence
                                            ? L10n.text(lang, en: "Apple Intelligence", vi: "Apple Intelligence", zh: "Apple 智能")
                                            : settings.model.name,
                                        color: backend == .appleIntelligence ? .positive : .accent
                                    )
                                }
                            }
                        }
                        Spacer(minLength: 4)
                        CozyPetDuoView(mood: .happy, petSize: 48)
                    }

                    Text(L10n.text(
                        lang,
                        en: "Describe an expense or send a bank alert to log it. You can also ask about budgets, savings goals, and spending.",
                        vi: "Mô tả khoản chi hoặc gửi thông báo ngân hàng để ghi giao dịch. Bạn cũng có thể hỏi về ngân sách, mục tiêu tiết kiệm và chi tiêu.",
                        zh: "描述一笔支出或发送银行通知即可记账，也可以询问预算、储蓄目标和消费情况。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(18)
            }
            .background {
                shape.fill(LinearGradient(colors: heroColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .floatingShadow(!isDark)
            }
            .overlay {
                shape.strokeBorder(Color.accent.opacity(isDark ? 0.25 : 0.2), lineWidth: 1.2)
            }
            .clipShape(shape)
            .cozyEntrance(index: 0)

            // Quick starter prompt cards
            VStack(spacing: 10) {
                ForEach(Array(prompts.enumerated()), id: \.offset) { idx, prompt in
                    let tint = tints[idx % tints.count]
                    Button {
                        CozyHaptics.light()
                        CozySounds.play(.pop)
                        isComposerFocused = false
                        assistant.send(prompt, settings: settings, store: store)
                    } label: {
                        HStack(spacing: 12) {
                            starterPromptIcon(index: idx, tint: tint)
                            Text(prompt)
                                .font(.appSecondary)
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            CozyUIIcon(.trendUp, size: 13, color: Color.accent.opacity(0.75))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .cardSurface(cornerRadius: 18)
                    }
                    .buttonStyle(.cozyCard)
                    .cozyEntrance(index: idx + 1)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func starterPromptIcon(index: Int, tint: Color) -> some View {
        let idx = index % 4
        if idx == 2 {
            CozyMetricIcon(kind: .budget, size: 36)
        } else {
            ZStack {
                switch idx {
                case 0:
                    CozyCategoryIcon(category: .food, size: 22, style: .watercolor)
                case 1:
                    CozyTabIconView(kind: .statistics, isSelected: true)
                        .scaleEffect(0.78)
                default:
                    CozyUIIcon(.sparkles, size: 18, color: Color(hex: 0x459E6E))
                }
            }
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            )
        }
    }

    // MARK: - Message Bubbles (Editorial Claude / Onsite style)

    @ViewBuilder
    private func messageRow(for entry: ChatEntry, lang: AppLanguage) -> some View {
        let isUser = entry.role == .user
        let isLastAssistant = !isUser && entry.id == assistant.messages.last?.id
        let isThinking = !isUser && entry.text.isEmpty && entry.actions.isEmpty && !entry.hasConsents && assistant.isStreaming && isLastAssistant

        if isUser {
            let userAvatar: ChibiAsset = settings.currentMember.id == HouseholdMember.defaultPartnerID ? .wife : .husband
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 42)
                VStack(alignment: .trailing, spacing: 6) {
                    if let attachments = entry.attachments, !attachments.isEmpty {
                        ChatAttachmentGrid(
                            attachments: attachments,
                            data: { imageLoader(for: $0) },
                            onOpen: { viewerItem = ChatImageViewerItem(attachment: $0) },
                            language: lang
                        )
                    }
                    if !entry.text.isEmpty {
                        Text(entry.text)
                            .font(.appBody)
                            .foregroundStyle(Color.onInk)
                            .textSelection(.enabled)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 10)
                            .background(
                                Color.ink,
                                in: UnevenRoundedRectangle(
                                    topLeadingRadius: 20,
                                    bottomLeadingRadius: 20,
                                    bottomTrailingRadius: 6,
                                    topTrailingRadius: 20,
                                    style: .continuous
                                )
                            )
                    }
                }
                ChibiAvatarView(asset: userAvatar, size: 28)
            }
        } else if isThinking || !entry.text.isEmpty || !entry.actions.isEmpty || entry.hasConsents {
            VStack(alignment: .leading, spacing: 8) {
                // Assistant header with golden puppy avatar
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xFFE9D8))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.accent.opacity(0.28), lineWidth: 1))
                        GoldenPuppyView(mood: isThinking ? .cozy : .happy, size: 22, isBouncing: isThinking)
                    }
                    Text("Tally")
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)

                    if isThinking {
                        TypingDotsView()
                            .padding(.leading, 2)
                    } else if !(isLastAssistant && assistant.isStreaming) {
                        Text("·")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary.opacity(0.5))
                        Text(entry.timestamp, style: .time)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary.opacity(0.65))
                    }
                    Spacer()
                }

                // Action confirmation cards (Transactions / Budgets / Goals)
                if !entry.actions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(entry.actions) { receipt in
                            actionReceiptCard(receipt, timestamp: entry.timestamp, lang: lang)
                        }
                    }
                }

                // Salary consent cards (asked by the assistant, answered here)
                if let consents = entry.consents, !consents.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(consents) { record in
                            salaryConsentCard(record, lang: lang)
                        }
                    }
                }

                // Still working after a card (e.g. salary access was just allowed): keep a sign of life.
                if isLastAssistant, assistant.isStreaming, entry.text.isEmpty, !isThinking,
                   assistant.salaryAccess.pending == nil {
                    TypingDotsView()
                        .padding(.leading, 6)
                        .padding(.vertical, 4)
                }

                // Cozy card-framed assistant Markdown response
                if !entry.text.isEmpty {
                    formattedMessageText(entry.text, isUser: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .cardSurface(cornerRadius: 20)
                }

                // Subtle action bar under completed assistant replies
                if !entry.text.isEmpty && !(isLastAssistant && assistant.isStreaming) {
                    HStack(spacing: 16) {
                        Button {
                            copyText(entry.text, id: entry.id)
                        } label: {
                            HStack(spacing: 4) {
                                CozyUIIcon(
                                    copiedMessageID == entry.id ? .checkmark : .copy,
                                    size: 13,
                                    color: copiedMessageID == entry.id ? Color.positive : Color.textSecondary
                                )
                                Text(copiedMessageID == entry.id
                                    ? L10n.text(lang, en: "Copied", vi: "Đã chép", zh: "已复制")
                                    : L10n.text(lang, en: "Copy", vi: "Sao chép", zh: "复制"))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(copiedMessageID == entry.id ? Color.positive : Color.textSecondary)
                        }
                        .buttonStyle(.themedPlain)

                        if isLastAssistant {
                            Button {
                                haptic(.light)
                                assistant.retryLast(settings: settings, store: store)
                            } label: {
                                HStack(spacing: 4) {
                                    CozyUIIcon(.refresh, size: 13, color: Color.textSecondary)
                                    Text(L10n.text(lang, en: "Retry", vi: "Thử lại", zh: "重试"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            }
                            .buttonStyle(.themedPlain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            .contextMenu {
                if !entry.text.isEmpty {
                    Button {
                        copyText(entry.text, id: entry.id)
                    } label: {
                        Label(L10n.text(lang, en: "Copy", vi: "Sao chép", zh: "复制"), systemImage: "doc.on.doc")
                    }
                }
                if isLastAssistant && !assistant.isStreaming {
                    Button {
                        assistant.retryLast(settings: settings, store: store)
                    } label: {
                        Label(L10n.text(lang, en: "Regenerate", vi: "Thử lại", zh: "重新生成"), systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formattedMessageText(_ text: String, isUser: Bool) -> some View {
        if isUser {
            Text(text)
                .font(.appBody)
                .foregroundStyle(Color.onInk)
                .textSelection(.enabled)
        } else {
            let blocks = AssistantMessageBlock.parse(text)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .text(let markdown):
                        Text(Self.inlineMarkdown(markdown))
                            .font(.appBody)
                            .foregroundStyle(Color.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .table(let headers, let rows):
                        messageTable(headers: headers, rows: rows)
                    }
                }
            }
        }
    }

    private static func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// A Markdown table from the assistant, laid out as a grid. Wide tables scroll sideways
    /// inside the bubble so columns keep a readable width on iPhone.
    private func messageTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        tableCell(header, isHeader: true)
                    }
                }
                .background(Color.hairline.opacity(0.6))
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Rectangle()
                        .fill(Color.hairline)
                        .frame(height: 1)
                        .gridCellColumns(max(headers.count, 1))
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            tableCell(cell, isHeader: false)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.hairlineStrong, lineWidth: 1)
            )
        }
    }

    private func tableCell(_ text: String, isHeader: Bool) -> some View {
        Text(Self.inlineMarkdown(text))
            .font(isHeader ? .appControl : .appSecondary)
            .monospacedDigit()
            .foregroundStyle(isHeader ? Color.textSecondary : Color.textPrimary)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 28, maxWidth: 190, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private func receiptIconView(_ receipt: AssistantActionReceipt) -> some View {
        switch receipt.icon {
        case .category(let category):
            CozyCategoryIcon(category: category, size: 24)
        case .goal(let goal):
            CozyGoalIcon(goal: goal, size: 24)
        case .plan:
            CozyUIIcon(.calendar, size: 17, color: Color.textPrimary)
        case .settled:
            CozyUIIcon(.checkmarkCircle, size: 17, color: Color.textPrimary)
        case .unsettled:
            CozyUIIcon(.refresh, size: 17, color: Color.textPrimary)
        case .deleted:
            CozyUIIcon(.trash, size: 17, color: Color.textPrimary)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: 16))
        }
    }

    @ViewBuilder
    private func actionReceiptCard(_ receipt: AssistantActionReceipt, timestamp: Date, lang: AppLanguage) -> some View {
        let linkedTransaction = AssistantReceiptLookup.transaction(
            for: receipt,
            timestamp: timestamp,
            in: store.activeTransactions,
            currency: settings.currency,
            language: lang,
            hideSalary: settings.hideSalary
        )

        let card = HStack(alignment: receipt.details?.isEmpty == false ? .top : .center, spacing: 10) {
            receiptIconView(receipt)
                .frame(width: 30, height: 30)
                .background(Color.softFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    CozyUIIcon(.checkmarkCircle, size: 13, color: Color.positive)
                    Text(receipt.title)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                Text(receipt.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                if let details = receipt.details, !details.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(details.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.textPrimary.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 3)
                }
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if let amount = receipt.amountText {
                    Text(amount)
                        .font(.appCaption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(receipt.isPositive ? Color.positive : Color.textPrimary)
                        .lineLimit(1)
                }
                if linkedTransaction != nil {
                    CozyUIIcon(.chevronRight, size: 12, color: Color.textSecondary.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        if let tx = linkedTransaction {
            Button {
                isComposerFocused = false
                CozyHaptics.light()
                editingTransaction = tx
            } label: {
                card
            }
            .buttonStyle(.themedPlain)
            .accessibilityHint(L10n.text(lang, en: "Opens transaction details", vi: "Mở chi tiết giao dịch", zh: "打开账单详情"))
        } else {
            card
        }
    }

    /// The assistant's request to use salary figures: Allow / Not now while waiting, then a small
    /// record of the answer. A card left waiting by a relaunch shows as dismissed.
    private func salaryConsentCard(_ record: SalaryConsentRecord, lang: AppLanguage) -> some View {
        let isLive = record.status == .pending && assistant.salaryAccess.pending?.id == record.id
        var shown = record
        if record.status == .pending && !isLive { shown.status = .cancelled }
        let tint: Color = switch shown.status {
        case .allowed: Color.positive
        case .pending: Color.accent
        default: Color.textSecondary
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                CozyUIIcon(shown.status == .allowed ? .eye : .eyeClosed, size: 17, color: tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(shown.title(in: lang))
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.reason)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if isLive {
                Text(salaryConsentExplainer(lang: lang))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button {
                        haptic(.light)
                        assistant.declineSalaryRequest(record.id)
                    } label: {
                        Text(L10n.text(lang, en: "Not now", vi: "Để sau", zh: "暂不"))
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.softFill, in: Capsule())
                    }
                    .buttonStyle(.themedPlain)
                    Button {
                        haptic(.medium)
                        assistant.allowSalaryRequest(record.id)
                    } label: {
                        Text(L10n.text(lang, en: "Allow", vi: "Cho phép", zh: "允许"))
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.ink, in: Capsule())
                    }
                    .buttonStyle(.themedPlain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isLive ? Color.accent.opacity(0.35) : Color.hairline, lineWidth: 1)
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: shown.status)
    }

    private func salaryConsentExplainer(lang: AppLanguage) -> String {
        let base = L10n.text(
            lang,
            en: "Allowing shows your salary in Tally, as the eye button does, so this answer can use it.",
            vi: "Cho phép sẽ hiện lương trong Tally, giống nút con mắt, để câu trả lời này dùng được.",
            zh: "允许后，Tally 会像点按眼睛按钮一样显示您的工资，以便本次回答使用。"
        )
        guard settings.requiresAuthToShowSalary else { return base }
        return base + " " + L10n.text(
            lang,
            en: "You'll confirm it's you first.",
            vi: "Bạn sẽ cần xác nhận danh tính trước.",
            zh: "需要先验证您的身份。"
        )
    }

    private func errorBanner(_ message: String, lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.negative)
            Text(message)
                .font(.appSecondary)
                .foregroundStyle(Color.negative)
            Spacer(minLength: 4)
            if !assistant.messages.isEmpty && !assistant.isStreaming {
                Button(L10n.text(lang, en: "Retry", vi: "Thử lại", zh: "重试")) {
                    assistant.retryLast(settings: settings, store: store)
                }
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Color.negative)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.negative.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
    }

    // MARK: - Live Voice Dictation Banner

    private var dictationLanguage: DictationLanguage? {
        DictationLanguage(rawValue: dictationLanguageID)
    }

    private func liveDictationBanner(lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            LiveAudioWaveformView(level: dictation.audioLevel)
                .frame(width: 28, height: 18)

            Text(dictation.isFinishing
                ? L10n.text(lang, en: "Transcribing…", vi: "Đang chép lời…", zh: "正在转写…")
                : L10n.text(lang, en: "Listening…", vi: "Đang nghe…", zh: "正在聆听…"))
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(Color.accent)

            if let detected = dictationLanguage ?? dictation.detectedLanguage {
                Tag(text: "\(detected.flag) \(detected.nativeName)", color: .accent)
            } else {
                Text("VI · EN · 中文")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                haptic(.light)
                dictation.finish()
            }
            .disabled(dictation.isFinishing)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.softFill, in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.cardBackground)
        .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
    }

    private func dictationLanguageMenu(lang: AppLanguage) -> some View {
        let title = L10n.text(lang, en: "Dictation language", vi: "Ngôn ngữ đọc chính tả", zh: "语音输入语言")
        let automatic = L10n.text(lang, en: "Auto", vi: "Tự động", zh: "自动")
        return Menu {
            Picker(title, selection: $dictationLanguageID) {
                Text(automatic).tag("")
                ForEach(DictationLanguage.allCases) { language in
                    Text(language.nativeName).tag(language.rawValue)
                }
            }
        } label: {
            Text(dictationLanguage?.shortLabel ?? automatic)
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: 36, minHeight: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(dictationLanguage?.nativeName ?? automatic)
        .disabled(dictation.isRecording || assistant.isStreaming || !settings.isAIReady)
    }

    // MARK: - Pro Floating Composer Bar (Mic inside input box, swipe down to dismiss keyboard)

    private func composerBar(lang: AppLanguage) -> some View {
        let hasContent = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty
        let canSend = settings.isAIReady && hasContent && preparingCount == 0 && !dictation.isRecording

        return VStack(spacing: 0) {
            Divider().overlay(Color.hairline)

            if !pendingImages.isEmpty || preparingCount > 0 {
                PendingAttachmentStrip(images: pendingImages, isPreparing: preparingCount > 0, language: lang) { image in
                    withAnimation(.snappy(duration: 0.18)) { pendingImages.removeAll { $0.id == image.id } }
                }
                .padding(.horizontal, 16)
            }

            if let attachNote {
                HStack(alignment: .top, spacing: 6) {
                    CozyUIIcon(.photo, size: 13, color: Color.textSecondary)
                    Text(attachNote)
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { self.attachNote = nil }
                    } label: {
                        CozyUIIcon(.xmark, size: 10, color: Color.textSecondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.themedPlain)
                    .accessibilityLabel(L10n.text(lang, en: "Dismiss", vi: "Đóng", zh: "关闭"))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Roomy, comfortable input capsule (Claude / ChatGPT iOS feel) with built-in Mic
                HStack(alignment: .bottom, spacing: 8) {
                    attachButton(lang: lang)
                        .padding(.bottom, 5)

                    TextField(
                        L10n.text(
                            lang,
                            en: "Message Tally…",
                            vi: "Nhắn cho Tally…",
                            zh: "给 Tally 发消息…"
                        ),
                        text: $draft,
                        axis: .vertical
                    )
                    .font(.appBody)
                    .lineLimit(1...6)
                    .focused($isComposerFocused)
                    .padding(.vertical, 12)
                    .disabled(!settings.isAIReady)

                    HStack(spacing: 2) {
                        dictationLanguageMenu(lang: lang)
                        dictationButton(lang: lang)
                    }
                    .padding(.bottom, 5)
                }
                .padding(.leading, 6)
                .padding(.trailing, 8)
                .frame(minHeight: 48)
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            dictation.isRecording ? Color.accent : (isComposerFocused ? Color.hairlineStrong : Color.hairline),
                            lineWidth: dictation.isRecording ? 1.5 : 1
                        )
                )

                // Dynamic Send / Stop button
                if assistant.isStreaming {
                    Button {
                        CozyHaptics.medium()
                        assistant.stop()
                    } label: {
                        CozyUIIcon(.stop, size: 16, color: Color.onInk)
                            .frame(width: 44, height: 44)
                            .background(Color.ink, in: Circle())
                    }
                    .buttonStyle(.cozyCard)
                    .accessibilityLabel(L10n.text(lang, en: "Stop generating", vi: "Dừng trả lời", zh: "停止生成"))
                } else {
                    Button {
                        sendDraft()
                    } label: {
                        CozyUIIcon(
                            .arrowUp,
                            size: 19,
                            color: canSend ? Color.onAccent : Color.textSecondary.opacity(0.45),
                            lineWidthScale: 1.15
                        )
                        .frame(width: 44, height: 44)
                        .background(canSend ? Color.accent : Color.softFill, in: Circle())
                        .shadow(color: canSend ? Color.accent.opacity(0.28) : .clear, radius: 8, y: 3)
                    }
                    .buttonStyle(.cozyCard)
                    .disabled(!canSend)
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: canSend)
                    .accessibilityLabel(L10n.text(lang, en: "Send message", vi: "Gửi tin nhắn", zh: "发送消息"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appBackground)
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        if value.translation.height > 24 && abs(value.translation.height) > abs(value.translation.width) {
                            isComposerFocused = false
                        }
                    }
            )
        }
    }

    // MARK: - Actions & Helpers

    private func dictationButton(lang: AppLanguage) -> some View {
        Button {
            toggleDictation(lang: lang)
        } label: {
            CozyUIIcon(
                dictation.isRecording ? .stop : .mic,
                size: dictation.isRecording ? 18 : 20,
                color: dictation.isRecording ? Color.accent : Color.textSecondary
            )
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.themedPlain)
        .disabled(!settings.isAIReady || assistant.isStreaming || dictation.isFinishing)
        .accessibilityLabel(dictation.isRecording
            ? L10n.text(lang, en: "Stop dictation", vi: "Dừng ghi âm", zh: "停止语音输入")
            : L10n.text(lang, en: "Start dictation", vi: "Bắt đầu đọc chính tả", zh: "开始语音输入"))
    }

    private func toggleDictation(lang: AppLanguage) {
        haptic(.medium)
        if dictation.isRecording {
            dictation.finish()
        } else {
            isComposerFocused = false
            draftBeforeDictation = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.start(appLanguage: lang, language: dictationLanguage) { spoken in
                applyDictatedText(spoken)
            }
        }
    }

    private func applyDictatedText(_ spoken: String) {
        let cleaned = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if draftBeforeDictation.isEmpty {
            draft = cleaned
        } else {
            draft = "\(draftBeforeDictation) \(cleaned)"
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingImages.isEmpty, preparingCount == 0 else { return }
        if !pendingImages.isEmpty, !canAttachImages {
            attachNote = AssistantService.imagesUnsupportedMessage(in: settings.language)
            return
        }
        haptic(.light)
        CozySounds.play(.pop)
        dictation.stop()
        let images = pendingImages
        draft = ""
        draftBeforeDictation = ""
        pendingImages = []
        attachNote = nil
        isComposerFocused = false
        hasScrolled = false
        assistant.send(text, images: images, settings: settings, store: store)
    }

    // MARK: - Image attachments

    private var canAttachImages: Bool { AssistantService.canAttachImages(settings: settings) }

    private func imageLoader(for attachment: ChatImageAttachment) -> @Sendable () -> Data? {
        let store = assistant.imageStore
        let id = attachment.id
        return { store?.load(id) }
    }

    /// Attach control: photo library on iPhone/iPad, file picker on Mac (plus drag-and-drop and
    /// paste on the whole sheet). Disabled with a short explanation when the on-device Apple
    /// Intelligence backend (text only) would answer.
    @ViewBuilder
    private func attachButton(lang: AppLanguage) -> some View {
        let enabled = settings.isAIReady && canAttachImages && !assistant.isStreaming
            && ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount) > 0
        let label = CozyUIIcon(.photo, size: 20, color: Color.textSecondary)
            .frame(width: 34, height: 34)
            .opacity(enabled ? 1 : 0.4)
        let accessibility = L10n.text(lang, en: "Attach images", vi: "Đính kèm ảnh", zh: "附加图片")
        if !canAttachImages || !settings.isAIReady {
            Button {
                CozyHaptics.light()
                withAnimation(.snappy(duration: 0.18)) {
                    attachNote = AssistantService.imagesUnsupportedMessage(in: lang)
                }
            } label: { label }
            .buttonStyle(.themedPlain)
            .disabled(!settings.isAIReady)
            .accessibilityLabel(accessibility)
            .accessibilityHint(AssistantService.imagesUnsupportedMessage(in: lang))
        } else {
            #if os(iOS)
            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: max(1, ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount)),
                matching: .images,
                preferredItemEncoding: .compatible
            ) { label }
            .buttonStyle(.themedPlain)
            .disabled(!enabled)
            .accessibilityLabel(accessibility)
            #else
            Button {
                CozyHaptics.light()
                isShowingFileImporter = true
            } label: { label }
            .buttonStyle(.themedPlain)
            .disabled(!enabled)
            .help(L10n.text(lang, en: "Attach images (or drag & drop / paste them here)", vi: "Đính kèm ảnh (hoặc kéo thả / dán vào đây)", zh: "附加图片（也可拖放或粘贴到此处）"))
            .contextMenu {
                Button(L10n.text(lang, en: "Paste Image", vi: "Dán ảnh", zh: "粘贴图片")) {
                    pasteImagesFromPasteboard()
                }
            }
            .accessibilityLabel(accessibility)
            #endif
        }
    }

    /// Loads image data from drag-and-drop or paste providers (image data or image files).
    private func attachImages(from providers: [NSItemProvider]) -> Bool {
        let slots = ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount)
        let usable = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }.prefix(slots)
        guard !usable.isEmpty else { return false }
        prepareImages(usable.map { provider in
            { @Sendable in await Self.loadImageData(from: provider) }
        })
        return true
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                      UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                else { return continuation.resume(returning: nil) }
                continuation.resume(returning: try? Data(contentsOf: url))
            }
        }
    }

    #if os(macOS)
    private func pasteImagesFromPasteboard() {
        let pasteboard = NSPasteboard.general
        let slots = ImageUploadPolicy.remainingSlots(current: pendingImages.count + preparingCount)
        var loaders: [@Sendable () async -> Data?] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL] {
            loaders += urls.map { url in { @Sendable in try? Data(contentsOf: url) } }
        }
        if loaders.isEmpty {
            for type in [NSPasteboard.PasteboardType.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)] {
                if let data = pasteboard.data(forType: type) {
                    loaders.append { @Sendable in data }
                    break
                }
            }
        }
        if loaders.isEmpty {
            attachNote = L10n.text(settings.language, en: "There's no image on the clipboard.", vi: "Bộ nhớ tạm không có ảnh.", zh: "剪贴板中没有图片。")
            return
        }
        prepareImages(Array(loaders.prefix(slots)))
    }
    #endif

    /// Downscales and re-encodes each image off the main thread, then adds it to the composer.
    private func prepareImages(_ loaders: [@Sendable () async -> Data?]) {
        guard !loaders.isEmpty else { return }
        let lang = settings.language
        let batchID = attachmentBatchID
        attachNote = nil
        preparingCount += loaders.count
        for loader in loaders {
            Task {
                let prepared: PreparedChatImage? = await Task.detached(priority: .userInitiated) {
                    guard let data = await loader() else { return nil }
                    return try? ChatImageEncoder.prepare(data)
                }.value
                guard batchID == attachmentBatchID else { return }
                preparingCount = max(0, preparingCount - 1)
                if let prepared, pendingImages.count < ImageUploadPolicy.maxImagesPerMessage {
                    withAnimation(.snappy(duration: 0.18)) { pendingImages.append(prepared) }
                } else if prepared == nil {
                    attachNote = L10n.text(lang, en: "That image couldn't be read. Try another one.", vi: "Không đọc được ảnh này. Hãy thử ảnh khác.", zh: "无法读取该图片，请换一张试试。")
                }
            }
        }
    }

    private func copyText(_ text: String, id: UUID) {
        haptic(.light)
        CozySounds.play(.tick)
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation(.snappy(duration: 0.16)) {
            copiedMessageID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if copiedMessageID == id {
                withAnimation(.easeOut(duration: 0.2)) {
                    copiedMessageID = nil
                }
            }
        }
    }

    private func followLatestMessage(proxy: ScrollViewProxy, animated: Bool) {
        guard !hasScrolled || isAtBottom else { return }
        scrollToBottom(proxy: proxy, animated: animated)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private enum HapticStyle { case light, medium }

    private func haptic(_ style: HapticStyle) {
        if style == .light {
            CozyHaptics.light()
        } else {
            CozyHaptics.medium()
        }
    }
}

// MARK: - Animated Thinking Dots & Live Audio Waveform

private struct ChatScrollIntent: ViewModifier {
    let onScroll: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18, macOS 15, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .interacting { onScroll() }
            }
        } else {
            content.simultaneousGesture(DragGesture().onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) { onScroll() }
            })
        }
    }
}

#if os(macOS)
private struct LegacyChatScrollIntent: ViewModifier {
    let onScroll: () -> Void
    @State private var previousOrigin: CGFloat?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
        } else {
            content.onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY.rounded() } action: { origin in
                if let previousOrigin, origin > previousOrigin { onScroll() }
                previousOrigin = origin
            }
        }
    }
}
#endif

private struct TypingDotsView: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(Color.textSecondary.opacity(phase == idx ? 0.85 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == idx ? 1.15 : 0.85)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(320))
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = (phase + 1) % 3
                }
            }
        }
    }
}

private struct LiveAudioWaveformView: View {
    let level: Float

    private let multipliers: [CGFloat] = [0.45, 0.9, 1.0, 0.7]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<multipliers.count, id: \.self) { idx in
                let height = max(4, CGFloat(level) * 18 * multipliers[idx])
                Capsule()
                    .fill(Color.accent)
                    .frame(width: 3.5, height: height)
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }
}

#if os(iOS)
private struct ChatHistorySwipe: ViewModifier {
    let onSwipe: () -> Void
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                let horizontal = -value.translation.width
                if width > 0, value.startLocation.x >= width - 56,
                   horizontal >= 65, horizontal > 2 * abs(value.translation.height) {
                    onSwipe()
                }
            })
    }
}
#endif

private struct ChatHistoryList: View {
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let isStreaming: Bool
    let language: AppLanguage
    let onSelect: (ChatSession) -> Void
    let onDelete: (UUID) -> Void
    @State private var searchText = ""
    @State private var pendingDeletion: ChatSession?
    @State private var isConfirmingDeletion = false

    private var deleteTitle: String {
        L10n.text(language, en: "Delete Chat", vi: "Xóa cuộc trò chuyện", zh: "删除对话")
    }

    private var matchingSessions: [ChatSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sessions }
        return sessions.filter { session in
            session.title.localizedStandardContains(query)
                || session.messages.contains { $0.text.localizedStandardContains(query) }
        }
    }

    var body: some View {
        let matches = matchingSessions
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchField

                if sessions.isEmpty {
                    EmptyStateCard(
                        symbol: "clock.arrow.circlepath",
                        title: L10n.text(language, en: "No chat history yet", vi: "Chưa có lịch sử trò chuyện", zh: "暂无对话记录"),
                        message: L10n.text(language, en: "Your conversations with Tally will be saved here automatically.", vi: "Các cuộc trò chuyện với Tally sẽ tự động được lưu tại đây.", zh: "您与 Tally 的对话会自动保存在这里。")
                    )
                } else if matches.isEmpty {
                    EmptyStateCard(
                        symbol: "magnifyingglass",
                        title: L10n.text(language, en: "No matching chats", vi: "Không tìm thấy cuộc trò chuyện", zh: "没有匹配的对话"),
                        message: L10n.text(language, en: "Try a different search.", vi: "Thử từ khóa khác.", zh: "请尝试其他搜索词。")
                    )
                } else {
                    ForEach(matches) { session in
                        chatRow(session)
                    }
                }
            }
            .documentColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .confirmationDialog(deleteTitle, isPresented: $isConfirmingDeletion, titleVisibility: .visible, presenting: pendingDeletion) { session in
            Button(deleteTitle, role: .destructive) { onDelete(session.id) }
            Button(L10n.text(language, en: "Cancel", vi: "Hủy", zh: "取消"), role: .cancel) {}
        } message: { session in
            Text(L10n.text(
                language,
                en: "Delete ‘\(session.title)’ and its messages? This can’t be undone.",
                vi: "Xóa ‘\(session.title)’ và các tin nhắn trong đó? Bạn không thể hoàn tác.",
                zh: "删除“\(session.title)”及其消息？此操作无法撤销。"
            ))
        }
        .onChange(of: isConfirmingDeletion) { _, isPresented in
            if !isPresented { pendingDeletion = nil }
        }
    }

    private func chatRow(_ session: ChatSession) -> some View {
        let isCurrentSession = session.id == activeSessionID
        let lastPreview = session.messages.last(where: { !$0.text.isEmpty })?.text ?? ""

        return Button {
            onSelect(session)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if !lastPreview.isEmpty {
                    Text(lastPreview)
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(session.updatedAt, style: .relative)
                    Text("·")
                    Text("\(session.messages.count) \(L10n.text(language, en: "msgs", vi: "tin nhắn", zh: "条"))")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.textSecondary.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardSurface(cornerRadius: 18)
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(isStreaming && !isCurrentSession)
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = session
                isConfirmingDeletion = true
            } label: {
                Label(deleteTitle, systemImage: "trash")
            }
            .disabled(isStreaming && isCurrentSession)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            CozyUIIcon(.search, size: 17, color: Color.textSecondary)
                .accessibilityHidden(true)
            TextField(L10n.text(language, en: "Search chats", vi: "Tìm cuộc trò chuyện", zh: "搜索对话"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.appBody)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    CozyUIIcon(.xmarkCircle, size: 18, color: Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text(language, en: "Clear search", vi: "Xoá tìm kiếm", zh: "清除搜索"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(Color.cardBackground, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.hairlineStrong, lineWidth: 1) }
    }
}
