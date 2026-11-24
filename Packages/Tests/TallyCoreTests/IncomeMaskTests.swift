import TallyCore
import XCTest

final class IncomeMaskTests: XCTestCase {
    func testMaskedReturnsPlaceholderWhenHidden() {
        let text = MoneyFormat.format(minor: 1_234_500, currency: .sgd)
        XCTAssertEqual(MoneyFormat.masked(text, hidden: true), "•••")
        XCTAssertFalse(MoneyFormat.masked(text, hidden: true).contains("$"))
    }

    func testMaskedPassesValueThroughWhenVisible() {
        let text = MoneyFormat.format(minor: 1_234_500, currency: .sgd)
        XCTAssertEqual(MoneyFormat.masked(text, hidden: false), text)
    }

    func testMaskedDoesNotEvaluateValueWhenHidden() {
        var evaluated = false
        _ = MoneyFormat.masked({ evaluated = true; return "x" }(), hidden: true)
        XCTAssertFalse(evaluated)
    }
}
