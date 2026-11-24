import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct BudgetsView: View {
    public var embedded: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewBudget = false
    @State private var editingBudget: BudgetLimitRecord?

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        let lang = settings.language
        let snapshot = store.monthlySnapshot

        if embedded {
            content(snapshot: snapshot, lang: lang)
                .sheet(isPresented: $showingNewBudget) {
                    BudgetEditorSheet(existing: nil)
                }
                .sheet(item: $editingBudget) { budget in
                    BudgetEditorSheet(existing: budget)
                }
        } else {
            NavigationStack {
                ScrollView {
                    content(snapshot: snapshot, lang: lang)
                        .documentColumn(maxWidth: 1020)
                }
                .pageBackground()
                .navigationTitle(L10n.text(lang, en: "Budgets", vi: "Ngân sách", zh: "预算"))
                .toolbar { TopToolbarControls() }
                .sheet(isPresented: $showingNewBudget) {
                    BudgetEditorSheet(existing: nil)
                }
                .sheet(item: $editingBudget) { budget in
                    BudgetEditorSheet(existing: budget)
                }
            }
        }
    }

    private func content(snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            PeriodHeaderBar {
                Button {
                    showingNewBudget = true
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.plus, size: 14, color: Color.onInk)
                        Text(L10n.text(lang, en: "Set limit", vi: "Đặt hạn mức", zh: "设置预算"))
                    }
                }
                .pillButton(prominent: true)
            }

            if snapshot.budgetTotalMinor > 0 {
                let usedRatio = Double(snapshot.budgetSpentMinor) / Double(max(1, snapshot.budgetTotalMinor))
                let isOver = snapshot.budgetLeftMinor < 0
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.text(lang, en: "Monthly budget", vi: "Tổng ngân sách tháng", zh: "本月预算"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            Text(MoneyFormat.format(minor: snapshot.budgetSpentMinor, currency: settings.currency, language: lang))
                                .font(.appMetric)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(isOver
                                 ? L10n.text(lang, en: "Over by", vi: "Vượt quá", zh: "已超出")
                                 : L10n.text(lang, en: "Remaining", vi: "Còn lại", zh: "剩余"))
                                .font(.appCaption)
                                .foregroundStyle(isOver ? Color.negative : Color.textSecondary)
                            Text(MoneyFormat.format(minor: abs(snapshot.budgetLeftMinor), currency: settings.currency, language: lang))
                                .font(.appHeading)
                                .foregroundStyle(isOver ? Color.negative : Color.positive)
                        }
                    }
                    TallyProgressBar(value: usedRatio, fill: isOver ? .negative : (usedRatio > 0.85 ? .caution : .positive))
                    Text("\(L10n.text(lang, en: "Total limit:", vi: "Tổng hạn mức:", zh: "总限额：")) \(MoneyFormat.format(minor: snapshot.budgetTotalMinor, currency: settings.currency, language: lang))")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            if snapshot.budgets.isEmpty {
                EmptyStateCard(
                    symbol: "chart.pie",
                    title: L10n.text(lang, en: "No budgets for this month", vi: "Chưa đặt ngân sách tháng này", zh: "本月尚未设置预算"),
                    message: L10n.text(lang, en: "Set monthly limits per category like Food, Housing, or Shopping.", vi: "Đặt hạn mức tháng cho từng mục như Ăn uống, Nhà ở, Mua sắm.", zh: "为餐饮、住房、购物等分类设置每月预算限额。"),
                    actionTitle: L10n.text(lang, en: "Set a budget", vi: "Đặt ngân sách", zh: "设置预算")
                ) {
                    showingNewBudget = true
                }

                Button {
                    _ = store.copyBudgetsFromPreviousMonth()
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.copy, size: 15, color: Color.textPrimary)
                        Text(L10n.text(lang, en: "Copy from previous month", vi: "Sao chép từ tháng trước", zh: "沿用上月预算"))
                    }
                }
                .blockButton(prominent: false)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(snapshot.budgets) { budget in
                        let spent = snapshot.expensesByCategory[budget.category] ?? 0
                        let remaining = budget.limitMinor - spent
                        let ratio = Double(spent) / Double(max(1, budget.limitMinor))
                        let pct = Int((ratio * 100).rounded(.down))

                        Button {
                            editingBudget = budget
                        } label: {
                            Card {
                                HStack(spacing: 12) {
                                    CategoryBadge(category: budget.category, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(budget.category.title(in: lang))
                                            .font(.appHeading)
                                        Text("\(MoneyFormat.format(minor: spent, currency: settings.currency, language: lang)) / \(MoneyFormat.format(minor: budget.limitMinor, currency: settings.currency, language: lang))")
                                            .font(.appCaption)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                    Tag(
                                        text: "\(pct)%",
                                        color: remaining < 0 ? .negative : (ratio > 0.85 ? .caution : .positive)
                                    )
                                }
                                TallyProgressBar(
                                    value: ratio,
                                    fill: remaining < 0 ? .negative : (ratio > 0.85 ? .caution : budget.category.color)
                                )
                                Text(
                                    remaining < 0
                                        ? "\(MoneyFormat.format(minor: abs(remaining), currency: settings.currency, language: lang)) \(L10n.text(lang, en: "over budget", vi: "vượt hạn mức", zh: "超出预算"))"
                                        : "\(MoneyFormat.format(minor: remaining, currency: settings.currency, language: lang)) \(L10n.text(lang, en: "left", vi: "còn lại", zh: "剩余"))"
                                )
                                .font(.appCaption)
                                .foregroundStyle(remaining < 0 ? Color.negative : Color.textSecondary)
                            }
                        }
                        .buttonStyle(.themedPlain)
                    }
                }
            }
        }
    }
}

