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

        // Hardware keyboard characters (Mac / iPad keyboard)
        var kb = AmountKeypadEngine(maxFractionDigits: 2)
        XCTAssertTrue(kb.handleKeyCharacter("1"))
        XCTAssertTrue(kb.handleKeyCharacter("0"))
        XCTAssertTrue(kb.handleKeyCharacter("+"))
        XCTAssertTrue(kb.handleKeyCharacter("2"))
        XCTAssertTrue(kb.handleKeyCharacter(","))
        XCTAssertTrue(kb.handleKeyCharacter("5"))
        XCTAssertTrue(kb.handleKeyCharacter("="))
        XCTAssertEqual(kb.expression, "12.5")
        XCTAssertFalse(kb.handleKeyCharacter("a"))

        var kbVND = AmountKeypadEngine(maxFractionDigits: 0)
        XCTAssertFalse(kbVND.handleKeyCharacter("."))
        XCTAssertTrue(kbVND.handleKeyCharacter("5"))
        XCTAssertTrue(kbVND.handleKeyCharacter("*"))
        XCTAssertTrue(kbVND.handleKeyCharacter("3"))
        XCTAssertEqual(kbVND.evaluatedValue ?? 0, 15, accuracy: 0.01)
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

    func testExpandedCurrenciesFormattingAndZeroDecimal() {
        XCTAssertTrue(CurrencyCode.vnd.isZeroDecimal)
        XCTAssertTrue(CurrencyCode.jpy.isZeroDecimal)
        XCTAssertTrue(CurrencyCode.krw.isZeroDecimal)
        XCTAssertTrue(CurrencyCode.idr.isZeroDecimal)
        XCTAssertFalse(CurrencyCode.hkd.isZeroDecimal)
        XCTAssertFalse(CurrencyCode.cny.isZeroDecimal)

        XCTAssertEqual(CurrencyCode.hkd.narrowSymbol, "HK$")
        XCTAssertEqual(CurrencyCode.jpy.narrowSymbol, "¥")
        XCTAssertEqual(CurrencyCode.hkd.name(in: .english), "Hong Kong Dollar")
        XCTAssertEqual(CurrencyCode.hkd.name(in: .vietnamese), "Đô la Hồng Kông")
        XCTAssertEqual(CurrencyCode.hkd.name(in: .chinese), "港元")

        let hkd = MoneyFormat.format(minor: CurrencyCode.hkd.toStorageMinor(83.75), currency: .hkd, language: .english)
        XCTAssertEqual(hkd, "HK$83.75")

        let jpy = MoneyFormat.format(minor: CurrencyCode.jpy.toStorageMinor(2_400), currency: .jpy, language: .english)
        XCTAssertEqual(jpy, "¥2,400")

        let aed = MoneyFormat.format(minor: CurrencyCode.toStorageMinor(120.5, currencyCode: "AED"), currencyCode: "AED", language: .english)
        XCTAssertEqual(aed, "AED 120.50")
    }

    func testCurrencyCodeNormalizationAndRejection() {
        XCTAssertEqual(CurrencyCode.normalizeCode("hkd"), "HKD")
        XCTAssertEqual(CurrencyCode.normalizeCode("HK$"), "HKD")
        XCTAssertEqual(CurrencyCode.normalizeCode("RMB"), "CNY")
        XCTAssertEqual(CurrencyCode.normalizeCode("NT$"), "TWD")
        XCTAssertEqual(CurrencyCode.normalizeCode(" aed "), "AED")

        XCTAssertNil(CurrencyCode.normalizeCode("SGT"))
        XCTAssertNil(CurrencyCode.normalizeCode("NOV"))
        XCTAssertNil(CurrencyCode.normalizeCode("REF"))
        XCTAssertNil(CurrencyCode.normalizeCode(""))
        XCTAssertNil(CurrencyCode.normalizeCode("XYZ"))
    }

    func testExchangeRateTableConversionAndNoMixing() {
        let hkdToSgd = ExchangeRateTable.fallback.convert(83.75, from: "HKD", to: .sgd)
        XCTAssertNotNil(hkdToSgd)
        XCTAssertEqual(hkdToSgd?.convertedMajor ?? 0, 14.32, accuracy: 0.02)
        XCTAssertEqual(hkdToSgd?.isLiveRate, false)

        let jpyToSgd = ExchangeRateTable.fallback.convert(2_400, from: "JPY", to: .sgd)
        XCTAssertNotNil(jpyToSgd)
        XCTAssertEqual(jpyToSgd?.convertedMajor ?? 0, 21.05, accuracy: 0.02)

        let aedToSgd = ExchangeRateTable.fallback.convert(27.5, from: "AED", to: .sgd)
        XCTAssertEqual(aedToSgd?.convertedMajor ?? 0, 10.0, accuracy: 0.02)

        let same = ExchangeRateTable.fallback.conversionRate(from: "SGD", to: "SGD")
        XCTAssertEqual(same?.rate, 1.0)

        // Live table missing a currency falls back cleanly as a pair (never mixing live + fallback).
        let partialLive = ExchangeRateTable(ratesPerSGD: ["SGD": 1.0, "USD": 0.70], rateDate: "2026-11-25", fetchedAt: Date())
        let hkdFallback = partialLive.conversionRate(from: "HKD", to: "USD")
        XCTAssertEqual(hkdFallback?.isLive, false)
        XCTAssertEqual(hkdFallback?.rate ?? 0, 0.75 / 5.85, accuracy: 0.0001)

        XCTAssertTrue(ExchangeRateTable.formatRate(0.17094, from: "HKD", to: .sgd).contains("1 HKD = 0.1709 SGD"))
        XCTAssertTrue(ExchangeRateTable.formatRate(1.0 / 19_000.0, from: "VND", to: .sgd).contains("1 SGD = 19,000 VND"))
    }

    func testAmountKeypadCurrencyCodeFormatting() {
        var engine = AmountKeypadEngine(initialAmountMajor: 2400, maxFractionDigits: 0)
        XCTAssertEqual(engine.formattedDisplayNumber(currencyCode: "JPY"), "2,400")
        XCTAssertEqual(engine.formattedDisplayNumber(currencyCode: "VND"), "2.400")

        engine = AmountKeypadEngine(initialAmountMajor: 83.75, maxFractionDigits: 2)
        XCTAssertEqual(engine.formattedDisplayNumber(currencyCode: "HKD"), "83.75")
        XCTAssertEqual(engine.formattedDisplayNumber(currencyCode: "AED"), "83.75")
    }

    func testConvertMinorSafetyAndPrecision() {
        let rates = ExchangeRateTable(ratesPerSGD: ["SGD": 1.0, "VND": 19_000.0, "USD": 0.75], fetchedAt: Date())

        // SGD -> VND (zero-decimal storage alignment: multiple of 100)
        let sgdMinor = CurrencyCode.sgd.toStorageMinor(65.71) // 6571 -> S$65.71 * 19_000 = 1,248,490 VND
        let vndMinor = rates.convertMinor(sgdMinor, from: .sgd, to: .vnd)
        XCTAssertEqual(vndMinor, 124_849_000)
        XCTAssertEqual(vndMinor % 100, 0)

        // VND -> SGD
        let backToSgd = rates.convertMinor(124_849_000, from: .vnd, to: .sgd)
        XCTAssertEqual(backToSgd, 6_571)

        // Negative, zero, and identity
        XCTAssertEqual(rates.convertMinor(-1_000, from: .sgd, to: .vnd), -19_000_000)
        XCTAssertEqual(rates.convertMinor(0, from: .sgd, to: .vnd), 0)
        XCTAssertEqual(rates.convertMinor(12_345, from: .sgd, to: .sgd), 12_345)

        // Extreme values never trap Int64
        XCTAssertNil(rates.convert(1e16, from: "SGD", to: .vnd))
        XCTAssertEqual(rates.convertMinor(Int64.min, from: .sgd, to: .vnd), Int64.min)
        XCTAssertEqual(rates.convertMinor(Int64.max, from: .sgd, to: .vnd), Int64.max)
    }
}
