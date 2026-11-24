import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct TransactionsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var editingTransaction: TransactionRecord?
    @State private var showInlineCalendar = false
    @State private var viewportWidth: CGFloat = 0

    public init() {}

    public var body: some View {
        @Bindable var store = store
        let lang = settings.language
        let groups = filteredGroups
        let hasActiveFilter = !searchText.isEmpty
            || store.activityCategoryFilter != nil
            || store.activityTypeFilter != .all
        let selectedSingleDay: String? = {
            if case .day(let dayKey) = store.selectedPeriod { return dayKey }
            return nil
        }()

        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    PeriodHeaderBar {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                showInlineCalendar.toggle()
                            }
                        } label: {
                            CozyUIIcon(
                                showInlineCalendar ? .list : .calendar,
                                size: 16,
                                color: showInlineCalendar ? Color.onInk : Color.textPrimary
                            )
                        }
                        .pillButton(prominent: showInlineCalendar)
                        .accessibilityLabel(
                            showInlineCalendar
                                ? L10n.text(lang, en: "Hide calendar", vi: "Ẩn lịch", zh: "隐藏日历")
                                : L10n.text(lang, en: "Show calendar", vi: "Hiện lịch", zh: "显示日历")
                        )
                    }

                    if showInlineCalendar && viewportWidth >= 840 {
                        unifiedFilterBar(lang: lang)
                        MemberFilterBar()

                        HStack(alignment: .top, spacing: 18) {
                            calendarCard(selectedSingleDay: selectedSingleDay, lang: lang)
                                .frame(width: 320)

                            transactionListContent(groups: groups, hasActiveFilter: hasActiveFilter, lang: lang)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        if showInlineCalendar {
                            calendarCard(selectedSingleDay: selectedSingleDay, lang: lang)
                        }

                        // Single unified filter strip: Type menu pill + Category chips
                        unifiedFilterBar(lang: lang)

                        MemberFilterBar()

                        transactionListContent(groups: groups, hasActiveFilter: hasActiveFilter, lang: lang)
                    }
                }
                .documentColumn(maxWidth: 1000)
            }
            .readViewportWidth($viewportWidth)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Transactions", vi: "Giao dịch", zh: "账单"))
            .searchable(text: $searchText, prompt: L10n.text(lang, en: "Search merchant, category, note", vi: "Tìm cửa hàng, danh mục, ghi chú", zh: "搜索商户、分类或备注"))
            .toolbar { TopToolbarControls() }
            .sheet(item: $editingTransaction) { tx in
                TransactionEditorSheet(existing: tx)
            }
            .onChange(of: store.activityTypeFilter) { _, _ in
                if let current = store.activityCategoryFilter, !filterCategories.contains(current) {
                    store.activityCategoryFilter = nil
                }
            }
        }
    }

    // MARK: - Calendar & List Subviews

    private func calendarCard(selectedSingleDay: String?, lang: AppLanguage) -> some View {
        InlineMonthCalendarCard(
            monthKey: store.selectedMonth,
            selectedDayKey: selectedSingleDay,
            language: lang,
            currency: settings.currency,
            dailyTotals: store.dailyCalendarTotals,
            onSelectDay: { dayKey in
                withAnimation(.snappy(duration: 0.18)) {
                    if selectedSingleDay == dayKey {
                        store.selectedPeriod = .month(DateKey.monthKey(fromDayKey: dayKey))
                    } else {
                        store.selectedPeriod = .day(dayKey)
                    }
                }
            },
            onSelectFullMonth: {
                withAnimation(.snappy(duration: 0.18)) {
                    store.selectedPeriod = .month(store.selectedMonth)
                }
            }
        )
    }

    @ViewBuilder
    private func transactionListContent(groups: [DailyTransactionGroup], hasActiveFilter: Bool, lang: AppLanguage) -> some View {
        if groups.isEmpty {
            EmptyStateCard(
                symbol: "tray",
                title: hasActiveFilter
                    ? L10n.text(lang, en: "No matching transactions", vi: "Không tìm thấy giao dịch phù hợp", zh: "没有匹配的账单")
                    : L10n.text(lang, en: "No transactions yet", vi: "Chưa có giao dịch nào", zh: "暂无账单"),
                message: hasActiveFilter
                    ? L10n.text(lang, en: "Try another search term or clear active filters.", vi: "Thử từ khoá khác hoặc xoá bộ lọc đang chọn.", zh: "尝试其他关键词或清除当前筛选。")
                    : L10n.text(lang, en: "Add a transaction or paste a bank notification.", vi: "Thêm giao dịch hoặc dán thông báo ngân hàng.", zh: "记一笔账单或粘贴银行通知。"),
                actionTitle: hasActiveFilter
                    ? L10n.text(lang, en: "Clear filters", vi: "Xoá bộ lọc", zh: "清除筛选")
                    : L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch", zh: "记一笔")
            ) {
                if hasActiveFilter {
                    withAnimation(.snappy(duration: 0.18)) {
                        searchText = ""
                        store.activityTypeFilter = .all
                        store.activityCategoryFilter = nil
                    }
                } else {
                    settings.isShowingQuickAdd = true
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            SectionLabel(DateKey.formatShortDay(group.dayKey, language: lang))
                            Spacer()
                            if group.totalIncomeMinor > 0 {
                                Text(MoneyFormat.format(minor: group.totalIncomeMinor, currency: settings.currency, language: lang, signed: true))
                                    .font(.appCaption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.positive)
                            }
                            if group.totalSpendingMinor > 0 {
                                Text("−\(MoneyFormat.format(minor: group.totalSpendingMinor, currency: settings.currency, language: lang))")
                                    .font(.appCaption.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 4)

                        Card {
                            VStack(spacing: 2) {
                                ForEach(Array(group.transactions.enumerated()), id: \.element.id) { idx, tx in
                                    if idx > 0 { Divider().overlay(Color.hairline) }
                                    TransactionRow(transaction: tx, showDate: false) {
                                        editingTransaction = tx
                                    }
                                    .contextMenu {
                                        if tx.needsReview {
                                            Button {
                                                store.confirmReviewed(id: tx.id)
                                            } label: {
                                                Label(L10n.text(lang, en: "Mark reviewed", vi: "Xác nhận", zh: "标记已核对"), systemImage: "checkmark.circle")
                                            }
                                        }
                                        Button {
                                            editingTransaction = tx
                                        } label: {
                                            Label(L10n.text(lang, en: "Edit", vi: "Chỉnh sửa", zh: "编辑"), systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            store.deleteTransaction(id: tx.id)
                                        } label: {
                                            Label(L10n.text(lang, en: "Delete", vi: "Xoá", zh: "删除"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Unified Filter Bar (Type Menu + Category Chips in 1 row)

    private func typeFilterLabel(_ option: ActivityTypeFilter, lang: AppLanguage) -> String {
        switch option {
        case .all: return L10n.text(lang, en: "All", vi: "Tất cả", zh: "全部")
        case .expense: return L10n.text(lang, en: "Expenses", vi: "Chi tiêu", zh: "支出")
        case .income: return L10n.text(lang, en: "Income", vi: "Thu nhập", zh: "收入")
        case .auto: return L10n.text(lang, en: "Auto", vi: "Tự động", zh: "自动")
        }
    }

    @ViewBuilder
    private func typeFilterIcon(_ option: ActivityTypeFilter, isSelected: Bool) -> some View {
        switch option {
        case .all:
            CozyUIIcon(.sparkles, size: 13, color: isSelected ? Color.onInk : Color.accent)
        case .expense:
            CozyCategoryIcon(
                category: .shopping,
                size: 15,
                style: isSelected ? .tinted(Color.onInk) : .watercolor
            )
        case .income:
            CozyCategoryIcon(
                category: .salary,
                size: 15,
                style: isSelected ? .tinted(Color.onInk) : .watercolor
            )
        case .auto:
            CozyUIIcon(.bolt, size: 13, color: isSelected ? Color.onInk : Color.accent)
        }
    }

    private var filterCategories: [CategoryID] {
        switch store.activityTypeFilter {
        case .expense:
            return CategoryID.expenseCategories
        case .income:
            return CategoryID.incomeCategories
        case .all, .auto:
            return CategoryID.expenseCategories + CategoryID.incomeCategories
        }
    }

    private func unifiedFilterBar(lang: AppLanguage) -> some View {
        let categories = filterCategories
        let isTypeFiltered = store.activityTypeFilter != .all
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Compact Type dropdown pill
                    Menu {
                        ForEach(ActivityTypeFilter.allCases) { option in
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    store.activityTypeFilter = option
                                }
                            } label: {
                                if store.activityTypeFilter == option {
                                    Label(typeFilterLabel(option, lang: lang), systemImage: "checkmark")
                                } else {
                                    Text(typeFilterLabel(option, lang: lang))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            typeFilterIcon(store.activityTypeFilter, isSelected: isTypeFiltered)
                            Text(typeFilterLabel(store.activityTypeFilter, lang: lang))
                                .font(.appCaption.weight(.semibold))
                                .lineLimit(1)
                            CozyUIIcon(
                                .chevronDown,
                                size: 12,
                                color: isTypeFiltered ? Color.onInk.opacity(0.8) : Color.textSecondary
                            )
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .foregroundStyle(isTypeFiltered ? Color.onInk : Color.textPrimary)
                        .background {
                            Capsule()
                                .fill(isTypeFiltered ? Color.ink : Color.cardBackground)
                                .floatingShadow(colorScheme == .light && !isTypeFiltered)
                        }
                        .overlay {
                            if !isTypeFiltered && colorScheme != .light {
                                Capsule().strokeBorder(Color.hairlineStrong, lineWidth: 1)
                            }
                        }
                    }

                    Rectangle()
                        .fill(Color.hairlineStrong)
                        .frame(width: 1, height: 18)

                    categoryChip(
                        id: "__all__",
                        category: nil,
                        title: L10n.text(lang, en: "All", vi: "Mọi mục", zh: "全部"),
                        isSelected: store.activityCategoryFilter == nil
                    ) {
                        withAnimation(.snappy(duration: 0.18)) {
                            store.activityCategoryFilter = nil
                        }
                    }

                    ForEach(categories) { cat in
                        let isSelected = store.activityCategoryFilter == cat
                        categoryChip(
                            id: cat.rawValue,
                            category: cat,
                            title: cat.title(in: lang),
                            isSelected: isSelected
                        ) {
                            withAnimation(.snappy(duration: 0.18)) {
                                store.activityCategoryFilter = isSelected ? nil : cat
                            }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
            .accessibilityLabel(L10n.text(lang, en: "Filter transactions", vi: "Lọc giao dịch", zh: "筛选账单"))
            .onChange(of: store.activityCategoryFilter) { _, newCat in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(newCat?.rawValue ?? "__all__", anchor: .center)
                }
            }
            .onAppear {
                if let selected = store.activityCategoryFilter {
                    proxy.scrollTo(selected.rawValue, anchor: .center)
                }
            }
        }
    }

    private func categoryChip(
        id: String,
        category: CategoryID?,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let floats = colorScheme == .light && !isSelected
        return Button(action: action) {
            HStack(spacing: 6) {
                if let category {
                    CozyCategoryIcon(
                        category: category,
                        size: 16,
                        style: isSelected ? .tinted(Color.onInk) : .watercolor
                    )
                } else {
                    CozyUIIcon(.sparkles, size: 14, color: isSelected ? Color.onInk : Color.accent)
                }
                Text(title)
                    .font(.appCaption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
            .background {
                Capsule()
                    .fill(isSelected ? Color.ink : Color.cardBackground)
                    .floatingShadow(floats)
            }
            .overlay {
                if !isSelected && !floats {
                    Capsule().strokeBorder(Color.hairlineStrong, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.themedPlain)
        .id(id)
    }

    private var filteredGroups: [DailyTransactionGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = store.snapshot.transactions.filter { tx in
            switch store.activityTypeFilter {
            case .all: break
            case .expense: if tx.type != .expense { return false }
            case .income: if tx.type != .income { return false }
            case .auto: if !tx.source.isAutomatic { return false }
            }
            if let cat = store.activityCategoryFilter, tx.category != cat {
                return false
            }
            guard !query.isEmpty else { return true }
            let haystack = "\(tx.name) \(tx.category.title(in: settings.language)) \(tx.note) \(tx.memberName)".lowercased()
            return haystack.contains(query)
        }
        return MonthlySnapshot.groupByDay(base)
    }
}
