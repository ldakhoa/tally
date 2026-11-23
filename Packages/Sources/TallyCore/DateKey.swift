import Foundation

/// Calendar day (`YYYY-MM-DD`) and month (`YYYY-MM`) helpers matching Tally Web's date keys.
public enum DateKey {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    public static func dayKey(from date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    public static func monthKey(from date: Date) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 2026, comps.month ?? 1)
    }

    public static func monthKey(fromDayKey dayKey: String) -> String {
        String(dayKey.prefix(7))
    }

    public static func date(fromDayKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (2000...2099).contains(year),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        guard let date = calendar.date(from: comps) else { return nil }
        return dayKey(from: date) == key ? date : nil
    }

    public static func date(fromMonthKey key: String) -> Date? {
        date(fromDayKey: "\(key)-01")
    }

    public static func shiftMonth(_ monthKey: String, by delta: Int) -> String {
        guard let base = date(fromMonthKey: monthKey),
              let shifted = calendar.date(byAdding: .month, value: delta, to: base)
        else { return monthKey }
        let next = self.monthKey(from: shifted)
        if next < "2000-01" || next > "2099-12" { return monthKey }
        return next
    }

    public static func shiftDay(_ dayKey: String, by delta: Int) -> String {
        guard let base = date(fromDayKey: dayKey),
              let shifted = calendar.date(byAdding: .day, value: delta, to: base)
        else { return dayKey }
        let next = self.dayKey(from: shifted)
        if next < "2000-01-01" || next > "2099-12-31" { return dayKey }
        return next
    }

    public static func daysBetween(_ startDayKey: String, _ endDayKey: String) -> Int {
        guard let start = date(fromDayKey: startDayKey),
              let end = date(fromDayKey: endDayKey)
        else { return 0 }
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    public static func dayRange(forMonth monthKey: String) -> (start: String, end: String) {
        let count = daysInMonth(monthKey)
        return ("\(monthKey)-01", String(format: "%@-%02d", monthKey, count))
    }

    public static func yearAndMonth(fromMonthKey monthKey: String) -> (year: Int, month: Int)? {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (2000...2099).contains(year),
              (1...12).contains(month)
        else { return nil }
        return (year, month)
    }

    public static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    public static func dayKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Number of leading empty cells (0...6) before day 1 of `monthKey` for a 7-column calendar grid.
    /// `firstWeekday`: 1 = Sunday (default), 2 = Monday.
    public static func leadingEmptySlots(inMonth monthKey: String, firstWeekday: Int = 1) -> Int {
        guard let firstDate = date(fromMonthKey: monthKey) else { return 0 }
        let weekday = calendar.component(.weekday, from: firstDate) // 1 = Sun ... 7 = Sat
        return (weekday - firstWeekday + 7) % 7
    }

    public static func daysInMonth(_ monthKey: String) -> Int {
        guard let base = date(fromMonthKey: monthKey),
              let range = calendar.range(of: .day, in: .month, for: base)
        else { return 30 }
        return range.count
    }

    public static func dayOfMonth(fromDayKey key: String) -> Int {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let day = Int(parts[2]) else { return 1 }
        return day
    }

    public static func relativeDayLabel(_ dayKey: String, language: AppLanguage, referenceDate: Date = Date()) -> String? {
        let todayKey = self.dayKey(from: referenceDate)
        if dayKey == todayKey { return L10n.today(language) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           dayKey == self.dayKey(from: yesterday) {
            return L10n.yesterday(language)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate),
           dayKey == self.dayKey(from: tomorrow) {
            return L10n.tomorrow(language)
        }
        return nil
    }

    public static func formatMonth(_ monthKey: String, language: AppLanguage) -> String {
        guard let date = date(fromMonthKey: monthKey) else { return monthKey }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let text = formatter.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    public static func formatShortDay(_ dayKey: String, language: AppLanguage, referenceDate: Date = Date()) -> String {
        if let relative = relativeDayLabel(dayKey, language: language, referenceDate: referenceDate) {
            return relative
        }
        guard let date = date(fromDayKey: dayKey) else { return dayKey }
        let refYear = calendar.component(.year, from: referenceDate)
        let targetYear = calendar.component(.year, from: date)
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate(targetYear == refYear ? "EEE, d MMM" : "EEE, d MMM yyyy")
        return formatter.string(from: date)
    }

    public static func formatCompactDay(_ dayKey: String, language: AppLanguage, referenceDate: Date = Date()) -> String {
        if let relative = relativeDayLabel(dayKey, language: language, referenceDate: referenceDate) {
            return relative
        }
        guard let date = date(fromDayKey: dayKey) else { return dayKey }
        let refYear = calendar.component(.year, from: referenceDate)
        let targetYear = calendar.component(.year, from: date)
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate(targetYear == refYear ? "d MMM" : "d MMM yyyy")
        return formatter.string(from: date)
    }

    /// Complete date label: returns Today / Yesterday / Tomorrow when applicable,
    /// otherwise full date (e.g. "15 Nov 2026").
    public static func formatFullDay(_ dayKey: String, language: AppLanguage, referenceDate: Date = Date()) -> String {
        if let relative = relativeDayLabel(dayKey, language: language, referenceDate: referenceDate) {
            return relative
        }
        guard let date = date(fromDayKey: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter.string(from: date)
    }

    /// Always formats the absolute date (e.g. "23 Nov 2026"), even for Today/Yesterday/Tomorrow.
    public static func formatAbsoluteDay(_ dayKey: String, language: AppLanguage) -> String {
        guard let date = date(fromDayKey: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return formatter.string(from: date)
    }

    /// Formats an inclusive date range cleanly without truncation (e.g. "12 – 23 Nov 2026" or "28 Oct – 5 Nov 2026").
    public static func formatDayRange(
        start startDayKey: String,
        end endDayKey: String,
        language: AppLanguage,
        referenceDate: Date = Date()
    ) -> String {
        let lo = min(startDayKey, endDayKey)
        let hi = max(startDayKey, endDayKey)
        if lo == hi {
            return formatFullDay(lo, language: language, referenceDate: referenceDate)
        }
        guard let startDate = date(fromDayKey: lo), let endDate = date(fromDayKey: hi) else {
            return "\(lo) – \(hi)"
        }
        let sComps = calendar.dateComponents([.year, .month, .day], from: startDate)
        let eComps = calendar.dateComponents([.year, .month, .day], from: endDate)

        if sComps.year == eComps.year, sComps.month == eComps.month, let sDay = sComps.day {
            let endText = formatAbsoluteDay(hi, language: language)
            if language.resolved == .english {
                return "\(sDay) – \(endText)"
            } else {
                // Vietnamese: "12 – 23 thg 11, 2026"
                return "\(sDay) – \(endText)"
            }
        }

        if sComps.year == eComps.year {
            let startFormatter = DateFormatter()
            startFormatter.locale = language.locale
            startFormatter.setLocalizedDateFormatFromTemplate("d MMM")
            let startText = startFormatter.string(from: startDate)
            let endText = formatAbsoluteDay(hi, language: language)
            return "\(startText) – \(endText)"
        }

        return "\(formatAbsoluteDay(lo, language: language)) – \(formatAbsoluteDay(hi, language: language))"
    }
}
