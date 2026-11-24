import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

/// Create / edit sheet for installment plans and loans.
struct InstallmentPlanEditorSheet: View {
    let existing: InstallmentPlanRecord?
    var initialKind: InstallmentKind = .installment

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum AmountField { case amount, monthly }
    private enum TextFieldID: Hashable { case name, lender, link, note }

    @State private var kind: InstallmentKind = .installment
    @State private var name = ""
    @State private var lender = ""
    @State private var amountKeypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var monthlyKeypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var activeAmountField: AmountField = .amount
    @State private var monthsText = "12"
    @State private var monthsEditing = false
    @State private var firstDayKey = DateKey.dayKey(from: Date())
    @State private var showingDatePicker = false
    @State private var category: CategoryID = .shopping
    @State private var categoryTouched = false
    @State private var memberID = ""
    @State private var memberName = ""
    @State private var linkText = ""
    @State private var note = ""
    @State private var alreadyPaidCount = 0
    @State private var errorMessage: String?
    @State private var didPopulate = false

    @FocusState private var focusedField: TextFieldID?

    private var isEditing: Bool { existing != nil }
    private var isTextEditing: Bool { focusedField != nil || monthsEditing }

    // MARK: Draft

    private var draft: InstallmentPlanDraft {
        let currency = settings.currency
        return InstallmentPlanDraft(
            kind: kind,
            name: name,
            lender: lender,
            amountMinor: currency.toStorageMinor(max(0, amountKeypad.evaluatedValue ?? 0)),
            monthlyPaymentMinor: currency.toStorageMinor(max(0, monthlyKeypad.evaluatedValue ?? 0)),
            months: InstallmentPresets.parseMonths(monthsText),
            firstPaymentDayKey: firstDayKey,
            category: category,
            memberID: memberID.isEmpty ? settings.currentMember.id : memberID,
            memberName: memberName.isEmpty ? settings.currentMember.name : memberName,
            linkText: linkText,
            note: note,
            currency: currency,
            alreadyPaidCount: effectiveAlreadyPaidCount
        )
    }

    /// Only meaningful while the plan has already started; otherwise nothing is due yet.
    private var effectiveAlreadyPaidCount: Int {
        firstDayKey <= DateKey.dayKey(from: Date()) ? alreadyPaidCount : 0
    }

    // MARK: Body

    var body: some View {
        let lang = settings.language
        let draft = draft
        let canSave = draft.isValid

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        kindSection(lang: lang)
                        nameSection(lang: lang)
                        amountSection(lang: lang)
                        monthsSection(lang: lang)
                        firstPaymentSection(lang: lang)
                        alreadyPaidSection(draft: draft, lang: lang)
                        previewCard(draft: draft, lang: lang)
                        categorySection(lang: lang)
                        memberSection(lang: lang)
                        if kind == .loan { linkSection(draft: draft, lang: lang) }
                        noteSection(lang: lang)

                        if let errorMessage {
                            Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .scrollDismissesKeyboard(.interactively)

                if !isTextEditing {
                    AmountKeypadView(
                        engine: activeKeypadBinding,
                        currency: settings.currency,
                        language: lang,
                        saveTitle: saveTitle(lang: lang),
                        isSaveEnabled: canSave,
                        onSave: save
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    compactSaveBar(canSave: canSave, lang: lang)
                }
            }
            .animation(.snappy(duration: 0.22), value: isTextEditing)
            .pageBackground()
            .keypadKeyboardInput(engine: activeKeypadBinding, isEnabled: !isTextEditing, isSaveEnabled: canSave, onSave: save)
            .navigationTitle(navigationTitle(lang: lang))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isTextEditing {
                        Button(L10n.text(lang, en: "Keypad", vi: "Bàn phím số", zh: "数字键盘")) {
                            endTextEditing()
                        }
                        .font(.appControl)
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                InstallmentDatePickerSheet(
                    dayKey: $firstDayKey,
                    title: L10n.text(lang, en: "First payment date", vi: "Ngày trả đầu tiên", zh: "首期还款日")
                )
            }
            .onAppear(perform: populate)
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 460, idealWidth: 500, minHeight: 640, idealHeight: 740)
    }

