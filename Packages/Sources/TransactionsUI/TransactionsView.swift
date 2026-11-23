import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct TransactionsView: View {
    private enum TypeFilter: String, CaseIterable, Identifiable {
        case all, expense, income, auto
        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var searchText = ""
    @State private var typeFilter: TypeFilter = .all
    @State private var editingTransaction: TransactionRecord?

    public init() {}

    public var body: some View {
        let lang = settings.language
        let groups = filteredGroups

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PeriodHeaderBar {
                        Button {
                            settings.isShowingQuickAdd = true
                        } label: {
                            Label(L10n.text(lang, en: "Add", vi: "Thêm"), systemImage: "plus")
                        }
                        .pillButton(prominent: true)
                    }

                    // Filter chips
                    ChipPicker(
                        L10n.text(lang, en: "Filter", vi: "Bộ lọc"),
                        selection: $typeFilter,
                        options: TypeFilter.allCases,
                        sideMargin: 0
                    ) { option in
                        switch option {
                        case .all: return L10n.text(lang, en: "All", vi: "Tất cả")
                        case .expense: return L10n.text(lang, en: "Expenses", vi: "Chi tiêu")
                        case .income: return L10n.text(lang, en: "Income", vi: "Thu nhập")
                        case .auto: return L10n.text(lang, en: "Auto-captured", vi: "Tự động")
                        }
                    } symbol: { option in
                        switch option {
                        case .all: return nil
                        case .expense: return "arrow.up.right"
                        case .income: return "arrow.down.left"
                        case .auto: return "bolt.horizontal.fill"
                        }
                    }

                    MemberFilterBar()

                    if groups.isEmpty {
                        EmptyStateCard(
                            symbol: "tray",
                            title: searchText.isEmpty
                                ? L10n.text(lang, en: "No transactions yet", vi: "Chưa có giao dịch nào")
                                : L10n.text(lang, en: "No matching transactions", vi: "Không tìm thấy giao dịch phù hợp"),
                            message: searchText.isEmpty
                                ? L10n.text(lang, en: "Add a transaction or paste a bank notification.", vi: "Thêm giao dịch hoặc dán thông báo ngân hàng.")
                                : L10n.text(lang, en: "Try another search term or filter.", vi: "Thử từ khoá hoặc bộ lọc khác."),
                            actionTitle: searchText.isEmpty ? L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch") : nil
                        ) {
                            settings.isShowingQuickAdd = true
                        }
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    SectionLabel(DateKey.formatShortDay(group.dayKey, language: lang))
                                    Spacer()
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
                                                        Label(L10n.text(lang, en: "Mark reviewed", vi: "Xác nhận"), systemImage: "checkmark.circle")
                                                    }
                                                }
                                                Button {
                                                    editingTransaction = tx
                                                } label: {
                                                    Label(L10n.text(lang, en: "Edit", vi: "Chỉnh sửa"), systemImage: "pencil")
                                                }
                                                Button(role: .destructive) {
                                                    store.deleteTransaction(id: tx.id)
                                                } label: {
                                                    Label(L10n.text(lang, en: "Delete", vi: "Xoá"), systemImage: "trash")
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
            .navigationTitle(L10n.text(lang, en: "Transactions", vi: "Giao dịch"))
            .searchable(text: $searchText, prompt: L10n.text(lang, en: "Search merchant, category, note", vi: "Tìm cửa hàng, danh mục, ghi chú"))
            .toolbar { TopToolbarControls() }
            .sheet(item: $editingTransaction) { tx in
                TransactionEditorSheet(existing: tx)
            }
        }
    }

    private var filteredGroups: [DailyTransactionGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = store.snapshot.transactions.filter { tx in
            switch typeFilter {
            case .all: break
            case .expense: if tx.type != .expense { return false }
            case .income: if tx.type != .income { return false }
            case .auto: if !tx.source.isAutomatic { return false }
            }
            guard !query.isEmpty else { return true }
            let haystack = "\(tx.name) \(tx.category.title(in: settings.language)) \(tx.note) \(tx.memberName)".lowercased()
            return haystack.contains(query)
        }
        return MonthlySnapshot.groupByDay(base)
    }
}
