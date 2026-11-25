import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Interactive, Paws & Cream guided onboarding for wiring Apple Pay, Bank Email, and Bank SMS
/// automations into Apple Shortcuts.
struct ShortcutOnboardingSheet: View {
    let initialGuide: ShortcutGuideKind

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var activeGuide: ShortcutGuideKind
    @State private var checkedSteps: [ShortcutGuideKind: Set<Int>] = [:]
    @State private var copiedTag: String?
    @State private var simAmount = "S$6.50"
    @State private var simMerchant = "Ya Kun Kaya Toast"
    @State private var simCard = "DBS Live Fresh"

    init(initialGuide: ShortcutGuideKind) {
        self.initialGuide = initialGuide
        self._activeGuide = State(initialValue: initialGuide)
    }

    private var totalSteps: Int {
        activeGuide == .applePay ? 4 : 3
    }

    private var completedStepSet: Set<Int> {
        checkedSteps[activeGuide] ?? []
    }

    private var isLiveCaptureActive: Bool {
        store.activeTransactions.contains { $0.source == activeGuide.transactionSource }
    }

    private var isGuideCompleted: Bool {
        settings.isShortcutGuideCompleted(activeGuide)
    }

    private var progressFraction: Double {
        if isGuideCompleted && completedStepSet.isEmpty {
            return 1.0
        }
        return Double(completedStepSet.count) / Double(max(1, totalSteps))
    }

