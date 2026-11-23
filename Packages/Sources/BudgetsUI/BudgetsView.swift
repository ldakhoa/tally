import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct BudgetsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewBudget = false
    @State private var editingBudget: BudgetLimitRecord?

    public init() {}

    public var body: some View {
        let lang = settings.language
        let snapshot = store.monthlySnapshot

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PeriodHeaderBar {
                        Button {
                            showingNewBudget = true
                        } label: {
                            Label(L10n.text(lang, en: "Set limit", vi: "Đặt hạn mức"), systemImage: "plus")
                        }
                        .pillButton(prominent: true)
                    }

                    if snapshot.budgetTotalMinor > 0 {
                        let usedRatio = Double(snapshot.budgetSpentMinor) / Double(max(1, snapshot.budgetTotalMinor))
                        let isOver = snapshot.budgetLeftMinor < 0
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.text(lang, en: "Monthly budget", vi: "Tổng ngân sách tháng"))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(MoneyFormat.format(minor: snapshot.budgetSpentMinor, currency: settings.currency, language: lang))
                                        .font(.appMetric)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(isOver
                                         ? L10n.text(lang, en: "Over by", vi: "Vượt quá")
                                         : L10n.text(lang, en: "Remaining", vi: "Còn lại"))
                                        .font(.appCaption)
                                        .foregroundStyle(isOver ? Color.negative : Color.textSecondary)
                                    Text(MoneyFormat.format(minor: abs(snapshot.budgetLeftMinor), currency: settings.currency, language: lang))
                                        .font(.appHeading)
                                        .foregroundStyle(isOver ? Color.negative : Color.positive)
                                }
                            }
                            TallyProgressBar(value: usedRatio, fill: isOver ? .negative : (usedRatio > 0.85 ? .caution : .positive))
                            Text("\(L10n.text(lang, en: "Total limit:", vi: "Tổng hạn mức:")) \(MoneyFormat.format(minor: snapshot.budgetTotalMinor, currency: settings.currency, language: lang))")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if snapshot.budgets.isEmpty {
                        EmptyStateCard(
                            symbol: "chart.pie",
                            title: L10n.text(lang, en: "No budgets for this month", vi: "Chưa đặt ngân sách tháng này"),
                            message: L10n.text(lang, en: "Set monthly limits per category like Food, Housing, or Shopping.", vi: "Đặt hạn mức tháng cho từng mục như Ăn uống, Nhà ở, Mua sắm."),
                            actionTitle: L10n.text(lang, en: "Set a budget", vi: "Đặt ngân sách")
                        ) {
                            showingNewBudget = true
                        }

                        Button {
                            _ = store.copyBudgetsFromPreviousMonth()
                        } label: {
                            Label(L10n.text(lang, en: "Copy from previous month", vi: "Sao chép từ tháng trước"), systemImage: "doc.on.doc")
                        }
                        .blockButton(prominent: false)
                    } else {
                        VStack(spacing: 12) {
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
                                                ? "\(MoneyFormat.format(minor: abs(remaining), currency: settings.currency, language: lang)) \(L10n.text(lang, en: "over budget", vi: "vượt hạn mức"))"
                                                : "\(MoneyFormat.format(minor: remaining, currency: settings.currency, language: lang)) \(L10n.text(lang, en: "left", vi: "còn lại"))"
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
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Budgets", vi: "Ngân sách"))
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

private struct BudgetEditorSheet: View {
    let existing: BudgetLimitRecord?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var category: CategoryID = .food
    @State private var limitText = ""
    @State private var errorMessage: String?

    var body: some View {
        let lang = settings.language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(DateKey.formatMonth(store.selectedMonth, language: lang))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)

                    if existing == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(L10n.text(lang, en: "Category", vi: "Danh mục"))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                                ForEach(availableCategories) { item in
                                    let selected = category == item
                                    Button {
                                        category = item
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: item.symbol)
                                                .font(.caption)
                                                .foregroundStyle(selected ? Color.onInk : item.color)
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
                        HStack(spacing: 10) {
                            CategoryBadge(category: existing.category, size: 38)
                            Text(existing.category.title(in: lang))
                                .font(.appHeading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Monthly limit (\(settings.currency.rawValue))", vi: "Hạn mức tháng (\(settings.currency.rawValue))"))
                        TextField(settings.currency.isZeroDecimal ? "5000000" : "600", text: $limitText)
                            .font(.appMetric)
                            #if os(iOS)
                            .keyboardType(settings.currency.isZeroDecimal ? .numberPad : .decimalPad)
                            #endif
                            .tallyField()
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                    }

                    Button(L10n.text(lang, en: "Save budget", vi: "Lưu hạn mức"), action: save)
                        .blockButton(prominent: true)

                    if let existing {
                        Button(L10n.text(lang, en: "Remove budget", vi: "Xoá hạn mức"), role: .destructive) {
                            store.deleteBudget(id: existing.id)
                            dismiss()
                        }
                        .blockButton(prominent: false, tint: .negative)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(existing == nil
                ? L10n.text(lang, en: "Set budget", vi: "Đặt ngân sách")
                : L10n.text(lang, en: "Edit budget", vi: "Sửa ngân sách"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) { dismiss() }
                }
            }
            .onAppear {
                if let existing {
                    category = existing.category
                    let major = settings.currency.toMajor(existing.limitMinor)
                    limitText = settings.currency.isZeroDecimal ? "\(Int64(major.rounded()))" : String(format: "%.2f", major)
                } else if let first = availableCategories.first {
                    category = first
                }
            }
        }
    }

    private var availableCategories: [CategoryID] {
        let taken = Set(store.snapshot.budgets.map(\.category))
        let free = CategoryID.expenseCategories.filter { !taken.contains($0) }
        return free.isEmpty ? CategoryID.expenseCategories : free
    }

    private func save() {
        let normalized = limitText.replacingOccurrences(of: ",", with: settings.currency.isZeroDecimal ? "" : ".")
        guard let major = Double(normalized), major > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter a valid limit.", vi: "Nhập hạn mức hợp lệ.")
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
