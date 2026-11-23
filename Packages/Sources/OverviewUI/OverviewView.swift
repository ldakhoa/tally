import AppServices
import BudgetKit
import Charts
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct OverviewView: View {
    public var onSelectTransactions: () -> Void
    public var onSelectGoals: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var editingTransaction: TransactionRecord?

    public init(onSelectTransactions: @escaping () -> Void = {}, onSelectGoals: @escaping () -> Void = {}) {
        self.onSelectTransactions = onSelectTransactions
        self.onSelectGoals = onSelectGoals
    }

    public var body: some View {
        let lang = settings.language
        let snapshot = store.snapshot

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header controls: Period switcher + Paste Alert + Add
                    PeriodHeaderBar {
                        PasteButton(payloadType: String.self) { items in
                            if let text = items.first, !text.isEmpty {
                                Task { await quickIngestPasted(text) }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel(L10n.text(lang, en: "Paste bank alert", vi: "Dán thông báo NH"))

                        Button {
                            settings.isShowingQuickAdd = true
                        } label: {
                            Label(L10n.text(lang, en: "Add", vi: "Thêm"), systemImage: "plus")
                        }
                        .pillButton(prominent: true)
                    }

                    MemberFilterBar()

                    // Auto-captured shortcut transactions waiting for review
                    if !store.pendingReviewTransactions.isEmpty {
                        pendingReviewBanner(store.pendingReviewTransactions, lang: lang)
                    }

                    // Featured Net Savings Hero Card (Onsite Ink surface)
                    heroSavingsCard(snapshot, lang: lang)

                    // 3 compact metric tiles: Income, Spending, Budget Left
                    metricsRow(snapshot, lang: lang)

                    // Weekly Cash Flow chart
                    cashFlowCard(snapshot, lang: lang)

                    // Spending Breakdown donut
                    spendingBreakdownCard(snapshot, lang: lang)

                    // Recent transactions
                    recentTransactionsCard(snapshot, lang: lang)

                    // Savings goals preview
                    goalsPreviewCard(lang: lang)

                    // First-run helper when completely blank
                    if store.activeTransactions.isEmpty && store.activeGoals.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.text(lang, en: "New to Tally?", vi: "Mới dùng Tally?"))
                                    .font(.appHeading)
                                Text(L10n.text(
                                    lang,
                                    en: "Add your first expense manually, paste a bank alert, or load sample household data to explore.",
                                    vi: "Thêm khoản chi đầu tiên, dán thông báo ngân hàng, hoặc tải dữ liệu mẫu gia đình để trải nghiệm."
                                ))
                                .font(.appSecondary)
                                .foregroundStyle(Color.textSecondary)

                                HStack(spacing: 10) {
                                    Button(L10n.text(lang, en: "Load sample data", vi: "Tải dữ liệu mẫu")) {
                                        store.loadSampleData(settings: settings)
                                    }
                                    .pillButton()

                                    Button(L10n.text(lang, en: "Smart paste", vi: "Dán thông báo")) {
                                        settings.isShowingSmartCapture = true
                                    }
                                    .pillButton(prominent: true)
                                }
                            }
                        }
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Overview", vi: "Tổng quan"))
            .toolbar { TopToolbarControls() }
            .sheet(item: $editingTransaction) { tx in
                TransactionEditorSheet(existing: tx)
            }
        }
    }

    private func quickIngestPasted(_ text: String) async {
        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
        guard let parsed = await AITransactionParser.parse(
            text: text,
            source: .bankNotification,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        ) else {
            settings.isShowingSmartCapture = true
            return
        }
        let member = settings.currentMember
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: parsed,
            targetCurrency: settings.currency,
            language: settings.language
        )
        let record = TransactionRecord(
            name: parsed.name,
            amountMinor: max(1, resolved.amountMinor),
            type: parsed.type,
            category: parsed.category,
            dayKey: parsed.dayKey,
            note: resolved.note,
            source: parsed.parsedByAI ? .aiQuickAdd : .bankNotification,
            rawSourceText: text,
            memberID: member.id,
            memberName: member.name,
            needsReview: true
        )
        store.saveTransaction(record)
        store.ensureVisible(dayKey: record.dayKey)
    }

    // MARK: - Pending Review Banner

    private func pendingReviewBanner(_ pending: [TransactionRecord], lang: AppLanguage) -> some View {
        Card(highlighted: true) {
            HStack(spacing: 10) {
                SettingsIconTile(symbol: "bolt.horizontal.fill", tint: .accent, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(
                        lang,
                        en: "\(pending.count) auto-captured to review",
                        vi: "\(pending.count) giao dịch tự động chờ duyệt"
                    ))
                    .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Tap to edit category or confirm all.",
                        vi: "Chạm để sửa danh mục hoặc xác nhận tất cả."
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(L10n.text(lang, en: "Confirm all", vi: "Duyệt hết")) {
                    withAnimation { store.confirmAllReviewed() }
                }
                .pillButton()
            }

            Divider().overlay(Color.hairline)

            VStack(spacing: 4) {
                ForEach(pending.prefix(3)) { tx in
                    HStack(spacing: 8) {
                        TransactionRow(transaction: tx, showDate: true) {
                            editingTransaction = tx
                        }
                        Button {
                            withAnimation { store.confirmReviewed(id: tx.id) }
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.positive)
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(L10n.text(lang, en: "Confirm", vi: "Xác nhận"))
                    }
                }
            }
        }
    }

    // MARK: - Hero Net Savings Card

    private func heroSavingsCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(
                    L10n.text(lang, en: "Net savings", vi: "Tiết kiệm ròng"),
                    systemImage: "leaf.fill"
                )
                .font(.appControl)
                .foregroundStyle(Color.onInk.opacity(0.8))

                Spacer()

                if let rate = snapshot.savingsRatePercent {
                    Text("\(rate)% \(L10n.text(lang, en: "saved", vi: "thu nhập"))")
                        .font(.appCaption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.onInk)
                        .background(Color.onInk.opacity(0.16), in: Capsule())
                }
            }

            Text(MoneyFormat.format(minor: snapshot.netSavingsMinor, currency: settings.currency, language: lang))
                .font(.appMetricHero)
                .foregroundStyle(Color.onInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Divider().overlay(Color.onInk.opacity(0.16))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Today's spending", vi: "Chi tiêu hôm nay"))
                        .font(.appCaption)
                        .foregroundStyle(Color.onInk.opacity(0.7))
                    Text(MoneyFormat.format(minor: snapshot.todaySpendingMinor, currency: settings.currency, language: lang))
                        .font(.appHeading)
                        .foregroundStyle(Color.onInk)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(L10n.text(lang, en: "Transactions", vi: "Giao dịch"))
                        .font(.appCaption)
                        .foregroundStyle(Color.onInk.opacity(0.7))
                    Text("\(snapshot.transactions.count)")
                        .font(.appHeading)
                        .foregroundStyle(Color.onInk)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color.ink))
    }

    // MARK: - Metrics Row

    private func metricsRow(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            metricTile(
                title: L10n.text(lang, en: "Income", vi: "Thu nhập"),
                value: MoneyFormat.format(minor: snapshot.incomeMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd && snapshot.incomeMinor >= 100_000_000_00),
                note: L10n.text(lang, en: "Received", vi: "Đã nhận"),
                symbol: "arrow.down.left",
                tint: .positive
            )
            metricTile(
                title: L10n.text(lang, en: "Spending", vi: "Chi tiêu"),
                value: MoneyFormat.format(minor: snapshot.spendingMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd && snapshot.spendingMinor >= 100_000_000_00),
                note: snapshot.period.isFullMonth
                    ? L10n.text(lang, en: "Spent this month", vi: "Chi trong tháng")
                    : snapshot.period.formattedTitle(language: lang),
                symbol: "arrow.up.right",
                tint: .accent
            )
            metricTile(
                title: snapshot.budgetLeftMinor < 0
                    ? L10n.text(lang, en: "Over budget", vi: "Vượt ngân sách")
                    : L10n.text(lang, en: "Budget left", vi: "Ngân sách còn"),
                value: snapshot.budgetTotalMinor > 0
                    ? MoneyFormat.format(minor: abs(snapshot.budgetLeftMinor), currency: settings.currency, language: lang, compact: settings.currency == .vnd && abs(snapshot.budgetLeftMinor) >= 100_000_000_00)
                    : "—",
                note: snapshot.budgetTotalMinor > 0
                    ? "\(L10n.text(lang, en: "of", vi: "trên")) \(MoneyFormat.format(minor: snapshot.budgetTotalMinor, currency: settings.currency, language: lang, compact: true))"
                    : L10n.text(lang, en: "Set limits in Budgets", vi: "Đặt hạn mức"),
                symbol: "creditcard",
                tint: snapshot.budgetLeftMinor < 0 ? .negative : .info
            )
            metricTile(
                title: L10n.text(lang, en: "Household", vi: "Gia đình"),
                value: "\(max(1, snapshot.memberBreakdown.count))",
                note: snapshot.memberBreakdown.map { $0.memberName.isEmpty ? "—" : $0.memberName }.joined(separator: " · "),
                symbol: "person.2.fill",
                tint: .textSecondary
            )
        }
    }

    private func metricTile(title: String, value: String, note: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsIconTile(symbol: symbol, tint: tint == .textSecondary ? nil : tint, size: 28)
                Text(title)
                    .font(.appCaption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.appMetric)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note.isEmpty ? " " : note)
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 20)
    }

    // MARK: - Cash Flow Chart

    private func cashFlowCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let incomeLabel = L10n.text(lang, en: "Income", vi: "Thu")
        let spendLabel = L10n.text(lang, en: "Spending", vi: "Chi")

        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Cash flow", vi: "Dòng tiền"))
                        .font(.appHeading)
                    Text(snapshot.period.isFullMonth
                         ? L10n.text(lang, en: "Weekly income vs. spending", vi: "Thu & chi theo tuần")
                         : L10n.text(lang, en: "Income vs. spending", vi: "Thu & chi trong kỳ"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    legendDot(color: Color.positive.opacity(0.7), label: incomeLabel)
                    legendDot(color: Color.ink, label: spendLabel)
                }
            }

            Chart {
                ForEach(snapshot.weeklyCashFlow) { bin in
                    BarMark(
                        x: .value("Week", bin.label),
                        y: .value(incomeLabel, settings.currency.toMajor(bin.incomeMinor))
                    )
                    .foregroundStyle(Color.positive.opacity(0.75))
                    .cornerRadius(4)
                    .position(by: .value("Kind", incomeLabel))

                    BarMark(
                        x: .value("Week", bin.label),
                        y: .value(spendLabel, settings.currency.toMajor(bin.spendingMinor))
                    )
                    .foregroundStyle(Color.ink)
                    .cornerRadius(4)
                    .position(by: .value("Kind", spendLabel))
                }
            }
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(MoneyFormat.format(minor: settings.currency.toStorageMinor(num), currency: settings.currency, language: lang, compact: true))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(height: 175)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.appCaption).foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Spending Breakdown Donut

    private func spendingBreakdownCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(lang, en: "Spending breakdown", vi: "Phân bổ chi tiêu"))
                    .font(.appHeading)
                Text(L10n.text(lang, en: "Where your money went", vi: "Tiền đã đi về đâu"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            if snapshot.categoryBreakdown.isEmpty {
                Text(L10n.text(lang, en: "Expenses will appear here as you record them.", vi: "Chi tiêu sẽ hiển thị tại đây khi bạn ghi nhận."))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, 12)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Chart(snapshot.categoryBreakdown.prefix(6)) { item in
                            SectorMark(
                                angle: .value("Amount", Double(item.spentMinor)),
                                innerRadius: .ratio(0.64),
                                angularInset: 1.5
                            )
                            .foregroundStyle(item.category.color)
                            .cornerRadius(4)
                        }
                        .frame(width: 126, height: 126)

                        VStack(spacing: 1) {
                            Text(MoneyFormat.format(minor: snapshot.spendingMinor, currency: settings.currency, language: lang, compact: true))
                                .font(.appControl)
                                .lineLimit(1)
                            Text(L10n.text(lang, en: "Spent", vi: "Tổng chi"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.categoryBreakdown.prefix(5)) { item in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(item.category.color)
                                    .frame(width: 8, height: 8)
                                Text(item.category.title(in: lang))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(MoneyFormat.format(minor: item.spentMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd))
                                    .font(.appCaption.weight(.semibold))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Recent Transactions & Goals Preview

    private func recentTransactionsCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                L10n.text(lang, en: "Recent activity", vi: "Giao dịch gần đây"),
                actionLabel: L10n.text(lang, en: "All transactions", vi: "Tất cả giao dịch"),
                action: onSelectTransactions
            )

            if snapshot.transactions.isEmpty {
                EmptyStateCard(
                    symbol: "list.bullet.rectangle",
                    title: snapshot.period.isFullMonth
                        ? L10n.text(lang, en: "No transactions this month", vi: "Chưa có giao dịch tháng này")
                        : L10n.text(lang, en: "No transactions in this period", vi: "Chưa có giao dịch trong kỳ này"),
                    message: L10n.text(lang, en: "Add an expense or connect Apple Shortcuts to capture automatically.", vi: "Thêm khoản chi hoặc kết nối Phím tắt Apple để tự động ghi nhận."),
                    actionTitle: L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch")
                ) {
                    settings.isShowingQuickAdd = true
                }
            } else {
                Card {
                    VStack(spacing: 2) {
                        ForEach(Array(snapshot.transactions.prefix(5).enumerated()), id: \.element.id) { index, tx in
                            if index > 0 { Divider().overlay(Color.hairline) }
                            TransactionRow(transaction: tx) {
                                editingTransaction = tx
                            }
                        }
                    }
                }
            }
        }
    }

    private func goalsPreviewCard(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                L10n.text(lang, en: "Savings goals", vi: "Mục tiêu tiết kiệm"),
                actionLabel: L10n.text(lang, en: "All goals", vi: "Tất cả mục tiêu"),
                action: onSelectGoals
            )

            if store.activeGoals.isEmpty {
                Card {
                    Text(L10n.text(lang, en: "No savings goals yet. Set a target in Goals.", vi: "Chưa có mục tiêu tiết kiệm nào."))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Card {
                    VStack(spacing: 14) {
                        ForEach(Array(store.activeGoals.prefix(3).enumerated()), id: \.element.id) { idx, goal in
                            if idx > 0 { Divider().overlay(Color.hairline) }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: goal.icon.symbol)
                                        .foregroundStyle(goal.icon.color)
                                    Text(goal.name)
                                        .font(.appBodyMedium)
                                    Spacer()
                                    Text("\(goal.percent)%")
                                        .font(.appControl)
                                }
                                TallyProgressBar(value: goal.progress, fill: goal.icon.color)
                                Text("\(MoneyFormat.format(minor: goal.savedMinor, currency: settings.currency, language: lang)) / \(MoneyFormat.format(minor: goal.targetMinor, currency: settings.currency, language: lang))")
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
