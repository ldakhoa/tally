@testable import BudgetKit
import XCTest

final class AssistantReceiptIconTests: XCTestCase {
    private func receipt(_ kind: AssistantActionReceipt.Kind, _ emoji: String) -> AssistantActionReceipt {
        AssistantActionReceipt(kind: kind, emoji: emoji, title: "t", subtitle: "s")
    }

    func testEveryCategoryEmojiMapsBackToItsCategory() {
        for category in CategoryID.allCases {
            XCTAssertEqual(receipt(.transactionAdded, category.cuteEmoji).icon, .category(category))
            XCTAssertEqual(receipt(.budgetSet, category.cuteEmoji).icon, .category(category))
        }
    }

    func testEveryGoalEmojiMapsBackToItsGoalIcon() {
        for goal in GoalIcon.allCases {
            XCTAssertEqual(receipt(.goalCreated, goal.cuteEmoji).icon, .goal(goal))
        }
    }

    func testHouseEmojiDependsOnReceiptKind() {
        XCTAssertEqual(receipt(.transactionUpdated, "🏡").icon, .category(.housing))
        XCTAssertEqual(receipt(.goalUpdated, "🏡").icon, .goal(.house))
    }

    func testDeletionsAndPlans() {
        XCTAssertEqual(receipt(.transactionDeleted, "🗑️").icon, .deleted)
        XCTAssertEqual(receipt(.goalDeleted, "🗑️").icon, .deleted)
        XCTAssertEqual(receipt(.planCreated, "").icon, .plan)
        XCTAssertEqual(receipt(.planSettled, "").icon, .settled)
    }

    func testUnknownEmojiFallsBack() {
        XCTAssertEqual(receipt(.transactionAdded, "🦄").icon, .emoji("🦄"))
    }
}
