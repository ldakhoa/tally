import AppServices
import BudgetKit
import Charts
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct StatisticsView: View {
    public var onSelectTransactions: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    private enum KPIInspectSheet: String, Identifiable {
        case dailyAverage
        case vsPrevious
        case savingsRate
        var id: String { rawValue }
    }

    @State private var breakdownKind: TransactionType = .expense
    @State private var editingTransaction: TransactionRecord?
    @State private var activeKPISheet: KPIInspectSheet?
    @State private var viewportWidth: CGFloat = 0
    @State private var hoveredTrendMonth: String?
    @State private var hoveredDayIndex: Int?

    public init(onSelectTransactions: @escaping () -> Void = {}) {
        self.onSelectTransactions = onSelectTransactions
    }

    public var body: some View {
        let lang = settings.language
        let stats = store.statisticsSnapshot
        let hasPeriodData = !stats.current.transactions.isEmpty
        let hasAnyHistory = stats.monthlyTrend.contains { $0.transactionCount > 0 }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PeriodHeaderBar { EmptyView() }

                    MemberFilterBar()

                    if !hasPeriodData && !hasAnyHistory {
                        EmptyStateCard(
                            symbol: "chart.bar.xaxis",
                            title: L10n.text(lang, en: "No statistics yet", vi: "Chưa có dữ liệu thống kê", zh: "暂无统计数据"),
                            message: L10n.text(
                                lang,
                                en: "Record expenses or sync bank emails to see spending trends, top merchants, and weekly habits.",
                                vi: "Ghi nhận chi tiêu hoặc đồng bộ email ngân hàng để xem xu hướng, cửa hàng chi nhiều và thói quen theo tuần.",
                                zh: "记账或同步银行邮件后，即可查看消费趋势、常用商户和每周习惯。"
                            ),
                            actionTitle: L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch", zh: "记一笔")
                        ) {
                            settings.isShowingQuickAdd = true
                        }
                    } else {
                        // 1. Key highlights grid (Avg/day, vs. previous, savings rate, peak day)
                        kpiGrid(stats, lang: lang)

                        // 2. 6-month income vs. spending trend
                        monthlyTrendCard(stats, lang: lang)

                        // 3. Daily spending pace across the active period
                        if stats.dailySeries.count > 1 && stats.current.spendingMinor > 0 {
                            dailyPaceCard(stats, lang: lang)
                        }

                        // 4. Category breakdown (Expense / Income) & Weekday pattern
                        if viewportWidth >= 800 && stats.current.spendingMinor > 0 {
                            HStack(alignment: .top, spacing: 16) {
                                categoryBreakdownCard(stats, lang: lang)
                                    .frame(maxWidth: .infinity)
                                weekdayPatternCard(stats, lang: lang)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            categoryBreakdownCard(stats, lang: lang)

                            // 5. Spending by day of week
                            if stats.current.spendingMinor > 0 {
                                weekdayPatternCard(stats, lang: lang)
                            }
                        }

                        // 6. Top merchants & Largest expenses
                        if viewportWidth >= 800 && (!stats.topMerchants.isEmpty || !stats.largestExpenses.isEmpty) {
                            HStack(alignment: .top, spacing: 16) {
                                if !stats.topMerchants.isEmpty {
                                    topMerchantsCard(stats, lang: lang)
                                        .frame(maxWidth: .infinity)
                                }
                                if !stats.largestExpenses.isEmpty {
                                    largestExpensesCard(stats, lang: lang)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        } else {
                            // 6. Top merchants
                            if !stats.topMerchants.isEmpty {
                                topMerchantsCard(stats, lang: lang)
                            }

                            // 8. Largest expenses in period
                            if !stats.largestExpenses.isEmpty {
                                largestExpensesCard(stats, lang: lang)
                            }
                        }

                        // 7. Household split (when >1 member has activity)
                        if stats.current.memberBreakdown.count > 1 {
                            householdSplitCard(stats, lang: lang)
                        }
                    }
                }
                .documentColumn(maxWidth: 1080)
            }
            .readViewportWidth($viewportWidth)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Statistics", vi: "Thống kê", zh: "统计"))
            .sheet(item: $editingTransaction) { tx in
                TransactionEditorSheet(existing: tx)
            }
            .sheet(item: $activeKPISheet) { kind in
                kpiDetailSheet(kind: kind, stats: stats, lang: lang)
            }
        }
    }

    // MARK: - KPI Highlights Grid

    private func kpiGrid(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let columnCount = viewportWidth >= 720 ? 4 : 2
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
        let displayCurrency = settings.effectiveDisplayCurrency
        let compactZeroDecimal = displayCurrency.isZeroDecimal

        let deltaText: String
        let deltaTint: Color
        if let pct = stats.spendingChangePercent {
            let rounded = Int(pct.rounded())
            deltaText = rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
            deltaTint = rounded > 0 ? .accent : (rounded < 0 ? .positive : .textSecondary)
        } else {
            deltaText = "—"
            deltaTint = .textSecondary
        }

        let prevNote = stats.previousSpendingMinor > 0
            ? "\(L10n.text(lang, en: "Prev:", vi: "Kỳ trước:", zh: "上期：")) \(settings.formatMoney(minor: stats.previousSpendingMinor, compact: true))"
            : L10n.text(lang, en: "No prior data", vi: "Chưa có kỳ trước", zh: "暂无上期数据")

        let hidesNet = stats.isSalaryMasked(hidden: settings.hideSalary)
        let savingsRateText = hidesNet
            ? MoneyFormat.hiddenPlaceholder
            : (stats.current.savingsRatePercent.map { "\($0)%" } ?? "—")
        let netNote = MoneyFormat.masked(settings.formatMoney(
            minor: stats.current.netSavingsMinor,
            compact: compactZeroDecimal,
            signed: true
        ), hidden: hidesNet)
        let shownAvgDay = settings.displayMinor(stats.averageDailySpendingMinor)

        return LazyVGrid(columns: columns, spacing: 12) {
            Button {
                activeKPISheet = .dailyAverage
            } label: {
                statTileContent(
                    title: L10n.text(lang, en: "Avg / day", vi: "Chi TB / ngày", zh: "日均支出"),
                    value: MoneyFormat.format(
                        minor: shownAvgDay,
                        currency: displayCurrency,
                        language: lang,
                        compact: compactZeroDecimal && shownAvgDay >= 10_000_000_00
                    ),
                    valueColor: .textPrimary,
                    note: L10n.text(
                        lang,
                        en: "\(stats.spendingDaysCount) of \(stats.elapsedDaysCount) days",
                        vi: "\(stats.spendingDaysCount)/\(stats.elapsedDaysCount) ngày có chi",
                        zh: "\(stats.spendingDaysCount)/\(stats.elapsedDaysCount) 天有消费"
                    ),
                    symbol: "calendar.day.timeline.left",
                    tint: .info,
                    showChevron: true
                )
            }
            .buttonStyle(.themedPlain)

            Button {
                activeKPISheet = .vsPrevious
            } label: {
                statTileContent(
                    title: L10n.text(lang, en: "vs. Previous", vi: "So với kỳ trước", zh: "较上期"),
                    value: deltaText,
                    valueColor: deltaTint == .textSecondary ? .textPrimary : deltaTint,
                    note: prevNote,
                    symbol: (stats.spendingChangePercent ?? 0) > 0 ? "arrow.up.right" : "arrow.down.right",
                    tint: deltaTint,
                    showChevron: true
                )
            }
            .buttonStyle(.themedPlain)

            Button {
                activeKPISheet = .savingsRate
            } label: {
                statTileContent(
                    title: L10n.text(lang, en: "Savings rate", vi: "Tỷ lệ tiết kiệm", zh: "结余率"),
                    value: savingsRateText,
                    valueColor: hidesNet ? .textPrimary : ((stats.current.netSavingsMinor >= 0) ? .positive : .accent),
                    note: netNote,
                    symbol: "leaf.fill",
                    tint: .positive,
                    showChevron: true
                )
            }
            .buttonStyle(.themedPlain)

            Button {
                if let peak = stats.highestSpendDay {
                    store.selectedPeriod = .day(peak.dayKey)
                    store.activityTypeFilter = .expense
                    store.activityCategoryFilter = nil
                    onSelectTransactions()
                }
            } label: {
                statTileContent(
                    title: L10n.text(lang, en: "Peak day", vi: "Ngày chi cao nhất", zh: "单日最高"),
                    value: stats.highestSpendDay.map {
                        let shownPeak = settings.displayMinor($0.spendingMinor)
                        return MoneyFormat.format(
                            minor: shownPeak,
                            currency: displayCurrency,
                            language: lang,
                            compact: compactZeroDecimal && shownPeak >= 10_000_000_00
                        )
                    } ?? "—",
                    valueColor: .textPrimary,
                    note: stats.highestSpendDay.map {
                        DateKey.formatCompactDay($0.dayKey, language: lang)
                    } ?? L10n.text(lang, en: "No expenses", vi: "Chưa có chi tiêu", zh: "暂无支出"),
                    symbol: "flame.fill",
                    tint: .accent,
                    showChevron: stats.highestSpendDay != nil
                )
            }
            .buttonStyle(.themedPlain)
            .disabled(stats.highestSpendDay == nil)
        }
    }

    private func statTile(
        title: String,
        value: String,
        valueColor: Color = .textPrimary,
        note: String,
        symbol: String,
        tint: Color
    ) -> some View {
        statTileContent(
            title: title,
            value: value,
            valueColor: valueColor,
            note: note,
            symbol: symbol,
            tint: tint,
            showChevron: false
        )
    }

    private func statTileContent(
        title: String,
        value: String,
        valueColor: Color,
        note: String,
        symbol: String,
        tint: Color,
        showChevron: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SettingsIconTile(symbol: symbol, tint: tint == .textSecondary ? nil : tint, size: 28)
                Text(title)
                    .font(.appCaption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if showChevron {
                    CozyUIIcon(.chevronRight, size: 12, color: Color.textSecondary.opacity(0.55))
                }
            }
            Text(value)
                .salaryMaskAccessibility(value == MoneyFormat.hiddenPlaceholder, language: settings.language)
                .font(.appMetric)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .salaryMaskAccessibility(note == MoneyFormat.hiddenPlaceholder, language: settings.language)
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 20)
    }

    // MARK: - 6-Month Trend Card

    private func monthlyTrendCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let incomeLabel = L10n.text(lang, en: "Income", vi: "Thu", zh: "收入")
        let spendLabel = L10n.text(lang, en: "Spending", vi: "Chi", zh: "支出")
        let displayCurrency = settings.effectiveDisplayCurrency
        let activeMonths = stats.monthlyTrend.filter { $0.spendingMinor > 0 }
        let avgMonthlySpend: Int64 = activeMonths.isEmpty
            ? 0
            : activeMonths.reduce(Int64(0)) { $0 + $1.spendingMinor } / Int64(activeMonths.count)

        return Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "6-month trend", vi: "Xu hướng 6 tháng", zh: "近 6 个月趋势"))
                        .font(.appHeading)
                    Text(
                        avgMonthlySpend > 0
                            ? "\(L10n.text(lang, en: "Avg spend:", vi: "Chi TB/tháng:", zh: "月均支出：")) \(settings.formatMoney(minor: avgMonthlySpend, compact: true))"
                            : L10n.text(lang, en: "Income vs. spending by month", vi: "Thu & chi theo từng tháng", zh: "每月收支对比")
                    )
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    if stats.monthlyTrend.contains(where: { !$0.isSalaryMasked(hidden: settings.hideSalary) }) {
                        legendDot(color: Color.positive.opacity(0.75), label: incomeLabel)
                    }
                    legendDot(color: Color.ink, label: spendLabel)
                }
            }

            Chart {
                // While salary is hidden, the income bar of a month that includes salary is not part
                // of the chart data at all (not just unlabeled), so the scale cannot reveal it.
                ForEach(TrendChartBar.bars(for: stats.monthlyTrend, hideSalary: settings.hideSalary)) { bar in
                    let label = DateKey.formatShortMonth(bar.monthKey, language: lang)
                    let isDimmed = hoveredTrendMonth != nil && hoveredTrendMonth != label
                    let kindLabel = bar.kind == .income ? incomeLabel : spendLabel
                    let color: Color = bar.kind == .income
                        ? Color.positive.opacity(isDimmed ? 0.28 : 0.75)
                        : (bar.monthKey == stats.current.monthKey ? Color.accent : Color.ink).opacity(isDimmed ? 0.36 : 1.0)

                    BarMark(
                        x: .value("Month", label),
                        y: .value(kindLabel, settings.displayMajor(bar.amountMinor))
                    )
                    .foregroundStyle(color)
                    .cornerRadius(4)
                    .position(by: .value("Kind", kindLabel))
                }
            }
            .chartXSelection(value: $hoveredTrendMonth)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(MoneyFormat.format(
                                minor: displayCurrency.toStorageMinor(num),
                                currency: displayCurrency,
                                language: lang,
                                compact: true
                            ))
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
                    if let selectedLabel = hoveredTrendMonth,
                       let idx = stats.monthlyTrend.firstIndex(where: { DateKey.formatShortMonth($0.monthKey, language: lang) == selectedLabel }),
                       let plotAnchor = proxy.plotFrame {
                        let point = stats.monthlyTrend[idx]
                        let plotRect = geo[plotAnchor]
                        let fallbackX = (CGFloat(idx) + 0.5) / CGFloat(max(1, stats.monthlyTrend.count)) * plotRect.width
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

                            chartTooltipCard(
                                title: DateKey.formatMonth(point.monthKey, language: lang),
                                rows: (point.isSalaryMasked(hidden: settings.hideSalary) ? [] : [
                                    (
                                        label: incomeLabel,
                                        value: settings.formatMoney(
                                            minor: point.incomeMinor,
                                            signed: point.incomeMinor > 0
                                        ),
                                        color: Color.positive
                                    )
                                ]) + [
                                    (
                                        label: spendLabel,
                                        value: settings.formatMoney(minor: point.spendingMinor),
                                        color: Color.accent
                                    )
                                ]
                            )
                            .position(x: clampedX, y: plotRect.minY + 26)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 10)
            .frame(height: 190)
            .onChange(of: hoveredTrendMonth) { _, newValue in
                if newValue != nil {
                    CozyHaptics.selection()
                    CozySounds.play(.tick)
                }
            }

            // Quick month pills to jump into any month in the 6-month window
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(stats.monthlyTrend) { point in
                        let isSelected = store.selectedPeriod == .month(point.monthKey)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.selectedPeriod = .month(point.monthKey)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(DateKey.formatShortMonth(point.monthKey, language: lang))
                                    .font(.appCaption.weight(.semibold))
                                if point.spendingMinor > 0 {
                                    Text(settings.formatMoney(minor: point.spendingMinor, compact: true))
                                    .font(.appCaption)
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? Color.onInk.opacity(0.85) : Color.textSecondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                            .background(isSelected ? Color.ink : Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.themedPlain)
                    }
                }
            }
        }
    }

    // MARK: - Daily Spending Pace

    private func dailyPaceCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let displayCurrency = settings.effectiveDisplayCurrency
        let avgMajor = settings.displayMajor(stats.averageDailySpendingMinor)
        let avgLabel = L10n.text(lang, en: "Daily avg", vi: "TB ngày", zh: "日均")

        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Daily spending", vi: "Chi tiêu theo ngày", zh: "每日支出"))
                        .font(.appHeading)
                    Text(
                        "\(L10n.text(lang, en: "Avg per transaction:", vi: "TB mỗi giao dịch:", zh: "笔均支出：")) \(settings.formatMoney(minor: stats.averageExpenseMinor))"
                    )
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Tag(
                    text: settings.formatMoney(minor: stats.current.spendingMinor, compact: true),
                    color: .accent
                )
            }

            Chart {
                ForEach(stats.dailySeries) { point in
                    let isSelected = hoveredDayIndex == point.dayIndex
                    let isDimmed = hoveredDayIndex != nil && !isSelected
                    let baseColor = (isSelected || point.dayKey == stats.highestSpendDay?.dayKey)
                        ? Color.accent
                        : Color.ink.opacity(0.75)

                    BarMark(
                        x: .value("Day", point.dayIndex),
                        y: .value("Spend", settings.displayMajor(point.spendingMinor))
                    )
                    .foregroundStyle(baseColor.opacity(isDimmed ? 0.34 : 1.0))
                    .cornerRadius(3)
                }

                if avgMajor > 0 {
                    RuleMark(y: .value(avgLabel, avgMajor))
                        .foregroundStyle(Color.accent.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing) {
                            if hoveredDayIndex == nil {
                                Text("\(avgLabel) \(settings.formatMoney(minor: stats.averageDailySpendingMinor, compact: true))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cardBackground.opacity(0.9), in: Capsule())
                            }
                        }
                }
            }
            .chartXSelection(value: $hoveredDayIndex)
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(MoneyFormat.format(
                                minor: displayCurrency.toStorageMinor(num),
                                currency: displayCurrency,
                                language: lang,
                                compact: true
                            ))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { val in
                    AxisValueLabel {
                        if let idx = val.as(Int.self),
                           let point = stats.dailySeries.first(where: { $0.dayIndex == idx }) {
                            Text("\(DateKey.dayOfMonth(fromDayKey: point.dayKey))")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let selectedIdx = hoveredDayIndex,
                       let idx = stats.dailySeries.firstIndex(where: { $0.dayIndex == selectedIdx }),
                       let plotAnchor = proxy.plotFrame {
                        let selectedDay = stats.dailySeries[idx]
                        let plotRect = geo[plotAnchor]
                        let fallbackX = (CGFloat(idx) + 0.5) / CGFloat(max(1, stats.dailySeries.count)) * plotRect.width
                        let posX = proxy.position(forX: selectedDay.dayIndex) ?? fallbackX
                        let rawX = plotRect.minX + posX
                        let halfW: CGFloat = 78
                        let clampedX = min(max(rawX, min(plotRect.midX, plotRect.minX + halfW)), max(plotRect.midX, plotRect.maxX - halfW))
                        let rows: [(label: String, value: String, color: Color)] = {
                            var list: [(label: String, value: String, color: Color)] = [
                                (
                                    label: L10n.text(lang, en: "Spend", vi: "Chi", zh: "支出"),
                                    value: settings.formatMoney(minor: selectedDay.spendingMinor),
                                    color: .accent
                                )
                            ]
                            if selectedDay.incomeMinor > 0, !selectedDay.isSalaryMasked(hidden: settings.hideSalary) {
                                list.append((
                                    label: L10n.text(lang, en: "Income", vi: "Thu", zh: "收入"),
                                    value: settings.formatMoney(
                                        minor: selectedDay.incomeMinor,
                                        signed: true
                                    ),
                                    color: .positive
                                ))
                            }
                            return list
                        }()

                        ZStack(alignment: .topLeading) {
                            Path { path in
                                path.move(to: CGPoint(x: rawX, y: plotRect.minY))
                                path.addLine(to: CGPoint(x: rawX, y: plotRect.maxY))
                            }
                            .stroke(Color.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                            chartTooltipCard(
                                title: DateKey.formatFullDay(selectedDay.dayKey, language: lang),
                                rows: rows
                            )
                            .position(x: clampedX, y: plotRect.minY + 26)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
            .padding(.top, 10)
            .frame(height: 175)
            .onChange(of: hoveredDayIndex) { _, newValue in
                if newValue != nil {
                    CozyHaptics.selection()
                    CozySounds.play(.tick)
                }
            }
        }
    }

    private func chartTooltipCard(
        title: String,
        rows: [(label: String, value: String, color: Color)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.color)
                        .frame(width: 6, height: 6)
                    Text(row.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                    Text(row.value)
                        .salaryMaskAccessibility(row.value == MoneyFormat.hiddenPlaceholder, language: settings.language)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                }
                .lineLimit(1)
            }
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

    // MARK: - Category Breakdown

    private func categoryBreakdownCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let items = breakdownKind == .expense ? stats.current.categoryBreakdown : stats.incomeBreakdown
        let totalMinor = breakdownKind == .expense ? stats.current.spendingMinor : stats.current.incomeMinor
        // Income breakdown while salary is hidden: the salary row's amount is masked, and so is
        // the total. Shares, the donut and the bars are all ratios of that total, so they would
        // let salary be worked out from the visible non-salary rows; they are left out too.
        let hidesTotal = breakdownKind == .income && stats.isSalaryMasked(hidden: settings.hideSalary)
        let hidesShares = hidesTotal
        func hidesAmount(_ item: CategorySpend) -> Bool {
            breakdownKind == .income && item.isSalaryMasked(hidden: settings.hideSalary)
        }

        return Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "By category", vi: "Theo danh mục", zh: "按分类统计"))
                        .font(.appHeading)
                    Text(L10n.text(lang, en: "Tap a category to view transactions", vi: "Chạm danh mục để xem giao dịch", zh: "点击分类查看明细"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    ForEach(TransactionType.allCases) { kind in
                        let selected = breakdownKind == kind
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { breakdownKind = kind }
                        } label: {
                            Text(kind.title(in: lang))
                                .font(.appCaption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(selected ? Color.onInk : Color.textSecondary)
                                .background(selected ? Color.ink : Color.softFill, in: Capsule())
                        }
                        .buttonStyle(.themedPlain)
                    }
                }
            }

            if items.isEmpty {
                Text(
                    breakdownKind == .expense
                        ? L10n.text(lang, en: "No expenses in this period.", vi: "Không có chi tiêu trong kỳ này.", zh: "本期暂无支出。")
                        : L10n.text(lang, en: "No income in this period.", vi: "Không có thu nhập trong kỳ này.", zh: "本期暂无收入。")
                )
                .font(.appSecondary)
                .foregroundStyle(Color.textSecondary)
                .padding(.vertical, 8)
            } else {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        if hidesShares {
                            Circle()
                                .strokeBorder(Color.hairlineStrong, lineWidth: 14)
                                .frame(width: 120, height: 120)
                        } else {
                            Chart(items) { item in
                                SectorMark(
                                    angle: .value("Amount", Double(item.spentMinor)),
                                    innerRadius: .ratio(0.64),
                                    angularInset: 1.5
                                )
                                .foregroundStyle(item.category.color)
                                .cornerRadius(4)
                            }
                            .frame(width: 120, height: 120)
                        }

                        VStack(spacing: 1) {
                            Text(MoneyFormat.masked(settings.formatMoney(minor: totalMinor, compact: true), hidden: hidesTotal))
                                .salaryMaskAccessibility(hidesTotal, language: lang)
                                .font(.appControl)
                                .lineLimit(1)
                            Text(breakdownKind == .expense
                                 ? L10n.text(lang, en: "Spent", vi: "Tổng chi", zh: "总支出")
                                 : L10n.text(lang, en: "Earned", vi: "Tổng thu", zh: "总收入"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items.prefix(4)) { item in
                            HStack(spacing: 6) {
                                Circle().fill(item.category.color).frame(width: 8, height: 8)
                                Text(item.category.title(in: lang))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if !hidesShares {
                                    Text("\(Int((item.share * 100).rounded()))%")
                                        .font(.appCaption.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider().overlay(Color.hairline)

                VStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            store.activityTypeFilter = breakdownKind == .expense ? .expense : .income
                            store.activityCategoryFilter = item.category
                            onSelectTransactions()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    CategoryBadge(category: item.category, size: 32)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.category.title(in: lang))
                                            .font(.appBodyMedium)
                                            .foregroundStyle(Color.textPrimary)
                                        if !hidesShares {
                                            Text("\(Int((item.share * 100).rounded()))%")
                                                .font(.appCaption)
                                                .foregroundStyle(Color.textSecondary)
                                        }
                                    }
                                    Spacer()
                                    Text(MoneyFormat.masked(settings.formatMoney(minor: item.spentMinor), hidden: hidesAmount(item)))
                                        .salaryMaskAccessibility(hidesAmount(item), language: lang)
                                        .font(.appAmount)
                                        .foregroundStyle(breakdownKind == .income ? Color.positive : Color.textPrimary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color.textSecondary.opacity(0.5))
                                }
                                if !hidesShares {
                                    TallyProgressBar(value: item.share, fill: item.category.color)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.themedPlain)
                    }
                }
            }
        }
    }

    // MARK: - Day of Week Pattern

    private func weekdayPatternCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let displayCurrency = settings.effectiveDisplayCurrency
        let peak = stats.weekdayBreakdown.max(by: { $0.totalMinor < $1.totalMinor })

        return Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Spending by weekday", vi: "Chi tiêu theo thứ trong tuần", zh: "按星期消费"))
                        .font(.appHeading)
                    if let peak, peak.totalMinor > 0 {
                        let peakText = settings.formatMoney(minor: peak.totalMinor, compact: true)
                        Text(L10n.text(
                            lang,
                            en: "Highest on \(DateKey.shortWeekdayLabel(weekday: peak.weekday, language: lang)) · \(peakText)",
                            vi: "Cao nhất vào \(DateKey.shortWeekdayLabel(weekday: peak.weekday, language: lang)) · \(peakText)",
                            zh: "周\(DateKey.shortWeekdayLabel(weekday: peak.weekday, language: lang))最高 · \(peakText)"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }

            Chart(stats.weekdayBreakdown) { item in
                BarMark(
                    x: .value("Day", DateKey.shortWeekdayLabel(weekday: item.weekday, language: lang)),
                    y: .value("Spent", settings.displayMajor(item.totalMinor))
                )
                .foregroundStyle(item.weekday == peak?.weekday && item.totalMinor > 0 ? Color.accent : Color.ink.opacity(0.72))
                .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { val in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel {
                        if let num = val.as(Double.self) {
                            Text(MoneyFormat.format(
                                minor: displayCurrency.toStorageMinor(num),
                                currency: displayCurrency,
                                language: lang,
                                compact: true
                            ))
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
            .frame(height: 155)
        }
    }

    // MARK: - Top Merchants

    private func topMerchantsCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let maxMerchant = max(1, stats.topMerchants.first?.totalMinor ?? 1)

        return Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(lang, en: "Top merchants", vi: "Cửa hàng chi nhiều nhất", zh: "常去商户"))
                    .font(.appHeading)
                Text(L10n.text(lang, en: "Ranked by total spend in period", vi: "Xếp hạng theo tổng chi trong kỳ", zh: "按本期总消费排序"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 12) {
                ForEach(Array(stats.topMerchants.enumerated()), id: \.element.id) { idx, merchant in
                    if idx > 0 { Divider().overlay(Color.hairline) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            CategoryBadge(category: merchant.category, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(merchant.displayName)
                                    .font(.appBodyMedium)
                                    .lineLimit(1)
                                Text(
                                    L10n.text(
                                        lang,
                                        en: "\(merchant.count)× · \(merchant.category.title(in: lang))",
                                        vi: "\(merchant.count) lần · \(merchant.category.title(in: lang))",
                                        zh: "\(merchant.count) 次 · \(merchant.category.title(in: lang))"
                                    )
                                )
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Text(settings.formatMoney(minor: merchant.totalMinor))
                                .font(.appAmount)
                        }
                        TallyProgressBar(
                            value: Double(merchant.totalMinor) / Double(maxMerchant),
                            fill: merchant.category.color
                        )
                    }
                }
            }
        }
    }

    // MARK: - Household Split

    private func householdSplitCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let totalSpent = max(1, stats.current.spendingMinor)

        return Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(lang, en: "Household split", vi: "Chi tiêu theo thành viên", zh: "家庭成员支出"))
                    .font(.appHeading)
                Text(L10n.text(lang, en: "Share of period spending", vi: "Tỷ trọng chi tiêu trong kỳ", zh: "本期支出占比"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 12) {
                ForEach(Array(stats.current.memberBreakdown.enumerated()), id: \.element.id) { idx, member in
                    let share = Double(member.spendingMinor) / Double(totalSpent)
                    let name = member.memberName.isEmpty
                        ? L10n.text(lang, en: "Member", vi: "Thành viên", zh: "成员")
                        : member.memberName
                    let barColor: Color = idx == 0 ? .ink : (idx == 1 ? .accent : .info)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(name).font(.appBodyMedium)
                            Spacer()
                            Text("\(Int((share * 100).rounded()))%")
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Text(settings.formatMoney(minor: member.spendingMinor))
                                .font(.appAmount)
                        }
                        TallyProgressBar(value: share, fill: barColor)
                    }
                }
            }
        }
    }

    // MARK: - Largest Expenses

    private func largestExpensesCard(_ stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(lang, en: "Largest expenses", vi: "Khoản chi lớn nhất", zh: "最大支出"))
                    .font(.appHeading)
                Text(L10n.text(lang, en: "Tap to inspect or edit", vi: "Chạm để xem hoặc chỉnh sửa", zh: "点击查看或编辑"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            VStack(spacing: 2) {
                ForEach(Array(stats.largestExpenses.enumerated()), id: \.element.id) { idx, tx in
                    if idx > 0 { Divider().overlay(Color.hairline) }
                    TransactionRow(transaction: tx, showDate: true) {
                        editingTransaction = tx
                    }
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.appCaption).foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Interactive KPI Detail Sheets

    private func kpiDetailSheet(kind: KPIInspectSheet, stats: StatisticsSnapshot, lang: AppLanguage) -> some View {
        let title: String
        switch kind {
        case .dailyAverage:
            title = L10n.text(lang, en: "Daily spending pace", vi: "Nhịp chi tiêu theo ngày", zh: "每日支出节奏")
        case .vsPrevious:
            title = L10n.text(lang, en: "vs. Previous period", vi: "So sánh với kỳ trước", zh: "与上期对比")
        case .savingsRate:
            title = L10n.text(lang, en: "Savings & cashflow", vi: "Tiết kiệm & dòng tiền", zh: "结余与现金流")
        }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch kind {
                    case .dailyAverage:
                        let activeDays = stats.dailySeries
                            .filter { $0.spendingMinor > 0 }
                            .sorted { $0.spendingMinor > $1.spendingMinor }
                        let maxDay = max(1, activeDays.first?.spendingMinor ?? 1)

                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(L10n.text(lang, en: "Daily average", vi: "Trung bình / ngày", zh: "日均支出"))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(settings.formatMoney(minor: stats.averageDailySpendingMinor))
                                        .font(.appMetric)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(L10n.text(lang, en: "Avg / transaction", vi: "TB / giao dịch", zh: "笔均支出"))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(settings.formatMoney(minor: stats.averageExpenseMinor))
                                        .font(.appHeading)
                                }
                            }
                        }

                        if !activeDays.isEmpty {
                            Card {
                                Text(L10n.text(lang, en: "Highest spending days (tap to inspect)", vi: "Những ngày chi cao nhất (chạm để xem)", zh: "最高支出日期（点击查看）"))
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                VStack(spacing: 10) {
                                    ForEach(activeDays.prefix(10)) { point in
                                        Button {
                                            activeKPISheet = nil
                                            store.selectedPeriod = .day(point.dayKey)
                                            store.activityTypeFilter = .expense
                                            store.activityCategoryFilter = nil
                                            onSelectTransactions()
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(DateKey.formatShortDay(point.dayKey, language: lang))
                                                        .font(.appBodyMedium)
                                                    Spacer()
                                                    Text(settings.formatMoney(minor: point.spendingMinor))
                                                        .font(.appAmount)
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(Color.textSecondary.opacity(0.5))
                                                }
                                                TallyProgressBar(
                                                    value: Double(point.spendingMinor) / Double(maxDay),
                                                    fill: point.dayKey == stats.highestSpendDay?.dayKey ? .accent : .ink
                                                )
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.themedPlain)
                                    }
                                }
                            }
                        }

                    case .vsPrevious:
                        let prevPeriod = store.selectedPeriod.shifted(by: -1)
                        let prevSnap = MonthlySnapshot.compute(
                            period: prevPeriod,
                            allTransactions: store.transactions,
                            allBudgets: store.budgets,
                            memberFilter: store.selectedMemberID
                        )
                        let diffMinor = stats.current.spendingMinor - prevSnap.spendingMinor

                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(store.selectedPeriod.formattedTitle(language: lang))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(settings.formatMoney(minor: stats.current.spendingMinor))
                                        .font(.appMetric)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(prevPeriod.formattedTitle(language: lang))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(settings.formatMoney(minor: prevSnap.spendingMinor))
                                        .font(.appHeading)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            Divider().overlay(Color.hairline)
                            HStack {
                                Text(L10n.text(lang, en: "Difference", vi: "Chênh lệch", zh: "差额"))
                                    .font(.appSecondary)
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text(settings.formatMoney(minor: diffMinor, signed: true))
                                    .font(.appHeading)
                                    .foregroundStyle(diffMinor > 0 ? Color.accent : Color.positive)
                            }
                        }

                        // Category-by-category comparison
                        let allCats = Set(stats.current.expensesByCategory.keys).union(prevSnap.expensesByCategory.keys)
                        let rows = allCats.map { cat -> (cat: CategoryID, now: Int64, prev: Int64, delta: Int64) in
                            let nowAmt = stats.current.expensesByCategory[cat] ?? 0
                            let prevAmt = prevSnap.expensesByCategory[cat] ?? 0
                            return (cat, nowAmt, prevAmt, nowAmt - prevAmt)
                        }.sorted { abs($0.delta) > abs($1.delta) }

                        if !rows.isEmpty {
                            Card {
                                Text(L10n.text(lang, en: "Changes by category", vi: "Biến động theo danh mục", zh: "各分类变化"))
                                    .font(.appCaption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                                VStack(spacing: 10) {
                                    ForEach(rows, id: \.cat) { row in
                                        HStack(spacing: 10) {
                                            CategoryBadge(category: row.cat, size: 32)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(row.cat.title(in: lang)).font(.appBodyMedium)
                                                Text("\(settings.formatMoney(minor: row.prev, compact: true)) → \(settings.formatMoney(minor: row.now, compact: true))")
                                                    .font(.appCaption)
                                                    .foregroundStyle(Color.textSecondary)
                                            }
                                            Spacer()
                                            Text(settings.formatMoney(minor: row.delta, signed: true))
                                                .font(.appCaption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(row.delta > 0 ? Color.accent : Color.positive)
                                        }
                                    }
                                }
                            }
                        }

                        Button {
                            activeKPISheet = nil
                            withAnimation(.snappy(duration: 0.2)) {
                                store.selectedPeriod = prevPeriod
                            }
                        } label: {
                            Label(
                                L10n.text(lang, en: "Jump to \(prevPeriod.formattedTitle(language: lang))", vi: "Xem kỳ \(prevPeriod.formattedTitle(language: lang))", zh: "查看 \(prevPeriod.formattedTitle(language: lang))"),
                                systemImage: "arrow.left.circle"
                            )
                        }
                        .blockButton(prominent: true)

                    case .savingsRate:
                        Card {
                            VStack(spacing: 12) {
                                HStack {
                                    Text(L10n.text(lang, en: "Income", vi: "Thu nhập", zh: "收入"))
                                        .font(.appSecondary)
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                    Text(MoneyFormat.masked(settings.formatMoney(minor: stats.current.incomeMinor, signed: true), hidden: stats.isSalaryMasked(hidden: settings.hideSalary)))
                                        .salaryMaskAccessibility(stats.isSalaryMasked(hidden: settings.hideSalary), language: lang)
                                        .font(.appHeading)
                                        .foregroundStyle(Color.positive)
                                }
                                HStack {
                                    Text(L10n.text(lang, en: "Spending", vi: "Chi tiêu", zh: "支出"))
                                        .font(.appSecondary)
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                    Text(settings.formatMoney(minor: -stats.current.spendingMinor))
                                        .font(.appHeading)
                                        .foregroundStyle(Color.textPrimary)
                                }
                                Divider().overlay(Color.hairline)
                                HStack {
                                    Text(L10n.text(lang, en: "Net savings", vi: "Tiết kiệm ròng", zh: "净结余"))
                                        .font(.appBodyMedium)
                                    Spacer()
                                    Text(MoneyFormat.masked(settings.formatMoney(minor: stats.current.netSavingsMinor, signed: true), hidden: stats.isSalaryMasked(hidden: settings.hideSalary)))
                                        .salaryMaskAccessibility(stats.isSalaryMasked(hidden: settings.hideSalary), language: lang)
                                        .font(.appMetric)
                                        .foregroundStyle(stats.isSalaryMasked(hidden: settings.hideSalary) ? Color.textPrimary : (stats.current.netSavingsMinor >= 0 ? Color.positive : Color.accent))
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Button {
                                activeKPISheet = nil
                                store.activityTypeFilter = .income
                                store.activityCategoryFilter = nil
                                onSelectTransactions()
                            } label: {
                                Text(L10n.text(lang, en: "View income", vi: "Xem thu nhập", zh: "查看收入"))
                            }
                            .blockButton(prominent: false)

                            Button {
                                activeKPISheet = nil
                                store.activityTypeFilter = .expense
                                store.activityCategoryFilter = nil
                                onSelectTransactions()
                            } label: {
                                Text(L10n.text(lang, en: "View expenses", vi: "Xem chi tiêu", zh: "查看支出"))
                            }
                            .blockButton(prominent: true)
                        }
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .cozySheetToolbar(title: title) {
                Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) {
                    activeKPISheet = nil
                }
            }
        }
        .presentationDetents([.medium, .large])
        .cozySheetFrame(minWidth: 420, idealWidth: 460, minHeight: 400, idealHeight: 480)
    }
}
