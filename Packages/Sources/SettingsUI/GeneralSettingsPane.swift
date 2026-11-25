import AppServices
import DesignSystem
import SwiftUI
import TallyCore
import ThemeTokens

struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(ExchangeRateService.self) private var exchangeRates: ExchangeRateService?
    @Environment(\.colorScheme) private var colorScheme

    @State private var pendingCurrencySwitch: CurrencyCode?

    private var fxService: ExchangeRateService { exchangeRates ?? .shared }

    private var currencyBinding: Binding<CurrencyCode> {
        Binding(
            get: { settings.currency },
            set: { newCode in
                guard newCode != settings.currency else { return }
                if store.hasActiveRecords {
                    pendingCurrencySwitch = newCode
                } else {
                    settings.setHouseholdCurrency(newCode)
                }
            }
        )
    }

    private var displayCurrencyBinding: Binding<CurrencyCode?> {
        Binding(
            get: { settings.displayCurrency },
            set: { newDisplay in
                settings.displayCurrency = newDisplay
                if newDisplay != nil {
                    Task { await fxService.refreshIfStale() }
                }
            }
        )
    }

    /// Hiding never asks; showing asks for Face ID / passcode when that requirement is on.
    private var hideSalaryBinding: Binding<Bool> {
        Binding(
            get: { settings.hideSalary },
            set: { hide in
                if hide {
                    settings.salaryGate.hide()
                } else {
                    Task { await settings.salaryGate.reveal(reason: SalaryAuthPrompt.reveal(in: settings.language)) }
                }
            }
        )
    }

    /// Turning the requirement on needs a passcode on the device; turning it off needs
    /// authentication.
    private var requireAuthBinding: Binding<Bool> {
        Binding(
            get: { settings.requiresAuthToShowSalary },
            set: { enabled in
                Task {
                    await settings.salaryGate.setRequiresAuthentication(
                        enabled,
                        reason: SalaryAuthPrompt.turnOffRequirement(in: settings.language)
                    )
                }
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language
        let gate = settings.salaryGate

        Form {
            Section {
                Picker(L10n.text(lang, en: "Language", vi: "Ngôn ngữ", zh: "语言"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title(in: lang)).tag(option)
                    }
                }

                Picker(L10n.text(lang, en: "Currency", vi: "Đơn vị tiền tệ", zh: "货币"), selection: currencyBinding) {
                    ForEach(CurrencyCode.allCases) { code in
                        Text("\(code.rawValue) · \(code.name(in: lang))").tag(code)
                    }
                }

                Picker(L10n.text(lang, en: "Display in", vi: "Hiển thị bằng", zh: "显示货币"), selection: displayCurrencyBinding) {
                    Text(L10n.text(
                        lang,
                        en: "Same as household (\(settings.currency.rawValue))",
                        vi: "Theo tiền tệ chung (\(settings.currency.rawValue))",
                        zh: "跟随家庭货币（\(settings.currency.rawValue)）"
                    ))
                    .tag(CurrencyCode?.none)

                    ForEach(CurrencyCode.allCases.filter { $0 != settings.currency }) { code in
                        Text("\(code.rawValue) · \(code.name(in: lang))")
                            .tag(CurrencyCode?.some(code))
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "Exchange rates", vi: "Tỷ giá quy đổi", zh: "汇率更新"))
                            .font(.appBody)
                        Text(fxStatusText(lang: lang))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    if fxService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await fxService.refreshNow() }
                        } label: {
                            CozyUIIcon(.refresh, size: 16, color: Color.accent)
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(L10n.text(lang, en: "Refresh exchange rates", vi: "Cập nhật tỷ giá", zh: "刷新汇率"))
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Language & Currency", vi: "Ngôn ngữ & Tiền tệ", zh: "语言与货币"))
            } footer: {
                if settings.isConvertingDisplay {
                    let display = settings.effectiveDisplayCurrency
                    let rateLine = fxService.table.conversionRate(from: settings.currency.rawValue, to: display.rawValue)
                        .map { "\(ExchangeRateTable.formatRate($0.rate, from: settings.currency.rawValue, to: display)) · " } ?? ""
                    formSectionFooter(L10n.text(
                        lang,
                        en: "\(rateLine)Stored household data remains in \(settings.currency.rawValue); this device shows amounts converted to \(display.rawValue).",
                        vi: "\(rateLine)Dữ liệu gốc vẫn lưu bằng \(settings.currency.rawValue); thiết bị này hiển thị số tiền đã quy đổi sang \(display.rawValue).",
                        zh: "\(rateLine)家庭原始数据仍以 \(settings.currency.rawValue) 存储；本设备将以 \(display.rawValue) 显示换算金额。"
                    ))
                }
            }

            Section {
                TextField(
                    L10n.text(lang, en: "Your name (e.g. Khoa)", vi: "Tên của bạn (VD: Khoa)", zh: "您的名字（例如：Khoa）"),
                    text: $settings.myDisplayName
                )
                TextField(
                    L10n.text(lang, en: "Partner's name (e.g. Wife)", vi: "Tên vợ / chồng (VD: Vợ)", zh: "伴侣的名字（例如：老婆）"),
                    text: $settings.partnerDisplayName
                )
            } header: {
                formSectionHeader(L10n.text(lang, en: "Household profile", vi: "Hồ sơ gia đình", zh: "家庭资料"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Each transaction logged on this device is tagged with your name so you and your partner can filter spending.",
                    vi: "Mỗi giao dịch ghi trên thiết bị này sẽ tự động gắn tên bạn để hai vợ chồng dễ lọc và xem chi tiêu.",
                    zh: "在此设备上记录的每笔账单都会自动标记您的名字，方便两人筛选和查看支出。"
                ))
            }

            Section {
                Picker(L10n.text(lang, en: "Appearance", vi: "Chế độ sáng/tối", zh: "外观模式"), selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title(in: lang)).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                let dark = colorScheme == .dark
                ForEach(AppTheme.choices(dark: dark)) { choice in
                    let isSelected = settings.theme.isChoice(choice, dark: dark)
                    let palette = choice.palette(dark: dark)
                    Button {
                        settings.theme = settings.theme.choosing(choice, dark: dark)
                    } label: {
                        HStack(spacing: 12) {
                            HStack(spacing: 3) {
                                Circle().fill(Color(hex: palette.ios.page.rgb)).frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(Color.hairlineStrong, lineWidth: 0.7))
                                Circle().fill(Color(hex: palette.ink.rgb)).frame(width: 16, height: 16)
                                Circle().fill(Color(hex: palette.accent.rgb)).frame(width: 16, height: 16)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.choiceTitle(dark: dark)).font(.appBodyMedium)
                                Text(choice.summary(in: lang)).font(.appCaption).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            if isSelected {
                                CozyUIIcon(.checkmark, size: 16, color: Color.accent)
                            }
                        }
                    }
                    .buttonStyle(.themedPlain)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Theme", vi: "Chủ đề giao diện", zh: "主题风格"))
            }

            Section {
                Toggle(isOn: hideSalaryBinding) {
                    HStack(spacing: 10) {
                        CozyUIIcon(settings.hideSalary ? .eyeClosed : .eye, size: 20, color: Color.textSecondary)
                        Text(L10n.text(lang, en: "Hide salary", vi: "Ẩn lương", zh: "隐藏工资"))
                    }
                }
                .disabled(gate.isAuthenticating)

                Toggle(isOn: requireAuthBinding) {
                    HStack(spacing: 10) {
                        CozyUIIcon(.key, size: 20, color: Color.textSecondary)
                        Text(gate.authKind.requirementTitle(in: lang))
                    }
                }
                .disabled(gate.isAuthenticating)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    formSectionFooter(L10n.text(
                        lang,
                        en: "Masks salary, and totals, net savings and savings rate for any period that includes salary. Other income and spending stay visible. Applies to this device only.",
                        vi: "Ẩn lương, cùng tổng thu, tiết kiệm ròng và tỷ lệ tiết kiệm của mọi kỳ có lương. Thu nhập khác và chi tiêu vẫn hiển thị. Chỉ áp dụng cho thiết bị này.",
                        zh: "隐藏工资，以及包含工资的任何时间段的总收入、净结余和结余率。其他收入和支出仍然可见。仅对本设备生效。"
                    ))
                    if gate.requiresAuthentication {
                        formSectionFooter(L10n.text(
                            lang,
                            en: "Salary starts hidden every time Tally opens and is hidden again when you leave the app.",
                            vi: "Lương luôn được ẩn mỗi khi mở Tally và ẩn lại khi bạn rời khỏi app.",
                            zh: "每次打开 Tally 时工资都会先隐藏，离开应用后也会重新隐藏。"
                        ))
                    }
                    if let notice = gate.notice {
                        formSectionFooter(notice.message(in: lang))
                            .foregroundStyle(Color.negative)
                    }
                }
            }
            .onAppear { gate.refreshAvailability() }

            Section {
                Toggle(
                    L10n.text(lang, en: "Sound effects", vi: "Âm thanh tương tác", zh: "交互音效"),
                    isOn: $settings.soundEffectsEnabled
                )
                .onChange(of: settings.soundEffectsEnabled) { _, enabled in
                    if enabled {
                        CozySounds.play(.pop)
                    }
                }
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Subtle pop & chime sounds when tapping tabs and buttons. Automatically muted when your device is on silent.",
                    vi: "Âm thanh nhẹ kiểu pop khi chạm nút & chuyển tab. Tự động tắt khi thiết bị bật chế độ im lặng.",
                    zh: "点击按钮和切换标签时的轻柔提示音，设备静音时自动关闭。"
                ))
            }
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "General", vi: "Cài đặt chung", zh: "通用"))
        .onDisappear {
            store.reconcileMemberIdentities(settings: settings, notifyCloud: true)
        }
        .sheet(item: $pendingCurrencySwitch) { target in
            CurrencySwitchSheet(from: settings.currency, to: target)
        }
    }

    private func fxStatusText(lang: AppLanguage) -> String {
        if let err = fxService.lastError, !err.isEmpty {
            return L10n.text(lang, en: "Offline fallback · refresh failed", vi: "Tỷ giá ngoại tuyến · cập nhật lỗi", zh: "离线估算汇率 · 刷新失败")
        }
        if fxService.table.isLive {
            let dateLabel = fxService.table.rateDate.map { DateKey.formatCompactDay($0, language: lang) } ?? L10n.today(lang)
            return L10n.text(lang, en: "Live · \(dateLabel)", vi: "Trực tuyến · \(dateLabel)", zh: "实时汇率 · \(dateLabel)")
        }
        return L10n.text(lang, en: "Built-in offline estimates", vi: "Tỷ giá ước tính ngoại tuyến", zh: "内置离线估算汇率")
    }
}
