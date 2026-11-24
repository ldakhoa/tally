import BudgetKit
import SwiftUI
import TallyCore

// MARK: - Airbnb HorizonCalendar-Style Period Picker

/// Vertical continuous-scrolling calendar inspired by Airbnb's HorizonCalendar.
/// Displays daily spending & income directly inside each day cell by default (e.g. `-$20`, `+$100`)
/// and supports selecting a single day, an inclusive date range, or a full calendar month.
public struct HorizonPeriodCalendarView: View {
    @Environment(\.hideSalary) private var hideSalary

    @Binding public var selection: DatePeriod
    public let language: AppLanguage
    public var currency: CurrencyCode
    public var dailyTotals: [String: DailyCalendarTotal]
    public var highlightedDayKeys: Set<String>

    @State private var scrollTargetMonth: String?

    public init(
        selection: Binding<DatePeriod>,
        language: AppLanguage,
        currency: CurrencyCode = .sgd,
        dailyTotals: [String: DailyCalendarTotal] = [:],
        highlightedDayKeys: Set<String> = []
    ) {
        self._selection = selection
        self.language = language
        self.currency = currency
        self.dailyTotals = dailyTotals
        self.highlightedDayKeys = highlightedDayKeys
    }

    public var body: some View {
        let todayKey = DateKey.dayKey(from: Date())
        let months = monthRange(including: selection.primaryMonthKey, todayKey: todayKey)
        let monthlySummaries = MonthlySnapshot.monthlyTotals(from: dailyTotals)

        VStack(spacing: 0) {
            quickPresetBar(todayKey: todayKey)
            weekdayHeader
            Divider().overlay(Color.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(months, id: \.self) { monthKey in
                            monthSection(
                                monthKey: monthKey,
                                todayKey: todayKey,
                                monthTotal: monthlySummaries[monthKey]
                            )
                            .id(monthKey)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .onAppear {
                    let target = selection.primaryMonthKey
                    DispatchQueue.main.async {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
                .onChange(of: scrollTargetMonth) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTargetMonth = nil
                }
            }
        }
    }

    // MARK: - Quick Presets

    private func quickPresetBar(todayKey: String) -> some View {
        let presets: [(label: String, period: DatePeriod)] = [
            (L10n.today(language), .today()),
            (L10n.yesterday(language), .yesterday()),
            (L10n.tomorrow(language), .tomorrow()),
            (L10n.text(language, en: "Last 7 days", vi: "7 ngày qua", zh: "最近7天"),
             .normalizedRange(start: DateKey.shiftDay(todayKey, by: -6), end: todayKey)),
            (L10n.text(language, en: "This month", vi: "Tháng này", zh: "本月"), .currentMonth()),
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, preset in
                    let isActive = selection == preset.period
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            selection = preset.period
                            scrollTargetMonth = preset.period.primaryMonthKey
                        }
                    } label: {
                        Text(preset.label)
                            .font(.appCaption.weight(.medium))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .foregroundStyle(isActive ? Color.onInk : Color.textPrimary)
                            .background(isActive ? Color.ink : Color.softFill, in: Capsule())
                    }
                    .buttonStyle(.themedPlain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Sticky Weekday Header

    private var weekdayHeader: some View {
        let symbols = localizedWeekdaySymbols(language: language)
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appBackground)
    }

    // MARK: - Month Section

    private func monthSection(
        monthKey: String,
        todayKey: String,
        monthTotal: DailyCalendarTotal?
    ) -> some View {
        let isThisMonthSelected = (selection == .month(monthKey))
        let leadingSlots = DateKey.leadingEmptySlots(inMonth: monthKey, firstWeekday: 1)
        let dayCount = DateKey.daysInMonth(monthKey)
        let totalCells = leadingSlots + dayCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateKey.formatMonth(monthKey, language: language))
                        .font(.appHeading)
                        .foregroundStyle(Color.textPrimary)

                    if let monthTotal, (monthTotal.spendingMinor > 0 || monthTotal.incomeMinor > 0) {
                        HStack(spacing: 8) {
                            if monthTotal.incomeMinor > 0 {
                                Text(MoneyFormat.masked(MoneyFormat.format(
                                    minor: monthTotal.incomeMinor,
                                    currency: currency,
                                    language: language,
                                    compact: true,
                                    signed: true
                                ), hidden: monthTotal.isSalaryMasked(hidden: hideSalary)))
                                .salaryMaskAccessibility(monthTotal.isSalaryMasked(hidden: hideSalary), language: language)
                                .foregroundStyle(Color.positive)
                            }
                            if monthTotal.spendingMinor > 0 {
                                Text(MoneyFormat.format(
                                    minor: -monthTotal.spendingMinor,
                                    currency: currency,
                                    language: language,
                                    compact: true
                                ))
                                .foregroundStyle(Color.accent)
                            }
                        }
                        .font(.appCaption.weight(.semibold))
                        .monospacedDigit()
                    }
                }
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = .month(monthKey)
                    }
                } label: {
                    Text(
                        isThisMonthSelected
                            ? L10n.text(language, en: "Full month ✓", vi: "Cả tháng ✓", zh: "整月 ✓")
                            : L10n.text(language, en: "Full month", vi: "Cả tháng", zh: "整月")
                    )
                    .font(.appCaption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(isThisMonthSelected ? Color.onInk : Color.textSecondary)
                    .background(isThisMonthSelected ? Color.ink : Color.softFill, in: Capsule())
                }
                .buttonStyle(.themedPlain)
            }
            .padding(.horizontal, 4)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 4
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < leadingSlots {
                        Color.clear.frame(height: 58)
                    } else {
                        let dayNum = index - leadingSlots + 1
                        let dayKey = String(format: "%@-%02d", monthKey, dayNum)
                        let col = index % 7
                        dayCell(
                            dayNumber: dayNum,
                            dayKey: dayKey,
                            todayKey: todayKey,
                            columnIndex: col,
                            isFirstDayOfMonth: dayNum == 1,
                            isLastDayOfMonth: dayNum == dayCount
                        )
                    }
                }
            }
        }
    }

    private func dayCell(
        dayNumber: Int,
        dayKey: String,
        todayKey: String,
        columnIndex: Int,
        isFirstDayOfMonth: Bool,
        isLastDayOfMonth: Bool
    ) -> some View {
        let startKey = selection.startDayKey
        let endKey = selection.endDayKey
        let isRangeSpan = startKey != endKey
        let isStart = dayKey == startKey
        let isEnd = dayKey == endKey
        let isEndpoint = isStart || isEnd
        let isInRange = dayKey > startKey && dayKey < endKey
        let isToday = dayKey == todayKey
        let summary = dailyTotals[dayKey]
        let hasActivity = (summary?.hasActivity ?? false) || highlightedDayKeys.contains(dayKey)

        return Button {
            handleDayTap(dayKey)
        } label: {
            ZStack {
                // Continuous range band (Airbnb HorizonCalendar signature look)
                if isRangeSpan {
                    if isInRange {
                        Rectangle()
                            .fill(Color.ink.opacity(0.08))
                            .frame(height: 54)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: (columnIndex == 0 || isFirstDayOfMonth) ? 12 : 0,
                                    bottomLeadingRadius: (columnIndex == 0 || isFirstDayOfMonth) ? 12 : 0,
                                    bottomTrailingRadius: (columnIndex == 6 || isLastDayOfMonth) ? 12 : 0,
                                    topTrailingRadius: (columnIndex == 6 || isLastDayOfMonth) ? 12 : 0
                                )
                            )
                    } else if isStart {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.ink.opacity(0.08)
                        }
                        .frame(height: 54)
                    } else if isEnd {
                        HStack(spacing: 0) {
                            Color.ink.opacity(0.08)
                            Color.clear
                        }
                        .frame(height: 54)
                    }
                }

                VStack(spacing: 2) {
                    ZStack {
                        if isEndpoint {
                            Circle()
                                .fill(Color.ink)
                                .frame(width: 28, height: 28)
                        } else if isToday {
                            Circle()
                                .strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                        }

                        Text("\(dayNumber)")
                            .font(isEndpoint || isToday ? .appCaption.weight(.semibold) : .appCaption)
                            .monospacedDigit()
                            .foregroundStyle(isEndpoint ? Color.onInk : Color.textPrimary)
                    }
                    .frame(height: 28)

                    CalendarDayMoneyLabel(
                        summary: summary,
                        hasFallbackActivity: hasActivity,
                        currency: currency,
                        language: language
                    )
                    .frame(height: 24, alignment: .top)
                }
                .padding(.horizontal, 1)
            }
            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
        .accessibilityLabel(accessibilityDescription(dayKey: dayKey, summary: summary))
        .accessibilityAddTraits(isEndpoint ? .isSelected : [])
    }

    private func accessibilityDescription(dayKey: String, summary: DailyCalendarTotal?) -> String {
        let base = DateKey.formatFullDay(dayKey, language: language)
        guard let summary, summary.hasActivity else { return base }
        var parts = [base]
        if summary.incomeMinor > 0 {
            parts.append(MoneyFormat.masked(MoneyFormat.format(minor: summary.incomeMinor, currency: currency, language: language, signed: true), hidden: summary.isSalaryMasked(hidden: hideSalary)))
        }
        if summary.spendingMinor > 0 {
            parts.append(MoneyFormat.format(minor: -summary.spendingMinor, currency: currency, language: language))
        }
        return parts.joined(separator: ", ")
    }

    private func handleDayTap(_ tappedDayKey: String) {
        withAnimation(.snappy(duration: 0.16)) {
            switch selection {
            case .day(let existing):
                if existing == tappedDayKey {
                    selection = .day(tappedDayKey)
                } else {
                    selection = .normalizedRange(start: existing, end: tappedDayKey)
                }
            case .range, .month:
                selection = .day(tappedDayKey)
            }
        }
    }
}

