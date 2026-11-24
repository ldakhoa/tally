import AppServices
import BudgetKit
import Charts
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct OverviewView: View {
    public var onSelectTransactions: () -> Void
    public var onSelectStatistics: () -> Void
    public var onSelectBudgets: () -> Void
    public var onSelectGoals: () -> Void
    public var onSelectCommitments: () -> Void
    public var onSelectSettings: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme

    @State private var editingTransaction: TransactionRecord?
    @State private var viewportWidth: CGFloat = 0
    @State private var hoveredWeekLabel: String?

    public init(
        onSelectTransactions: @escaping () -> Void = {},
        onSelectStatistics: @escaping () -> Void = {},
        onSelectBudgets: @escaping () -> Void = {},
        onSelectGoals: @escaping () -> Void = {},
        onSelectCommitments: @escaping () -> Void = {},
        onSelectSettings: @escaping () -> Void = {}
    ) {
        self.onSelectTransactions = onSelectTransactions
        self.onSelectStatistics = onSelectStatistics
        self.onSelectBudgets = onSelectBudgets
        self.onSelectGoals = onSelectGoals
        self.onSelectCommitments = onSelectCommitments
        self.onSelectSettings = onSelectSettings
    }

    public var body: some View {
        let lang = settings.language
        let snapshot = store.snapshot

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header controls: Period switcher + Paste Alert
                    PeriodHeaderBar {
                        PasteButton(payloadType: String.self) { items in
                            if let text = items.first, !text.isEmpty {
                                Task { await quickIngestPasted(text) }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .accessibilityLabel(L10n.text(lang, en: "Paste bank alert", vi: "Dán thông báo NH", zh: "粘贴银行通知"))
                    }

                    MemberFilterBar()

                    // Auto-captured shortcut transactions waiting for review
                    if !store.pendingReviewTransactions.isEmpty {
                        pendingReviewBanner(store.pendingReviewTransactions, lang: lang)
                    }

                    // Featured Cozy Net Savings Hero Card with Puppy & Kitty Companions
                    heroSavingsCard(snapshot, lang: lang)
                        .cozyEntrance(index: 0)

                    // 3 compact metric tiles: Income, Spending, Budget Left
                    metricsRow(snapshot, lang: lang)
                        .cozyEntrance(index: 1)

                    // Installments & loans: this month's committed payments (hidden when none are active)
                    commitmentsCard(lang: lang)

                    if viewportWidth >= 780 {
                        HStack(alignment: .top, spacing: 16) {
                            cashFlowCard(snapshot, lang: lang)
                                .frame(maxWidth: .infinity)
                            spendingBreakdownCard(snapshot, lang: lang)
                                .frame(maxWidth: .infinity)
                        }
                        .cozyEntrance(index: 2)

                        HStack(alignment: .top, spacing: 16) {
                            recentTransactionsCard(snapshot, lang: lang)
                                .frame(maxWidth: .infinity)
                            goalsPreviewCard(lang: lang)
                                .frame(maxWidth: .infinity)
                        }
                        .cozyEntrance(index: 3)
                    } else {
                        // Weekly Cash Flow chart
                        cashFlowCard(snapshot, lang: lang)
                            .cozyEntrance(index: 2)

                        // Spending Breakdown donut
                        spendingBreakdownCard(snapshot, lang: lang)
                            .cozyEntrance(index: 3)

                        // Recent transactions
                        recentTransactionsCard(snapshot, lang: lang)
                            .cozyEntrance(index: 4)

                        // Savings goals preview
                        goalsPreviewCard(lang: lang)
                            .cozyEntrance(index: 5)
                    }

                    // First-run helper when completely blank
                    if store.activeTransactions.isEmpty && store.activeGoals.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(L10n.text(lang, en: "New to Tally?", vi: "Mới dùng Tally?", zh: "初次使用 Tally？"))
                                    .font(.appHeading)
                                Text(L10n.text(
                                    lang,
                                    en: "Add your first expense manually, paste a bank alert, or load sample household data to explore.",
                                    vi: "Thêm khoản chi đầu tiên, dán thông báo ngân hàng, hoặc tải dữ liệu mẫu gia đình để trải nghiệm.",
                                    zh: "手动记下第一笔支出、粘贴银行通知，或加载家庭示例数据快速体验。"
                                ))
                                .font(.appSecondary)
                                .foregroundStyle(Color.textSecondary)

                                HStack(spacing: 10) {
                                    Button(L10n.text(lang, en: "Load sample data", vi: "Tải dữ liệu mẫu", zh: "加载示例数据")) {
                                        store.loadSampleData(settings: settings)
                                    }
                                    .pillButton()

                                    Button(L10n.text(lang, en: "Smart paste", vi: "Dán thông báo", zh: "智能粘贴")) {
                                        settings.isShowingSmartCapture = true
                                    }
                                    .pillButton(prominent: true)
                                }
                            }
                        }
                    }
                }
                .documentColumn(maxWidth: 1080)
            }
            .readViewportWidth($viewportWidth)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Overview", vi: "Tổng quan", zh: "概览"))
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
        let outcome = store.saveAutoCapturedTransaction(record)
        store.ensureVisible(dayKey: outcome.saved.dayKey)
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
                        vi: "\(pending.count) giao dịch tự động chờ duyệt",
                        zh: "\(pending.count) 笔自动记录待确认"
                    ))
                    .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Tap to edit category or confirm all.",
                        vi: "Chạm để sửa danh mục hoặc xác nhận tất cả.",
                        zh: "点击可修改分类，或一键全部确认。"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(L10n.text(lang, en: "Confirm all", vi: "Duyệt hết", zh: "全部确认")) {
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
                            CozyUIIcon(.checkmarkCircle, size: 22, color: Color.positive)
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(L10n.text(lang, en: "Confirm", vi: "Xác nhận", zh: "确认"))
                    }
                }
            }
        }
    }

    // MARK: - Hero Net Savings Card (Cozy Pastel + Puppy & Kitty Companions)

    private func heroPetMood(for snapshot: MonthlySnapshot) -> PetMood {
        if snapshot.budgetTotalMinor > 0 && snapshot.budgetLeftMinor < 0 {
            return .alert
        }
        if snapshot.transactions.isEmpty {
            return .sleepy
        }
        if snapshot.netSavingsMinor > 0 && !snapshot.isSalaryMasked(hidden: settings.hideSalary) {
            return .happy
        }
        return .cozy
    }

    private func heroMoodNote(for mood: PetMood, lang: AppLanguage) -> String {
        switch mood {
        case .happy:
            return L10n.text(lang, en: "Doing great together! Tap us for hearts ✨", vi: "Hai vợ chồng tiết kiệm giỏi lắm! Chạm thả tim nè ✨", zh: "两人存钱超棒！点一点比心 ✨")
        case .alert:
            return L10n.text(lang, en: "A little over budget, let's slow down 🥺", vi: "Hơi lố ngân sách xíu rồi nha 🥺", zh: "稍微超出预算啦，放慢脚步哦 🥺")
        case .sleepy:
            return L10n.text(lang, en: "Cozy & quiet... log your first treat 🐾", vi: "Êm ấm quá... ghi khoản đầu tiên đi nè 🐾", zh: "安安静静…来记下第一笔账吧 🐾")
        case .cozy:
            return L10n.text(lang, en: "Tap us for good luck 💕", vi: "Chạm hai vợ chồng lấy hên nhé 💕", zh: "点点我们俩沾沾好运 💕")
        }
    }

    private func heroSavingsCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let mood = heroPetMood(for: snapshot)
        let netHidden = snapshot.isSalaryMasked(hidden: settings.hideSalary)
        let isDark = colorScheme == .dark
        let gradientColors: [Color] = isDark
            ? [Color(hex: 0x3A2A25), Color(hex: 0x2F2224)]
            : [Color(hex: 0xFFE9D8), Color(hex: 0xFFF5E6)]
        let borderTint: Color = isDark
            ? Color(hex: 0xF59382, alpha: 0.25)
            : Color(hex: 0xE67360, alpha: 0.22)

        return ZStack {
            PawPrintBackdrop(tint: .accent)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.appCaption)
                                .foregroundStyle(Color.accent)
                            Text(L10n.text(lang, en: "Net savings", vi: "Tiết kiệm ròng", zh: "净结余"))
                                .font(.appControl)
                                .foregroundStyle(Color.textSecondary)
                        }

                        Text(MoneyFormat.masked(MoneyFormat.format(minor: snapshot.netSavingsMinor, currency: settings.currency, language: lang), hidden: netHidden))
                            .salaryMaskAccessibility(netHidden, language: lang)
                            .font(.appMetricHero)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: snapshot.netSavingsMinor)

                        if let rate = snapshot.savingsRatePercent, !netHidden {
                            Text("✨ \(rate)% \(L10n.text(lang, en: "saved", vi: "thu nhập", zh: "结余率"))")
                                .font(.appCaption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .foregroundStyle(Color.accent)
                                .background(Color.accent.opacity(isDark ? 0.2 : 0.14), in: Capsule())
                        }
                    }

                    Spacer(minLength: 4)

                    CozyCoupleDuoView(avatarSize: 56)
                        .padding(.top, -2)
                }

                Text(heroMoodNote(for: mood, lang: lang))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)

                Divider().overlay(Color.hairlineStrong)

                HStack {
                    Button {
                        store.selectedPeriod = .today()
                        store.activityTypeFilter = .expense
                        store.activityCategoryFilter = nil
                        onSelectTransactions()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text(lang, en: "Today's spending", vi: "Chi tiêu hôm nay", zh: "今日支出"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            Text(MoneyFormat.format(minor: snapshot.todaySpendingMinor, currency: settings.currency, language: lang))
                                .font(.appHeading)
                                .foregroundStyle(Color.textPrimary)
                                .contentTransition(.numericText())
                        }
                    }
                    .buttonStyle(.themedPlain)

                    Spacer()

                    Button {
                        store.activityTypeFilter = .all
                        store.activityCategoryFilter = nil
                        onSelectTransactions()
                    } label: {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L10n.text(lang, en: "Transactions", vi: "Giao dịch", zh: "账单笔数"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            Text("\(snapshot.transactions.count)")
                                .font(.appHeading)
                                .foregroundStyle(Color.textPrimary)
                                .contentTransition(.numericText())
                        }
                    }
                    .buttonStyle(.themedPlain)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .floatingShadow(!isDark)
        }
        .overlay {
            shape.strokeBorder(borderTint, lineWidth: 1.2)
        }
        .clipShape(shape)
    }

    // MARK: - Metrics Row

    private func metricsRow(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let columnCount = viewportWidth >= 720 ? 4 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
        return LazyVGrid(columns: columns, spacing: 12) {
            metricTile(
                title: L10n.text(lang, en: "Income", vi: "Thu nhập", zh: "收入"),
                value: MoneyFormat.masked(MoneyFormat.format(minor: snapshot.incomeMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd && snapshot.incomeMinor >= 100_000_000_00), hidden: snapshot.isSalaryMasked(hidden: settings.hideSalary)),
                note: L10n.text(lang, en: "Received", vi: "Đã nhận", zh: "已入账"),
                icon: .income,
                isIncome: true
            ) {
                store.activityTypeFilter = .income
                store.activityCategoryFilter = nil
                onSelectTransactions()
            }
            metricTile(
                title: L10n.text(lang, en: "Spending", vi: "Chi tiêu", zh: "支出"),
                value: MoneyFormat.format(minor: snapshot.spendingMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd && snapshot.spendingMinor >= 100_000_000_00),
                note: snapshot.period.isFullMonth
                    ? L10n.text(lang, en: "Spent this month", vi: "Chi trong tháng", zh: "本月已花")
                    : snapshot.period.formattedTitle(language: lang),
                icon: .spending
            ) {
                store.activityTypeFilter = .expense
                store.activityCategoryFilter = nil
                onSelectTransactions()
            }
            metricTile(
                title: snapshot.budgetLeftMinor < 0
                    ? L10n.text(lang, en: "Over budget", vi: "Vượt ngân sách", zh: "已超预算")
                    : L10n.text(lang, en: "Budget left", vi: "Ngân sách còn", zh: "剩余预算"),
                value: snapshot.budgetTotalMinor > 0
                    ? MoneyFormat.format(minor: abs(snapshot.budgetLeftMinor), currency: settings.currency, language: lang, compact: settings.currency == .vnd && abs(snapshot.budgetLeftMinor) >= 100_000_000_00)
                    : "—",
                note: snapshot.budgetTotalMinor > 0
                    ? "\(L10n.text(lang, en: "of", vi: "trên", zh: "共")) \(MoneyFormat.format(minor: snapshot.budgetTotalMinor, currency: settings.currency, language: lang, compact: true))"
                    : L10n.text(lang, en: "Set limits in Budgets", vi: "Đặt hạn mức", zh: "去设置预算"),
                icon: .budget
            ) {
                onSelectBudgets()
            }
            metricTile(
                title: L10n.text(lang, en: "Household", vi: "Gia đình", zh: "家庭"),
                value: "\(max(1, snapshot.memberBreakdown.count))",
                note: snapshot.memberBreakdown.map { $0.memberName.isEmpty ? "—" : $0.memberName }.joined(separator: " · "),
                icon: .household
            ) {
                onSelectSettings()
            }
        }
    }

    private func metricTile(title: String, value: String, note: String, icon: CozyMetricIconKind, isIncome: Bool = false, action: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            metricTileButton(title: title, value: value, note: note, icon: icon, isIncome: isIncome, action: action)
            if isIncome {
                hideSalaryToggle
                    .padding(.top, 14)
                    .padding(.trailing, 12)
            }
        }
    }

    /// Hand-drawn eye / eye-closed privacy toggle that masks salary and the figures that include it.
    /// Revealing asks for Face ID / passcode when that requirement is on; hiding never does.
    private var hideSalaryToggle: some View {
        let lang = settings.language
        let hidden = settings.hideSalary
        return Button {
            CozyHaptics.light()
            Task {
                await settings.toggleSalaryVisibility()
            }
        } label: {
            CozyUIIcon(hidden ? .eyeClosed : .eye, size: 20, color: Color.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
        .accessibilityLabel(hidden
            ? L10n.text(lang, en: "Show salary", vi: "Hiện lương", zh: "显示工资")
            : L10n.text(lang, en: "Hide salary", vi: "Ẩn lương", zh: "隐藏工资"))
    }

    private func metricTileButton(title: String, value: String, note: String, icon: CozyMetricIconKind, isIncome: Bool, action: @escaping () -> Void) -> some View {
        Button {
            CozyHaptics.light()
            CozySounds.play(.pop)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    CozyMetricIcon(kind: icon, size: 36)
                    Text(title)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if isIncome {
                        Color.clear.frame(width: 32, height: 12)
                    } else {
                        CozyUIIcon(.chevronRight, size: 12, color: Color.textSecondary.opacity(0.55))
                    }
                }
                Text(value)
                    .salaryMaskAccessibility(value == MoneyFormat.hiddenPlaceholder, language: settings.language)
                    .font(.appMetric)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(note.isEmpty ? " " : note)
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.cozyCard)
    }

    // MARK: - Cash Flow Chart

    private func cashFlowCard(_ snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let incomeLabel = L10n.text(lang, en: "Income", vi: "Thu", zh: "收入")
        let spendLabel = L10n.text(lang, en: "Spending", vi: "Chi", zh: "支出")
        let hideSalary = settings.hideSalary
        // Only weeks whose income includes salary lose their income bar; others are drawn.
        let plottedIncomeBins = snapshot.weeklyCashFlow.filter { !$0.isSalaryMasked(hidden: hideSalary) }

        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Cash flow", vi: "Dòng tiền", zh: "现金流"))
                        .font(.appHeading)
                    Text(snapshot.period.isFullMonth
                         ? L10n.text(lang, en: "Weekly income vs. spending", vi: "Thu & chi theo tuần", zh: "每周收支对比")
                         : L10n.text(lang, en: "Income vs. spending", vi: "Thu & chi trong kỳ", zh: "本期收支对比"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if !plottedIncomeBins.isEmpty {
                        legendDot(color: Color.positive.opacity(0.7), label: incomeLabel)
                    }
                    legendDot(color: Color.ink, label: spendLabel)
                }
            }

            Chart {
                ForEach(snapshot.weeklyCashFlow) { bin in
                    let isDimmed = hoveredWeekLabel != nil && hoveredWeekLabel != bin.label

                    // A week whose income includes hidden salary is left out of the chart data so
                    // the bar height and axis scale cannot reveal it.
                    if !bin.isSalaryMasked(hidden: hideSalary) {
                        BarMark(
                            x: .value("Week", bin.label),
                            y: .value(incomeLabel, settings.currency.toMajor(bin.incomeMinor))
                        )
                        .foregroundStyle(Color.positive.opacity(isDimmed ? 0.28 : 0.75))
                        .cornerRadius(4)
                        .position(by: .value("Kind", incomeLabel))
                    }

                    BarMark(
                        x: .value("Week", bin.label),
                        y: .value(spendLabel, settings.currency.toMajor(bin.spendingMinor))
                    )
                    .foregroundStyle(Color.ink.opacity(isDimmed ? 0.36 : 1.0))
                    .cornerRadius(4)
                    .position(by: .value("Kind", spendLabel))
                }
            }
            .chartXSelection(value: $hoveredWeekLabel)
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
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let selectedLabel = hoveredWeekLabel,
                       let idx = snapshot.weeklyCashFlow.firstIndex(where: { $0.label == selectedLabel }),
                       let plotAnchor = proxy.plotFrame {
                        let bin = snapshot.weeklyCashFlow[idx]
                        let plotRect = geo[plotAnchor]
                        let fallbackX = (CGFloat(idx) + 0.5) / CGFloat(max(1, snapshot.weeklyCashFlow.count)) * plotRect.width
                        let posX = proxy.position(forX: selectedLabel) ?? fallbackX
                        let rawX = plotRect.minX + posX
                        let halfW: CGFloat = 78
                        let clampedX = min(max(rawX, min(plotRect.midX, plotRect.minX + halfW)), max(plotRect.midX, plotRect.maxX - halfW))

                        ZStack(alignment: .topLeading) {
                            Path { path in
                                path.move(to: CGPoint(x: rawX, y: plotRect.minY))
                                path.addLine(to: CGPoint(x: rawX, y: plotRect.maxY))
                            }
                            .stroke(Color.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                            cashFlowTooltipCard(
                                title: bin.label,
                                incomeLabel: incomeLabel,
                                incomeText: MoneyFormat.masked(MoneyFormat.format(
                                    minor: bin.incomeMinor,
                                    currency: settings.currency,
                                    language: lang,
                                    signed: bin.incomeMinor > 0
                                ), hidden: bin.isSalaryMasked(hidden: hideSalary)),
                                spendLabel: spendLabel,
                                spendText: MoneyFormat.format(
                                    minor: bin.spendingMinor,
                                    currency: settings.currency,
                                    language: lang
                                )
                            )
                            .position(x: clampedX, y: plotRect.minY + 26)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 10)
            .frame(height: 185)
            .onChange(of: hoveredWeekLabel) { _, newValue in
                if newValue != nil {
                    CozyHaptics.selection()
                    CozySounds.play(.tick)
                }
            }
        }
    }

    private func cashFlowTooltipCard(
        title: String,
        incomeLabel: String,
        incomeText: String,
        spendLabel: String,
        spendText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Circle().fill(Color.positive).frame(width: 6, height: 6)
                Text(incomeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                Text(incomeText)
                    .salaryMaskAccessibility(incomeText == MoneyFormat.hiddenPlaceholder, language: settings.language)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            .lineLimit(1)

            HStack(spacing: 6) {
                Circle().fill(Color.ink).frame(width: 6, height: 6)
                Text(spendLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                Text(spendText)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Color.cardBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.hairlineStrong, lineWidth: 1)
        )
        .shadow(color: Color(hex: 0x6B4423, alpha: 0.12), radius: 6, y: 2)
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
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Spending breakdown", vi: "Phân bổ chi tiêu", zh: "支出分布"))
                        .font(.appHeading)
                    Text(L10n.text(lang, en: "Where your money went", vi: "Tiền đã đi về đâu", zh: "钱都花去哪儿了"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(action: onSelectStatistics) {
                    CozyUIIcon(.arrowRight, size: 15, color: Color.textPrimary)
                }
                .buttonStyle(IconButtonStyle(filled: true))
                .accessibilityLabel(L10n.text(lang, en: "View statistics", vi: "Xem thống kê", zh: "查看统计"))
            }

            if snapshot.categoryBreakdown.isEmpty {
                Text(L10n.text(lang, en: "Expenses will appear here as you record them.", vi: "Chi tiêu sẽ hiển thị tại đây khi bạn ghi nhận.", zh: "记账后，支出分布会显示在这里。"))
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
                            Text(L10n.text(lang, en: "Spent", vi: "Tổng chi", zh: "总支出"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(snapshot.categoryBreakdown.prefix(5)) { item in
                            Button {
                                store.activityTypeFilter = .expense
                                store.activityCategoryFilter = item.category
                                onSelectTransactions()
                            } label: {
                                HStack(spacing: 7) {
                                    CategoryBadge(category: item.category, size: 22)
                                    Text(item.category.title(in: lang))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(MoneyFormat.format(minor: item.spentMinor, currency: settings.currency, language: lang, compact: settings.currency == .vnd))
                                        .font(.appCaption.weight(.semibold))
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.themedPlain)
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
                L10n.text(lang, en: "Recent transactions", vi: "Giao dịch gần đây", zh: "近期账单"),
                actionLabel: L10n.text(lang, en: "All transactions", vi: "Tất cả giao dịch", zh: "全部账单"),
                action: onSelectTransactions
            )

            if snapshot.transactions.isEmpty {
                EmptyStateCard(
                    symbol: "list.bullet.rectangle",
                    title: snapshot.period.isFullMonth
                        ? L10n.text(lang, en: "No transactions this month", vi: "Chưa có giao dịch tháng này", zh: "本月暂无账单")
                        : L10n.text(lang, en: "No transactions in this period", vi: "Chưa có giao dịch trong kỳ này", zh: "本期暂无账单"),
                    message: L10n.text(lang, en: "Add an expense or connect Apple Shortcuts to capture automatically.", vi: "Thêm khoản chi hoặc kết nối Phím tắt Apple để tự động ghi nhận.", zh: "手动记一笔支出，或连接 Apple 快捷指令自动记账。"),
                    actionTitle: L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch", zh: "记一笔")
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

    @ViewBuilder
    private func commitmentsCard(lang: AppLanguage) -> some View {
        let overview = CommitmentsOverview(plans: store.activePlans, todayKey: DateKey.dayKey(from: Date()))
        if !overview.active.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(
                    L10n.text(lang, en: "Commitments", vi: "Khoản cam kết", zh: "分期与贷款"),
                    actionLabel: L10n.text(lang, en: "All commitments", vi: "Tất cả khoản cam kết", zh: "全部分期与贷款"),
                    action: onSelectCommitments
                )

                Button {
                    CozyHaptics.light()
                    onSelectCommitments()
                } label: {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 16) {
                            commitmentStat(
                                title: L10n.text(lang, en: "This month", vi: "Tháng này", zh: "本月应还"),
                                minor: overview.committedThisMonthMinor,
                                lang: lang
                            )
                            commitmentStat(
                                title: L10n.text(lang, en: "Remaining debt", vi: "Dư nợ còn lại", zh: "剩余债务"),
                                minor: overview.remainingDebtMinor,
                                lang: lang
                            )
                        }

                        if let next = overview.nextPayment {
                            Divider().overlay(Color.hairline)
                            HStack(spacing: 10) {
                                CategoryBadge(category: next.plan.category, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(L10n.text(lang, en: "Next payment", vi: "Kỳ tiếp theo", zh: "下期还款"))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(next.plan.name)
                                        .font(.appBodyMedium)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(MoneyFormat.format(minor: next.payment.amountMinor, currency: settings.currency, language: lang))
                                        .font(.appAmount)
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Text(DateKey.formatCompactDay(next.payment.dayKey, language: lang))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.themedPlain)
                .accessibilityHint(L10n.text(lang, en: "Opens commitments", vi: "Mở khoản cam kết", zh: "打开分期与贷款"))
            }
            .cozyEntrance(index: 2)
        }
    }

    private func commitmentStat(title: String, minor: Int64, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
            Text(MoneyFormat.format(minor: minor, currency: settings.currency, language: lang))
                .font(.appMetric)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goalsPreviewCard(lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(
                L10n.text(lang, en: "Savings goals", vi: "Mục tiêu tiết kiệm", zh: "存钱目标"),
                actionLabel: L10n.text(lang, en: "All goals", vi: "Tất cả mục tiêu", zh: "全部目标"),
                action: onSelectGoals
            )

            if store.activeGoals.isEmpty {
                Card {
                    Text(L10n.text(lang, en: "No savings goals yet. Set a target in Goals.", vi: "Chưa có mục tiêu tiết kiệm nào.", zh: "还没有存钱目标，去“目标”里创建一个吧。"))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                Card {
                    VStack(spacing: 14) {
                        ForEach(Array(store.activeGoals.prefix(3).enumerated()), id: \.element.id) { idx, goal in
                            if idx > 0 { Divider().overlay(Color.hairline) }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    GoalBadge(icon: goal.icon, size: 26)
                                    Text(goal.name)
                                        .font(.appBodyMedium)
                                    Spacer()
                                    Tag(text: "\(goal.percent)%", color: goal.icon.color)
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
