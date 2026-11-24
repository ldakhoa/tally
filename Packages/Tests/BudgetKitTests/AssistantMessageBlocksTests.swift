@testable import BudgetKit
import XCTest

final class AssistantMessageBlocksTests: XCTestCase {
    func testPlainTextStaysOneBlock() {
        let text = "Hello **there**\n\n1. One\n2. Two"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [.text(text)])
    }

    func testTableBetweenParagraphs() {
        let text = """
        I read all four screens.

        | # | Plan | Monthly |
        |---|---|---|
        | 17 | IL 24M @ 11% + 4% fee | S$610.00 |
        | 18 | Apple Online Store (0%) | S$167.00 |

        I need these from you:
        """
        XCTAssertEqual(AssistantMessageBlock.parse(text), [
            .text("I read all four screens."),
            .table(headers: ["#", "Plan", "Monthly"], rows: [
                ["17", "IL 24M @ 11% + 4% fee", "S$610.00"],
                ["18", "Apple Online Store (0%)", "S$167.00"],
            ]),
            .text("I need these from you:"),
        ])
    }

    func testTableWithoutOuterPipesAndAlignmentColons() {
        let text = "Plan | Paid\n:--- | ---:\nLaptop | 3"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [
            .table(headers: ["Plan", "Paid"], rows: [["Laptop", "3"]]),
        ])
    }

    func testShortAndLongRowsAreNormalisedToHeaderWidth() {
        let text = "| A | B |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [
            .table(headers: ["A", "B"], rows: [["1", ""], ["1", "2"]]),
        ])
    }

    func testEscapedPipeStaysInsideCell() {
        let text = "| A | B |\n|---|---|\n| x \\| y | 2 |"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [
            .table(headers: ["A", "B"], rows: [["x | y", "2"]]),
        ])
    }

    func testHeaderWithoutSeparatorIsNotATable() {
        // While a reply is still streaming, the header arrives before its separator line.
        let text = "Totals:\n| A | B |"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [.text(text)])
    }

    func testPipeInProseIsNotATable() {
        let text = "Use a | b here\n--- not a separator"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [.text(text)])
    }

    func testSeparatorColumnCountMustMatchHeader() {
        let text = "| A | B |\n|---|"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [.text(text)])
    }

    func testTableWithNoRowsYet() {
        let text = "| A | B |\n|---|---|"
        XCTAssertEqual(AssistantMessageBlock.parse(text), [.table(headers: ["A", "B"], rows: [])])
    }
}
