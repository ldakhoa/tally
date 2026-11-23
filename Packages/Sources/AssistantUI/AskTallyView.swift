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
                                    title: L10n.text(lang, en: "Connect Claude AI", vi: "Kết nối Claude AI"),
                                    message: L10n.text(lang, en: "Add your Anthropic API key in Settings to chat about your household spending and parse bank alerts with Claude.", vi: "Thêm Anthropic API key trong Cài đặt để hỏi đáp chi tiêu và đọc thông báo ngân hàng bằng Claude."),
                                    actionTitle: L10n.text(lang, en: "Open Settings", vi: "Mở Cài đặt")
                                ) {
                                    dismiss()
                                    settings.isShowingSettings = true
                                }
                            } else if assistant.messages.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(L10n.text(lang, en: "Ask about \(DateKey.formatMonth(store.selectedMonth, language: lang))", vi: "Hỏi về \(DateKey.formatMonth(store.selectedMonth, language: lang))"))
                                        .font(.appHeading)
                                    Text(L10n.text(lang, en: "Tally reads your current month's spending, budgets, and goals to give practical answers.", vi: "Tally đọc dữ liệu thu chi, ngân sách và mục tiêu tháng hiện tại để tư vấn sát thực tế."))
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
                }

                Divider().overlay(Color.hairline)

                HStack(spacing: 10) {
                    TextField(
                        L10n.text(lang, en: "Ask Tally anything…", vi: "Hỏi Tally về chi tiêu…"),
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
            .navigationTitle(L10n.text(lang, en: "Ask Tally", vi: "Hỏi Tally AI"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Close", vi: "Đóng")) { dismiss() }
                }
                if !assistant.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(L10n.text(lang, en: "New chat", vi: "Chat mới")) {
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
            VStack(alignment: .leading, spacing: 4) {
                if entry.text.isEmpty && !isUser {
                    ProgressView().controlSize(.small)
                } else {
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
            if !isUser { Spacer(minLength: 32) }
        }
    }
}
