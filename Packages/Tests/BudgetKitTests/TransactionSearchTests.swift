import BudgetKit
import XCTest

final class TransactionSearchTests: XCTestCase {
    func testBlankQueryMatchesEverything() {
        XCTAssertTrue(TransactionSearch.matches(query: "   ", fields: ["Grab"]))
        XCTAssertTrue(TransactionSearch.tokens("").isEmpty)
    }

    func testDiacriticAndCaseInsensitive() {
        XCTAssertTrue(TransactionSearch.matches(query: "pho", fields: ["Phở Thìn", "Ăn uống"]))
        XCTAssertTrue(TransactionSearch.matches(query: "duong", fields: ["Tiền Đường"]))
        XCTAssertTrue(TransactionSearch.matches(query: "FAIRPRICE", fields: ["NTUC FairPrice"]))
    }

    func testEveryWordMustMatchAcrossFields() {
        let fields = ["Highlands Coffee", "Food & drink", "with Linh", "S$6.50", "6.50"]
        XCTAssertTrue(TransactionSearch.matches(query: "coffee linh", fields: fields))
        XCTAssertTrue(TransactionSearch.matches(query: "food 6.5", fields: fields))
        XCTAssertFalse(TransactionSearch.matches(query: "coffee grab", fields: fields))
    }
}