// MARK: - Airbnb HorizonCalendar-Style Single Date Picker

/// Single-date vertical scrolling calendar for forms (e.g., Transaction Editor).
public struct HorizonSingleDateCalendarView: View {
    @Environment(\.hideSalary) private var hideSalary

    @Binding public var selectedDayKey: String
    public let language: AppLanguage
    public var currency: CurrencyCode
    public var dailyTotals: [String: DailyCalendarTotal]
    public var highlightedDayKeys: Set<String>
    public var onSelect: ((String) -> Void)?

    @State private var scrollTargetMonth: String?

    public init(
        selectedDayKey: Binding<String>,
        language: AppLanguage,
        currency: CurrencyCode = .sgd,
        dailyTotals: [String: DailyCalendarTotal] = [:],
        highlightedDayKeys: Set<String> = [],
        onSelect: ((String) -> Void)? = nil
    ) {
        self._selectedDayKey = selectedDayKey
        self.language = language
        self.currency = currency
        self.dailyTotals = dailyTotals
        self.highlightedDayKeys = highlightedDayKeys
        self.onSelect = onSelect
    }

    public var body: some View {
        let todayKey = DateKey.dayKey(from: Date())
        let activeMonth = DateKey.monthKey(fromDayKey: selectedDayKey)
        let months = monthRange(including: activeMonth, todayKey: todayKey)

        VStack(spacing: 0) {
            quickDayBar(todayKey: todayKey)

            let symbols = localizedWeekdaySymbols(language: language)
            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appBackground)

            Divider().overlay(Color.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(months, id: \.self) { monthKey in
                            singleDateMonthSection(monthKey: monthKey, todayKey: todayKey)
                                .id(monthKey)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(activeMonth, anchor: .center)
                    }
                }
                .onChange(of: scrollTargetMonth) { _, target in
                    guard let target else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTargetMonth = nil
                }
            }
        }
    }

    private func quickDayBar(todayKey: String) -> some View {
        let presets: [(label: String, dayKey: String)] = [
            (L10n.today(language), todayKey),
            (L10n.yesterday(language), DateKey.shiftDay(todayKey, by: -1)),
            (L10n.tomorrow(language), DateKey.shiftDay(todayKey, by: 1)),
        ]

        return HStack(spacing: 8) {
            ForEach(presets, id: \.dayKey) { preset in
                let isActive = selectedDayKey == preset.dayKey
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        selectedDayKey = preset.dayKey
                        scrollTargetMonth = DateKey.monthKey(fromDayKey: preset.dayKey)
                    }
                    onSelect?(preset.dayKey)
                } label: {
                    Text(preset.label)
                        .font(.appCaption.weight(.medium))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .foregroundStyle(isActive ? Color.onInk : Color.textPrimary)
                        .background(isActive ? Color.ink : Color.softFill, in: Capsule())
                }
                .buttonStyle(.themedPlain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func singleDateMonthSection(monthKey: String, todayKey: String) -> some View {
        let leadingSlots = DateKey.leadingEmptySlots(inMonth: monthKey, firstWeekday: 1)
        let dayCount = DateKey.daysInMonth(monthKey)
        let totalCells = leadingSlots + dayCount

        return VStack(alignment: .leading, spacing: 10) {
            Text(DateKey.formatMonth(monthKey, language: language))
                .font(.appHeading)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 4)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 4
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < leadingSlots {
                        Color.clear.frame(height: 58)
                    } else {
                        let dayNum = index - leadingSlots + 1
                        let dayKey = String(format: "%@-%02d", monthKey, dayNum)
                        let isSelected = dayKey == selectedDayKey
                        let isToday = dayKey == todayKey
                        let summary = dailyTotals[dayKey]
                        let hasActivity = (summary?.hasActivity ?? false) || highlightedDayKeys.contains(dayKey)

                        Button {
                            withAnimation(.snappy(duration: 0.16)) {
                                selectedDayKey = dayKey
                            }
                            onSelect?(dayKey)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(Color.ink)
                                            .frame(width: 28, height: 28)
                                    } else if isToday {
                                        Circle()
                                            .strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5)
                                            .frame(width: 28, height: 28)
                                    }

                                    Text("\(dayNum)")
                                        .font(isSelected || isToday ? .appCaption.weight(.semibold) : .appCaption)
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                                }
                                .frame(height: 28)

                                CalendarDayMoneyLabel(
                                    summary: summary,
                                    hasFallbackActivity: hasActivity,
                                    currency: currency,
                                    language: language
                                )
                                .frame(height: 24, alignment: .top)
                            }
                            .padding(.horizontal, 1)
                            .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(DateKey.formatFullDay(dayKey, language: language))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

// MARK: - Inline Single-Month Money Calendar (for Transactions Calendar mode)

/// Compact inline month calendar card showing daily spending/income totals directly in every cell.
public struct InlineMonthCalendarCard: View {
    @Environment(\.hideSalary) private var hideSalary

    public let monthKey: String
    public let selectedDayKey: String?
    public let language: AppLanguage
    public let currency: CurrencyCode
    public let dailyTotals: [String: DailyCalendarTotal]
    public let onSelectDay: (String) -> Void
    public let onSelectFullMonth: () -> Void

    public init(
        monthKey: String,
        selectedDayKey: String?,
        language: AppLanguage,
        currency: CurrencyCode,
        dailyTotals: [String: DailyCalendarTotal],
        onSelectDay: @escaping (String) -> Void,
        onSelectFullMonth: @escaping () -> Void
    ) {
        self.monthKey = monthKey
        self.selectedDayKey = selectedDayKey
        self.language = language
        self.currency = currency
        self.dailyTotals = dailyTotals
        self.onSelectDay = onSelectDay
        self.onSelectFullMonth = onSelectFullMonth
    }

    public var body: some View {
        let todayKey = DateKey.dayKey(from: Date())
        let leadingSlots = DateKey.leadingEmptySlots(inMonth: monthKey, firstWeekday: 1)
        let dayCount = DateKey.daysInMonth(monthKey)
        let totalCells = leadingSlots + dayCount
        let symbols = localizedWeekdaySymbols(language: language)
        let monthSummary = MonthlySnapshot.periodTotal(for: .month(monthKey), dailyTotals: dailyTotals)

        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(DateKey.formatMonth(monthKey, language: language))
                        .font(.appHeading)
                    HStack(spacing: 8) {
                        if monthSummary.incomeMinor > 0 {
                            Text(MoneyFormat.masked(MoneyFormat.format(
                                minor: monthSummary.incomeMinor,
                                currency: currency,
                                language: language,
                                compact: true,
                                signed: true
                            ), hidden: monthSummary.isSalaryMasked(hidden: hideSalary)))
                            .salaryMaskAccessibility(monthSummary.isSalaryMasked(hidden: hideSalary), language: language)
                            .foregroundStyle(Color.positive)
                        }
                        if monthSummary.spendingMinor > 0 {
                            Text(MoneyFormat.format(
                                minor: -monthSummary.spendingMinor,
                                currency: currency,
                                language: language,
                                compact: true
                            ))
                            .foregroundStyle(Color.accent)
                        }
                        if monthSummary.incomeMinor == 0 && monthSummary.spendingMinor == 0 {
                            Text(L10n.text(language, en: "No activity", vi: "Chưa có giao dịch", zh: "暂无记录"))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .font(.appCaption.weight(.semibold))
                    .monospacedDigit()
                }
                Spacer()
                if selectedDayKey != nil {
                    Button(L10n.text(language, en: "All month", vi: "Cả tháng", zh: "整月")) {
                        onSelectFullMonth()
                    }
                    .pillButton()
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
                spacing: 4
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < leadingSlots {
                        Color.clear.frame(height: 54)
                    } else {
                        let dayNum = index - leadingSlots + 1
                        let dayKey = String(format: "%@-%02d", monthKey, dayNum)
                        let isSelected = dayKey == selectedDayKey
                        let isToday = dayKey == todayKey
                        let summary = dailyTotals[dayKey]

                        Button {
                            onSelectDay(dayKey)
                        } label: {
                            VStack(spacing: 2) {
                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(Color.ink)
                                            .frame(width: 26, height: 26)
                                    } else if isToday {
                                        Circle()
                                            .strokeBorder(Color.ink.opacity(0.5), lineWidth: 1.5)
                                            .frame(width: 26, height: 26)
                                    }

                                    Text("\(dayNum)")
                                        .font(isSelected || isToday ? .appCaption.weight(.semibold) : .appCaption)
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)
                                }
                                .frame(height: 26)

                                CalendarDayMoneyLabel(
                                    summary: summary,
                                    hasFallbackActivity: false,
                                    currency: currency,
                                    language: language
                                )
                                .frame(height: 24, alignment: .top)
                            }
                            .padding(.horizontal, 1)
                            .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.ink.opacity(0.06))
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
}

// MARK: - Day Cell Money Badge

private struct CalendarDayMoneyLabel: View {
    @Environment(\.hideSalary) private var hideSalary

    let summary: DailyCalendarTotal?
    let hasFallbackActivity: Bool
    let currency: CurrencyCode
    let language: AppLanguage

    var body: some View {
        let income = summary?.incomeMinor ?? 0
        let spending = summary?.spendingMinor ?? 0
        let hidesIncome = summary?.isSalaryMasked(hidden: hideSalary) ?? false

        if income > 0 || spending > 0 {
            let hasBoth = income > 0 && spending > 0
            let fontSize: CGFloat = hasBoth ? 8.5 : 9.5

            VStack(spacing: 0) {
                if income > 0 {
                    Text(MoneyFormat.masked(MoneyFormat.formatCalendarAmount(
                        minor: income,
                        currency: currency,
                        language: language,
                        isIncome: true
                    ), hidden: hidesIncome))
                    .salaryMaskAccessibility(hidesIncome, language: language)
                    .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.positive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                if spending > 0 {
                    Text(MoneyFormat.formatCalendarAmount(
                        minor: spending,
                        currency: currency,
                        language: language,
                        isIncome: false
                    ))
                    .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            }
        } else if hasFallbackActivity {
            Circle()
                .fill(Color.accent)
                .frame(width: 4, height: 4)
                .padding(.top, 4)
        } else {
            Color.clear
        }
    }
}

// MARK: - Helpers

private func localizedWeekdaySymbols(language: AppLanguage) -> [String] {
    switch language.resolved {
    case .vietnamese:
        return ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
    case .chinese:
        return ["日", "一", "二", "三", "四", "五", "六"]
    case .english:
        return ["S", "M", "T", "W", "T", "F", "S"]
    }
}

private func monthRange(including focusMonth: String, todayKey: String) -> [String] {
    let todayMonth = DateKey.monthKey(fromDayKey: todayKey)
    let earliest = min(DateKey.shiftMonth(todayMonth, by: -24), DateKey.shiftMonth(focusMonth, by: -3))
    let latest = max(DateKey.shiftMonth(todayMonth, by: 12), DateKey.shiftMonth(focusMonth, by: 3))

    var result: [String] = []
    var cursor = earliest
    var safety = 0
    while cursor <= latest && safety < 120 {
        result.append(cursor)
        let next = DateKey.shiftMonth(cursor, by: 1)
        if next == cursor { break }
        cursor = next
        safety += 1
    }
    return result
}
