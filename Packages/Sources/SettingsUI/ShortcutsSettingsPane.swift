import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

/// 1-tap installable signed Apple Shortcuts + 20-second Singapore-tailored Automation guides
/// (Apple Pay, DBS/OCBC/UOB/Trust Emails, SMS/PayNow) + live parser tester.
struct ShortcutsSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var sampleInput = "DBS Alert: A transaction of SGD 18.50 was made on your DBS Card at FAIRPRICE on 2026-11-23."
    @State private var parsedPreview: ParsedTransactionDraft?
    @State private var isTesting = false
    @State private var sharingShortcutURL: ShortcutFileItem?

    private struct ShortcutFileItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            // Section 1: 1-Tap Pre-Built Signed Shortcuts
            Section {
                shortcutInstallRow(
                    symbol: "square.and.arrow.up.fill",
                    tint: .accent,
                    title: L10n.text(lang, en: "Log to Tally (Share Sheet)", vi: "Log to Tally (Chia sẻ ảnh & tin nhắn)"),
                    subtitle: L10n.text(
                        lang,
                        en: "Share any PayNow screenshot, Grab receipt, or DBS/OCBC email → Tally reads text & logs it.",
                        vi: "Chia sẻ ảnh chụp PayNow, biên lai Grab, hoặc email ngân hàng → Tally tự đọc và lưu."
                    ),
                    resourceName: "LogToTally",
                    lang: lang
                )

                shortcutInstallRow(
                    symbol: "bolt.fill",
                    tint: .positive,
                    title: L10n.text(lang, en: "Quick Spend → Tally", vi: "Ghi nhanh → Tally"),
                    subtitle: L10n.text(
                        lang,
                        en: "Pin to Lock Screen or Action Button: type \"Ya Kun 6.50\" or \"ăn phở 65k\" to log in 2 seconds.",
                        vi: "Gắn lên Màn hình khoá hoặc nút Action: gõ \"Ya Kun 6.50\" hoặc \"ăn phở 65k\" là lưu ngay."
                    ),
                    resourceName: "QuickSpendTally",
                    lang: lang
                )
            } header: {
                formSectionHeader(L10n.text(lang, en: "1-Tap Ready-Made Shortcuts", vi: "Cài phím tắt làm sẵn (1 chạm)"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Tap Install, then choose \"Shortcuts\" in the share sheet (or AirDrop it straight to your wife's iPhone too).",
                    vi: "Bấm Cài đặt rồi chọn \"Phím tắt\" (hoặc AirDrop thẳng file này sang iPhone của vợ)."
                ))
            }

            // Section 2: 20-Second Background Automations (1 single action!)
            Section {
                Button {
                    if let url = URL(string: "shortcuts://create-automation") {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        SettingsIconTile(symbol: "arrow.up.forward.app.fill", tint: .ink, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text(lang, en: "Open Apple Shortcuts → Automations", vi: "Mở Phím tắt Apple → Tự động hoá"))
                                .font(.appBodyMedium)
                            Text(L10n.text(lang, en: "iOS requires picking the trigger once per phone", vi: "iOS yêu cầu tự chọn bộ kích hoạt 1 lần trên mỗi máy"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .buttonStyle(.themedPlain)

                automationGuide(
                    symbol: "creditcard.fill",
                    tint: .positive,
                    title: L10n.text(lang, en: "Apple Pay (Zero-touch)", vi: "Apple Pay (Hoàn toàn tự động)"),
                    steps: L10n.text(
                        lang,
                        en: """
                        Trigger: Transaction (Wallet) → select your cards → Run Immediately.
                        Add 1 action: "Auto-Log to Tally" (auto-uses Shortcut Input) — runs silently in background.
                        """,
                        vi: """
                        Kích hoạt: Giao dịch (Wallet) → chọn thẻ → Chạy ngay lập tức.
                        Thêm đúng 1 tác vụ: "Auto-Log to Tally" (tự lấy Đầu vào phím tắt) — chạy ngầm hoàn toàn.
                        """
                    )
                )

                automationGuide(
                    symbol: "envelope.fill",
                    tint: .info,
                    title: L10n.text(lang, en: "DBS / OCBC / UOB / Trust Emails", vi: "Email DBS / OCBC / UOB / Trust"),
                    steps: L10n.text(
                        lang,
                        en: """
                        Trigger: Email → Subject Contains "Transaction Alert" (or Sender: dbs.com, ocbc.com, uob.com.sg, trustbank.sg).
                        Add 1 action: "Auto-Log to Tally" with Shortcut Input.
                        """,
                        vi: """
                        Kích hoạt: Email → Tiêu đề chứa "Transaction Alert" (hoặc Người gửi: dbs.com, ocbc.com, uob.com.sg, trustbank.sg).
                        Thêm đúng 1 tác vụ: "Auto-Log to Tally" với Đầu vào phím tắt.
                        """
                    )
                )

                automationGuide(
                    symbol: "message.fill",
                    tint: .caution,
                    title: L10n.text(lang, en: "Bank SMS & PayNow", vi: "Tin nhắn SMS ngân hàng & PayNow"),
                    steps: L10n.text(
                        lang,
                        en: """
                        Trigger: Message → Message Contains "SGD" (add a second one for "VND" if needed) → Run Immediately.
                        Add 1 action: "Auto-Log to Tally" with Shortcut Input.
                        """,
                        vi: """
                        Kích hoạt: Tin nhắn → Tin nhắn chứa "SGD" (hoặc "VND") → Chạy ngay lập tức.
                        Thêm đúng 1 tác vụ: "Auto-Log to Tally" với Đầu vào phím tắt.
                        """
                    )
                )

                Toggle(isOn: $settings.flagAutoCapturedForReview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "Flag auto-captured items for review", vi: "Đánh dấu chờ duyệt cho giao dịch tự động"))
                        Text(L10n.text(lang, en: "Shows a quick review card on Overview to verify categories.", vi: "Hiện thẻ duyệt nhanh ở Tổng quan để kiểm tra danh mục."))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Automatic Background Capture (1 Action)", vi: "Tự động ghi ngầm (Chỉ 1 tác vụ)"))
            }

            // Section 3: Interactive Bank Alert Parser Tester
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        presetChip("DBS Card") {
                            sampleInput = "DBS Alert: A transaction of SGD 18.50 was made on your DBS Card at FAIRPRICE on 2026-11-23."
                        }
                        presetChip("PayNow") {
                            sampleInput = "You have transferred SGD 32.00 via PayNow to KOPITIAM HAWKER."
                        }
                        presetChip("VN Bank") {
                            sampleInput = "SD TK 190382910 -125,000 VND luc 09:15 tai HIGHLANDS COFFEE"
                        }
                    }
                }

                TextEditor(text: $sampleInput)
                    .font(.appSecondary)
                    .frame(minHeight: 74)

                Button {
                    Task { await testParse() }
                } label: {
                    if isTesting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(lang, en: "Testing…", vi: "Đang thử…"))
                        }
                    } else {
                        Label(
                            L10n.text(lang, en: "Test parser on this text", vi: "Thử đọc đoạn tin nhắn này"),
                            systemImage: "play.fill"
                        )
                    }
                }
                .pillButton(prominent: true)

                if let parsed = parsedPreview {
                    HStack(spacing: 12) {
                        CategoryBadge(category: parsed.category, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parsed.name).font(.appBodyMedium)
                            Text("\(parsed.category.title(in: lang)) · \(parsed.type.title(in: lang)) · \(parsed.parsedByAI ? "Claude AI" : "Offline")")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        let cur = parsed.currency ?? settings.currency
                        let minor = cur.toStorageMinor(parsed.amountMajor)
                        Text(MoneyFormat.format(minor: minor, currency: cur, language: lang))
                            .font(.appAmount)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Test Bank Alert Parser", vi: "Thử bộ đọc tin nhắn ngân hàng"))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "Auto-Capture", vi: "Tự động ghi"))
        #if os(iOS)
        .sheet(item: $sharingShortcutURL) { item in
            ShortcutShareSheet(url: item.url)
        }
        #endif
    }

    private func shortcutInstallRow(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        resourceName: String,
        lang: AppLanguage
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.appBodyMedium)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(L10n.text(lang, en: "Install", vi: "Cài đặt")) {
                if let url = Bundle.main.url(forResource: resourceName, withExtension: "shortcut")
                    ?? Bundle.main.url(forResource: resourceName, withExtension: "shortcut", subdirectory: "Shortcuts") {
                    sharingShortcutURL = ShortcutFileItem(url: url)
                }
            }
            .pillButton(prominent: true)
        }
        .padding(.vertical, 4)
    }

    private func presetChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .pillButton()
    }

    private func automationGuide(symbol: String, tint: Color, title: String, steps: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsIconTile(symbol: symbol, tint: tint, size: 30)
                Text(title).font(.appHeading)
            }
            Text(steps)
                .font(.appSecondary)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func testParse() async {
        isTesting = true
        defer { isTesting = false }
        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
        parsedPreview = await AITransactionParser.parse(
            text: sampleInput,
            source: .bankNotification,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        )
    }
}

#if os(iOS)
import UIKit

private struct ShortcutShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
