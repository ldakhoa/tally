@testable import BudgetKit
import ClaudeKit
import TallyCore
import XCTest

final class ExternalToolsTests: XCTestCase {
    private let today = "2026-11-24"

    private func tx(_ day: String, _ major: Int64, _ category: CategoryID, name: String? = nil, note: String = "", member: String = "me", memberName: String = "Alex") -> TransactionRecord {
        TransactionRecord(name: name ?? category.rawValue, amountMinor: major * 100, type: category.transactionType, category: category, dayKey: day, note: note, memberID: member, memberName: memberName)
    }

    private var transactions: [TransactionRecord] {
        [
            tx("2026-10-01", 5_000, .salary),
            tx("2026-10-05", 40, .food, name: "Phở Hà Nội"),
            tx("2026-10-06", 300, .shopping, name: "IKEA", note: "sofa deposit", member: "p", memberName: "Sam"),
            tx("2026-11-01", 5_000, .salary),
            tx("2026-11-03", 200, .freelance, name: "Design gig"),
            tx("2026-11-10", 25, .food, name: "Lunch"),
            tx("2026-11-12", 60, .transport, name: "Grab"),
        ]
    }

    private func context(hidden: Bool = false) -> AdviserToolContext {
        AdviserToolContext(
            data: AdviserDataSet(transactions: transactions, budgets: [], goals: [SavingsGoalRecord(name: "Japan trip", icon: .plane, targetMinor: 400_000, savedMinor: 100_000)], plans: [], currency: .sgd, todayKey: today, salaryHidden: hidden),
            currentMemberID: "me",
            members: [HouseholdMember(id: "me", name: "Alex"), HouseholdMember(id: "p", name: "Sam")],
            salaryRequestAvailable: false
        )
    }

