import AppServices
import DesignSystem
import SwiftUI
import TallyCore

struct CurrencyPickerSheet: View {
    let selectedCode: String
    let householdCurrency: CurrencyCode
    let fxTable: ExchangeRateTable
    let language: AppLanguage
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var popularCodes: [String] {
        CurrencyCode.allCases
            .map(\.rawValue)
            .filter { $0 != householdCurrency.rawValue }
    }

    private var otherCodes: [String] {
        let popular = Set(popularCodes).union([householdCurrency.rawValue])
        return fxTable.availableCurrencyCodes.filter { !popular.contains($0) }
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(_ code: String) -> Bool {
        guard !query.isEmpty else { return true }
        let name = CurrencyCode.displayName(forCode: code, language: language)
        let symbol = CurrencyCode.displaySymbol(forCode: code)
        return code.localizedCaseInsensitiveContains(query)
            || name.localizedCaseInsensitiveContains(query)
            || symbol.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                List {
                    if matches(householdCurrency.rawValue) {
                        Section {
                            currencyRow(householdCurrency.rawValue)
                        } header: {
                            Text(L10n.text(language, en: "Household currency", vi: "Tiền tệ mặc định", zh: "家庭默认货币"))
                        }
                    }

                    let matchedPopular = popularCodes.filter(matches)
                    if !matchedPopular.isEmpty {
                        Section {
                            ForEach(matchedPopular, id: \.self) { code in
                                currencyRow(code)
                            }
                        } header: {
                            Text(L10n.text(language, en: "Popular", vi: "Phổ biến", zh: "常用货币"))
                        }
                    }

                    let matchedOthers = otherCodes.filter(matches)
                    if !matchedOthers.isEmpty {
                        Section {
                            ForEach(matchedOthers, id: \.self) { code in
                                currencyRow(code)
                            }
                        } header: {
                            Text(L10n.text(language, en: "All currencies", vi: "Tất cả tiền tệ", zh: "全部货币"))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            }
            .pageBackground()
            .cozySheetToolbar(title: L10n.text(language, en: "Currency", vi: "Chọn tiền tệ", zh: "选择货币")) {
                Button(L10n.text(language, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .cozySheetFrame(minWidth: 400, idealWidth: 440, minHeight: 500, idealHeight: 580)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            CozyUIIcon(.search, size: 15, color: Color.textSecondary)
            TextField(
                L10n.text(language, en: "Search HKD, Yen, Euro…", vi: "Tìm HKD, Yên, Đô la…", zh: "搜索 HKD、日元、欧元…"),
                text: $searchText
            )
            .font(.appSecondary)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    CozyUIIcon(.xmarkCircle, size: 16, color: Color.textSecondary)
                }
                .buttonStyle(.themedPlain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
    }

    private func currencyRow(_ code: String) -> some View {
        let isSelected = code == selectedCode
        let symbol = CurrencyCode.displaySymbol(forCode: code).trimmingCharacters(in: .whitespaces)
        let name = CurrencyCode.displayName(forCode: code, language: language)
        let rateInfo: String? = {
            guard code != householdCurrency.rawValue,
                  let info = fxTable.conversionRate(from: code, to: householdCurrency.rawValue)
            else { return nil }
            return ExchangeRateTable.formatRate(info.rate, from: code, to: householdCurrency)
        }()

        return Button {
            onSelect(code)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(symbol)
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                    .frame(minWidth: 42, minHeight: 32)
                    .padding(.horizontal, 6)
                    .background(isSelected ? Color.ink : Color.softFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(code)
                            .font(.appBodyMedium)
                            .foregroundStyle(Color.textPrimary)
                        Text("· \(name)")
                            .font(.appSecondary)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    if let rateInfo {
                        Text(rateInfo)
                            .font(.appCaption)
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    CozyUIIcon(.checkmark, size: 16, color: Color.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
    }
}
