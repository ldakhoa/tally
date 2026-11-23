import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

/// Paste a bank notification, email, Apple Pay alert, or natural Vietnamese/English text
/// (e.g. "ăn phở 65k", "TK 1903xxx -125,000 VND tai HIGHLANDS COFFEE") and turn it into
/// a transaction using Claude AI or the built-in local parser.
public struct SmartCaptureSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var isParsing = false
    @State private var draft: ParsedTransactionDraft?
    @State private var errorMessage: String?
    @State private var showingEditor = false

    public init() {}

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text(
                        lang,
                        en: "Paste a DBS/OCBC/UOB/PayNow alert, bank SMS, or type naturally like \"FairPrice 24.80\" or \"ăn phở 65k\".",
                        vi: "Dán tin nhắn DBS/OCBC/UOB/PayNow, SMS ngân hàng hoặc gõ nhanh như \"FairPrice 24.80\", \"ăn phở 65k\".",
                        zh: "粘贴银行通知、短信，或直接输入如 \"FairPrice 24.80\"、\"咖啡 6.5\"。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)

                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { items in
                            if let first = items.first, !first.isEmpty {
                                rawText = first
                                Task { await runParse() }
                            }
                        }
                        .buttonBorderShape(.capsule)

                        if !rawText.isEmpty {
                            Button(L10n.text(lang, en: "Clear", vi: "Xoá", zh: "清空")) {
                                rawText = ""
                                draft = nil
                                errorMessage = nil
                            }
                            .pillButton()
                        }
                    }

                    TextEditor(text: $rawText)
                        .font(.appBody)
                        .frame(minHeight: 120)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Color.editorBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))

                    HStack(spacing: 10) {
                        Button {
                            Task { await runParse() }
                        } label: {
                            if isParsing {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(L10n.text(lang, en: "Reading…", vi: "Đang đọc…", zh: "解析中…"))
                                }
                            } else {
                                Label(
                                    settings.isAIReady && settings.autoParseWithAI
                                        ? L10n.text(lang, en: "Parse with AI", vi: "Đọc bằng AI", zh: "用 AI 解析")
                                        : L10n.text(lang, en: "Parse text", vi: "Phân tích", zh: "解析文本"),
                                    systemImage: settings.isAIReady && settings.autoParseWithAI ? "sparkles" : "wand.and.stars"
                                )
                            }
                        }
                        .blockButton(prominent: true)
                        .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.appSecondary)
                            .foregroundStyle(Color.negative)
                    }

                    if let draft {
                        Card {
                            HStack(spacing: 12) {
                                CategoryBadge(category: draft.category, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(draft.name)
                                        .font(.appHeading)
                                    HStack(spacing: 6) {
                                        Text(draft.category.title(in: lang))
                                        Text("·")
                                        Text(DateKey.formatShortDay(draft.dayKey, language: lang))
                                        if draft.parsedByAI {
                                            Tag(text: "Claude AI", color: .accent)
                                        }
                                    }
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                let minor = settings.currency.toStorageMinor(draft.amountMajor)
                                Text(MoneyFormat.format(
                                    minor: draft.type == .income ? minor : -minor,
                                    currency: settings.currency,
                                    language: lang,
                                    signed: draft.type == .income
                                ))
                                .font(.appAmount)
                                .foregroundStyle(draft.type == .income ? Color.positive : Color.textPrimary)
                            }

                            HStack(spacing: 10) {
                                Button(L10n.text(lang, en: "Edit details", vi: "Chỉnh sửa", zh: "编辑详情")) {
                                    showingEditor = true
                                }
                                .pillButton()

                                Spacer()

                                Button(L10n.text(lang, en: "Save now", vi: "Lưu ngay", zh: "立即保存")) {
                                    saveDraft(draft)
                                }
                                .pillButton(prominent: true)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Smart capture", vi: "Nhập nhanh thông minh", zh: "智能记账"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Close", vi: "Đóng", zh: "关闭")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingEditor, onDismiss: { dismiss() }) {
                TransactionEditorSheet(
                    prefill: draft,
                    sourceOverride: draft?.parsedByAI == true ? .aiQuickAdd : .bankNotification,
                    rawSourceText: rawText
                )
            }
        }
    }

    private func runParse() async {
        isParsing = true
        errorMessage = nil
        defer { isParsing = false }

        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
        if let parsed = await AITransactionParser.parse(
            text: rawText,
            source: .aiQuickAdd,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        ) {
            draft = parsed
        } else {
            draft = nil
            errorMessage = L10n.text(
                settings.language,
                en: "Could not find an amount in that text. Try including a number like 65k or $12.50.",
                vi: "Không tìm thấy số tiền trong đoạn văn bản. Hãy thử kèm số tiền như 65k hoặc 125,000 VND.",
                zh: "未在文本中找到金额，请尝试包含数字，例如 65 或 $12.50。"
            )
        }
    }

    private func saveDraft(_ parsed: ParsedTransactionDraft) {
        let member = settings.currentMember
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: parsed,
            targetCurrency: settings.currency,
            language: settings.language
        )
        let record = TransactionRecord(
            name: parsed.name,
            amountMinor: max(1, resolved.amountMinor),
            type: parsed.type,
            category: parsed.category,
            dayKey: parsed.dayKey,
            note: resolved.note,
            source: parsed.parsedByAI ? .aiQuickAdd : .bankNotification,
            rawSourceText: rawText,
            memberID: member.id,
            memberName: member.name,
            needsReview: false
        )
        let outcome = store.saveAutoCapturedTransaction(record)
        store.ensureVisible(dayKey: outcome.saved.dayKey)
        dismiss()
    }
}
