import AppServices
import DesignSystem
import SwiftUI
import TallyCore
import ThemeTokens

struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            Section {
                Picker(L10n.text(lang, en: "Language", vi: "Ngôn ngữ", zh: "语言"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title(in: lang)).tag(option)
                    }
                }

                Picker(L10n.text(lang, en: "Currency", vi: "Đơn vị tiền tệ", zh: "货币"), selection: $settings.currency) {
                    ForEach(CurrencyCode.allCases) { code in
                        Text("\(code.rawValue) · \(code.name(in: lang))").tag(code)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Language & Currency", vi: "Ngôn ngữ & Tiền tệ", zh: "语言与货币"))
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
                    en: "Each transaction logged on this iPhone is tagged with your name so you and your partner can filter spending.",
                    vi: "Mỗi giao dịch ghi trên iPhone này sẽ tự động gắn tên bạn để hai vợ chồng dễ lọc và xem chi tiêu.",
                    zh: "在这台 iPhone 上记录的每笔账单都会自动标记您的名字，方便两人筛选和查看支出。"
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
                    en: "Subtle pop & chime sounds when tapping tabs and buttons. Automatically muted when iPhone is on silent.",
                    vi: "Âm thanh nhẹ kiểu pop khi chạm nút & chuyển tab. Tự động tắt khi iPhone bật chế độ im lặng.",
                    zh: "点击按钮和切换标签时的轻柔提示音，iPhone 静音时自动关闭。"
                ))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "General", vi: "Cài đặt chung", zh: "通用"))
        .onDisappear {
            store.reconcileMemberIdentities(settings: settings, notifyCloud: true)
        }
    }
}