    // MARK: Sections

    private func kindSection(lang: AppLanguage) -> some View {
        Group {
            if isEditing {
                HStack(spacing: 8) {
                    Tag(text: kind.title(in: lang), color: Color.accent)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 2) {
                    ForEach(InstallmentKind.allCases) { option in
                        let selected = kind == option
                        Button {
                            CozyHaptics.selection()
                            endTextEditing()
                            withAnimation(.snappy(duration: 0.18)) { switchKind(to: option) }
                        } label: {
                            Text(option.title(in: lang))
                                .font(.appControl)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .foregroundStyle(selected ? Color.onInk : Color.textSecondary)
                                .background(selected ? Color.ink : Color.clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(Color.softFill, in: Capsule())
            }
        }
    }

    private func nameSection(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(L10n.text(lang, en: "Name", vi: "Tên", zh: "名称"))
                TextField(
                    kind == .loan
                        ? L10n.text(lang, en: "e.g. Car loan, Renovation loan", vi: "VD: Vay mua xe, Vay sửa nhà", zh: "例如：购车贷款、装修贷款")
                        : L10n.text(lang, en: "e.g. iPhone, Sofa (0% IPP)", vi: "VD: iPhone, Sofa (trả góp 0%)", zh: "例如：iPhone、沙发（0% 分期）"),
                    text: $name
                )
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .tallyField()
            }

            if kind == .loan {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Lender", vi: "Bên cho vay", zh: "贷款机构"))
                    TextField(
                        L10n.text(lang, en: "e.g. DBS, Trust, Vietcombank", vi: "VD: DBS, Trust, Vietcombank", zh: "例如：DBS、Trust、银行名称"),
                        text: $lender
                    )
                    .focused($focusedField, equals: .lender)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .tallyField()
                }
            }
        }
    }

    private func amountSection(lang: AppLanguage) -> some View {
        let code = settings.currency.rawValue
        return HStack(spacing: 10) {
            amountTile(
                title: kind == .loan
                    ? L10n.text(lang, en: "Amount borrowed (\(code))", vi: "Số tiền vay (\(code))", zh: "借款金额（\(code)）")
                    : L10n.text(lang, en: "Total amount (\(code))", vi: "Tổng số tiền (\(code))", zh: "总金额（\(code)）"),
                engine: amountKeypad,
                isActive: !isTextEditing && activeAmountField == .amount
            ) {
                activate(.amount)
            }
            if kind == .loan {
                amountTile(
                    title: L10n.text(lang, en: "Monthly payment", vi: "Trả hàng tháng", zh: "每月还款"),
                    engine: monthlyKeypad,
                    isActive: !isTextEditing && activeAmountField == .monthly
                ) {
                    activate(.monthly)
                }
            }
        }
    }

    private func monthsSection(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L10n.text(lang, en: "Number of months", vi: "Số tháng", zh: "期数"))
            InstallmentMonthsField(monthsText: $monthsText, isEditing: $monthsEditing, language: lang)
        }
    }

    private func firstPaymentSection(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L10n.text(lang, en: "First payment", vi: "Kỳ trả đầu tiên", zh: "首期还款日"))
            HStack {
                InstallmentDatePill(dayKey: firstDayKey, language: lang) {
                    endTextEditing()
                    showingDatePicker = true
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Shown only when the first payment date is today or earlier: how many of the payments due so
    /// far are already recorded in Tally (or were paid before it), so the plan does not book them
    /// a second time.
    @ViewBuilder
    private func alreadyPaidSection(draft: InstallmentPlanDraft, lang: AppLanguage) -> some View {
        let todayKey = DateKey.dayKey(from: Date())
        if draft.startsOnOrBefore(todayKey) {
            let maxCount = max(0, draft.months ?? 0)
            let due = draft.duePaymentCount(todayKey: todayKey)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L10n.text(lang, en: "Payments already made", vi: "Các kỳ đã trả", zh: "已支付的期数"))
                HStack(spacing: 10) {
                    countButton(label: { Text("−").font(.appControl.weight(.bold)) }, enabled: alreadyPaidCount > 0) {
                        alreadyPaidCount = max(0, alreadyPaidCount - 1)
                    }
                    .accessibilityLabel(L10n.text(lang, en: "Fewer", vi: "Bớt", zh: "减少"))
                    Text("\(alreadyPaidCount)")
                        .font(.appMetric)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 36)
                    countButton(label: { CozyUIIcon(.plus, size: 14, color: Color.textPrimary) }, enabled: alreadyPaidCount < maxCount) {
                        alreadyPaidCount = min(maxCount, alreadyPaidCount + 1)
                    }
                    .accessibilityLabel(L10n.text(lang, en: "More", vi: "Thêm", zh: "增加"))
                    Spacer(minLength: 4)
                    if due > 0, alreadyPaidCount != min(due, maxCount) {
                        Button(L10n.text(lang, en: "All \(due) due so far", vi: "Cả \(due) kỳ đã đến hạn", zh: "至今到期的 \(due) 期")) {
                            CozyHaptics.selection()
                            withAnimation(.snappy(duration: 0.16)) { alreadyPaidCount = min(due, maxCount) }
                        }
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .buttonStyle(.themedPlain)
                    }
                }
                Text(alreadyPaidCount == 0
                    ? L10n.text(
                        lang,
                        en: "This plan started in the past. Payments due so far will be added as expenses in their months. If you already recorded them in Tally (for example from bank emails), count them here so they aren't added twice.",
                        vi: "Kế hoạch này đã bắt đầu từ trước. Các kỳ đã đến hạn sẽ được ghi thành khoản chi vào tháng tương ứng. Nếu bạn đã ghi chúng trong Tally (ví dụ từ email ngân hàng), hãy nhập số kỳ ở đây để không bị ghi trùng.",
                        zh: "该计划已开始。至今到期的款项会按月份记为支出。如果您已在 Tally 中记录过（例如来自银行邮件），请在此填写期数，避免重复记账。"
                    )
                    : L10n.text(
                        lang,
                        en: "The first \(alreadyPaidCount) payments count as paid but won't be added as expenses again.",
                        vi: "\(alreadyPaidCount) kỳ đầu được tính là đã trả nhưng sẽ không được ghi thành khoản chi lần nữa.",
                        zh: "前 \(alreadyPaidCount) 期计为已支付，但不会再次记为支出。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: maxCount) { _, newMax in
                if alreadyPaidCount > newMax { alreadyPaidCount = newMax }
            }
        }
    }

    private func countButton<Label: View>(@ViewBuilder label: () -> Label, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            CozyHaptics.selection()
            endTextEditing()
            withAnimation(.snappy(duration: 0.16)) { action() }
        } label: {
            label()
                .foregroundStyle(Color.textPrimary)
                .frame(width: 36, height: 36)
                .background(Color.softFill, in: Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.themedPlain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    @ViewBuilder
    private func previewCard(draft: InstallmentPlanDraft, lang: AppLanguage) -> some View {
        let currency = settings.currency
        switch kind {
        case .installment:
            if draft.amountMinor > 0, draft.monthsAreValid, let months = draft.months,
               let line = InstallmentPresets.monthlyPreview(totalMinor: draft.amountMinor, months: months, currency: currency, language: lang) {
                previewSurface {
                    Text(line).font(.appHeading).monospacedDigit()
                    if let lastNote = InstallmentPresets.lastPaymentNote(totalMinor: draft.amountMinor, months: months, currency: currency, language: lang) {
                        Text(lastNote).font(.appCaption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        case .loan:
            if let below = shortfall(in: draft) {
                previewSurface {
                    HStack(alignment: .top, spacing: 8) {
                        CozyUIIcon(.warning, size: 16, color: Color.caution)
                        Text(L10n.text(
                            lang,
                            en: "Monthly payment × months is \(money(draft.loanTotalMinor)), \(money(below)) less than the amount borrowed. Raise the payment or add months.",
                            vi: "Trả hàng tháng × số tháng là \(money(draft.loanTotalMinor)), thấp hơn số tiền vay \(money(below)). Hãy tăng khoản trả hoặc số tháng.",
                            zh: "每月还款 × 期数为 \(money(draft.loanTotalMinor))，比借款金额少 \(money(below))。请提高每月还款或增加期数。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.caution)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if let record = draft.previewRecord(), let months = draft.months,
                      let line = InstallmentPresets.monthlyPreview(
                        totalMinor: record.totalMinor, months: months,
                        regularMinor: draft.monthlyPaymentMinor, currency: currency, language: lang
                      ) {
                previewSurface {
                    Text(line).font(.appHeading).monospacedDigit()
                    if let lastNote = InstallmentPresets.lastPaymentNote(
                        totalMinor: record.totalMinor, months: months,
                        regularMinor: draft.monthlyPaymentMinor, currency: currency, language: lang
                    ) {
                        Text(lastNote).font(.appCaption).foregroundStyle(Color.textSecondary)
                    }
                    Divider().overlay(Color.hairline)
                    metricLine(
                        L10n.text(lang, en: "Effective rate (p.a.)", vi: "Lãi suất thực (năm)", zh: "实际年利率"),
                        InstallmentRateFormat.percent(record.effectiveAnnualRate, language: lang)
                    )
                    metricLine(
                        L10n.text(lang, en: "Total interest", vi: "Tổng tiền lãi", zh: "利息总额"),
                        money(record.totalInterestMinor)
                    )
                    metricLine(
                        L10n.text(lang, en: "Total to repay", vi: "Tổng phải trả", zh: "还款总额"),
                        money(record.totalMinor)
                    )
                }
            }
        }
    }

    private func previewSurface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardSurface(cornerRadius: 18)
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.appSecondary).foregroundStyle(Color.textSecondary)
            Spacer(minLength: 8)
            Text(value).font(.appBodyMedium).monospacedDigit()
        }
    }

    private func categorySection(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(L10n.text(lang, en: "Category", vi: "Danh mục", zh: "分类"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TransactionType.expense.categories) { item in
                        let selected = category == item
                        Button {
                            CozyHaptics.selection()
                            categoryTouched = true
                            withAnimation(.snappy(duration: 0.18)) { category = item }
                        } label: {
                            HStack(spacing: 6) {
                                CozyCategoryIcon(category: item, size: 17, style: selected ? .tinted(Color.onInk) : .watercolor)
                                Text(item.title(in: lang))
                                    .font(.appCaption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                            .background(selected ? Color.ink : Color.cardBackground, in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func memberSection(lang: AppLanguage) -> some View {
        let members = memberOptions
        if members.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(L10n.text(lang, en: "Who pays", vi: "Ai trả", zh: "由谁支付"))
                HStack {
                    Menu {
                        ForEach(members) { member in
                            Button {
                                memberID = member.id
                                memberName = member.name
                            } label: {
                                if member.id == memberID {
                                    Label(member.name, systemImage: "checkmark")
                                } else {
                                    Text(member.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            CozyUIIcon(.person, size: 14, color: Color.textSecondary)
                            Text(memberName.isEmpty ? settings.currentMember.name : memberName)
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            CozyUIIcon(.chevronUpDown, size: 12, color: Color.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.cardBackground, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func linkSection(draft: InstallmentPlanDraft, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(L10n.text(lang, en: "Bank app link (optional)", vi: "Liên kết ứng dụng ngân hàng (tuỳ chọn)", zh: "银行 App 链接（可选）"))
            TextField(
                L10n.text(lang, en: "https://… or myapp://", vi: "https://… hoặc myapp://", zh: "https://… 或 myapp://"),
                text: $linkText
            )
            .focused($focusedField, equals: .link)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .tallyField()

            if draft.linkIsUnrecognized {
                Text(L10n.text(
                    lang,
                    en: "This doesn't look like a web address or app link, so it won't be saved.",
                    vi: "Nội dung này không giống địa chỉ web hay liên kết ứng dụng nên sẽ không được lưu.",
                    zh: "这看起来不是网址或 App 链接，将不会保存。"
                ))
                .font(.appCaption)
                .foregroundStyle(Color.caution)
            }
        }
    }

    private func noteSection(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(L10n.text(lang, en: "Note", vi: "Ghi chú", zh: "备注"))
            TextField(
                L10n.text(lang, en: "Card, account, reference…", vi: "Thẻ, tài khoản, mã tham chiếu…", zh: "银行卡、账户、参考编号…"),
                text: $note
            )
            .focused($focusedField, equals: .note)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .tallyField()
        }
    }

    // MARK: Amount tile (same look as the goal editor)

    private func amountTile(title: String, engine: AmountKeypadEngine, isActive: Bool, action: @escaping () -> Void) -> some View {
        let currency = settings.currency
        let display = engine.formattedDisplayNumber(currency: currency)
        let isEmpty = engine.isEmpty

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2)
                    if isActive {
                        Circle().fill(Color.accent).frame(width: 6, height: 6)
                    }
                }

                if engine.hasOperator {
                    Text(engine.formattedExpression)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if currency != .vnd {
                        Text(currency.narrowSymbol)
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text(display)
                        .font(.appMetric)
                        .monospacedDigit()
                        .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                    if currency == .vnd {
                        Text("₫")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? Color.ink : Color.hairline, lineWidth: isActive ? 1.8 : 1)
            )
        }
        .buttonStyle(.themedPlain)
        .accessibilityLabel(title)
        .accessibilityValue(engine.isEmpty ? "" : display)
    }

    private func compactSaveBar(canSave: Bool, lang: AppLanguage) -> some View {
        HStack(spacing: 10) {
            Button {
                endTextEditing()
            } label: {
                CozyUIIcon(.keypad, size: 19, color: Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.softFill, in: Circle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityLabel(L10n.text(lang, en: "Show number keypad", vi: "Mở bàn phím số", zh: "显示数字键盘"))

            Button(saveTitle(lang: lang), action: save)
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

    // MARK: Helpers

    private var activeKeypadBinding: Binding<AmountKeypadEngine> {
        Binding(
            get: { activeAmountField == .monthly && kind == .loan ? monthlyKeypad : amountKeypad },
            set: { newValue in
                if activeAmountField == .monthly && kind == .loan {
                    monthlyKeypad = newValue
                } else {
                    amountKeypad = newValue
                }
            }
        )
    }

    private func activate(_ field: AmountField) {
        endTextEditing()
        withAnimation(.snappy(duration: 0.16)) { activeAmountField = field }
    }

    private func endTextEditing() {
        focusedField = nil
        monthsEditing = false
    }

    private func switchKind(to newKind: InstallmentKind) {
        guard newKind != kind else { return }
        kind = newKind
        activeAmountField = .amount
        if !categoryTouched {
            category = newKind == .loan ? .bills : .shopping
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.format(minor: minor, currency: settings.currency, language: settings.language)
    }

    private func shortfall(in draft: InstallmentPlanDraft) -> Int64? {
        for issue in draft.issues {
            if case .paymentsBelowPrincipal(let missing) = issue { return missing }
        }
        return nil
    }

    private func navigationTitle(lang: AppLanguage) -> String {
        switch (isEditing, kind) {
        case (false, _):
            return L10n.text(lang, en: "New commitment", vi: "Khoản trả góp / vay mới", zh: "新建分期 / 贷款")
        case (true, .loan):
            return L10n.text(lang, en: "Edit loan", vi: "Sửa khoản vay", zh: "编辑贷款")
        case (true, .installment):
            return L10n.text(lang, en: "Edit installment", vi: "Sửa trả góp", zh: "编辑分期")
        }
    }

    private func saveTitle(lang: AppLanguage) -> String {
        isEditing
            ? L10n.text(lang, en: "Save changes", vi: "Lưu thay đổi", zh: "保存修改")
            : L10n.text(lang, en: "Save plan", vi: "Lưu kế hoạch", zh: "保存计划")
    }

    private var memberOptions: [HouseholdMember] {
        var list = store.knownMembers(settings: settings)
        let partner = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partner.isEmpty && !list.contains(where: { $0.name == partner }) {
            list.append(HouseholdMember(id: HouseholdMember.defaultPartnerID, name: partner))
        }
        return list
    }

    private func issueMessage(_ issue: InstallmentPlanDraft.Issue, lang: AppLanguage) -> String {
        switch issue {
        case .missingName:
            return L10n.text(lang, en: "Enter a name.", vi: "Nhập tên.", zh: "请输入名称。")
        case .invalidAmount:
            return kind == .loan
                ? L10n.text(lang, en: "Enter the amount borrowed.", vi: "Nhập số tiền vay.", zh: "请输入借款金额。")
                : L10n.text(lang, en: "Enter the total amount.", vi: "Nhập tổng số tiền.", zh: "请输入总金额。")
        case .missingMonthlyPayment:
            return L10n.text(lang, en: "Enter the monthly payment.", vi: "Nhập số tiền trả hàng tháng.", zh: "请输入每月还款额。")
        case .invalidMonths:
            return L10n.text(
                lang,
                en: "Pick how many monthly payments (1 to \(InstallmentPlanDraft.maxMonths)).",
                vi: "Chọn số kỳ trả hàng tháng (từ 1 đến \(InstallmentPlanDraft.maxMonths)).",
                zh: "请选择每月还款的期数（1 到 \(InstallmentPlanDraft.maxMonths)）。"
            )
        case .invalidFirstPaymentDay:
            return L10n.text(lang, en: "Pick the first payment date.", vi: "Chọn ngày trả đầu tiên.", zh: "请选择首期还款日。")
        case .amountTooSmallForMonths(let minimum):
            return L10n.text(
                lang,
                en: "This amount is too small to split into that many monthly payments. Use at least \(money(minimum)) or fewer months.",
                vi: "Số tiền quá nhỏ để chia thành ngần ấy kỳ. Hãy dùng ít nhất \(money(minimum)) hoặc giảm số tháng.",
                zh: "金额太小，无法拆分为这么多期。请至少输入 \(money(minimum)) 或减少期数。"
            )
        case .alreadyPaidOutOfRange(let maxCount):
            return L10n.text(
                lang,
                en: "Payments already made can't be more than the number of months (\(maxCount)).",
                vi: "Số kỳ đã trả không được lớn hơn số tháng (\(maxCount)).",
                zh: "已支付的期数不能超过总期数（\(maxCount)）。"
            )
        case .paymentsBelowPrincipal(let missing):
            return L10n.text(
                lang,
                en: "Monthly payment × months is \(money(missing)) short of the amount borrowed.",
                vi: "Trả hàng tháng × số tháng còn thiếu \(money(missing)) so với số tiền vay.",
                zh: "每月还款 × 期数比借款金额少 \(money(missing))。"
            )
        }
    }

    private func populate() {
        guard !didPopulate else { return }
        didPopulate = true
        let digits = settings.currency.fractionDigits
        memberID = settings.currentMember.id
        memberName = settings.currentMember.name

        if let existing {
            let loaded = InstallmentPlanDraft(plan: existing)
            kind = loaded.kind
            name = loaded.name
            lender = loaded.lender
            amountKeypad = AmountKeypadEngine(initialAmountMajor: settings.currency.toMajor(loaded.amountMinor), maxFractionDigits: digits)
            monthlyKeypad = AmountKeypadEngine(
                initialAmountMajor: loaded.monthlyPaymentMinor > 0 ? settings.currency.toMajor(loaded.monthlyPaymentMinor) : nil,
                maxFractionDigits: digits
            )
            monthsText = String(loaded.months ?? 12)
            firstDayKey = loaded.firstPaymentDayKey
            category = loaded.category
            categoryTouched = true
            memberID = loaded.memberID
            memberName = loaded.memberName
            linkText = loaded.linkText
            note = loaded.note
            alreadyPaidCount = loaded.alreadyPaidCount
        } else {
            kind = initialKind
            category = initialKind == .loan ? .bills : .shopping
            amountKeypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: digits)
            monthlyKeypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: digits)
        }
    }

    private func save() {
        let lang = settings.language
        let draft = draft
        guard let record = draft.makeRecord(existing: existing) else {
            errorMessage = draft.issues.first.map { issueMessage($0, lang: lang) }
            return
        }
        guard store.savePlan(record) else {
            errorMessage = L10n.text(lang, en: "These terms can't be saved. Check the amount and months.", vi: "Không thể lưu các điều khoản này. Hãy kiểm tra số tiền và số tháng.", zh: "无法保存这些条款，请检查金额和期数。")
            return
        }
        CozyHaptics.success()
        dismiss()
    }
}
