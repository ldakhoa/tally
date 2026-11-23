import SwiftUI
import TallyCore

// MARK: - Airbnb HorizonCalendar-Style Period Picker

/// Vertical continuous-scrolling calendar inspired by Airbnb's HorizonCalendar.
/// Supports selecting a single day (Today / Yesterday / Tomorrow / any date),
/// an inclusive date range (tap start, then tap end), or a full calendar month.
public struct HorizonPeriodCalendarView: View {
    @Binding public var selection: DatePeriod
    public let language: AppLanguage
    public var highlightedDayKeys: Set<String>

    @State private var scrollTargetMonth: String?

    public init(
        selection: Binding<DatePeriod>,
        language: AppLanguage,
        highlightedDayKeys: Set<String> = []
    ) {
        self._selection = selection
        self.language = language
        self.highlightedDayKeys = highlightedDayKeys
    }

    public var body: some View {
        let todayKey = DateKey.dayKey(from: Date())
        let months = monthRange(including: selection.primaryMonthKey, todayKey: todayKey)

        VStack(spacing: 0) {
            quickPresetBar(todayKey: todayKey)
            weekdayHeader
            Divider().overlay(Color.hairline)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 26) {
                        ForEach(months, id: \.self) { monthKey in
                            monthSection(monthKey: monthKey, todayKey: todayKey)
                                .id(monthKey)
                        }
                    }
                    .padding(.horizontal, 16)
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
            (L10n.text(language, en: "Last 7 days", vi: "7 ngày qua"),
             .normalizedRange(start: DateKey.shiftDay(todayKey, by: -6), end: todayKey)),
            (L10n.text(language, en: "This month", vi: "Tháng này"), .currentMonth()),
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appBackground)
    }

    // MARK: - Month Section

    private func monthSection(monthKey: String, todayKey: String) -> some View {
        let isThisMonthSelected = (selection == .month(monthKey))
        let leadingSlots = DateKey.leadingEmptySlots(inMonth: monthKey, firstWeekday: 1)
        let dayCount = DateKey.daysInMonth(monthKey)
        let totalCells = leadingSlots + dayCount

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(DateKey.formatMonth(monthKey, language: language))
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selection = .month(monthKey)
                    }
                } label: {
                    Text(
                        isThisMonthSelected
                            ? L10n.text(language, en: "Full month ✓", vi: "Cả tháng ✓")
                            : L10n.text(language, en: "Full month", vi: "Cả tháng")
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
                spacing: 6
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < leadingSlots {
                        Color.clear.frame(height: 44)
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
        let hasActivity = highlightedDayKeys.contains(dayKey)

        return Button {
            handleDayTap(dayKey)
        } label: {
            ZStack {
                // Continuous range band (Airbnb HorizonCalendar signature look)
                if isRangeSpan {
                    if isInRange {
                        Rectangle()
                            .fill(Color.ink.opacity(0.10))
                            .frame(height: 38)
                            .clipShape(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: (columnIndex == 0 || isFirstDayOfMonth) ? 19 : 0,
                                    bottomLeadingRadius: (columnIndex == 0 || isFirstDayOfMonth) ? 19 : 0,
                                    bottomTrailingRadius: (columnIndex == 6 || isLastDayOfMonth) ? 19 : 0,
                                    topTrailingRadius: (columnIndex == 6 || isLastDayOfMonth) ? 19 : 0
                                )
                            )
                    } else if isStart {
                        HStack(spacing: 0) {
                            Color.clear
                            Color.ink.opacity(0.10)
                        }
                        .frame(height: 38)
                    } else if isEnd {
                        HStack(spacing: 0) {
                            Color.ink.opacity(0.10)
                            Color.clear
                        }
                        .frame(height: 38)
                    }
                }

                // Selected endpoint / single day circle
                if isEndpoint {
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 38, height: 38)
                } else if isToday {
                    Circle()
                        .strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                }

                VStack(spacing: 1) {
                    Text("\(dayNumber)")
                        .font(isEndpoint || isToday ? .appControl.weight(.semibold) : .appSecondary)
                        .monospacedDigit()
                        .foregroundStyle(isEndpoint ? Color.onInk : Color.textPrimary)

                    if hasActivity {
                        Circle()
                            .fill(isEndpoint ? Color.onInk.opacity(0.85) : Color.accent)
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
        .accessibilityLabel(DateKey.formatFullDay(dayKey, language: language))
        .accessibilityAddTraits(isEndpoint ? .isSelected : [])
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
    @Binding public var selectedDayKey: String
    public let language: AppLanguage
    public var highlightedDayKeys: Set<String>
    public var onSelect: ((String) -> Void)?

    @State private var scrollTargetMonth: String?

    public init(
        selectedDayKey: Binding<String>,
        language: AppLanguage,
        highlightedDayKeys: Set<String> = [],
        onSelect: ((String) -> Void)? = nil
    ) {
        self._selectedDayKey = selectedDayKey
        self.language = language
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
            .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
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
                spacing: 6
            ) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < leadingSlots {
                        Color.clear.frame(height: 44)
                    } else {
                        let dayNum = index - leadingSlots + 1
                        let dayKey = String(format: "%@-%02d", monthKey, dayNum)
                        let isSelected = dayKey == selectedDayKey
                        let isToday = dayKey == todayKey
                        let hasActivity = highlightedDayKeys.contains(dayKey)

                        Button {
                            withAnimation(.snappy(duration: 0.16)) {
                                selectedDayKey = dayKey
                            }
                            onSelect?(dayKey)
                        } label: {
                            ZStack {
                                if isSelected {
                                    Circle()
                                        .fill(Color.ink)
                                        .frame(width: 38, height: 38)
                                } else if isToday {
                                    Circle()
                                        .strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.5)
                                        .frame(width: 38, height: 38)
                                }

                                VStack(spacing: 1) {
                                    Text("\(dayNum)")
                                        .font(isSelected || isToday ? .appControl.weight(.semibold) : .appSecondary)
                                        .monospacedDigit()
                                        .foregroundStyle(isSelected ? Color.onInk : Color.textPrimary)

                                    if hasActivity {
                                        Circle()
                                            .fill(isSelected ? Color.onInk.opacity(0.85) : Color.accent)
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
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

// MARK: - Helpers

private func localizedWeekdaySymbols(language: AppLanguage) -> [String] {
    if language.resolved == .vietnamese {
        return ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
    }
    return ["S", "M", "T", "W", "T", "F", "S"]
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