private struct BudgetEditorSheet: View {
    let existing: BudgetLimitRecord?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var category: CategoryID = .food
    @State private var keypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    var body: some View {
        let lang = settings.language
        let liveAmount = resolvedLimitMajor
        let canSave = liveAmount > 0

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Hero amount stage
                        amountHeroStage(lang: lang)

                        HStack {
                            Text(DateKey.formatMonth(store.selectedMonth, language: lang))
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.softFill, in: Capsule())
                            Spacer()
                        }

                        if existing == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(L10n.text(lang, en: "Category", vi: "Danh mục", zh: "分类"))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                                    ForEach(availableCategories) { item in
                                        let selected = category == item
                                        Button {
                                            withAnimation(.snappy(duration: 0.16)) {
                                                category = item
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                CozyCategoryIcon(
                                                    category: item,
                                                    size: 18,
                                                    style: selected ? .tinted(Color.onInk) : .watercolor
                                                )
                                                Text(item.title(in: lang))
                                                    .font(.appCaption.weight(.medium))
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 10)
                                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                            .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                            .background(selected ? Color.ink : Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                        }
                                        .buttonStyle(.themedPlain)
                                    }
                                }
                            }
                        } else if let existing {
                            Card {
                                HStack(spacing: 12) {
                                    CategoryBadge(category: existing.category, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(existing.category.title(in: lang))
                                            .font(.appHeading)
                                        Text(L10n.text(lang, en: "Monthly spending limit", vi: "Hạn mức chi tiêu tháng", zh: "每月支出限额"))
                                            .font(.appCaption)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }

                AmountKeypadView(
                    engine: $keypad,
                    currency: settings.currency,
                    language: lang,
                    saveTitle: saveButtonTitle(amountMajor: liveAmount, lang: lang),
                    isSaveEnabled: canSave,
                    onSave: save
                )
            }
            .pageBackground()
            .keypadKeyboardInput(engine: $keypad, isEnabled: true, isSaveEnabled: canSave, onSave: save)
            .navigationTitle(existing == nil
                ? L10n.text(lang, en: "Set budget", vi: "Đặt ngân sách", zh: "设置预算")
                : L10n.text(lang, en: "Edit budget", vi: "Sửa ngân sách", zh: "编辑预算"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
                if existing != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            CozyUIIcon(.trash, size: 18, color: Color.negative)
                        }
                        .accessibilityLabel(L10n.text(lang, en: "Remove budget", vi: "Xoá hạn mức", zh: "删除预算"))
                    }
                }
            }
            .confirmationDialog(
                L10n.text(lang, en: "Remove this budget?", vi: "Xoá hạn mức này?", zh: "删除此预算？"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.text(lang, en: "Remove budget", vi: "Xoá hạn mức", zh: "删除预算"), role: .destructive) {
                    if let existing { store.deleteBudget(id: existing.id) }
                    dismiss()
                }
            }
            .onAppear {
                let maxDigits = settings.currency.fractionDigits
                if let existing {
                    category = existing.category
                    let major = settings.currency.toMajor(existing.limitMinor)
                    keypad = AmountKeypadEngine(initialAmountMajor: major, maxFractionDigits: maxDigits)
                } else {
                    keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: maxDigits)
                    if let first = availableCategories.first {
                        category = first
                    }
                }
            }
        }
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 640)
    }

    private func amountHeroStage(lang: AppLanguage) -> some View {
        let currency = settings.currency
        let displayNumber = keypad.formattedDisplayNumber(currency: currency)
        let isEmpty = keypad.isEmpty
        let amountColor: Color = isEmpty ? Color.textSecondary.opacity(0.38) : Color.textPrimary

        return VStack(spacing: 4) {
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
                Text(L10n.text(lang, en: "Monthly limit (\(currency.rawValue))", vi: "Hạn mức tháng (\(currency.rawValue))", zh: "每月限额（\(currency.rawValue)）"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if currency != .vnd {
                    Text(currency.narrowSymbol)
                        .font(.custom("AvenirNext-Medium", size: 26))
                        .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                }
                Text(displayNumber)
                    .font(.custom("AvenirNext-DemiBold", size: 42).monospacedDigit())
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
    }

    private var resolvedLimitMajor: Double {
        max(0, keypad.evaluatedValue ?? 0)
    }

    private func saveButtonTitle(amountMajor: Double, lang: AppLanguage) -> String {
        guard amountMajor > 0 else {
            return L10n.text(lang, en: "Save budget", vi: "Lưu hạn mức", zh: "保存预算")
        }
        let formatted = MoneyFormat.format(
            minor: settings.currency.toStorageMinor(amountMajor),
            currency: settings.currency,
            language: lang
        )
        return L10n.text(lang, en: "Save · \(formatted)", vi: "Lưu · \(formatted)", zh: "保存 · \(formatted)")
    }

    private var availableCategories: [CategoryID] {
        let taken = Set(store.monthlySnapshot.budgets.map(\.category))
        let free = CategoryID.expenseCategories.filter { !taken.contains($0) }
        return free.isEmpty ? CategoryID.expenseCategories : free
    }

    private func save() {
        let major = resolvedLimitMajor
        guard major > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter a valid limit.", vi: "Nhập hạn mức hợp lệ.", zh: "请输入有效的预算金额。")
            return
        }
        let record = BudgetLimitRecord(
            monthKey: store.selectedMonth,
            category: existing?.category ?? category,
            limitMinor: settings.currency.toStorageMinor(major)
        )
        store.saveBudget(record)
        dismiss()
    }
}
