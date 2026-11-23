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
                VStack(alignment: .leading, spacing: 14) {
                    PeriodHeaderBar {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                showInlineCalendar.toggle()
                            }
                        } label: {
                            Image(systemName: showInlineCalendar ? "list.bullet" : "calendar")
                                .font(.appControl)
                        }
                        .pillButton(prominent: showInlineCalendar)
                        .accessibilityLabel(
                            showInlineCalendar
                                ? L10n.text(lang, en: "Hide calendar", vi: "Ẩn lịch", zh: "隐藏日历")
                                : L10n.text(lang, en: "Show calendar", vi: "Hiện lịch", zh: "显示日历")
                        )

                        Button {
                            settings.isShowingQuickAdd = true
                        } label: {
                            Label(L10n.text(lang, en: "Add", vi: "Thêm", zh: "记一笔"), systemImage: "plus")
                        }
                        .pillButton(prominent: true)
                    }

                    if showInlineCalendar {
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

                    // Transaction type filter chips
                    ChipPicker(
                        L10n.text(lang, en: "Filter", vi: "Bộ lọc", zh: "筛选"),
                        selection: $store.activityTypeFilter,
                        options: ActivityTypeFilter.allCases,
                        sideMargin: 0
                    ) { option in
                        switch option {
                        case .all: return L10n.text(lang, en: "All", vi: "Tất cả", zh: "全部")
                        case .expense: return "🛍️ " + L10n.text(lang, en: "Expenses", vi: "Chi tiêu", zh: "支出")
                        case .income: return "💰 " + L10n.text(lang, en: "Income", vi: "Thu nhập", zh: "收入")
                        case .auto: return "⚡ " + L10n.text(lang, en: "Auto-captured", vi: "Tự động", zh: "自动记录")
                        }
                    } symbol: { option in
                        option == .all ? "pawprint.fill" : nil
                    }

                    // Category filter strip (works directly inside Transactions)
                    categoryFilterBar(lang: lang)

                    MemberFilterBar()

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
                .documentColumn()
            }
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

    // MARK: - Category Filter Bar

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

    private func categoryFilterBar(lang: AppLanguage) -> some View {
        let categories = filterCategories
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(
                        id: "__all__",
                        emoji: "🏷️",
                        title: L10n.text(lang, en: "All categories", vi: "Mọi danh mục", zh: "全部分类"),
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
                            emoji: cat.cuteEmoji,
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
            .accessibilityLabel(L10n.text(lang, en: "Filter by category", vi: "Lọc theo danh mục", zh: "按分类筛选"))
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
        emoji: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let floats = colorScheme == .light && !isSelected
        return Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji)
                    .font(.system(size: 13))
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