    private func list(_ input: JSONValue = [:], hidden: Bool = false) throws -> (output: AdviserToolOutput, json: [String: Any], names: [String]) {
        let output = try XCTUnwrap(ExternalToolCatalog.run(ClaudeToolUse(id: "t", name: "list_transactions", input: input), context: context(hidden: hidden)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.text.utf8)) as? [String: Any], output.text)
        let rows = json["transactions"] as? [[String: Any]] ?? []
        return (output, json, rows.compactMap { $0["name"] as? String })
    }

    // MARK: Catalog

    func testReadAndWriteToolsAreDisjointAndCoverTheAppsTools() {
        let read = ExternalToolCatalog.readTools.map(\.name)
        let write = ExternalToolCatalog.writeTools.map(\.name)
        XCTAssertEqual(Set(read).count, read.count)
        XCTAssertTrue(Set(read).isDisjoint(with: write))
        XCTAssertEqual(Set(read), ExternalToolCatalog.readNames)
        XCTAssertEqual(Set(write), ExternalToolCatalog.writeNames)
        // Everything Ask Tally can do, except asking for salary (no consent card outside the app).
        let app = Set(AssistantToolCatalog.allTools.map(\.name)).subtracting([SalaryAccessTool.name])
        XCTAssertEqual(Set(read + write), app.union(["get_overview", "list_transactions"]))
        XCTAssertFalse((read + write).contains(SalaryAccessTool.name))
        XCTAssertTrue(read.allSatisfy { !ExternalToolCatalog.isDestructive($0) })
        XCTAssertTrue(ExternalToolCatalog.isDestructive("delete_transaction"))
    }

    func testOtherToolsAreNotHandledHere() {
        XCTAssertNil(ExternalToolCatalog.run(ClaudeToolUse(id: "t", name: "summarize_period", input: [:]), context: context()))
    }

    // MARK: list_transactions

    func testListsNewestFirstWithSignedAmounts() throws {
        let result = try list()
        XCTAssertEqual(result.names, ["Grab", "Lunch", "Design gig", "salary", "IKEA", "Phở Hà Nội", "salary"])
        XCTAssertEqual(result.json["total_matching"] as? Int, 7)
        let rows = try XCTUnwrap(result.json["transactions"] as? [[String: Any]])
        XCTAssertEqual(rows[0]["amount"] as? String, "−S$60.00")
        XCTAssertEqual(rows[0]["amount_value"] as? Double, 60)
        XCTAssertEqual(rows[0]["category"] as? String, "transport")
        XCTAssertEqual(rows[0]["date"] as? String, "2026-11-12")
        XCTAssertEqual(rows[2]["amount"] as? String, "+S$200.00")
        XCTAssertEqual(rows[4]["member"] as? String, "Sam")
        XCTAssertEqual(rows[4]["note"] as? String, "sofa deposit")
        XCTAssertNotNil(rows[0]["id"])
        XCTAssertFalse(result.output.isError)
    }

    func testFiltersByMonthRangeCategoryTypeMemberAndSearch() throws {
        XCTAssertEqual(try list(["month": "2026-10"]).names, ["IKEA", "Phở Hà Nội", "salary"])
        XCTAssertEqual(try list(["start_date": "2026-11-10", "end_date": "2026-11-11"]).names, ["Lunch"])
        XCTAssertEqual(try list(["start_date": "2026-11-10"]).names, ["Grab", "Lunch"])
        XCTAssertEqual(try list(["category": "food"]).names, ["Lunch", "Phở Hà Nội"])
        XCTAssertEqual(try list(["type": "income", "month": "2026-11"]).names, ["Design gig", "salary"])
        XCTAssertEqual(try list(["member": "partner"]).names, ["IKEA"])
        XCTAssertEqual(try list(["member": "Sam"]).names, ["IKEA"])
        // Case- and diacritic-insensitive, in the name or the note.
        XCTAssertEqual(try list(["search": "pho ha noi"]).names, ["Phở Hà Nội"])
        XCTAssertEqual(try list(["search": "SOFA"]).names, ["IKEA"])
    }

    func testPagingReportsNextOffset() throws {
        let first = try list(["limit": 3])
        XCTAssertEqual(first.names.count, 3)
        XCTAssertEqual(first.json["next_offset"] as? Int, 3)
        let last = try list(["limit": 3, "offset": 6])
        XCTAssertEqual(last.names, ["salary"])
        XCTAssertNil(last.json["next_offset"])
        XCTAssertEqual(try list(["limit": 100_000]).names.count, 7)
    }

    func testInvalidArgumentsAreToolErrors() throws {
        for input in [
            ["month": "2026-13"], ["start_date": "yesterday"], ["end_date": "2026-02-30"],
            ["start_date": "2026-11-10", "end_date": "2026-11-01"], ["category": "pets"], ["type": "transfer"],
            ["member": "Nobody"], ["limit": 0], ["limit": 1.5], ["offset": -1],
        ] as [JSONValue] {
            let output = try XCTUnwrap(ExternalToolCatalog.run(ClaudeToolUse(id: "t", name: "list_transactions", input: input), context: context()))
            XCTAssertTrue(output.isError, "\(input)")
            XCTAssertTrue(output.text.hasPrefix("Error: "), output.text)
        }
    }

    // MARK: Salary privacy

    func testHiddenSalaryRowsAreLeftOutAndFlagged() throws {
        let result = try list(hidden: true)
        XCTAssertEqual(result.names, ["Grab", "Lunch", "Design gig", "IKEA", "Phở Hà Nội"])
        XCTAssertEqual(result.json["total_matching"] as? Int, 5)
        XCTAssertNotNil(result.json["salary_hidden"])
        XCTAssertFalse(result.output.text.contains("5,000"), result.output.text)
        XCTAssertTrue(result.output.salaryLocked)

        // A range with no salary in it says nothing about salary.
        let noSalary = try list(["category": "food"], hidden: true)
        XCTAssertNil(noSalary.json["salary_hidden"])
        // Asking for the salary category directly returns nothing.
        XCTAssertEqual(try list(["category": "salary"], hidden: true).names, [])
    }

    func testVisibleSalaryIsListedNormally() throws {
        let result = try list(["category": "salary"])
        XCTAssertEqual(result.names.count, 2)
        XCTAssertNil(result.json["salary_hidden"])
    }

    // MARK: Overview

    func testOverviewGivesDatesMembersCategoriesGoalsAndHistory() throws {
        let text = try XCTUnwrap(ExternalToolCatalog.run(ClaudeToolUse(id: "t", name: "get_overview", input: [:]), context: context())).text
        XCTAssertTrue(text.contains("Currency: SGD"), text)
        XCTAssertTrue(text.contains("Today: 2026-11-24 (Tuesday)"), text)
        XCTAssertTrue(text.contains("- Alex (\"me\""), text)
        XCTAssertTrue(text.contains("- Sam"), text)
        XCTAssertTrue(text.contains("food"), text)
        XCTAssertTrue(text.contains("Japan trip: S$1,000.00 / S$4,000.00 (25%)"), text)
        XCTAssertTrue(text.contains("Transactions on record: 7, from 2026-10-01 to 2026-11-12."), text)
        XCTAssertTrue(text.contains("Salary: visible."), text)
    }

    func testOverviewWithHiddenSalaryShowsNoSalaryFigure() throws {
        let text = try XCTUnwrap(ExternalToolCatalog.run(ClaudeToolUse(id: "t", name: "get_overview", input: [:]), context: context(hidden: true))).text
        XCTAssertTrue(text.contains("Salary: hidden by the user."), text)
        XCTAssertTrue(text.contains("locked (salary hidden)"), text)
        XCTAssertFalse(text.contains("5,000"), text)
        XCTAssertFalse(text.contains("5,200"), text)
    }

    func testInstructionsSayWhetherChangesAreAllowed() {
        XCTAssertTrue(ExternalToolCatalog.instructions(currency: .sgd, allowsChanges: false).contains("read-only"))
        let writable = ExternalToolCatalog.instructions(currency: .vnd, allowsChanges: true)
        XCTAssertTrue(writable.contains("Confirm with the user before deleting"))
        XCTAssertTrue(writable.contains("VND"))
    }
}
