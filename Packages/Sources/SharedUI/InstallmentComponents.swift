import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

// MARK: - Shared installment building blocks (used by the convert sheet here and the plan editor in GoalsUI)

public enum InstallmentPresets {
    public static let months = [3, 6, 12, 24, 36]
    public static let maxMonths = InstallmentPlanRecord.maxMonths

    /// Parses the free-text months field; `nil` when empty or not a number.
    public static func parseMonths(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces))
    }

    /// "S$42.92 / month × 12" preview line shared by the convert sheet and the plan editor.
    public static func monthlyPreview(
        totalMinor: Int64,
        months: Int,
        regularMinor: Int64? = nil,
        currency: CurrencyCode,
        language: AppLanguage
    ) -> String? {
        let amounts = InstallmentPlanRecord.paymentAmounts(
            totalMinor: totalMinor,
            months: months,
            regularMinor: regularMinor,
            step: InstallmentPlanRecord.roundingStep(for: currency)
        )
        guard let regular = amounts.first else { return nil }
        let money = MoneyFormat.format(minor: regular, currency: currency, language: language)
        return L10n.text(
            language,
            en: "\(money) / month × \(months)",
            vi: "\(money) / tháng × \(months)",
            zh: "每月 \(money) × \(months) 期"
        )
    }

    /// The last payment differs from the regular one when the total does not divide evenly.
    public static func lastPaymentNote(
        totalMinor: Int64,
        months: Int,
        regularMinor: Int64? = nil,
        currency: CurrencyCode,
        language: AppLanguage
    ) -> String? {
        let amounts = InstallmentPlanRecord.paymentAmounts(
            totalMinor: totalMinor,
            months: months,
            regularMinor: regularMinor,
            step: InstallmentPlanRecord.roundingStep(for: currency)
        )
        guard let first = amounts.first, let last = amounts.last, first != last else { return nil }
        let money = MoneyFormat.format(minor: last, currency: currency, language: language)
        return L10n.text(
            language,
            en: "Last payment \(money)",
            vi: "Kỳ cuối \(money)",
            zh: "最后一期 \(money)"
        )
    }
}

/// Quick month chips (3 / 6 / 12 / 24 / 36) plus a free-text custom field.
public struct InstallmentMonthsField: View {
    @Binding public var monthsText: String
    /// Mirrors whether the custom field has keyboard focus so the host can hide its keypad.
    @Binding public var isEditing: Bool
    public let language: AppLanguage

    @FocusState private var focused: Bool

    public init(monthsText: Binding<String>, isEditing: Binding<Bool>, language: AppLanguage) {
        self._monthsText = monthsText
        self._isEditing = isEditing
        self.language = language
    }

    public var body: some View {
        let current = InstallmentPresets.parseMonths(monthsText)
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InstallmentPresets.months, id: \.self) { value in
                        let selected = current == value
                        Button {
                            CozyHaptics.selection()
                            focused = false
                            withAnimation(.snappy(duration: 0.16)) { monthsText = String(value) }
                        } label: {
                            Text(L10n.text(language, en: "\(value) mo", vi: "\(value) tháng", zh: "\(value) 期"))
                                .font(.appControl)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                .background(selected ? Color.ink : Color.cardBackground, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.hairlineStrong, lineWidth: 1))
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(L10n.text(language, en: "\(value) months", vi: "\(value) tháng", zh: "\(value) 个月"))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                TextField(L10n.text(language, en: "Custom number of months", vi: "Số tháng khác", zh: "自定义期数"), text: $monthsText)
                    .focused($focused)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    .tallyField()
                    .accessibilityLabel(L10n.text(language, en: "Number of months", vi: "Số tháng", zh: "期数"))
                Text(L10n.text(language, en: "months", vi: "tháng", zh: "个月"))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .onChange(of: monthsText) { _, newValue in
            let digits = newValue.filter(\.isNumber)
            if digits != newValue { monthsText = String(digits.prefix(3)) }
            else if digits.count > 3 { monthsText = String(digits.prefix(3)) }
        }
        .onChange(of: focused) { _, newValue in
            if isEditing != newValue { isEditing = newValue }
        }
        .onChange(of: isEditing) { _, newValue in
            if !newValue && focused { focused = false }
        }
    }
}

/// Single-day picker sheet (HorizonCalendar) used for first-payment and payoff dates.
public struct InstallmentDatePickerSheet: View {
    @Binding public var dayKey: String
    public let title: String

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public init(dayKey: Binding<String>, title: String) {
        self._dayKey = dayKey
        self.title = title
    }

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            HorizonSingleDateCalendarView(
                selectedDayKey: $dayKey,
                language: lang,
                currency: settings.effectiveDisplayCurrency,
                dailyTotals: settings.displayDailyTotals(store.dailyCalendarTotals)
            ) { _ in
                dismiss()
            }
            .pageBackground()
            .cozySheetToolbar(title: title) {
                Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 420, idealWidth: 440, minHeight: 520, idealHeight: 580)
    }
}

/// Cream capsule button showing a calendar glyph and a formatted day, used for date fields.
public struct InstallmentDatePill: View {
    public let dayKey: String
    public let language: AppLanguage
    public let action: () -> Void

