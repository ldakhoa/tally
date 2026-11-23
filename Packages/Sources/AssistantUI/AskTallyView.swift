import AppServices
import BudgetKit
import ClaudeKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore
#if os(iOS)
import UIKit
#endif

public struct AskTallyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(AssistantService.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft = ""
    @State private var draftBeforeDictation = ""
    @State private var dictation = VoiceDictationManager()
    @State private var copiedMessageID: UUID?
    @State private var celebrationTrigger = 0
    @State private var isShowingHistory = false
    @FocusState private var isComposerFocused: Bool

    private let bottomAnchorID = "ask-tally-bottom-anchor"

    public init() {}

    public var body: some View {
        let lang = settings.language
        NavigationStack {
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
                                .id(bottomAnchorID)
                        }
                        .documentColumn()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isComposerFocused {
                            isComposerFocused = false
                        }
                    }
                    .onChange(of: assistant.messages.count) { _, _ in
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                    .onChange(of: assistant.messages.last?.text) { _, _ in
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                    .onChange(of: assistant.messages.last?.actions.count) { oldCount, newCount in
                        scrollToBottom(proxy: proxy, animated: true)
                        if let newCount, newCount > (oldCount ?? 0) {
                            celebrationTrigger += 1
                        }
                    }
                    .onChange(of: isComposerFocused) { _, focused in
                        if focused {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
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
            .navigationTitle(L10n.text(lang, en: "Ask Tally", vi: "Trợ lý Tally AI", zh: "Tally AI 助手"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Close", vi: "Đóng", zh: "关闭")) {
                        dictation.stop()
                        dismiss()
                    }
                }
                if !assistant.sessions.isEmpty || !assistant.messages.isEmpty {
                    ToolbarItemGroup(placement: .primaryAction) {
                        if !assistant.sessions.isEmpty {
                            Button {
                                CozyHaptics.light()
                                isComposerFocused = false
                                isShowingHistory = true
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.appControl)
                            }
                            .accessibilityLabel(L10n.text(lang, en: "Chat history", vi: "Lịch sử chat", zh: "历史对话"))
                        }

                        if !assistant.messages.isEmpty {
                            Button {
                                CozyHaptics.light()
                                dictation.stop()
                                assistant.startNewChat()
                            } label: {
                                CozyUIIcon(.compose, size: 18, color: Color.textPrimary)
                            }
                            .accessibilityLabel(L10n.text(lang, en: "New chat", vi: "Chat mới", zh: "新对话"))
                        }
                    }
                }
            }
            .sheet(isPresented: $isShowingHistory) {
                ChatHistorySheet(
                    sessions: assistant.sessions,
                    activeSessionID: assistant.activeSessionID,
                    language: lang,
                    onSelect: { session in
                        CozyHaptics.selection()
                        assistant.selectSession(session)
                        isShowingHistory = false
                    },
                    onNewChat: {
                        CozyHaptics.light()
                        assistant.startNewChat()
                        isShowingHistory = false
                    },
                    onDelete: { id in
                        CozyHaptics.light()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            assistant.deleteSession(id: id)
                        }
                    }
                )
            }
            .interactiveDismissDisabled(
                !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || dictation.isRecording
                    || assistant.isStreaming
            )
            .onDisappear {
                dictation.stop()
            }
        }
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
                        en: "Type or speak in English, Vietnamese, or Chinese — Tally can log expenses, set budgets, manage savings goals, and chat about spending.",
                        vi: "Gõ hoặc nói bằng tiếng Việt, Anh hoặc Trung — Tally tự động ghi chi tiêu, đặt ngân sách, tạo mục tiêu tiết kiệm và tâm sự thu chi cùng hai bạn.",
                        zh: "支持中文、英文或越南语打字/语音输入——Tally 可自动记账、设置预算、管理存钱目标并解答家庭收支。"
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
        let isThinking = !isUser && entry.text.isEmpty && entry.actions.isEmpty && assistant.isStreaming && isLastAssistant

        if isUser {
            let userAvatar: ChibiAsset = settings.currentMember.id == HouseholdMember.defaultPartnerID ? .wife : .husband
            HStack(alignment: .bottom, spacing: 8) {
                Spacer(minLength: 42)
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
                ChibiAvatarView(asset: userAvatar, size: 28)
            }
        } else if isThinking || !entry.text.isEmpty || !entry.actions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Assistant header with cute Shiba Pet avatar
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xFFE9D8))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.accent.opacity(0.28), lineWidth: 1))
                        ShibaPuppyView(mood: isThinking ? .cozy : .happy, size: 22, isBouncing: isThinking)
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
                            actionReceiptCard(receipt)
                        }
                    }
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
        if !isUser,
           let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            Text(attributed)
                .font(.appBody)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.appBody)
                .foregroundStyle(isUser ? Color.onInk : Color.textPrimary)
                .textSelection(.enabled)
        }
    }

    private func actionReceiptCard(_ receipt: AssistantActionReceipt) -> some View {
        HStack(spacing: 10) {
            Text(receipt.emoji)
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(Color.softFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
            }

            Spacer(minLength: 6)

            if let amount = receipt.amountText {
                Text(amount)
                    .font(.appCaption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(receipt.isPositive ? Color.positive : Color.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
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

    // MARK: - Live Voice Dictation Banner (Auto-detects VI / EN / ZH)

    private func liveDictationBanner(lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            LiveAudioWaveformView(level: dictation.audioLevel)
                .frame(width: 28, height: 18)

            Text(L10n.text(
                lang,
                en: "Listening…",
                vi: "Đang nghe…",
                zh: "正在聆听…"
            ))
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(Color.accent)

            if let detected = dictation.detectedLanguage {
                Tag(text: "\(detected.flag) \(detected.nativeName)", color: .accent)
            } else {
                Text("VI · EN · 中文")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                haptic(.light)
                dictation.stop()
            }
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

    // MARK: - Pro Floating Composer Bar (Mic inside input box, swipe down to dismiss keyboard)

    private func composerBar(lang: AppLanguage) -> some View {
        let canSend = settings.isAIReady && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(spacing: 0) {
            Divider().overlay(Color.hairline)

            HStack(alignment: .bottom, spacing: 10) {
                // Roomy, comfortable input capsule (Claude / ChatGPT iOS feel) with built-in Mic
                HStack(alignment: .bottom, spacing: 8) {
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
                    .padding(.bottom, 5)
                    .disabled(!settings.isAIReady || assistant.isStreaming)
                    .accessibilityLabel(
                        dictation.isRecording
                            ? L10n.text(lang, en: "Stop dictation", vi: "Dừng ghi âm", zh: "停止语音输入")
                            : L10n.text(lang, en: "Dictate in Vietnamese, English, or Chinese", vi: "Nói tiếng Việt, Anh hoặc Trung", zh: "语音输入（自动识别中英越）")
                    )
                }
                .padding(.leading, 16)
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

    private func toggleDictation(lang: AppLanguage) {
        haptic(.medium)
        if dictation.isRecording {
            dictation.stop()
        } else {
            isComposerFocused = false
            draftBeforeDictation = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.start(appLanguage: lang) { spoken in
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
        guard !text.isEmpty else { return }
        haptic(.light)
        CozySounds.play(.pop)
        dictation.stop()
        draft = ""
        draftBeforeDictation = ""
        isComposerFocused = false
        assistant.send(text, settings: settings, store: store)
    }

    private func copyText(_ text: String, id: UUID) {
        haptic(.light)
        CozySounds.play(.tick)
        #if os(iOS)
        UIPasteboard.general.string = text
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

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
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

// MARK: - Cozy Chat History Sheet

private struct ChatHistorySheet: View {
    let sessions: [ChatSession]
    let activeSessionID: UUID?
    let language: AppLanguage
    let onSelect: (ChatSession) -> Void
    let onNewChat: () -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: onNewChat) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accent)
                            Text(L10n.text(language, en: "Start a new chat", vi: "Bắt đầu cuộc trò chuyện mới", zh: "开始新对话"))
                                .font(.appControlLarge)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .padding(14)
                        .cardSurface(cornerRadius: 18)
                    }
                    .buttonStyle(.cozyCard)

                    if sessions.isEmpty {
                        EmptyStateCard(
                            symbol: "clock.arrow.circlepath",
                            title: L10n.text(language, en: "No chat history yet", vi: "Chưa có lịch sử trò chuyện", zh: "暂无对话记录"),
                            message: L10n.text(language, en: "Your conversations with Tally will be saved here automatically.", vi: "Các cuộc trò chuyện với Tally sẽ tự động được lưu tại đây.", zh: "您与 Tally 的对话会自动保存在这里。")
                        )
                    } else {
                        ForEach(sessions) { session in
                            let isActive = session.id == activeSessionID
                            let lastPreview = session.messages.last(where: { !$0.text.isEmpty })?.text ?? ""

                            HStack(spacing: 10) {
                                Button {
                                    onSelect(session)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(session.title)
                                                .font(.appHeading)
                                                .foregroundStyle(Color.textPrimary)
                                                .lineLimit(1)
                                            if isActive {
                                                Tag(
                                                    text: L10n.text(language, en: "Active", vi: "Đang mở", zh: "当前"),
                                                    color: .accent
                                                )
                                            }
                                        }

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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    onDelete(session.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary.opacity(0.7))
                                        .frame(width: 34, height: 34)
                                        .background(Color.softFill, in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.text(language, en: "Delete chat", vi: "Xoá cuộc trò chuyện", zh: "删除对话"))
                            }
                            .padding(14)
                            .cardSurface(cornerRadius: 18, highlighted: isActive)
                        }
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(L10n.text(language, en: "Chat History", vi: "Lịch sử Tally", zh: "对话记录"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(language, en: "Done", vi: "Xong", zh: "完成")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