    var body: some View {
        let lang = settings.language

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ChipPicker(
                        L10n.text(lang, en: "Automation type", vi: "Loại tự động hoá", zh: "自动化类型"),
                        selection: $activeGuide,
                        options: ShortcutGuideKind.allCases,
                        sideMargin: 0,
                        label: { guideShortTitle($0, lang: lang) },
                        symbol: { guideSymbol($0) }
                    )

                    heroCard(lang: lang)

                    switch activeGuide {
                    case .applePay:
                        applePaySteps(lang: lang)
                    case .bankEmail:
                        bankEmailSteps(lang: lang)
                    case .bankSMS:
                        bankSMSSteps(lang: lang)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .pageBackground()
            .cozySheetToolbar(title: L10n.text(lang, en: "Shortcut Setup Guide", vi: "Hướng dẫn Phím tắt", zh: "快捷指令设置指南")) {
                Button(L10n.text(lang, en: "Close", vi: "Đóng", zh: "关闭")) {
                    dismiss()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomCompletionBar(lang: lang)
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 500, idealWidth: 540, minHeight: 580, idealHeight: 680)
    }

    // MARK: - Hero Card

    private func heroCard(lang: AppLanguage) -> some View {
        let statusTag = heroStatusTag(lang: lang)
        let doneCount = (isGuideCompleted && completedStepSet.isEmpty) ? totalSteps : completedStepSet.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CozyPetDuoView(mood: (isLiveCaptureActive || isGuideCompleted) ? .happy : .cozy, petSize: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(guideFullTitle(activeGuide, lang: lang))
                            .font(.appHeading)
                            .foregroundStyle(Color.textPrimary)
                        Spacer(minLength: 4)
                        Tag(text: statusTag.label, color: statusTag.color)
                    }

                    Text(heroSubtitle(activeGuide, lang: lang))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            #if os(macOS)
            HStack(spacing: 8) {
                CozyUIIcon(.creditCard, size: 14, color: Color.info)
                Text(L10n.text(
                    lang,
                    en: "Tip: Wallet & SMS automations live on your iPhone/iPad and sync transactions to your Mac automatically via iCloud.",
                    vi: "Mẹo: Tự động hoá Wallet & SMS được cài trên iPhone/iPad và tự động đồng bộ sang Mac qua iCloud.",
                    zh: "提示：钱包与短信自动化需在 iPhone/iPad 上设置，记录会自动通过 iCloud 同步到 Mac。"
                ))
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.info.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            #endif

            VStack(alignment: .leading, spacing: 6) {
                TallyProgressBar(value: progressFraction, fill: .positive)
                HStack {
                    Text(L10n.text(
                        lang,
                        en: "\(doneCount) of \(totalSteps) steps done",
                        vi: "Đã xong \(doneCount)/\(totalSteps) bước",
                        zh: "已完成 \(doneCount)/\(totalSteps) 步"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(L10n.text(lang, en: "Tap step numbers to check off", vi: "Chạm số bước để đánh dấu", zh: "点击步骤编号即可勾选"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Apple Pay Guided Steps

    @ViewBuilder
    private func applePaySteps(lang: AppLanguage) -> some View {
        stepCard(
            step: 1,
            title: L10n.text(lang, en: "Pick the Wallet Trigger", vi: "Chọn bộ kích hoạt Ví (Wallet)", zh: "选择钱包触发器"),
            badge: L10n.text(lang, en: "~10 sec", vi: "~10 giây", zh: "约 10 秒"),
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "In Apple Shortcuts, go to Automation → + → Transaction → pick your Apple Pay cards → choose Run Immediately (tip: turn off Notify When Run) → tap Next.",
                vi: "Trong Phím tắt Apple, vào Tự động hoá → + → Giao dịch → chọn các thẻ Apple Pay → chọn Chạy ngay lập tức (mẹo: tắt Thông báo khi chạy) → bấm Tiếp.",
                zh: "打开 Apple 快捷指令 → 自动化 → + → 交易 → 勾选 Apple Pay 银行卡 → 选择“立即运行”（建议关闭“运行时通知”）→ 点下一步。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                openShortcutsAutomations()
            } label: {
                HStack(spacing: 6) {
                    CozyUIIcon(.trendUp, size: 14, color: Color.onInk)
                    Text(openAutomationsLabel(lang: lang))
                }
            }
            .pillButton(prominent: true)
        }

        stepCard(
            step: 2,
            title: L10n.text(lang, en: "Add Tally's Action", vi: "Thêm tác vụ của Tally", zh: "添加 Tally 操作"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap New Blank Automation → Add Action → search Tally → pick \"Log Apple Pay Transaction\".",
                vi: "Chọn Tự động hoá trống mới → Thêm tác vụ → tìm Tally → chọn \"Log Apple Pay Transaction\".",
                zh: "点“新建空白自动化” → 添加操作 → 搜索 Tally → 选择“Log Apple Pay Transaction”。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                copyPillButton(text: "Log Apple Pay Transaction", tagID: "action-applepay", lang: lang)

                if let helperURL = settings.shortcutICloudURL(for: .applePayHelper) {
                    Button {
                        openURL(helperURL)
                    } label: {
                        HStack(spacing: 6) {
                            CozyUIIcon(.bolt, size: 13, color: Color.textPrimary)
                            Text(L10n.text(lang, en: "Add Helper Shortcut (1-Tap)", vi: "Cài phím tắt phụ (1 chạm)", zh: "一键添加辅助快捷指令"))
                        }
                    }
                    .pillButton()
                }
            }
        }

        stepCard(
            step: 3,
            title: L10n.text(lang, en: "Wire Shortcut Input (2-Tap Trick)", vi: "Nối Shortcut Input (mẹo 2 chạm)", zh: "绑定 Shortcut Input（2 步小技巧）"),
            badge: L10n.text(lang, en: "Important", vi: "Quan trọng", zh: "关键步骤"),
            badgeColor: .accent,
            lang: lang
        ) {
            // Visual mini-preview of the Shortcuts action card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Log Apple Pay")
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    shortcutTokenPill("Amount", color: .accent)
                    Text("at")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    shortcutTokenPill("Merchant", color: .positive)
                }

                HStack(spacing: 6) {
                    Text("▸ Card or Pass Name:")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    shortcutTokenPill("Card or Pass", color: .info)
                }

                HStack(spacing: 6) {
                    Text("▸ Currency:")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(L10n.text(lang, en: "(leave blank — auto-detected)", vi: "(để trống — tự nhận diện)", zh: "（留空 — 自动识别币种）"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )

            Text(L10n.text(
                lang,
                en: """
                1. Tap Amount → pick Shortcut Input → tap the Shortcut Input pill again → choose Amount.
                2. Tap Merchant → pick Shortcut Input → tap it again → choose Merchant.
                3. Optional: tap the ▸ arrow to map Card or Pass Name → Card or Pass.
                """,
                vi: """
                1. Chạm Amount → chọn Shortcut Input → chạm lại vào thẻ Shortcut Input lần nữa → chọn Amount.
                2. Chạm Merchant → chọn Shortcut Input → chạm lại lần nữa → chọn Merchant.
                3. Tuỳ chọn: mở mũi tên ▸ để nối Card or Pass Name → Card or Pass.
                """,
                zh: """
                1. 点 Amount → 选择“快捷指令输入” → 再点一次该紫色胶囊 → 选“金额 (Amount)”。
                2. 点 Merchant → 选择“快捷指令输入” → 再点一次 → 选“商户 (Merchant)”。
                3. 可选：展开 ▸ 箭头，将 Card or Pass Name 设为“卡或凭证 (Card or Pass)”。
                """
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(L10n.text(
                lang,
                en: "Leave Currency blank — Tally reads S$, $, HK$, €, ₫, ¥ straight from Wallet's Amount and converts foreign currencies automatically.",
                vi: "Cứ để trống Currency — Tally tự đọc S$, $, HK$, €, ₫, ¥ ngay từ Amount của Wallet và tự quy đổi ngoại tệ.",
                zh: "Currency 留空即可——Tally 会直接从钱包的金额文本中识别 S$、$、HK$、€、₫、¥ 并自动换算外币。"
            ))
            .font(.appCaption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        stepCard(
            step: 4,
            title: L10n.text(lang, en: "Save & Test How Tally Parses It", vi: "Lưu & thử cách Tally đọc giao dịch", zh: "保存并测试解析效果"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap Done in Shortcuts. On your first real Apple Pay tap, pick \"Always Allow\" if iOS asks permission so future taps run silently even while locked.",
                vi: "Bấm Xong trong Phím tắt. Ở lần chạm Apple Pay đầu tiên, chọn \"Luôn cho phép\" nếu iOS hỏi quyền để các lần sau tự chạy ngầm kể cả khi khoá máy.",
                zh: "在快捷指令中点“完成”。首次真实刷 Apple Pay 时如系统询问权限，请选择“始终允许”，之后即使锁屏也能静默记账。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(L10n.text(
                lang,
                en: "Note: Wallet triggers fire on physical NFC terminal taps. Online/in-app Apple Pay payments are captured by Cloud Bank Email Inbox without duplicates.",
                vi: "Lưu ý: Bộ kích hoạt Ví chạy khi chạm thanh toán NFC tại quầy. Giao dịch Apple Pay online/trong app được Hộp thư Ngân hàng tự bắt và chống trùng.",
                zh: "提示：钱包触发器在实体 NFC 刷卡时触发；线上/App 内 Apple Pay 付款可通过云端银行邮件收件箱捕获，且会自动去重。"
            ))
            .font(.appCaption)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            applePaySimulator(lang: lang)
        }
    }

    // MARK: - Bank Email Guided Steps

    @ViewBuilder
    private func bankEmailSteps(lang: AppLanguage) -> some View {
        stepCard(
            step: 1,
            title: L10n.text(lang, en: "Pick the Email Trigger", vi: "Chọn bộ kích hoạt Email", zh: "选择邮件触发器"),
            badge: L10n.text(lang, en: "~10 sec", vi: "~10 giây", zh: "约 10 秒"),
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "In Apple Shortcuts, go to Automation → + → Email → set Subject Contains \"Transaction Alert\" (or filter Sender) → Run Immediately → Next.",
                vi: "Trong Phím tắt Apple, vào Tự động hoá → + → Email → đặt Tiêu đề chứa \"Transaction Alert\" (hoặc lọc Người gửi) → Chạy ngay lập tức → Tiếp.",
                zh: "打开 Apple 快捷指令 → 自动化 → + → 电子邮件 → 设置主题包含“Transaction Alert”（或按发件人筛选）→ 立即运行 → 下一步。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                openShortcutsAutomations()
            } label: {
                HStack(spacing: 6) {
                    CozyUIIcon(.trendUp, size: 14, color: Color.onInk)
                    Text(openAutomationsLabel(lang: lang))
                }
            }
            .pillButton(prominent: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    copyPillButton(text: "Transaction Alert", tagID: "email-subject", lang: lang)
                    copyPillButton(text: "dbs.com", tagID: "email-dbs", lang: lang)
                    copyPillButton(text: "ocbc.com", tagID: "email-ocbc", lang: lang)
                    copyPillButton(text: "uob.com.sg", tagID: "email-uob", lang: lang)
                    copyPillButton(text: "trustbank.sg", tagID: "email-trust", lang: lang)
                }
            }
        }

        stepCard(
            step: 2,
            title: L10n.text(lang, en: "Add 1 Action: Auto-Log to Tally", vi: "Thêm 1 tác vụ: Auto-Log to Tally", zh: "添加 1 个操作：Auto-Log to Tally"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap New Blank Automation → Add Action → search Tally → pick \"Auto-Log to Tally\". It connects to Shortcut Input automatically.",
                vi: "Chọn Tự động hoá trống mới → Thêm tác vụ → tìm Tally → chọn \"Auto-Log to Tally\". Tác vụ tự lấy Đầu vào phím tắt.",
                zh: "点“新建空白自动化” → 添加操作 → 搜索 Tally → 选择“Auto-Log to Tally”，它会自动接收快捷指令输入。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            copyPillButton(text: "Auto-Log to Tally", tagID: "action-email", lang: lang)
        }

        stepCard(
            step: 3,
            title: L10n.text(lang, en: "Save & Consider Cloud Email Sync", vi: "Lưu & gợi ý đồng bộ Email đám mây", zh: "保存并了解云端邮件同步"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap Done and pick \"Always Allow\" on your first bank email. Want hands-free Gmail sync for both partners without Apple Shortcuts? Check Cloud Bank Email Inbox in Settings.",
                vi: "Bấm Xong và chọn \"Luôn cho phép\" ở email ngân hàng đầu tiên. Muốn tự động đọc Gmail cho cả hai vợ chồng mà không cần Phím tắt? Xem mục Hộp thư Email ngân hàng trong Cài đặt.",
                zh: "点“完成”并在收到第一封银行邮件时选“始终允许”。如果想免快捷指令自动同步夫妻双方的 Gmail 账单，可在设置中开启“云端银行邮件收件箱”。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bank SMS Guided Steps

    @ViewBuilder
    private func bankSMSSteps(lang: AppLanguage) -> some View {
        stepCard(
            step: 1,
            title: L10n.text(lang, en: "Pick the Message Trigger", vi: "Chọn bộ kích hoạt Tin nhắn", zh: "选择短信触发器"),
            badge: L10n.text(lang, en: "~10 sec", vi: "~10 giây", zh: "约 10 秒"),
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "In Apple Shortcuts, go to Automation → + → Message → Message Contains \"SGD\" (add a second one for \"VND\" if needed) → Run Immediately → Next.",
                vi: "Trong Phím tắt Apple, vào Tự động hoá → + → Tin nhắn → Tin nhắn chứa \"SGD\" (có thể thêm bộ thứ hai cho \"VND\") → Chạy ngay lập tức → Tiếp.",
                zh: "打开 Apple 快捷指令 → 自动化 → + → 信息 → 信息包含“SGD”（如有需要可再建一条“VND”）→ 立即运行 → 下一步。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                openShortcutsAutomations()
            } label: {
                HStack(spacing: 6) {
                    CozyUIIcon(.trendUp, size: 14, color: Color.onInk)
                    Text(openAutomationsLabel(lang: lang))
                }
            }
            .pillButton(prominent: true)

            HStack(spacing: 8) {
                copyPillButton(text: "SGD", tagID: "sms-sgd", lang: lang)
                copyPillButton(text: "VND", tagID: "sms-vnd", lang: lang)
            }
        }

        stepCard(
            step: 2,
            title: L10n.text(lang, en: "Add 1 Action: Auto-Log to Tally", vi: "Thêm 1 tác vụ: Auto-Log to Tally", zh: "添加 1 个操作：Auto-Log to Tally"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap New Blank Automation → Add Action → search Tally → pick \"Auto-Log to Tally\". It automatically receives the SMS text via Shortcut Input.",
                vi: "Chọn Tự động hoá trống mới → Thêm tác vụ → tìm Tally → chọn \"Auto-Log to Tally\". Nội dung SMS sẽ tự động được truyền qua Đầu vào phím tắt.",
                zh: "点“新建空白自动化” → 添加操作 → 搜索 Tally → 选择“Auto-Log to Tally”，短信文本会自动通过快捷指令输入传入。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            copyPillButton(text: "Auto-Log to Tally", tagID: "action-sms", lang: lang)
        }

        stepCard(
            step: 3,
            title: L10n.text(lang, en: "Save & Allow Silent Capture", vi: "Lưu & cho phép ghi tự động", zh: "保存并允许静默记录"),
            badge: nil,
            lang: lang
        ) {
            Text(L10n.text(
                lang,
                en: "Tap Done. When your next bank or PayNow SMS arrives, choose \"Always Allow\" if prompted so Tally logs future alerts automatically.",
                vi: "Bấm Xong. Khi tin nhắn ngân hàng hoặc PayNow tiếp theo tới, chọn \"Luôn cho phép\" nếu được hỏi để Tally tự động ghi các lần sau.",
                zh: "点“完成”。下次收到银行或 PayNow 短信时如提示权限，请选择“始终允许”，之后即可全自动入账。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Live Apple Pay Simulator (Step 4)

    @ViewBuilder
    private func applePaySimulator(lang: AppLanguage) -> some View {
        let parsed = ApplePayInputParser.parse(
            amountText: simAmount,
            merchant: simMerchant,
            cardName: simCard,
            defaultCurrency: settings.currency
        )

        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(lang, en: "Simulate an Apple Pay tap", vi: "Mô phỏng một lần chạm Apple Pay", zh: "模拟一次 Apple Pay 刷卡"))
                .font(.appLabel)
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button("S$6.50 · Ya Kun") {
                        simAmount = "S$6.50"
                        simMerchant = "Ya Kun Kaya Toast"
                        simCard = "DBS Live Fresh"
                    }
                    .pillButton()

                    Button("HK$83.75 · PinDuoDuo") {
                        simAmount = "HK$83.75"
                        simMerchant = "PinDuoDuo"
                        simCard = "Trust Credit"
                    }
                    .pillButton()

                    Button("125.000 ₫ · Highlands") {
                        simAmount = "125.000 ₫"
                        simMerchant = "HIGHLANDS COFFEE"
                        simCard = "Techcombank Visa"
                    }
                    .pillButton()
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(lang, en: "Amount", vi: "Số tiền", zh: "金额"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    TextField("S$6.50", text: $simAmount)
                        .tallyField()
                }
                .frame(maxWidth: 130)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(lang, en: "Merchant", vi: "Cửa hàng", zh: "商户"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    TextField("Ya Kun", text: $simMerchant)
                        .tallyField()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(lang, en: "Card or Pass (optional)", vi: "Thẻ hoặc ví (tuỳ chọn)", zh: "银行卡（可选）"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                TextField("DBS Live Fresh", text: $simCard)
                    .tallyField()
            }

            if let parsed {
                let category = LocalTransactionParser.inferCategory(
                    text: "\(parsed.merchantName) \(parsed.cardName ?? "")",
                    type: .expense
                )
                let resolved = AITransactionParser.resolvedAmountAndNote(
                    for: ParsedTransactionDraft(
                        name: parsed.merchantName,
                        amountMajor: parsed.amountMajor,
                        currencyCode: parsed.currencyCode,
                        type: .expense,
                        category: category,
                        note: parsed.note
                    ),
                    targetCurrency: settings.currency,
                    language: lang
                )
                let isForeign = parsed.currencyCode != settings.currency.rawValue
                let origMinor = CurrencyCode.toStorageMinor(parsed.amountMajor, currencyCode: parsed.currencyCode)

                HStack(spacing: 12) {
                    CategoryBadge(category: category, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(parsed.merchantName)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(category.title(in: lang)) · \(parsed.note)")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(MoneyFormat.format(minor: resolved.amountMinor, currency: settings.currency, language: lang))
                            .font(.appAmount)
                            .foregroundStyle(Color.textPrimary)
                        if isForeign {
                            Text(MoneyFormat.format(minor: origMinor, currencyCode: parsed.currencyCode, language: lang))
                                .font(.appCaption)
                                .monospacedDigit()
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding(12)
                .background(Color.positive.opacity(0.09), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .strokeBorder(Color.positive.opacity(0.25), lineWidth: 1)
                )
            } else {
                HStack(spacing: 8) {
                    CozyUIIcon(.warning, size: 14, color: Color.caution)
                    Text(L10n.text(
                        lang,
                        en: "Enter an amount like S$6.50, HK$83.75, or 125.000 ₫ to preview.",
                        vi: "Nhập số tiền như S$6.50, HK$83.75, hoặc 125.000 ₫ để xem thử.",
                        zh: "输入类似 S$6.50、HK$83.75 或 125.000 ₫ 的金额即可预览。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.caution.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            }
        }
        .padding(12)
        .background(Color.editorBackground, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
    }

    // MARK: - Step & Helper Components

    private func stepCard<Content: View>(
        step: Int,
        title: String,
        badge: String?,
        badgeColor: Color = .textSecondary,
        lang: AppLanguage,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isDone = completedStepSet.contains(step)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    toggleStep(step)
                } label: {
                    ZStack {
                        Circle()
                            .fill(isDone ? Color.positive : Color.accent.opacity(0.15))
                            .frame(width: 28, height: 28)
                        if isDone {
                            CozyUIIcon(.checkmark, size: 13, color: Color.onAccent)
                        } else {
                            Text("\(step)")
                                .font(.appControl)
                                .monospacedDigit()
                                .foregroundStyle(Color.accent)
                        }
                    }
                }
                .buttonStyle(.themedPlain)
                .accessibilityLabel(L10n.text(
                    lang,
                    en: isDone ? "Mark step \(step) not done" : "Mark step \(step) done",
                    vi: isDone ? "Bỏ đánh dấu bước \(step)" : "Đánh dấu xong bước \(step)",
                    zh: isDone ? "取消完成第 \(step) 步" : "标记完成第 \(step) 步"
                ))

                Text(title)
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: 4)

                if let badge {
                    Tag(text: badge, color: badgeColor)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func shortcutTokenPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.appCaption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func copyPillButton(text: String, tagID: String, lang: AppLanguage) -> some View {
        let isCopied = copiedTag == tagID
        return Button {
            copyToPasteboard(text)
            CozyHaptics.light()
            copiedTag = tagID
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                if copiedTag == tagID {
                    copiedTag = nil
                }
            }
        } label: {
            HStack(spacing: 6) {
                CozyUIIcon(isCopied ? .checkmark : .copy, size: 13, color: isCopied ? Color.positive : Color.textPrimary)
                Text(isCopied ? L10n.text(lang, en: "Copied!", vi: "Đã chép!", zh: "已复制！") : text)
                    .lineLimit(1)
            }
        }
        .pillButton()
    }

    private func bottomCompletionBar(lang: AppLanguage) -> some View {
        VStack(spacing: 8) {
            if isGuideCompleted {
                Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                    dismiss()
                }
                .blockButton(prominent: true)

                Button(L10n.text(lang, en: "Reset completion status", vi: "Đặt lại trạng thái hoàn thành", zh: "重置完成状态")) {
                    settings.setShortcutGuideCompleted(false, for: activeGuide)
                    checkedSteps[activeGuide] = []
                }
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .buttonStyle(.themedPlain)
            } else {
                Button {
                    settings.setShortcutGuideCompleted(true, for: activeGuide)
                    CozyHaptics.success()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        CozyUIIcon(.checkmarkCircle, size: 16, color: Color.onInk)
                        Text(L10n.text(lang, en: "Mark Setup Complete", vi: "Đánh dấu đã cài xong", zh: "标记设置完成"))
                    }
                }
                .blockButton(prominent: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    // MARK: - Actions & Labels

    private func toggleStep(_ step: Int) {
        CozyHaptics.selection()
        var current = checkedSteps[activeGuide] ?? []
        if current.contains(step) {
            current.remove(step)
        } else {
            current.insert(step)
        }
        checkedSteps[activeGuide] = current
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

    private func copyToPasteboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func openAutomationsLabel(lang: AppLanguage) -> String {
        #if os(macOS)
        return L10n.text(lang, en: "Open Apple Shortcuts", vi: "Mở Phím tắt Apple", zh: "打开 Apple 快捷指令")
        #else
        return L10n.text(lang, en: "Open Shortcuts → Automations", vi: "Mở Phím tắt → Tự động hoá", zh: "打开快捷指令 → 自动化")
        #endif
    }

    private func guideShortTitle(_ kind: ShortcutGuideKind, lang: AppLanguage) -> String {
        switch kind {
        case .applePay: return "Apple Pay"
        case .bankEmail: return L10n.text(lang, en: "Bank Email", vi: "Email NH", zh: "银行邮件")
        case .bankSMS: return L10n.text(lang, en: "Bank SMS", vi: "SMS & PayNow", zh: "银行短信")
        }
    }

    private func guideFullTitle(_ kind: ShortcutGuideKind, lang: AppLanguage) -> String {
        switch kind {
        case .applePay: return L10n.text(lang, en: "Apple Pay (Zero-touch)", vi: "Apple Pay (Tự động)", zh: "Apple Pay（自动记账）")
        case .bankEmail: return L10n.text(lang, en: "Bank Email Alerts", vi: "Email Ngân hàng", zh: "银行交易邮件")
        case .bankSMS: return L10n.text(lang, en: "Bank SMS & PayNow", vi: "SMS & PayNow", zh: "银行短信与 PayNow")
        }
    }

    private func guideSymbol(_ kind: ShortcutGuideKind) -> String {
        switch kind {
        case .applePay: return "creditcard.fill"
        case .bankEmail: return "envelope.fill"
        case .bankSMS: return "message.fill"
        }
    }

    private func heroSubtitle(_ kind: ShortcutGuideKind, lang: AppLanguage) -> String {
        switch kind {
        case .applePay:
            return L10n.text(
                lang,
                en: "Apple keeps Wallet triggers private per device, so iOS asks you to pick the trigger once (~30 sec). After that, every tap logs silently.",
                vi: "Apple giữ bộ kích hoạt Ví riêng tư trên từng máy, nên iOS yêu cầu chọn 1 lần (~30 giây). Sau đó mỗi lần chạm thẻ sẽ tự lưu ngầm.",
                zh: "出于隐私保护，Apple 仅允许在每台设备上手动选择一次钱包触发器（约 30 秒）。完成后每次刷卡都会后台自动记录。"
            )
        case .bankEmail:
            return L10n.text(
                lang,
                en: "Forward bank emails from Apple Mail straight into Tally in ~20 seconds with 1 action.",
                vi: "Tự động chuyển email ngân hàng từ Apple Mail vào Tally chỉ trong ~20 giây với 1 tác vụ.",
                zh: "约 20 秒添加 1 个操作，即可将 Apple 邮件中的银行通知自动记入 Tally。"
            )
        case .bankSMS:
            return L10n.text(
                lang,
                en: "Capture DBS, OCBC, UOB, PayNow, and VN bank SMS alerts automatically in ~20 seconds.",
                vi: "Tự động bắt tin nhắn ngân hàng DBS, OCBC, UOB, PayNow & ngân hàng VN trong ~20 giây.",
                zh: "约 20 秒设置即可自动识别银行与 PayNow 短信通知。"
            )
        }
    }

    private func heroStatusTag(lang: AppLanguage) -> (label: String, color: Color) {
        if isLiveCaptureActive {
            return (L10n.text(lang, en: "Active", vi: "Đang chạy", zh: "已生效"), .positive)
        }
        if isGuideCompleted {
            return (L10n.text(lang, en: "Set up", vi: "Đã cài", zh: "已设置"), .info)
        }
        let est = activeGuide == .applePay
            ? L10n.text(lang, en: "~30 sec", vi: "~30 giây", zh: "约 30 秒")
            : L10n.text(lang, en: "~20 sec", vi: "~20 giây", zh: "约 20 秒")
        return (est, .accent)
    }
}
