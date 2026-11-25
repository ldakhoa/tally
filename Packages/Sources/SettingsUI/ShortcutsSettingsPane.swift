import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

/// 1-tap installable Apple Shortcuts (via iCloud Shortcut links or bundled signed `.shortcut` files),
/// guided Apple Pay / Bank Email / Bank SMS onboarding, and live parser tester.
struct ShortcutsSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var sampleInput = "DBS Alert: A transaction of SGD 18.50 was made on your DBS Card at FAIRPRICE on 2026-11-23."
    @State private var parsedPreview: ParsedTransactionDraft?
    @State private var isTesting = false
    @State private var sharingShortcutURL: ShortcutFileItem?
    @State private var activeOnboardingGuide: ShortcutGuideKind?
    @State private var showICloudLinks = false
    @State private var shareSheetLinkDraft = ""
    @State private var quickSpendLinkDraft = ""
    @State private var applePayLinkDraft = ""
    @State private var linkStatusMessage: String?
    @State private var linkStatusIsError = false

    private struct ShortcutFileItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var applePayLatestTransaction: TransactionRecord? {
        latestTransaction(for: .applePay)
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            // Section 0: Apple Pay Quick-Start Hero
            Section {
                applePayHeroCard(lang: lang)
            }

            // Section 1: 1-Tap Ready-Made Shortcuts
            Section {
                shortcutInstallRow(
                    template: .shareSheet,
                    symbol: "square.and.arrow.up.fill",
                    tint: .accent,
                    title: L10n.text(lang, en: "Log to Tally (Share Sheet)", vi: "Log to Tally (Chia sẻ ảnh & tin nhắn)", zh: "记录到 Tally（共享菜单）"),
                    subtitle: L10n.text(
                        lang,
                        en: "Share any PayNow screenshot, Grab receipt, or DBS/OCBC email → Tally reads text & logs it.",
                        vi: "Chia sẻ ảnh chụp PayNow, biên lai Grab, hoặc email ngân hàng → Tally tự đọc và lưu.",
                        zh: "共享 PayNow 截图、Grab 收据或银行邮件 → Tally 自动识别并记账。"
                    ),
                    lang: lang
                )

                shortcutInstallRow(
                    template: .quickSpend,
                    symbol: "bolt.fill",
                    tint: .positive,
                    title: L10n.text(lang, en: "Quick Spend → Tally", vi: "Ghi nhanh → Tally", zh: "快速记账 → Tally"),
                    subtitle: L10n.text(
                        lang,
                        en: "Pin to Lock Screen or Action Button: type \"Ya Kun 6.50\" or \"ăn phở 65k\" to log in 2 seconds.",
                        vi: "Gắn lên Màn hình khoá hoặc nút Action: gõ \"Ya Kun 6.50\" hoặc \"ăn phở 65k\" là lưu ngay.",
                        zh: "添加到锁屏或操作按钮：输入“咖啡 6.5”即可 2 秒完成记账。"
                    ),
                    lang: lang
                )

                if settings.shortcutICloudURL(for: .applePayHelper) != nil {
                    shortcutInstallRow(
                        template: .applePayHelper,
                        symbol: "creditcard.fill",
                        tint: .info,
                        title: L10n.text(lang, en: "Apple Pay → Tally", vi: "Apple Pay → Tally", zh: "Apple Pay → Tally"),
                        subtitle: L10n.text(
                            lang,
                            en: "Helper shortcut for Wallet Transaction automations — pair via Run Shortcut with Shortcut Input.",
                            vi: "Phím tắt hỗ trợ cho tự động hoá Wallet — gắn qua Run Shortcut với Shortcut Input.",
                            zh: "用于钱包自动化的辅助快捷指令 — 通过“运行快捷指令”并传入快捷指令输入使用。"
                        ),
                        lang: lang
                    )
                }

                DisclosureGroup(isExpanded: $showICloudLinks) {
                    iCloudLinksEditor(lang: lang)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "1-Tap iCloud Shortcut Links", vi: "Link iCloud cài phím tắt 1 chạm", zh: "一键安装 iCloud 快捷指令链接"))
                            .font(.appBodyMedium)
                        Text(L10n.text(
                            lang,
                            en: "Paste icloud.com/shortcuts links to skip the iOS share sheet",
                            vi: "Dán link icloud.com/shortcuts để nhảy thẳng vào Phím tắt Apple",
                            zh: "粘贴 icloud.com/shortcuts 链接，跳过共享菜单直接添加"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "1-Tap Ready-Made Shortcuts", vi: "Cài phím tắt làm sẵn (1 chạm)", zh: "一键安装现成快捷指令"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "When an iCloud link is saved, tapping Add Shortcut jumps straight into Apple Shortcuts. Without a link on iPhone, tap Install → choose Shortcuts in the share sheet → Add Shortcut.",
                    vi: "Khi đã lưu link iCloud, bấm Thêm phím tắt sẽ mở thẳng ứng dụng Phím tắt. Nếu chưa có link trên iPhone, bấm Cài đặt → chọn Phím tắt trong bảng chia sẻ → Thêm phím tắt.",
                    zh: "保存 iCloud 链接后，点击“添加快捷指令”将直接跳转 Apple 快捷指令。未设置链接时，在 iPhone 上点安装 → 在共享菜单选择“快捷指令”→“添加快捷指令”。"
                ))
            }

            // Section 2: Automatic Background Capture (Guided Setups)
            Section {
                Button {
                    openShortcutsAutomations()
                } label: {
                    HStack {
                        SettingsIconTile(symbol: "arrow.up.forward.app.fill", tint: .ink, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            #if os(macOS)
                            Text(L10n.text(lang, en: "Open Apple Shortcuts on Mac", vi: "Mở Phím tắt Apple trên Mac", zh: "在 Mac 上打开 Apple 快捷指令"))
                                .font(.appBodyMedium)
                            Text(L10n.text(lang, en: "Quick Spend & Share Sheet run on Mac; Wallet/SMS triggers run on iPhone or iPad and sync via iCloud", vi: "Ghi nhanh & Chia sẻ chạy trên Mac; tự động hoá Wallet/SMS chạy trên iPhone/iPad và đồng bộ iCloud", zh: "快速记账与共享菜单可在 Mac 运行；钱包/短信自动化在 iPhone/iPad 触发并通过 iCloud 同步"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            #else
                            Text(L10n.text(lang, en: "Open Apple Shortcuts → Automations", vi: "Mở Phím tắt Apple → Tự động hoá", zh: "打开 Apple 快捷指令 → 自动化"))
                                .font(.appBodyMedium)
                            Text(L10n.text(lang, en: "iOS requires picking the trigger once per device", vi: "iOS yêu cầu tự chọn bộ kích hoạt 1 lần trên mỗi máy", zh: "iOS 要求每台设备手动选择一次触发条件"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            #endif
                        }
                        Spacer()
                        CozyUIIcon(.chevronRight, size: 14, color: Color.textSecondary)
                    }
                }
                .buttonStyle(.themedPlain)

                ForEach(ShortcutGuideKind.allCases) { guide in
                    guidedSetupRow(guide, lang: lang)
                }

                Toggle(isOn: $settings.flagAutoCapturedForReview) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "Flag auto-captured items for review", vi: "Đánh dấu chờ duyệt cho giao dịch tự động", zh: "标记自动记录的账单待确认"))
                        Text(L10n.text(lang, en: "Shows a quick review card on Overview to verify categories.", vi: "Hiện thẻ duyệt nhanh ở Tổng quan để kiểm tra danh mục.", zh: "在概览页显示快速确认卡片，方便核对分类。"))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Automatic Background Capture (Guided)", vi: "Tự động ghi ngầm (Có hướng dẫn)", zh: "后台自动记账（分步引导）"))
            }

            // Section 3: Interactive Bank Alert & Apple Pay Parser Tester
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        presetChip("Apple Pay") {
                            sampleInput = "Apple Pay S$14.80 at YA KUN KAYA TOAST DBS Live Fresh"
                        }
                        presetChip("DBS Card") {
                            sampleInput = "DBS Alert: A transaction of SGD 18.50 was made on your DBS Card at FAIRPRICE on 2026-11-23."
                        }
                        presetChip("PayNow") {
                            sampleInput = "You have transferred SGD 32.00 via PayNow to KOPITIAM HAWKER."
                        }
                        presetChip("VN Bank") {
                            sampleInput = "SD TK 190382910 -125,000 VND luc 09:15 tai HIGHLANDS COFFEE"
                        }
                        presetChip("Trust FX") {
                            sampleInput = "0% FX fees! You've spent HKD 83.75 using Freedom credit card at PinDuoDuo HONG KONG HK on 25 Nov 2026 04:30SGT. You’ll receive estimated S$0.07 cashback*. Not you? Alert us via Trust app."
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
                            Text(L10n.text(lang, en: "Testing…", vi: "Đang thử…", zh: "测试中…"))
                        }
                    } else {
                        HStack(spacing: 6) {
                            CozyUIIcon(.play, size: 14, color: Color.onInk)
                            Text(L10n.text(lang, en: "Test parser on this text", vi: "Thử đọc đoạn tin nhắn này", zh: "测试解析此文本"))
                        }
                    }
                }
                .pillButton(prominent: true)

                if let parsed = parsedPreview {
                    let curCode = parsed.currencyCode ?? settings.currency.rawValue
                    let origMinor = CurrencyCode.toStorageMinor(parsed.amountMajor, currencyCode: curCode)
                    let isForeign = curCode != settings.currency.rawValue
                    let resolved = AITransactionParser.resolvedAmountAndNote(
                        for: parsed,
                        targetCurrency: settings.currency,
                        language: lang
                    )
                    HStack(spacing: 12) {
                        CategoryBadge(category: parsed.category, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(parsed.name).font(.appBodyMedium)
                            Text("\(parsed.category.title(in: lang)) · \(parsed.type.title(in: lang)) · \(parsed.parsedByAI ? "AI" : "Offline")")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if isForeign {
                                Text(MoneyFormat.format(minor: resolved.amountMinor, currency: settings.currency, language: lang))
                                    .font(.appAmount)
                                Text(MoneyFormat.format(minor: origMinor, currencyCode: curCode, language: lang))
                                    .font(.appCaption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.textSecondary)
                            } else {
                                Text(MoneyFormat.format(minor: origMinor, currencyCode: curCode, language: lang))
                                    .font(.appAmount)
                            }
                        }
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Test Bank Alert & Apple Pay Parser", vi: "Thử bộ đọc thông báo & Apple Pay", zh: "测试银行通知与 Apple Pay 解析"))
            }
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "Auto-Capture", vi: "Tự động ghi", zh: "自动记账"))
        .onAppear {
            syncLinkDrafts()
        }
        .sheet(item: $activeOnboardingGuide) { guide in
            ShortcutOnboardingSheet(initialGuide: guide)
        }
        #if os(iOS)
        .sheet(item: $sharingShortcutURL) { item in
            ShortcutShareSheet(url: item.url)
        }
        #endif
    }

    // MARK: - Section 0: Apple Pay Quick-Start Hero

    private func applePayHeroCard(lang: AppLanguage) -> some View {
        let latest = applePayLatestTransaction
        let isCompleted = settings.isShortcutGuideCompleted(.applePay)

        return HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(
                symbol: "creditcard.fill",
                tint: latest != nil ? .positive : (isCompleted ? .info : .accent),
                size: 38
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(L10n.text(lang, en: "Apple Pay Auto-Capture", vi: "Tự động ghi Apple Pay", zh: "Apple Pay 自动记账"))
                        .font(.appHeading)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 4)
                    if latest != nil {
                        Tag(text: L10n.text(lang, en: "Active", vi: "Đang chạy", zh: "已生效"), color: .positive)
                    } else if isCompleted {
                        Tag(text: L10n.text(lang, en: "Ready", vi: "Sẵn sàng", zh: "已就绪"), color: .info)
                    } else {
                        Tag(text: L10n.text(lang, en: "~30 sec", vi: "~30 giây", zh: "约 30 秒"), color: .accent)
                    }
                }

                if let latest {
                    Text(L10n.text(
                        lang,
                        en: "Last captured at \(latest.name) (\(relativeTimeString(from: latest.createdAt, lang: lang))). Every tap logs silently.",
                        vi: "Ghi gần nhất tại \(latest.name) (\(relativeTimeString(from: latest.createdAt, lang: lang))). Mỗi lần chạm sẽ tự lưu ngầm.",
                        zh: "最近一次在 \(latest.name) 自动记账（\(relativeTimeString(from: latest.createdAt, lang: lang))）。每次刷卡都会后台静默保存。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else if isCompleted {
                    Text(L10n.text(
                        lang,
                        en: "Setup marked ready. On your first real Apple Pay tap, pick \"Always Allow\" if iOS asks permission.",
                        vi: "Đã đánh dấu hoàn tất. Ở lần chạm Apple Pay đầu tiên, chọn \"Luôn cho phép\" nếu iOS hỏi quyền.",
                        zh: "已完成设置标记。首次真实刷 Apple Pay 时如系统询问，请选择“始终允许”。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.text(
                        lang,
                        en: "iOS keeps Wallet triggers private per device, so Apple Shortcuts asks you to pick the trigger once (~30 sec). Our interactive guide walks you through it.",
                        vi: "iOS giữ bộ kích hoạt Ví riêng tư trên từng máy, nên Phím tắt Apple yêu cầu tự chọn 1 lần (~30 giây). Hướng dẫn tương tác sẽ chỉ từng bước rõ ràng.",
                        zh: "出于隐私限制，Apple 要求每台设备在快捷指令中手动选择一次钱包触发器（约 30 秒）。跟随交互指南即可轻松完成。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    activeOnboardingGuide = .applePay
                } label: {
                    Text(
                        latest != nil
                            ? L10n.text(lang, en: "Review Setup Guide", vi: "Xem lại hướng dẫn", zh: "查看设置指南")
                            : (isCompleted
                                ? L10n.text(lang, en: "Open Setup Guide", vi: "Mở hướng dẫn", zh: "打开设置指南")
                                : L10n.text(lang, en: "Start 30-Second Setup", vi: "Bắt đầu cài (30 giây)", zh: "开始 30 秒设置"))
                    )
                }
                .pillButton(prominent: true)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Section 1: Shortcut Install Rows & iCloud Links

    private func shortcutInstallRow(
        template: ShortcutTemplateID,
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        lang: AppLanguage
    ) -> some View {
        let icloudURL = settings.shortcutICloudURL(for: template)

        return HStack(alignment: .top, spacing: 12) {
            SettingsIconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.appBodyMedium)
                    if icloudURL != nil {
                        Tag(text: L10n.text(lang, en: "1-Tap", vi: "1 chạm", zh: "一键"), color: .positive)
                    }
                }
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if let icloudURL {
                    ShareLink(item: icloudURL) {
                        CozyUIIcon(.exportBox, size: 15, color: Color.textPrimary)
                    }
                    .buttonStyle(IconButtonStyle(filled: true))
                    .accessibilityLabel(L10n.text(lang, en: "Share shortcut link", vi: "Chia sẻ link phím tắt", zh: "分享快捷指令链接"))

                    Button(L10n.text(lang, en: "Add Shortcut", vi: "Thêm phím tắt", zh: "添加快捷指令")) {
                        openURL(icloudURL)
                    }
                    .pillButton(prominent: true)
                } else if let resourceName = template.bundledResourceName,
                          let url = bundledShortcutURL(named: resourceName) {
                    #if os(macOS)
                    Button(L10n.text(lang, en: "Add Shortcut", vi: "Thêm phím tắt", zh: "添加快捷指令")) {
                        NSWorkspace.shared.open(url)
                    }
                    .pillButton(prominent: true)
                    #else
                    Button(L10n.text(lang, en: "Install", vi: "Cài đặt", zh: "安装")) {
                        sharingShortcutURL = ShortcutFileItem(url: url)
                    }
                    .pillButton(prominent: true)
                    #endif
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func iCloudLinksEditor(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(
                lang,
                en: "In Apple Shortcuts, open your shortcut → Share → Copy iCloud Link, then paste it here.",
                vi: "Trong Phím tắt Apple, mở phím tắt → Chia sẻ → Sao chép liên kết iCloud, rồi dán vào đây.",
                zh: "在 Apple 快捷指令中打开对应快捷指令 → 共享 → 拷贝 iCloud 链接，然后粘贴到此处。"
            ))
            .font(.appCaption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            linkInputField(
                label: L10n.text(lang, en: "Log to Tally (Share Sheet)", vi: "Log to Tally (Chia sẻ)", zh: "记录到 Tally（共享菜单）"),
                text: $shareSheetLinkDraft
            )

            linkInputField(
                label: L10n.text(lang, en: "Quick Spend → Tally", vi: "Ghi nhanh → Tally", zh: "快速记账 → Tally"),
                text: $quickSpendLinkDraft
            )

            linkInputField(
                label: L10n.text(lang, en: "Apple Pay → Tally (optional helper)", vi: "Apple Pay → Tally (tuỳ chọn)", zh: "Apple Pay → Tally（可选辅助）"),
                text: $applePayLinkDraft
            )

            HStack(spacing: 8) {
                Button(L10n.text(lang, en: "Save Links", vi: "Lưu liên kết", zh: "保存链接")) {
                    saveICloudLinks(lang: lang)
                }
                .pillButton(prominent: true)

                Button(L10n.text(lang, en: "Clear", vi: "Xoá", zh: "清空")) {
                    clearICloudLinks(lang: lang)
                }
                .pillButton()
            }

            if let linkStatusMessage {
                Text(linkStatusMessage)
                    .font(.appCaption)
                    .foregroundStyle(linkStatusIsError ? Color.negative : Color.positive)
            }
        }
        .padding(.vertical, 6)
    }

    private func linkInputField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.appCaption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            TextField("https://www.icloud.com/shortcuts/...", text: text)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                .tallyField()
        }
    }

    // MARK: - Section 2: Guided Automation Rows

    private func guidedSetupRow(_ guide: ShortcutGuideKind, lang: AppLanguage) -> some View {
        let hasLive = latestTransaction(for: guide.transactionSource) != nil
        let isCompleted = settings.isShortcutGuideCompleted(guide)

        return Button {
            activeOnboardingGuide = guide
        } label: {
            HStack(spacing: 12) {
                SettingsIconTile(symbol: guideSymbol(guide), tint: guideTint(guide), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(guideTitle(guide, lang: lang))
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text(guideSummary(guide, lang: lang))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if hasLive {
                    Tag(text: L10n.text(lang, en: "Active", vi: "Đang chạy", zh: "已生效"), color: .positive)
                } else if isCompleted {
                    Tag(text: L10n.text(lang, en: "Set up", vi: "Đã cài", zh: "已设置"), color: .info)
                } else {
                    Tag(
                        text: guide == .applePay
                            ? L10n.text(lang, en: "~30 sec", vi: "~30 giây", zh: "约 30 秒")
                            : L10n.text(lang, en: "~20 sec", vi: "~20 giây", zh: "约 20 秒"),
                        color: .textSecondary
                    )
                }
                CozyUIIcon(.chevronRight, size: 14, color: Color.textSecondary)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.themedPlain)
    }

    // MARK: - Helpers

    private func bundledShortcutURL(named resourceName: String) -> URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "shortcut")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "shortcut", subdirectory: "Shortcuts")
    }

    private func latestTransaction(for source: TransactionSource) -> TransactionRecord? {
        store.activeTransactions
            .filter { $0.source == source }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    private func relativeTimeString(from date: Date, lang: AppLanguage) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = lang.locale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func openShortcutsAutomations() {
        #if os(macOS)
        if let url = URL(string: "shortcuts://") {
            openURL(url)
        }
        #else
        if let url = URL(string: "shortcuts://create-automation") {
            openURL(url)
        }
        #endif
    }

    private func syncLinkDrafts() {
        shareSheetLinkDraft = settings.shortcutICloudLinkString(for: .shareSheet)
        quickSpendLinkDraft = settings.shortcutICloudLinkString(for: .quickSpend)
        applePayLinkDraft = settings.shortcutICloudLinkString(for: .applePayHelper)
    }

    private func saveICloudLinks(lang: AppLanguage) {
        let pairs: [(ShortcutTemplateID, String)] = [
            (.shareSheet, shareSheetLinkDraft),
            (.quickSpend, quickSpendLinkDraft),
            (.applePayHelper, applePayLinkDraft),
        ]
        for (_, raw) in pairs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && ShortcutICloudLink.normalizedURL(from: trimmed) == nil {
                linkStatusIsError = true
                linkStatusMessage = L10n.text(
                    lang,
                    en: "Use a valid icloud.com/shortcuts/... link (or leave blank).",
                    vi: "Vui lòng dán link icloud.com/shortcuts/... hợp lệ (hoặc để trống).",
                    zh: "请填写有效的 icloud.com/shortcuts/... 链接（或留空）。"
                )
                return
            }
        }
        for (template, raw) in pairs {
            settings.setShortcutICloudLink(raw, for: template)
        }
        syncLinkDrafts()
        linkStatusIsError = false
        linkStatusMessage = L10n.text(lang, en: "Saved 1-tap links!", vi: "Đã lưu liên kết 1 chạm!", zh: "已保存一键安装链接！")
        CozyHaptics.success()
    }

    private func clearICloudLinks(lang: AppLanguage) {
        for template in ShortcutTemplateID.allCases {
            settings.setShortcutICloudLink("", for: template)
        }
        syncLinkDrafts()
        linkStatusIsError = false
        linkStatusMessage = L10n.text(lang, en: "Cleared saved links (using bundled shortcuts).", vi: "Đã xoá link (dùng file phím tắt tích hợp).", zh: "已清除链接（改用内置快捷指令）。")
    }

    private func guideSymbol(_ guide: ShortcutGuideKind) -> String {
        switch guide {
        case .applePay: return "creditcard.fill"
        case .bankEmail: return "envelope.fill"
        case .bankSMS: return "message.fill"
        }
    }

    private func guideTint(_ guide: ShortcutGuideKind) -> Color {
        switch guide {
        case .applePay: return .positive
        case .bankEmail: return .info
        case .bankSMS: return .caution
        }
    }

    private func guideTitle(_ guide: ShortcutGuideKind, lang: AppLanguage) -> String {
        switch guide {
        case .applePay: return L10n.text(lang, en: "Apple Pay (Zero-touch)", vi: "Apple Pay (Hoàn toàn tự động)", zh: "Apple Pay（全自动）")
        case .bankEmail: return L10n.text(lang, en: "DBS / OCBC / UOB / Trust Emails", vi: "Email DBS / OCBC / UOB / Trust", zh: "DBS / OCBC / UOB / Trust 邮件")
        case .bankSMS: return L10n.text(lang, en: "Bank SMS & PayNow", vi: "Tin nhắn SMS ngân hàng & PayNow", zh: "银行短信与 PayNow")
        }
    }

    private func guideSummary(_ guide: ShortcutGuideKind, lang: AppLanguage) -> String {
        switch guide {
        case .applePay:
            return L10n.text(lang, en: "Transaction trigger → Log Apple Pay Transaction", vi: "Kích hoạt Giao dịch → Log Apple Pay Transaction", zh: "交易触发器 → Log Apple Pay Transaction")
        case .bankEmail:
            return L10n.text(lang, en: "Email trigger → Auto-Log to Tally (1 action)", vi: "Kích hoạt Email → Auto-Log to Tally (1 tác vụ)", zh: "邮件触发器 → Auto-Log to Tally（1 步）")
        case .bankSMS:
            return L10n.text(lang, en: "Message trigger → Auto-Log to Tally (1 action)", vi: "Kích hoạt Tin nhắn → Auto-Log to Tally (1 tác vụ)", zh: "短信触发器 → Auto-Log to Tally（1 步）")
        }
    }

    private func presetChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .pillButton()
    }

    private func testParse() async {
        isTesting = true
        defer { isTesting = false }
        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
        let source: TransactionSource = sampleInput.lowercased().contains("apple pay") ? .applePay : .bankNotification
        let draft = await AITransactionParser.parse(
            text: sampleInput,
            source: source,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        )
        if let code = draft?.currencyCode, code != settings.currency.rawValue {
            await ExchangeRateService.shared.refreshIfStale()
        }
        parsedPreview = draft
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
#elseif os(macOS)
import AppKit
#endif
