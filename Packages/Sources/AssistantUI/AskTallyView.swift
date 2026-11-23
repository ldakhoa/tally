import AppServices
import BudgetKit
import ClaudeKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct AskTallyView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(AssistantService.self) private var assistant
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""

    public init() {}

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if !settings.isAIReady {
                                EmptyStateCard(
                                    symbol: "key.fill",
                                    title: L10n.text(lang, en: "Connect Claude AI", vi: "Kết nối Claude AI", zh: "连接 Claude AI"),
                                    message: L10n.text(
                                        lang,
                                        en: "Add your Anthropic API key in Settings to log expenses, set budgets, create savings goals, and chat about spending with Claude.",
                                        vi: "Thêm Anthropic API key trong Cài đặt để chat ghi chi tiêu, đặt ngân sách, tạo mục tiêu tiết kiệm và hỏi đáp với Claude.",
                                        zh: "在设置中添加 Anthropic API 密钥，即可通过对话记账、设置预算、创建存钱目标并分析家庭收支。"
                                    ),
                                    actionTitle: L10n.text(lang, en: "Open Settings", vi: "Mở Cài đặt", zh: "打开设置")
                                ) {
                                    dismiss()
                                    settings.isShowingSettings = true
                                }
                            } else if assistant.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(L10n.text(
                                        lang,
                                        en: "Tally AI Assistant · \(DateKey.formatMonth(store.selectedMonth, language: lang))",
                                        vi: "Trợ lý Tally AI · \(DateKey.formatMonth(store.selectedMonth, language: lang))",
                                        zh: "Tally AI 助手 · \(DateKey.formatMonth(store.selectedMonth, language: lang))"
                                    ))
                                    .font(.appHeading)

                                    Text(L10n.text(
                                        lang,
                                        en: "Tell Tally to log expenses, set monthly budgets, create or top up savings goals, or analyze your spending.",
                                        vi: "Nhắn Tally để ghi thu chi, đặt ngân sách tháng, tạo/góp mục tiêu tiết kiệm, hoặc hỏi về tình hình chi tiêu.",
                                        zh: "直接告诉 Tally 记账、设置本月预算、创建或存入存钱目标，或分析消费情况。"
                                    ))
                                    .font(.appSecondary)
                                    .foregroundStyle(Color.textSecondary)

                                    ForEach(BudgetAssistantPrompt.suggestedPrompts(in: lang), id: \.self) { prompt in
                                        Button {
                                            assistant.send(prompt, settings: settings, store: store)
                                        } label: {
                                            HStack {
                                                Text(prompt)
                                                    .font(.appSecondary)
                                                    .multilineTextAlignment(.leading)
                                                Spacer()
                                                Image(systemName: "arrow.up.right")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                            .padding(14)
                                            .cardSurface(cornerRadius: 16)
                                        }
                                        .buttonStyle(.themedPlain)
                                    }
                                }
                            } else {
                                ForEach(assistant.messages) { msg in
                                    bubble(for: msg)
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
                                    .padding(.vertical, 6)
                                    .background(Color.softFill, in: Capsule())
                                }
                            }

                            if let err = assistant.errorMessage {
                                Text(err)
                                    .font(.appSecondary)
                                    .foregroundStyle(Color.negative)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.negative.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                            }
                        }
                        .documentColumn()
                    }
                    .onChange(of: assistant.messages.last?.text) { _, _ in
                        if let lastID = assistant.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                    .onChange(of: assistant.messages.last?.actions.count) { _, _ in
                        if let lastID = assistant.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }

                Divider().overlay(Color.hairline)

                HStack(spacing: 10) {
                    TextField(
                        L10n.text(
                            lang,
                            en: "Log expense, set budget, add goal, or ask…",
                            vi: "Ghi chi tiêu, đặt ngân sách, mục tiêu hoặc hỏi…",
                            zh: "记一笔、设预算、定目标或提问…"
                        ),
                        text: $draft,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .tallyField()
                    .disabled(!settings.isAIReady)

                    Button {
                        let text = draft
                        draft = ""
                        assistant.send(text, settings: settings, store: store)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.onInk)
                            .frame(width: 40, height: 40)
                            .background(Color.ink, in: Circle())
                    }
                    .buttonStyle(.themedPlain)
                    .disabled(!settings.isAIReady || assistant.isStreaming || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appBackground)
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Ask Tally", vi: "Trợ lý Tally AI", zh: "Tally AI 助手"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Close", vi: "Đóng", zh: "关闭")) { dismiss() }
                }
                if !assistant.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.text(lang, en: "New chat", vi: "Chat mới", zh: "新对话")) {
                            assistant.clear()
                        }
                    }
                }
            }
        }
    }

    private func bubble(for entry: ChatEntry) -> some View {
        let isUser = entry.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if !entry.actions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(entry.actions) { receipt in
                            actionReceiptCard(receipt)
                        }
                    }
                }

                if entry.text.isEmpty && !isUser {
                    if entry.actions.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                } else if !entry.text.isEmpty {
                    Text(entry.text)
                        .font(.appBody)
                        .foregroundStyle(isUser ? Color.onInk : Color.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser ? Color.ink : Color.cardBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                if !isUser {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                }
            }
            if !isUser { Spacer(minLength: 28) }
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.positive)
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
}
