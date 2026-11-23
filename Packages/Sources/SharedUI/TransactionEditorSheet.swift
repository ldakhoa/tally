import AppServices
import BudgetKit
import DesignSystem
import SwiftUI
import TallyCore

public struct TransactionEditorSheet: View {
    public let existing: TransactionRecord?
    public let prefill: ParsedTransactionDraft?
    public let sourceOverride: TransactionSource?
    public let rawSourceText: String?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum EditorField: Hashable {
        case description
        case note
    }

    @State private var name: String = ""
    @State private var keypad = AmountKeypadEngine(maxFractionDigits: 2)
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

    @FocusState private var focusedField: EditorField?

    public init(
        existing: TransactionRecord? = nil,
        prefill: ParsedTransactionDraft? = nil,
        sourceOverride: TransactionSource? = nil,
        rawSourceText: String? = nil
    ) {
        self.existing = existing
        self.prefill = prefill
        self.sourceOverride = sourceOverride
        self.rawSourceText = rawSourceText
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

                        if let raw = existing?.rawSourceText ?? rawSourceText, !raw.isEmpty {
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
                        currency: settings.currency,
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }

                ToolbarItem(placement: .principal) {
                    typeSegmentedPill(lang: lang)
                }

                ToolbarItem(placement: .primaryAction) {
                    if focusedField != nil {
                        Button(L10n.text(lang, en: "Keypad", vi: "Bàn phím số", zh: "数字键盘")) {
                            focusedField = nil
                        }
                        .font(.appControl)
                    } else if existing != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.negative)
                        }
                        .accessibilityLabel(L10n.text(lang, en: "Delete transaction", vi: "Xoá giao dịch", zh: "删除账单"))
                    }
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
                    .navigationTitle(L10n.text(lang, en: "Select date", vi: "Chọn ngày", zh: "选择日期"))
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                                showingDatePicker = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
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
        let currency = settings.currency
        let displayNumber = keypad.formattedDisplayNumber(currency: currency)
        let isEmpty = keypad.isEmpty
        let amountColor: Color = isEmpty
            ? Color.textSecondary.opacity(0.38)
            : (type == .income ? Color.positive : Color.textPrimary)

        return Button {
            focusedField = nil
        } label: {
            VStack(spacing: 4) {
                // Live arithmetic formula pill (when +, −, ×, ÷ is active)
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

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if currency != .vnd {
                        Text(type == .income && !isEmpty ? "+\(currency.narrowSymbol)" : currency.narrowSymbol)
                            .font(.custom("AvenirNext-Medium", size: 26))
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

                    if currency == .vnd {
                        Text("₫")
                            .font(.custom("AvenirNext-Medium", size: 26))
                            .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.textSecondary.opacity(0.6))
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
                                Image(systemName: item.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selected ? Color.onInk : item.color)
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
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
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
                            Image(systemName: "person.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(selectedMemberName.isEmpty ? settings.currentMember.name : selectedMemberName)
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Color.cardBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                    }
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
                        Image(systemName: note.isEmpty ? "note.text.badge.plus" : "note.text")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(note.isEmpty ? Color.textSecondary : Color.accent)
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
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
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

    // MARK: - Compact Save Bar (shown while system keyboard is visible)

    private func compactKeyboardSaveBar(amountMajor: Double, canSave: Bool, lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            Button {
                focusedField = nil
            } label: {
                Image(systemName: "number.square")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.textPrimary)
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
        let formatted = MoneyFormat.format(
            minor: settings.currency.toStorageMinor(amountMajor),
            currency: settings.currency,
            language: lang
        )
        return isEditing
            ? L10n.text(lang, en: "Update · \(formatted)", vi: "Cập nhật · \(formatted)", zh: "更新 · \(formatted)")
            : L10n.text(lang, en: "Save · \(formatted)", vi: "Lưu · \(formatted)", zh: "保存 · \(formatted)")
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
        let maxDigits = settings.currency.fractionDigits
        if let existing {
            name = existing.name
            let major = settings.currency.toMajor(existing.amountMinor)
            keypad = AmountKeypadEngine(initialAmountMajor: major, maxFractionDigits: maxDigits)
            type = existing.type
            category = existing.category
            dayKey = existing.dayKey
            note = existing.note
            showNoteField = !existing.note.isEmpty
            selectedMemberID = existing.memberID
            selectedMemberName = existing.memberName
        } else if let prefill {
            name = prefill.name
            keypad = AmountKeypadEngine(initialAmountMajor: prefill.amountMajor, maxFractionDigits: maxDigits)
            type = prefill.type
            category = prefill.category
            dayKey = prefill.dayKey
            note = prefill.note
            showNoteField = !prefill.note.isEmpty
            selectedMemberID = settings.currentMember.id
            selectedMemberName = settings.currentMember.name
        } else {
            keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: maxDigits)
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

        let record = TransactionRecord(
            id: existing?.id ?? UUID().uuidString,
            name: finalName,
            amountMinor: settings.currency.toStorageMinor(major),
            type: type,
            category: category,
            dayKey: dayKey,
            createdAt: existing?.createdAt ?? Date(),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: existing?.source ?? sourceOverride ?? .manual,
            rawSourceText: existing?.rawSourceText ?? rawSourceText,
            memberID: selectedMemberID.isEmpty ? settings.currentMember.id : selectedMemberID,
            memberName: selectedMemberName.isEmpty ? settings.currentMember.name : selectedMemberName,
            needsReview: false,
            updatedAt: Date(),
            isDeleted: false
        )
        store.saveTransaction(record)
        store.ensureVisible(dayKey: record.dayKey)
        dismiss()
    }
}
