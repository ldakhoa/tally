import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

public struct TransactionEditorSheet: View {
    public let existing: TransactionRecord?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(ExchangeRateService.self) private var exchangeRates: ExchangeRateService?
    @Environment(\.dismiss) private var dismiss

    private var fxService: ExchangeRateService { exchangeRates ?? .shared }

    private enum EditorField: Hashable {
        case description
        case note
        case convertedAmount
    }

    @State private var name: String = ""
    @State private var keypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var entryCurrencyCode: String = ""
    @State private var showingCurrencyPicker = false
    @State private var customConvertedText: String = ""
    @State private var isEditingConvertedAmount = false
    @State private var preservedForeign: (currencyCode: String, originalMinor: Int64, convertedMinor: Int64, rate: Double?)?
    @State private var forceLiveRate = false
    @State private var type: TransactionType = .expense
    @State private var category: CategoryID = .food
    @State private var dayKey: String = DateKey.dayKey(from: Date())
    @State private var showingDatePicker = false
    @State private var note: String = ""
    @State private var showNoteField = false
    @State private var selectedMemberID: String = ""
    @State private var selectedMemberName: String = ""
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var showingConvertSheet = false

    @FocusState private var focusedField: EditorField?

    public init(existing: TransactionRecord? = nil) {
        self.existing = existing
    }

    public var body: some View {
        let lang = settings.language
        let liveAmount = resolvedAmountMajor
        let canSave = liveAmount > 0

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Hero amount stage (tap to focus in-app keypad)
                        amountHeroStage(lang: lang)

                        // 2. Description input + quick suggestion chips (Coffee, Groceries, ...)
                        descriptionSection(lang: lang)

                        // 3. Horizontal category selector strip
                        categoryStrip(lang: lang)

                        // 4. Compact metadata pills (Date, Member, Note)
                        metadataStrip(lang: lang)

                        if showNoteField || !note.isEmpty {
                            noteInputCard(lang: lang)
                        }

                        installmentSection(lang: lang)

                        if let raw = existing?.rawSourceText, !raw.isEmpty {
                            Card(L10n.text(lang, en: "Original alert text", vi: "Nội dung thông báo gốc", zh: "原始通知内容"), symbol: "text.quote") {
                                Text(raw)
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.appSecondary)
                                .foregroundStyle(Color.negative)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }
                .scrollDismissesKeyboard(.interactively)

                // 5. Docked in-app calculator keypad (or compact Save bar while system keyboard is up)
                if focusedField == nil {
                    AmountKeypadView(
                        engine: $keypad,
                        currencyCode: activeCurrencyCode,
                        language: lang,
                        saveTitle: saveButtonTitle(amountMajor: liveAmount, lang: lang),
                        isSaveEnabled: canSave,
                        onSave: save
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    compactKeyboardSaveBar(amountMajor: liveAmount, canSave: canSave, lang: lang)
                }
            }
            .animation(.snappy(duration: 0.22), value: focusedField == nil)
            .pageBackground()
            .keypadKeyboardInput(engine: $keypad, isEnabled: focusedField == nil, isSaveEnabled: canSave, onSave: save)
            .cozySheetToolbar {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            } principal: {
                typeSegmentedPill(lang: lang)
                    .fixedSize()
            } trailing: {
                if focusedField != nil {
                    Button(L10n.text(lang, en: "Keypad", vi: "Bàn phím số", zh: "数字键盘")) {
                        focusedField = nil
                    }
                    .font(.appControl)
                } else if existing != nil {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        CozyUIIcon(.trash, size: 18, color: Color.negative)
                    }
                    .accessibilityLabel(L10n.text(lang, en: "Delete transaction", vi: "Xoá giao dịch", zh: "删除账单"))
                }
            }
            .confirmationDialog(
                L10n.text(lang, en: "Delete this transaction?", vi: "Xoá giao dịch này?", zh: "删除这笔账单？"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.text(lang, en: "Delete", vi: "Xoá", zh: "删除"), role: .destructive) {
                    if let id = existing?.id { store.deleteTransaction(id: id) }
                    dismiss()
                }
            }
            .onAppear(perform: populate)
            .sheet(isPresented: $showingConvertSheet) {
                if let existing {
                    ConvertToInstallmentSheet(transaction: existing) {
                        // The original expense is replaced by the plan's payments: close the editor.
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingCurrencyPicker) {
                CurrencyPickerSheet(
                    selectedCode: activeCurrencyCode,
                    householdCurrency: settings.currency,
                    fxTable: fxService.table,
                    language: lang
                ) { chosenCode in
                    selectCurrency(chosenCode)
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                NavigationStack {
                    HorizonSingleDateCalendarView(
                        selectedDayKey: $dayKey,
                        language: lang,
                        currency: settings.currency,
                        dailyTotals: store.dailyCalendarTotals
                    ) { _ in
                        showingDatePicker = false
                    }
                    .pageBackground()
                    .cozySheetToolbar(title: L10n.text(lang, en: "Select date", vi: "Chọn ngày", zh: "选择日期")) {
                        Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                            showingDatePicker = false
                        }
                    }
                }
                .presentationDetents([.large])
                .cozySheetFrame(minWidth: 420, idealWidth: 440, minHeight: 520, idealHeight: 580)
            }
        }
        .cozySheetFrame(minWidth: 460, idealWidth: 480, minHeight: 600, idealHeight: 660)
    }

