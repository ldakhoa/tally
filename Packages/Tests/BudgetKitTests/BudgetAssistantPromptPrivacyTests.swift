import BudgetKit
import TallyCore
import XCTest

final class BudgetAssistantPromptPrivacyTests: XCTestCase {
    private lazy var snap: MonthlySnapshot = makeSnapshot()

    private func makeSnapshot() -> MonthlySnapshot {
        let txs = [
            TransactionRecord(id: "salary-1", name: "Acme payroll", amountMinor: 123_456_00, type: .income, category: .salary, dayKey: "2026-11-02", memberID: "a", memberName: "Alex"),
            TransactionRecord(name: "Lunch", amountMinor: 12_00, type: .expense, category: .food, dayKey: "2026-11-03", memberID: "a", memberName: "Alex"),
        ]
        return MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: txs, allBudgets: [], todayKey: "2026-11-03")
    }

    private func prompt(hide: Bool? = nil) -> String {
        let now = DateKey.date(fromDayKey: "2026-11-03") ?? Date()
        if let hide {
            return BudgetAssistantPrompt.systemPrompt(snapshot: snap, goals: [], currency: .usd, language: .english, now: now, hideSalary: hide)
        }
        return BudgetAssistantPrompt.systemPrompt(snapshot: snap, goals: [], currency: .usd, language: .english, now: now)
    }

    func testHiddenPromptContainsNoSalaryFigures() {
        let income = MoneyFormat.format(minor: 123_456_00, currency: .usd, language: .english)
        let hidden = prompt(hide: true)
        XCTAssertFalse(hidden.contains(income))
        XCTAssertFalse(hidden.contains("1,234.56"))
        XCTAssertFalse(hidden.contains("Monthly income:"))
        XCTAssertFalse(hidden.contains("Net savings"))
        XCTAssertFalse(hidden.contains("Acme payroll"))
        XCTAssertFalse(hidden.contains("[id:salary-1]"))
        XCTAssertTrue(hidden.contains("hidden salary figures"))
        XCTAssertTrue(hidden.contains("Lunch"))
        XCTAssertTrue(hidden.contains("Monthly spending"))
    }

    func testVisiblePromptUnchangedByDefault() {
        let income = MoneyFormat.format(minor: 123_456_00, currency: .usd, language: .english)
        let shown = prompt(hide: false)
        XCTAssertEqual(shown, prompt())
        XCTAssertTrue(shown.contains("Monthly income: \(income)"))
        XCTAssertTrue(shown.contains("Net savings:"))
        XCTAssertTrue(shown.contains("Acme payroll"))
        XCTAssertFalse(shown.contains("hidden salary figures"))
    }
}
