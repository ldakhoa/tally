import AppServices
import DesignSystem
import SwiftUI
import TallyCore

/// Presented when switching Household Currency while the ledger already has records, so the user
/// can choose between live display conversion on this device, full ledger migration (with iCloud
/// sync), or keeping existing numbers unchanged.
struct CurrencySwitchSheet: View {
    let from: CurrencyCode
    let to: CurrencyCode

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(ExchangeRateService.self) private var exchangeRates: ExchangeRateService?
    @Environment(\.dismiss) private var dismiss

    private var fxService: ExchangeRateService { exchangeRates ?? .shared }

    var body: some View {
        let lang = settings.language
        let table = fxService.table
        let rateInfo = table.conversionRate(from: from.rawValue, to: to.rawValue)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previewCard(table: table, rateInfo: rateInfo, lang: lang)

                    viewOnlyButton(lang: lang)

                    convertLedgerButton(canConvert: rateInfo != nil, lang: lang)

                    symbolOnlySection(lang: lang)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .pageBackground()
            .cozySheetToolbar(title: L10n.text(lang, en: "Change currency", vi: "Đổi đơn vị tiền tệ", zh: "更改货币")) {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 620)
        .task {
            await fxService.refreshIfStale()
        }
    }

    // MARK: - Subviews

    private func previewCard(
        table: ExchangeRateTable,
        rateInfo: (rate: Double, isLive: Bool, rateDate: String?)?,
        lang: AppLanguage
    ) -> some View {
        let sampleMajor: Double = from.isZeroDecimal ? 100_000 : 100
        let sampleSourceMinor = from.toStorageMinor(sampleMajor)
        let sampleConverted = table.convert(sampleMajor, from: from.rawValue, to: to)

        return Card {
            HStack(spacing: 10) {
                currencyChip(from)
                CozyUIIcon(.arrowRight, size: 14, color: Color.textSecondary)
                currencyChip(to)
                Spacer(minLength: 8)
                if fxService.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await fxService.refreshNow() }
                    } label: {
                        CozyUIIcon(.refresh, size: 15, color: Color.accent)
                    }
                    .buttonStyle(.themedPlain)
                    .accessibilityLabel(L10n.text(lang, en: "Refresh exchange rates", vi: "Cập nhật tỷ giá", zh: "刷新汇率"))
                }
            }

            if let rateInfo {
                let rateText = ExchangeRateTable.formatRate(rateInfo.rate, from: from.rawValue, to: to)
                let statusText: String = {
                    if rateInfo.isLive {
                        let dateLabel = rateInfo.rateDate.map { DateKey.formatCompactDay($0, language: lang) } ?? L10n.today(lang)
                        return L10n.text(lang, en: "Live · \(dateLabel)", vi: "Trực tuyến · \(dateLabel)", zh: "实时 · \(dateLabel)")
                    }
                    return L10n.text(lang, en: "Offline estimate", vi: "Ước tính ngoại tuyến", zh: "离线估算")
                }()
                Text("\(rateText) · \(statusText)")
                    .font(.appCaption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(rateInfo.isLive ? Color.positive : Color.caution)
            }

            if let sampleConverted {
                HStack(spacing: 6) {
                    Text(MoneyFormat.format(minor: sampleSourceMinor, currency: from, language: lang))
                        .foregroundStyle(Color.textSecondary)
                    Text("→")
                        .foregroundStyle(Color.textSecondary)
                    Text(MoneyFormat.format(minor: sampleConverted.convertedMinor, currency: to, language: lang))
                        .foregroundStyle(Color.textPrimary)
                }
                .font(.appHeading)
                .monospacedDigit()
            }

            if let summary = recordSummaryText(lang: lang) {
                Text(summary)
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func currencyChip(_ code: CurrencyCode) -> some View {
        HStack(spacing: 5) {
            Text(code.narrowSymbol.trimmingCharacters(in: .whitespaces))
                .foregroundStyle(Color.textSecondary)
            Text(code.rawValue)
                .foregroundStyle(Color.textPrimary)
        }
        .font(.appControl)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.softFill, in: Capsule())
    }

    private func viewOnlyButton(lang: AppLanguage) -> some View {
        Button {
            settings.displayCurrency = to
            CozyHaptics.success()
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                CozyUIIcon(.eye, size: 19, color: Color.info)
                    .frame(width: 38, height: 38)
                    .background(Color.info.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(
                        lang,
                        en: "View in \(to.rawValue) only",
                        vi: "Chỉ hiển thị bằng \(to.rawValue)",
                        zh: "仅以 \(to.rawValue) 显示"
                    ))
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)

                    Text(L10n.text(
                        lang,
                        en: "Converts every amount live on this device without changing stored \(from.rawValue) records or affecting your partner's device.",
                        vi: "Quy đổi trực tiếp mọi số tiền trên máy này, giữ nguyên dữ liệu gốc \(from.rawValue) và không ảnh hưởng máy người thân.",
                        zh: "在本设备实时换算显示，不更改已存的 \(from.rawValue) 记录，也不影响伴侣设备。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                CozyUIIcon(.chevronRight, size: 13, color: Color.textSecondary.opacity(0.6))
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.cozyCard)
    }

    private func convertLedgerButton(canConvert: Bool, lang: AppLanguage) -> some View {
        Button {
            let converted = store.convertCurrency(
                from: from,
                to: to,
                rates: fxService.table,
                settings: settings
            )
            if converted {
                CozyHaptics.success()
                dismiss()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                CozyUIIcon(.refresh, size: 19, color: Color.accent)
                    .frame(width: 38, height: 38)
                    .background(Color.accent.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(
                        lang,
                        en: "Convert all data to \(to.rawValue)",
                        vi: "Quy đổi toàn bộ dữ liệu sang \(to.rawValue)",
                        zh: "将全部数据换算为 \(to.rawValue)"
                    ))
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)

                    Text(L10n.text(
                        lang,
                        en: "Converts all transactions, budgets, goals, and plans at this rate, preserves original transaction amounts, and syncs across iCloud.",
                        vi: "Quy đổi toàn bộ giao dịch, ngân sách, mục tiêu và kế hoạch theo tỷ giá này, giữ lại số tiền gốc và đồng bộ qua iCloud.",
                        zh: "按此汇率转换所有账单、预算、目标和分期，保留原始金额并同步到 iCloud。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)
                CozyUIIcon(.chevronRight, size: 13, color: Color.accent.opacity(0.8))
                    .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(highlighted: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cozyCard)
        .disabled(!canConvert)
        .opacity(canConvert ? 1 : 0.5)
    }

    private func symbolOnlySection(lang: AppLanguage) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Button {
                settings.setHouseholdCurrency(to)
                CozyHaptics.selection()
                dismiss()
            } label: {
                Text(L10n.text(
                    lang,
                    en: "Change symbol only (keep numbers)",
                    vi: "Chỉ đổi ký hiệu tiền tệ (giữ nguyên số)",
                    zh: "仅更换货币符号（保留数值）"
                ))
                .font(.appControl)
            }
            .buttonStyle(.themedPlain)
            .foregroundStyle(Color.textSecondary)
            .padding(.top, 4)

            Text(L10n.text(
                lang,
                en: "Use this only if existing numbers were already typed in \(to.rawValue) by mistake.",
                vi: "Chỉ dùng khi các con số hiện tại vốn đã được nhập bằng \(to.rawValue).",
                zh: "仅当现有数字原本就是以 \(to.rawValue) 录入时使用。"
            ))
            .font(.appCaption)
            .foregroundStyle(Color.textSecondary.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func recordSummaryText(lang: AppLanguage) -> String? {
        let txCount = store.activeTransactions.count
        let bdCount = store.activeBudgets.count
        let glCount = store.activeGoals.count
        let plCount = store.activePlans.count
        var parts: [String] = []
        if txCount > 0 {
            parts.append(L10n.text(lang, en: "\(txCount) transactions", vi: "\(txCount) giao dịch", zh: "\(txCount) 笔账单"))
        }
        if bdCount > 0 {
            parts.append(L10n.text(lang, en: "\(bdCount) budgets", vi: "\(bdCount) ngân sách", zh: "\(bdCount) 个预算"))
        }
        if glCount > 0 {
            parts.append(L10n.text(lang, en: "\(glCount) goals", vi: "\(glCount) mục tiêu", zh: "\(glCount) 个目标"))
        }
        if plCount > 0 {
            parts.append(L10n.text(lang, en: "\(plCount) plans", vi: "\(plCount) kế hoạch", zh: "\(plCount) 个计划"))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}
