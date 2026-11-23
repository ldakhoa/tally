import AppServices
import DesignSystem
import SwiftUI
import TallyCore
import ThemeTokens

struct GeneralSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            Section {
                Picker(L10n.text(lang, en: "Language", vi: "Ngôn ngữ"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.title(in: lang)).tag(option)
                    }
                }

                Picker(L10n.text(lang, en: "Currency", vi: "Đơn vị tiền tệ"), selection: $settings.currency) {
                    ForEach(CurrencyCode.allCases) { code in
                        Text("\(code.rawValue) · \(code.name(in: lang))").tag(code)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Language & Currency", vi: "Ngôn ngữ & Tiền tệ"))
            }

            Section {
                TextField(
                    L10n.text(lang, en: "Your name (e.g. Khoa)", vi: "Tên của bạn (VD: Khoa)"),
                    text: $settings.myDisplayName
                )
                TextField(
                    L10n.text(lang, en: "Partner's name (e.g. Wife)", vi: "Tên vợ / chồng (VD: Vợ)"),
                    text: $settings.partnerDisplayName
                )
            } header: {
                formSectionHeader(L10n.text(lang, en: "Household profile", vi: "Hồ sơ gia đình"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Each transaction logged on this iPhone is tagged with your name so you and your partner can filter spending.",
                    vi: "Mỗi giao dịch ghi trên iPhone này sẽ tự động gắn tên bạn để hai vợ chồng dễ lọc và xem chi tiêu."
                ))
            }

            Section {
                Picker(L10n.text(lang, en: "Appearance", vi: "Chế độ sáng/tối"), selection: $settings.appearance) {
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
                                Image(systemName: "checkmark")
                                    .font(.appControl)
                                    .foregroundStyle(Color.accent)
                            }
                        }
                    }
                    .buttonStyle(.themedPlain)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Theme (Onsite Style)", vi: "Chủ đề giao diện"))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "General", vi: "Cài đặt chung"))
    }
}
