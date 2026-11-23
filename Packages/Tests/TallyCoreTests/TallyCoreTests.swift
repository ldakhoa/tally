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

    func testAmountKeypadEngineEntryAndArithmetic() {
        // Decimal currency (SGD)
        var sgd = AmountKeypadEngine(maxFractionDigits: 2)
        sgd.tapDigit("1")
        sgd.tapDigit("2")
        sgd.tapDecimal()
        sgd.tapDigit("5")
        sgd.tapDigit("0")
        sgd.tapDigit("9") // ignored (max 2 decimals)
        XCTAssertEqual(sgd.formattedDisplayNumber(currency: .sgd), "12.50")
        XCTAssertEqual(sgd.evaluatedValue ?? 0, 12.5, accuracy: 0.001)

        // Addition & operator precedence
        sgd.tapOperator(.add)
        sgd.tapDigit("2")
        sgd.tapOperator(.multiply)
        sgd.tapDigit("3")
        XCTAssertEqual(sgd.evaluatedValue ?? 0, 18.5, accuracy: 0.001)
        XCTAssertEqual(sgd.formattedDisplayNumber(currency: .sgd), "18.5")

        sgd.commitEvaluation()
        XCTAssertFalse(sgd.hasOperator)
        XCTAssertEqual(sgd.expression, "18.5")

        // Division (split bill)
        sgd.clear()
        sgd.tapDigit("4")
        sgd.tapDigit("8")
        sgd.tapOperator(.divide)
        sgd.tapDigit("2")
        XCTAssertEqual(sgd.evaluatedValue ?? 0, 24.0, accuracy: 0.001)

        // Zero-decimal currency (VND) with 000 shortcut
        var vnd = AmountKeypadEngine(maxFractionDigits: 0)
        vnd.tapDigit("6")
        vnd.tapDigit("5")
        vnd.tapDecimal() // ignored for VND
        vnd.tapDigit("000")
        XCTAssertEqual(vnd.formattedDisplayNumber(currency: .vnd), "65.000")
        XCTAssertEqual(vnd.evaluatedValue ?? 0, 65_000, accuracy: 0.01)
    }

    func testChineseLanguageSupport() {
        let ref = DateKey.date(fromDayKey: "2026-11-23")!
        XCTAssertEqual(AppLanguage.chinese.resolved, .chinese)
        XCTAssertEqual(AppLanguage.chinese.title(in: .english), "中文")
        XCTAssertEqual(L10n.text(.chinese, en: "Budget", vi: "Ngân sách", zh: "预算"), "预算")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-23", language: .chinese, referenceDate: ref), "今天")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-22", language: .chinese, referenceDate: ref), "昨天")
        XCTAssertEqual(DateKey.formatFullDay("2026-11-24", language: .chinese, referenceDate: ref), "明天")
        XCTAssertEqual(DateKey.formatShortMonth("2026-11", language: .chinese), "11月")
        XCTAssertEqual(DateKey.shortWeekdayLabel(weekday: 1, language: .chinese), "日")
        XCTAssertEqual(CurrencyCode.sgd.name(in: .chinese), "新加坡元")
    }

    func testAIProviderLocalization() {
        XCTAssertEqual(AIProvider.allCases, [.auto, .appleIntelligence, .claude])
        XCTAssertEqual(AIProvider.appleIntelligence.title(in: .chinese), "Apple 智能")
        XCTAssertEqual(AIProvider.auto.shortTitle(in: .vietnamese), "Tự động")
        XCTAssertEqual(AIProvider.claude.shortTitle(in: .english), "Claude")
    }
}