    // MARK: - Top Type Switcher

    private func typeSegmentedPill(lang: AppLanguage) -> some View {
        HStack(spacing: 2) {
            ForEach(TransactionType.allCases) { option in
                let selected = type == option
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        type = option
                        if !option.categories.contains(category) {
                            category = option.categories.first ?? .other
                        }
                    }
                } label: {
                    Text(option.title(in: lang))
                        .font(.appCaption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? Color.onInk : Color.textSecondary)
                        .background(selected ? Color.ink : Color.clear, in: Capsule())
                }
                .buttonStyle(.themedPlain)
            }
        }
        .padding(3)
        .background(Color.softFill, in: Capsule())
    }

    // MARK: - Hero Amount Stage

    private func amountHeroStage(lang: AppLanguage) -> some View {
        let code = activeCurrencyCode
        let displayNumber = keypad.formattedDisplayNumber(currencyCode: code)
        let isEmpty = keypad.isEmpty
        let amountColor: Color = isEmpty
            ? Color.textSecondary.opacity(0.38)
            : (type == .income ? Color.positive : Color.textPrimary)
        let isVND = code == CurrencyCode.vnd.rawValue
        let rawSymbol = CurrencyCode.displaySymbol(forCode: code).trimmingCharacters(in: .whitespaces)
        let symbolNeedsSpace = rawSymbol == code || code == "CHF"

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                if keypad.hasOperator {
                    HStack(spacing: 6) {
                        Text(keypad.formattedExpression)
                            .font(.appCaption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                        Text("=")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.softFill, in: Capsule())
                } else {
                    Text(
                        type == .income
                            ? L10n.text(lang, en: "Income amount", vi: "Số tiền thu", zh: "收入金额")
                            : L10n.text(lang, en: "Expense amount", vi: "Số tiền chi", zh: "支出金额")
                    )
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }

                Button {
                    focusedField = nil
                    showingCurrencyPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(code)
                            .font(.appCaption.weight(.semibold))
                        CozyUIIcon(.chevronDown, size: 10, color: isForeignEntry ? Color.onInk.opacity(0.85) : Color.textSecondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(isForeignEntry ? Color.onInk : Color.textPrimary)
                    .background(isForeignEntry ? Color.ink : Color.softFill, in: Capsule())
                }
                .buttonStyle(.themedPlain)
                .accessibilityLabel(L10n.text(lang, en: "Change currency (\(code))", vi: "Đổi tiền tệ (\(code))", zh: "切换货币（\(code)）"))
            }

            Button {
                focusedField = nil
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !isVND {
                        let prefix = (type == .income && !isEmpty ? "+" : "") + rawSymbol + (symbolNeedsSpace ? " " : "")
                        Text(prefix)
                            .font(.custom("AvenirNext-Medium", size: rawSymbol.count > 2 ? 22 : 26))
                            .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                    } else if type == .income && !isEmpty {
                        Text("+")
                            .font(.custom("AvenirNext-Medium", size: 28))
                            .foregroundStyle(Color.positive.opacity(0.8))
                    }

                    Text(displayNumber)
                        .font(.custom("AvenirNext-DemiBold", size: 44).monospacedDigit())
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .contentTransition(.numericText())

                    if isVND {
                        Text("₫")
                            .font(.custom("AvenirNext-Medium", size: 26))
                            .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isForeignEntry {
                foreignConversionStrip(lang: lang)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func foreignConversionStrip(lang: AppLanguage) -> some View {
        let preview = conversionPreview
        let household = settings.currency
        let prefix = (preview.source == .custom || preview.source == .preservedHistorical) ? "=" : "≈"
        let convertedText = MoneyFormat.format(minor: preview.minor, currency: household, language: lang)
        let rateLabel: String = {
            switch preview.source {
            case .domestic:
                return ""
            case .custom:
                let ratePart = preview.rate.map { "\(ExchangeRateTable.formatRate($0, from: activeCurrencyCode, to: household)) · " } ?? ""
                return ratePart + L10n.text(lang, en: "Custom", vi: "Tự nhập", zh: "自定义")
            case .preservedHistorical:
                let ratePart = preview.rate.map { "\(ExchangeRateTable.formatRate($0, from: activeCurrencyCode, to: household)) · " } ?? ""
                return ratePart + L10n.text(lang, en: "Saved rate", vi: "Tỷ giá đã lưu", zh: "已保存汇率")
            case .live:
                let ratePart = preview.rate.map { "\(ExchangeRateTable.formatRate($0, from: activeCurrencyCode, to: household)) · " } ?? ""
                return ratePart + L10n.text(lang, en: "Live", vi: "Tỷ giá thực", zh: "实时汇率")
            case .estimated:
                let ratePart = preview.rate.map { "\(ExchangeRateTable.formatRate($0, from: activeCurrencyCode, to: household)) · " } ?? ""
                return ratePart + L10n.text(lang, en: "Est.", vi: "Ước tính", zh: "估算")
            case .unavailable:
                return L10n.text(lang, en: "Rate unavailable — enter \(household.rawValue)", vi: "Chưa có tỷ giá — nhập \(household.rawValue)", zh: "暂无汇率 — 请手动输入 \(household.rawValue)")
            }
        }()

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if resolvedAmountMajor > 0 {
                    Text("\(prefix) \(convertedText)")
                        .font(.appCaption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(preview.source == .unavailable ? Color.negative : Color.textPrimary)
                }

                if !rateLabel.isEmpty {
                    Text(rateLabel)
                        .font(.appCaption)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        isEditingConvertedAmount.toggle()
                        if isEditingConvertedAmount {
                            if customConvertedText.isEmpty && preview.minor > 0 {
                                let major = household.toMajor(preview.minor)
                                customConvertedText = household.isZeroDecimal
                                    ? "\(Int64(major.rounded()))"
                                    : String(format: "%.2f", major)
                            }
                            focusedField = .convertedAmount
                        } else if focusedField == .convertedAmount {
                            focusedField = nil
                        }
                    }
                } label: {
                    CozyUIIcon(.pencil, size: 12, color: Color.textSecondary)
                        .padding(4)
                }
                .buttonStyle(.themedPlain)
                .accessibilityLabel(L10n.text(lang, en: "Edit billed amount in \(household.rawValue)", vi: "Sửa số tiền thực trừ (\(household.rawValue))", zh: "修改 \(household.rawValue) 入账金额"))

                if preview.source == .custom || preview.source == .preservedHistorical {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            customConvertedText = ""
                            isEditingConvertedAmount = false
                            forceLiveRate = true
                            if focusedField == .convertedAmount { focusedField = nil }
                        }
                        Task { await fxService.refreshIfStale() }
                    } label: {
                        CozyUIIcon(.refresh, size: 12, color: Color.accent)
                            .padding(4)
                    }
                    .buttonStyle(.themedPlain)
                    .accessibilityLabel(L10n.text(lang, en: "Use live exchange rate", vi: "Dùng tỷ giá thực", zh: "使用实时汇率"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.softFill, in: Capsule())

            if isEditingConvertedAmount {
                HStack(spacing: 8) {
                    Text(L10n.text(lang, en: "Billed in \(household.rawValue)", vi: "Thực trừ (\(household.rawValue))", zh: "实际入账 (\(household.rawValue))"))
                        .font(.appCaption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)

                    TextField(household.isZeroDecimal ? "0" : "0.00", text: $customConvertedText)
                        .font(.appBodyMedium.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .convertedAmount)
                        #if os(iOS)
                        .keyboardType(household.isZeroDecimal ? .numberPad : .decimalPad)
                        #endif
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }

                    Button(L10n.text(lang, en: "Auto", vi: "Tự động", zh: "自动")) {
                        withAnimation(.snappy(duration: 0.16)) {
                            customConvertedText = ""
                            isEditingConvertedAmount = false
                            forceLiveRate = true
                            if focusedField == .convertedAmount { focusedField = nil }
                        }
                    }
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .buttonStyle(.themedPlain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Description Input + Quick Chips

    private func descriptionSection(lang: AppLanguage) -> some View {
        let placeholder = type == .income
            ? L10n.text(lang, en: "Salary, PayNow, refund…", vi: "Lương, chuyển khoản, hoàn tiền…", zh: "工资、转账、退款…")
            : L10n.text(lang, en: "Coffee, groceries, lunch…", vi: "Cà phê, đi chợ, ăn trưa…", zh: "咖啡、买菜、午餐…")

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CategoryBadge(category: category, size: 32)

                TextField(placeholder, text: $name)
                    .font(.appBodyMedium)
                    .focused($focusedField, equals: .description)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                if !name.isEmpty {
                    Button {
                        name = ""
                    } label: {
                        CozyUIIcon(.xmarkCircle, size: 17, color: Color.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.themedPlain)
                    .accessibilityLabel(L10n.text(lang, en: "Clear description", vi: "Xoá mô tả", zh: "清空描述"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .cardSurface(cornerRadius: 16)

            // Quick tap-to-fill description chips (Coffee, Groceries, Lunch, ...)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(quickSuggestions(lang: lang), id: \.self) { suggestion in
                        let isSelected = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            .caseInsensitiveCompare(suggestion) == .orderedSame
                        Button {
                            withAnimation(.snappy(duration: 0.16)) {
                                name = suggestion
                                focusedField = nil
                            }
                        } label: {
                            Text(suggestion)
                                .font(.appCaption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 30)
                                .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                                .background(
                                    isSelected ? Color.ink : Color.softFill,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.themedPlain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Category Strip

    private func categoryStrip(lang: AppLanguage) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(type.categories) { item in
                        let selected = category == item
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                category = item
                            }
                        } label: {
                            HStack(spacing: 6) {
                                CozyCategoryIcon(
                                    category: item,
                                    size: 17,
                                    style: selected ? .tinted(Color.onInk) : .watercolor
                                )
                                Text(item.title(in: lang))
                                    .font(.appCaption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                            .background(
                                selected ? Color.ink : Color.cardBackground,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.themedPlain)
                        .id(item)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .onChange(of: category) { _, newCat in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(newCat, anchor: .center)
                }
            }
        }
    }

    // MARK: - Metadata Strip (Date · Who Paid · Note)

    private func metadataStrip(lang: AppLanguage) -> some View {
        let members = memberOptions
        let showMemberPicker = members.count > 1

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date pill
                Button {
                    focusedField = nil
                    showingDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.calendar, size: 14, color: Color.textSecondary)
                        Text(DateKey.formatFullDay(dayKey, language: lang))
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Color.cardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.themedPlain)

                // Household member menu pill
                if showMemberPicker {
                    Menu {
                        ForEach(members) { m in
                            Button {
                                selectedMemberID = m.id
                                selectedMemberName = m.name
                            } label: {
                                if m.id == selectedMemberID {
                                    Label(m.name, systemImage: "checkmark")
                                } else {
                                    Text(m.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            CozyUIIcon(.person, size: 14, color: Color.textSecondary)
                            Text(selectedMemberName.isEmpty ? settings.currentMember.name : selectedMemberName)
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            CozyUIIcon(.chevronUpDown, size: 12, color: Color.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Color.cardBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                    }
                    .cozyMenuPill()
                }

                // Note toggle pill
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        showNoteField.toggle()
                        if showNoteField {
                            focusedField = .note
                        } else if focusedField == .note {
                            focusedField = nil
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.note, size: 14, color: note.isEmpty ? Color.textSecondary : Color.accent)
                        Text(
                            note.isEmpty
                                ? L10n.text(lang, en: "Note", vi: "Ghi chú", zh: "备注")
                                : note
                        )
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    .background(Color.cardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.themedPlain)
            }
            .padding(.horizontal, 2)
        }
    }

    private func noteInputCard(lang: AppLanguage) -> some View {
        HStack(spacing: 8) {
            CozyUIIcon(.note, size: 15, color: Color.textSecondary)
            TextField(
                L10n.text(lang, en: "Card, split note, receipt details…", vi: "Thẻ, chia tiền, chi tiết hoá đơn…", zh: "银行卡、AA备注、小票详情…"),
                text: $note
            )
            .font(.appSecondary)
            .focused($focusedField, equals: .note)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
    }

    // MARK: - Installments

    /// "Convert to installment" for saved expenses that are not already plan payments; a short
    /// note for plan payments themselves.
    @ViewBuilder
    private func installmentSection(lang: AppLanguage) -> some View {
        if let existing, existing.type == .expense, type == .expense, !existing.isDeleted {
            if existing.isPlanPayment {
                HStack(alignment: .top, spacing: 8) {
                    CozyUIIcon(.creditCard, size: 15, color: Color.textSecondary)
                    Text(L10n.text(
                        lang,
                        en: "This is a payment of an installment or loan. Edit or settle the plan from Commitments.",
                        vi: "Đây là một kỳ trả góp hoặc khoản vay. Hãy sửa hoặc tất toán kế hoạch tại Khoản cam kết.",
                        zh: "这是分期或贷款的一期还款。请在“分期与贷款”中编辑或结清计划。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 4)
            } else {
                let looksLikeIPP = InstallmentHint.looksLikeInstallment(existing)
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        focusedField = nil
                        showingConvertSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            CozyUIIcon(.creditCard, size: 16, color: looksLikeIPP ? Color.onInk : Color.textPrimary)
                            Text(L10n.text(lang, en: "Convert to installment", vi: "Chuyển thành trả góp", zh: "转为分期"))
                        }
                    }
                    .pillButton(prominent: looksLikeIPP)

                    if looksLikeIPP {
                        Text(L10n.text(
                            lang,
                            en: "This looks like an installment purchase. Spread it over monthly payments?",
                            vi: "Giao dịch này có vẻ là mua trả góp. Chia thành các kỳ trả hàng tháng?",
                            zh: "这看起来是一笔分期消费，要拆分成每月还款吗？"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Compact Save Bar (shown while system keyboard is visible)

    private func compactKeyboardSaveBar(amountMajor: Double, canSave: Bool, lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            Button {
                focusedField = nil
            } label: {
                CozyUIIcon(.keypad, size: 19, color: Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.softFill, in: Circle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityLabel(L10n.text(lang, en: "Show number keypad", vi: "Mở bàn phím số", zh: "显示数字键盘"))

            Button(saveButtonTitle(amountMajor: amountMajor, lang: lang), action: save)
                .blockButton(prominent: true)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Color.appBackground
                .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Data & Helpers

    private enum ConversionSource: Equatable {
        case domestic
        case custom
        case preservedHistorical
        case live(String?)
        case estimated
        case unavailable
    }

    private struct ConversionPreview {
        let minor: Int64
        let rate: Double?
        let source: ConversionSource
    }

    private var activeCurrencyCode: String {
        entryCurrencyCode.isEmpty ? settings.currency.rawValue : entryCurrencyCode
    }

    private var isForeignEntry: Bool {
        activeCurrencyCode != settings.currency.rawValue
    }

    private var parsedCustomConvertedMajor: Double? {
        let trimmed = customConvertedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(trimmed), value > 0, value.isFinite else { return nil }
        return value
    }

    private var conversionPreview: ConversionPreview {
        let entered = resolvedAmountMajor
        let household = settings.currency
        guard isForeignEntry else {
            return ConversionPreview(minor: household.toStorageMinor(entered), rate: nil, source: .domestic)
        }
        if let customMajor = parsedCustomConvertedMajor, customMajor > 0 {
            let minor = max(1, household.toStorageMinor(customMajor))
            let rate = entered > 0 ? (customMajor / entered) : nil
            return ConversionPreview(
                minor: minor,
                rate: (rate?.isFinite == true && (rate ?? 0) > 0) ? rate : nil,
                source: .custom
            )
        }
        if let preserved = preservedForeign,
           !forceLiveRate,
           preserved.currencyCode == activeCurrencyCode,
           CurrencyCode.toStorageMinor(entered, currencyCode: activeCurrencyCode) == preserved.originalMinor {
            return ConversionPreview(minor: preserved.convertedMinor, rate: preserved.rate, source: .preservedHistorical)
        }
        if entered > 0 {
            if let conv = fxService.table.convert(entered, from: activeCurrencyCode, to: household) {
                return ConversionPreview(
                    minor: max(1, conv.convertedMinor),
                    rate: conv.rate,
                    source: conv.isLiveRate ? .live(conv.rateDate) : .estimated
                )
            }
            return ConversionPreview(
                minor: max(1, household.toStorageMinor(entered)),
                rate: nil,
                source: .unavailable
            )
        }
        if let info = fxService.table.conversionRate(from: activeCurrencyCode, to: household.rawValue) {
            return ConversionPreview(
                minor: 0,
                rate: info.rate,
                source: info.isLive ? .live(info.rateDate) : .estimated
            )
        }
        return ConversionPreview(minor: 0, rate: nil, source: .unavailable)
    }

    private var resolvedAmountMajor: Double {
        max(0, keypad.evaluatedValue ?? 0)
    }

    private func saveButtonTitle(amountMajor: Double, lang: AppLanguage) -> String {
        let isEditing = existing != nil
        guard amountMajor > 0 else {
            return isEditing
                ? L10n.text(lang, en: "Save changes", vi: "Lưu thay đổi", zh: "保存修改")
                : L10n.text(lang, en: "Save transaction", vi: "Lưu giao dịch", zh: "保存账单")
        }
        let targetMinor = isForeignEntry
            ? conversionPreview.minor
            : settings.currency.toStorageMinor(amountMajor)
        let formatted = MoneyFormat.format(
            minor: targetMinor,
            currency: settings.currency,
            language: lang
        )
        return isEditing
            ? L10n.text(lang, en: "Update · \(formatted)", vi: "Cập nhật · \(formatted)", zh: "更新 · \(formatted)")
            : L10n.text(lang, en: "Save · \(formatted)", vi: "Lưu · \(formatted)", zh: "保存 · \(formatted)")
    }

    private func selectCurrency(_ code: String) {
        let normalized = CurrencyCode.normalizeCode(code) ?? settings.currency.rawValue
        guard normalized != activeCurrencyCode else { return }
        entryCurrencyCode = normalized
        customConvertedText = ""
        isEditingConvertedAmount = false
        forceLiveRate = true
        let newDigits = CurrencyCode.fractionDigits(forCode: normalized)
        if keypad.maxFractionDigits != newDigits {
            if let current = keypad.evaluatedValue, current > 0 {
                keypad = AmountKeypadEngine(initialAmountMajor: current, maxFractionDigits: newDigits)
            } else {
                keypad.maxFractionDigits = newDigits
            }
        }
        if normalized != settings.currency.rawValue {
            Task { await fxService.refreshIfStale() }
        }
    }

    private func quickSuggestions(lang: AppLanguage) -> [String] {
        var result = category.quickDescriptions(in: lang)
        var seen = Set(result.map { $0.lowercased() })

        // Append up to 3 recent user merchants from this category so frequent spots are 1 tap away.
        var addedRecent = 0
        for tx in store.activeTransactions where tx.category == category && tx.type == type {
            let trimmed = tx.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 24 else { continue }
            let key = trimmed.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(trimmed)
                addedRecent += 1
                if addedRecent >= 3 { break }
            }
        }
        return result
    }

    private var memberOptions: [HouseholdMember] {
        var list = store.knownMembers(settings: settings)
        let partner = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partner.isEmpty && !list.contains(where: { $0.name == partner }) {
            list.append(HouseholdMember(id: HouseholdMember.defaultPartnerID, name: partner))
        }
        return list
    }

    private func populate() {
        if let existing {
            name = existing.name
            if existing.isForeignCurrency,
               let origCode = existing.originalCurrencyCode,
               let origMinor = existing.originalAmountMinor {
                let normalized = CurrencyCode.normalizeCode(origCode) ?? origCode.uppercased()
                entryCurrencyCode = normalized
                let maxDigits = CurrencyCode.fractionDigits(forCode: normalized)
                keypad = AmountKeypadEngine(initialAmountMajor: CurrencyCode.toMajor(origMinor), maxFractionDigits: maxDigits)
                preservedForeign = (normalized, origMinor, existing.amountMinor, existing.exchangeRate)
            } else {
                entryCurrencyCode = settings.currency.rawValue
                let maxDigits = settings.currency.fractionDigits
                let major = settings.currency.toMajor(existing.amountMinor)
                keypad = AmountKeypadEngine(initialAmountMajor: major, maxFractionDigits: maxDigits)
                preservedForeign = nil
            }
            type = existing.type
            category = existing.category
            dayKey = existing.dayKey
            note = existing.note
            showNoteField = !existing.note.isEmpty
            selectedMemberID = existing.memberID
            selectedMemberName = existing.memberName
        } else {
            entryCurrencyCode = settings.currency.rawValue
            keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: settings.currency.fractionDigits)
            preservedForeign = nil
            selectedMemberID = settings.currentMember.id
            selectedMemberName = settings.currentMember.name
            dayKey = store.selectedPeriod.defaultNewTransactionDayKey()
        }
    }

    private func save() {
        let major = resolvedAmountMajor
        guard major > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter an amount greater than 0.", vi: "Vui lòng nhập số tiền lớn hơn 0.", zh: "请输入大于 0 的金额。")
            return
        }

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = cleanedName.isEmpty ? category.title(in: settings.language) : cleanedName

        let finalAmountMinor: Int64
        let origMinor: Int64?
        let origCode: String?
        let finalRate: Double?
        let needsReview: Bool

        if isForeignEntry {
            let preview = conversionPreview
            finalAmountMinor = max(1, preview.minor)
            origMinor = max(1, CurrencyCode.toStorageMinor(major, currencyCode: activeCurrencyCode))
            origCode = activeCurrencyCode
            finalRate = preview.rate ?? (major > 0 ? settings.currency.toMajor(finalAmountMinor) / major : nil)
            needsReview = preview.source == .unavailable
        } else {
            finalAmountMinor = max(1, settings.currency.toStorageMinor(major))
            origMinor = nil
            origCode = nil
            finalRate = nil
            needsReview = false
        }

        let record = TransactionRecord(
            id: existing?.id ?? UUID().uuidString,
            name: finalName,
            amountMinor: finalAmountMinor,
            type: type,
            category: category,
            dayKey: dayKey,
            createdAt: existing?.createdAt ?? Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: existing?.source ?? .manual,
            rawSourceText: existing?.rawSourceText,
            memberID: selectedMemberID.isEmpty ? settings.currentMember.id : selectedMemberID,
            memberName: selectedMemberName.isEmpty ? settings.currentMember.name : selectedMemberName,
            needsReview: needsReview,
            updatedAt: Date(),
            isDeleted: false,
            originalAmountMinor: origMinor,
            originalCurrencyCode: origCode,
            exchangeRate: finalRate
        )
        store.saveTransaction(record)
        store.ensureVisible(dayKey: record.dayKey)
        dismiss()
    }
}
