import Foundation

/// Active date filter across Overview, Activity, and Budgets.
/// Supports a single day ("Today", "Yesterday", "Tomorrow", or full date),
/// an inclusive date range (Airbnb-style), or a full calendar month.
public enum DatePeriod: Hashable, Codable, Sendable {
    case day(String)
    case range(start: String, end: String)
    case month(String)

    public static func today(referenceDate: Date = Date()) -> DatePeriod {
        .day(DateKey.dayKey(from: referenceDate))
    }

    public static func yesterday(referenceDate: Date = Date()) -> DatePeriod {
        .day(DateKey.shiftDay(DateKey.dayKey(from: referenceDate), by: -1))
    }

    public static func tomorrow(referenceDate: Date = Date()) -> DatePeriod {
        .day(DateKey.shiftDay(DateKey.dayKey(from: referenceDate), by: 1))
    }

    public static func currentMonth(referenceDate: Date = Date()) -> DatePeriod {
        .month(DateKey.monthKey(from: referenceDate))
    }

    public static func normalizedRange(start: String, end: String) -> DatePeriod {
        if start == end { return .day(start) }
        if start > end { return .range(start: end, end: start) }
        return .range(start: start, end: end)
    }

    public var startDayKey: String {
        switch self {
        case .day(let d): return d
        case .range(let start, let end): return min(start, end)
        case .month(let m): return DateKey.dayRange(forMonth: m).start
        }
    }

    public var endDayKey: String {
        switch self {
        case .day(let d): return d
        case .range(let start, let end): return max(start, end)
        case .month(let m): return DateKey.dayRange(forMonth: m).end
        }
    }

    /// The primary `YYYY-MM` month associated with this period (used for monthly budgets & AI context).
    public var primaryMonthKey: String {
        switch self {
        case .day(let d): return DateKey.monthKey(fromDayKey: d)
        case .range(_, let end): return DateKey.monthKey(fromDayKey: end)
        case .month(let m): return m
        }
    }

    public var isFullMonth: Bool {
        if case .month = self { return true }
        return false
    }

    public func contains(dayKey: String) -> Bool {
        dayKey >= startDayKey && dayKey <= endDayKey
    }

    /// Default day when creating a new transaction while viewing this period.
    public func defaultNewTransactionDayKey(referenceDate: Date = Date()) -> String {
        let todayKey = DateKey.dayKey(from: referenceDate)
        switch self {
        case .day(let d):
            return d
        case .range(let start, let end):
            let lo = min(start, end)
            let hi = max(start, end)
            return (todayKey >= lo && todayKey <= hi) ? todayKey : hi
        case .month(let m):
            return DateKey.monthKey(fromDayKey: todayKey) == m ? todayKey : "\(m)-01"
        }
    }

    public func shifted(by delta: Int) -> DatePeriod {
        switch self {
        case .day(let d):
            return .day(DateKey.shiftDay(d, by: delta))
        case .month(let m):
            return .month(DateKey.shiftMonth(m, by: delta))
        case .range(let start, let end):
            let lo = min(start, end)
            let hi = max(start, end)
            let span = max(1, DateKey.daysBetween(lo, hi) + 1)
            let step = delta * span
            return .range(
                start: DateKey.shiftDay(lo, by: step),
                end: DateKey.shiftDay(hi, by: step)
            )
        }
    }

    public func formattedTitle(language: AppLanguage, referenceDate: Date = Date()) -> String {
        switch self {
        case .day(let d):
            return DateKey.formatFullDay(d, language: language, referenceDate: referenceDate)
        case .range(let start, let end):
            return DateKey.formatDayRange(start: start, end: end, language: language, referenceDate: referenceDate)
        case .month(let m):
            return DateKey.formatMonth(m, language: language)
        }
    }

    /// Optional secondary subtitle for relative days (e.g. "23 Nov 2026" when title is "Today").
    public func formattedSubtitle(language: AppLanguage, referenceDate: Date = Date()) -> String? {
        switch self {
        case .day(let d):
            guard DateKey.relativeDayLabel(d, language: language, referenceDate: referenceDate) != nil else {
                return nil
            }
            return DateKey.formatAbsoluteDay(d, language: language)
        case .range, .month:
            return nil
        }
    }
}
