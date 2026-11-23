import TallyCore
import XCTest

final class TallyCoreTests: XCTestCase {
    func testMoneyFormattingVNDAndSGD() {
        let vnd = MoneyFormat.format(minor: CurrencyCode.vnd.toStorageMinor(125_000), currency: .vnd, language: .vietnamese)
        XCTAssertEqual(vnd, "125.000 ₫")

        let sgd = MoneyFormat.format(minor: CurrencyCode.sgd.toStorageMinor(18.5), currency: .sgd, language: .english)
        XCTAssertEqual(sgd, "S$18.50")

        let compactVI = MoneyFormat.format(minor: CurrencyCode.vnd.toStorageMinor(2_500_000), currency: .vnd, language: .vietnamese, compact: true)
        XCTAssertEqual(compactVI, "2.5 tr₫")
    }

    func testDateKeyShiftMonth() {
        XCTAssertEqual(DateKey.shiftMonth("2026-12", by: 1), "2027-01")
        XCTAssertEqual(DateKey.shiftMonth("2026-01", by: -1), "2025-12")
        XCTAssertEqual(DateKey.daysInMonth("2026-02"), 28)
        XCTAssertNotNil(DateKey.date(fromDayKey: "2026-11-23"))
        XCTAssertNil(DateKey.date(fromDayKey: "2026-02-31"))
    }

    func testRelativeDayLabelsAndCompleteFormatting() {
        let ref = DateKey.date(fromDayKey: "2026-11-23")!

        // English: Today / Yesterday / Tomorrow
        XCTAssertEqual(DateKey.formatFullDay("2026-11-23", language: .english, referenceDate: ref), "Today")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-22", language: .english, referenceDate: ref), "Yesterday")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-24", language: .english, referenceDate: ref), "Tomorrow")
        XCTAssertEqual(DateKey.formatCompactDay("2026-11-24", language: .english, referenceDate: ref), "Tomorrow")
        XCTAssertEqual(DateKey.formatShortDay("2026-11-24", language: .english, referenceDate: ref), "Tomorrow")

        // Vietnamese: Hôm nay / Hôm qua / Ngày mai
        XCTAssertEqual(DateKey.formatFullDay("2026-11-23", language: .vietnamese, referenceDate: ref), "Hôm nay")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-22", language: .vietnamese, referenceDate: ref), "Hôm qua")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-24", language: .vietnamese, referenceDate: ref), "Ngày mai")

        // Other date shows complete date with year
        let other = DateKey.formatFullDay("2026-11-15", language: .english, referenceDate: ref)
        XCTAssertTrue(other.contains("15") && other.contains("Nov") && other.contains("2026"), "Expected complete date, got \(other)")
    }

    func testDatePeriodOperations() {
        let ref = DateKey.date(fromDayKey: "2026-11-23")!

        // Day period shifting
        let today = DatePeriod.today(referenceDate: ref)
        XCTAssertEqual(today, .day("2026-11-23"))
        XCTAssertEqual(today.shifted(by: -1), .day("2026-11-22"))
        XCTAssertEqual(today.shifted(by: 1), .day("2026-11-24"))
        XCTAssertEqual(today.formattedTitle(language: .english, referenceDate: ref), "Today")
        XCTAssertEqual(today.shifted(by: -1).formattedTitle(language: .english, referenceDate: ref), "Yesterday")
        XCTAssertEqual(today.shifted(by: 1).formattedTitle(language: .english, referenceDate: ref), "Tomorrow")
        XCTAssertNotNil(today.formattedSubtitle(language: .english, referenceDate: ref))

        // Range normalization & containment
        let range = DatePeriod.normalizedRange(start: "2026-11-20", end: "2026-11-15")
        XCTAssertEqual(range, .range(start: "2026-11-15", end: "2026-11-20"))
        XCTAssertTrue(range.contains(dayKey: "2026-11-15"))
        XCTAssertTrue(range.contains(dayKey: "2026-11-18"))
        XCTAssertTrue(range.contains(dayKey: "2026-11-20"))
        XCTAssertFalse(range.contains(dayKey: "2026-11-14"))
        XCTAssertFalse(range.contains(dayKey: "2026-11-21"))
        XCTAssertEqual(DatePeriod.normalizedRange(start: "2026-11-15", end: "2026-11-15"), .day("2026-11-15"))

        // Range shifting moves by span (6 days)
        XCTAssertEqual(range.shifted(by: 1), .range(start: "2026-11-21", end: "2026-11-26"))

        // Month period
        let nov = DatePeriod.month("2026-11")
        XCTAssertEqual(nov.startDayKey, "2026-11-01")
        XCTAssertEqual(nov.endDayKey, "2026-11-30")
        XCTAssertEqual(nov.shifted(by: 1), .month("2026-12"))
        XCTAssertEqual(DateKey.daysBetween("2026-11-15", "2026-11-20"), 5)
    }
}