    public init(dayKey: String, language: AppLanguage, action: @escaping () -> Void) {
        self.dayKey = dayKey
        self.language = language
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                CozyUIIcon(.calendar, size: 14, color: Color.textSecondary)
                Text(DateKey.formatFullDay(dayKey, language: language))
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Color.cardBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.themedPlain)
        .accessibilityLabel(L10n.text(language, en: "Date: \(DateKey.formatAbsoluteDay(dayKey, language: language))", vi: "Ngày: \(DateKey.formatAbsoluteDay(dayKey, language: language))", zh: "日期：\(DateKey.formatAbsoluteDay(dayKey, language: language))"))
    }
}

// MARK: - Convert an existing expense into an installment plan

public struct ConvertToInstallmentSheet: View {
    public let transaction: TransactionRecord
    public var onConverted: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var monthsText = "12"
    @State private var monthsEditing = false
    @State private var firstDayKey: String
    @State private var showingDatePicker = false
    @State private var errorMessage: String?

    public init(transaction: TransactionRecord, onConverted: @escaping () -> Void = {}) {
        self.transaction = transaction
        self.onConverted = onConverted
        self._firstDayKey = State(initialValue: transaction.dayKey)
    }

    public var body: some View {
        let lang = settings.language
        let currency = settings.currency
        let months = InstallmentPresets.parseMonths(monthsText) ?? 0
        let monthsValid = months >= 1 && months <= InstallmentPresets.maxMonths

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CategoryBadge(category: transaction.category, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(transaction.name).font(.appHeading).lineLimit(2)
                            Text(MoneyFormat.format(minor: transaction.amountMinor, currency: currency, language: lang))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .cardSurface(cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(L10n.text(lang, en: "Number of months", vi: "Số tháng trả góp", zh: "分期期数"))
                        InstallmentMonthsField(monthsText: $monthsText, isEditing: $monthsEditing, language: lang)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(L10n.text(lang, en: "First payment", vi: "Kỳ trả đầu tiên", zh: "首期还款日"))
                        HStack {
                            InstallmentDatePill(dayKey: firstDayKey, language: lang) {
                                monthsEditing = false
                                showingDatePicker = true
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    if monthsValid,
                       let line = InstallmentPresets.monthlyPreview(totalMinor: transaction.amountMinor, months: months, currency: currency, language: lang) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line)
                                .font(.appHeading)
                                .monospacedDigit()
                            if let note = InstallmentPresets.lastPaymentNote(totalMinor: transaction.amountMinor, months: months, currency: currency, language: lang) {
                                Text(note).font(.appCaption).foregroundStyle(Color.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .cardSurface(cornerRadius: 18)
                    }

                    Text(L10n.text(
                        lang,
                        en: "The full amount is replaced by monthly payments, booked automatically as each one falls due.",
                        vi: "Khoản chi đầy đủ sẽ được thay bằng các kỳ trả hàng tháng, tự ghi nhận khi đến hạn.",
                        zh: "整笔金额将由每月还款取代，到期时自动入账。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)

                    if !monthsValid {
                        Text(L10n.text(
                            lang,
                            en: "Pick how many monthly payments (1 to \(InstallmentPresets.maxMonths)).",
                            vi: "Chọn số kỳ trả hàng tháng (từ 1 đến \(InstallmentPresets.maxMonths)).",
                            zh: "请选择每月还款的期数（1 到 \(InstallmentPresets.maxMonths)）。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.caution)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                    }

                    Button(L10n.text(lang, en: "Convert to installment", vi: "Chuyển thành trả góp", zh: "转为分期"), action: convert)
                        .blockButton(prominent: true)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .pageBackground()
            .cozySheetToolbar(title: L10n.text(lang, en: "Convert to installment", vi: "Chuyển thành trả góp", zh: "转为分期")) {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            }
            .sheet(isPresented: $showingDatePicker) {
                InstallmentDatePickerSheet(
                    dayKey: $firstDayKey,
                    title: L10n.text(lang, en: "First payment date", vi: "Ngày trả đầu tiên", zh: "首期还款日")
                )
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 620)
    }

    private func convert() {
        let lang = settings.language
        guard let months = InstallmentPresets.parseMonths(monthsText),
              months >= 1, months <= InstallmentPresets.maxMonths
        else {
            errorMessage = L10n.text(lang, en: "Enter a number of months first.", vi: "Hãy nhập số tháng trước.", zh: "请先输入期数。")
            return
        }
        let step = InstallmentPlanRecord.roundingStep(for: settings.currency)
        if InstallmentPlanRecord.paymentAmounts(totalMinor: transaction.amountMinor, months: months, step: step).isEmpty {
            let minimum = MoneyFormat.format(minor: step * Int64(months), currency: settings.currency, language: lang)
            errorMessage = L10n.text(
                lang,
                en: "This amount is too small to split into that many monthly payments. It needs at least \(minimum), or fewer months.",
                vi: "Số tiền quá nhỏ để chia thành ngần ấy kỳ. Cần ít nhất \(minimum) hoặc giảm số tháng.",
                zh: "金额太小，无法拆分为这么多期。至少需要 \(minimum)，或减少期数。"
            )
            return
        }
        let plan = store.convertTransactionToPlan(
            transactionID: transaction.id,
            months: months,
            firstPaymentDayKey: firstDayKey,
            currency: settings.currency
        )
        guard plan != nil else {
            errorMessage = L10n.text(
                lang,
                en: "This transaction can't be converted. It may already be part of a plan.",
                vi: "Không thể chuyển giao dịch này. Có thể nó đã thuộc một kế hoạch.",
                zh: "无法转换这笔账单，它可能已属于某个分期计划。"
            )
            return
        }
        CozyHaptics.success()
        dismiss()
        onConverted()
    }
}
