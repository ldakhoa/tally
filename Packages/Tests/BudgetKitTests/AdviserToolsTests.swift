@testable import BudgetKit
import ClaudeKit
import TallyCore
import XCTest

final class AdviserToolsTests: XCTestCase {
    private let today = "2026-11-24"

    private func tx(_ day: String, _ major: Int64, _ category: CategoryID, member: String = "me", memberName: String = "Alex") -> TransactionRecord {
        TransactionRecord(name: category.rawValue, amountMinor: major * 100, type: category.transactionType, category: category, dayKey: day, memberID: member, memberName: memberName)
    }

    private var transactions: [TransactionRecord] {
        [
            tx("2026-08-01", 5_000, .salary), tx("2026-08-05", 2_500, .food),
            tx("2026-09-01", 5_000, .salary), tx("2026-09-05", 2_750, .food),
            tx("2026-10-01", 5_000, .salary), tx("2026-10-05", 2_900, .food), tx("2026-10-06", 300, .food, member: "p", memberName: "Sam"),
            tx("2026-11-01", 5_000, .salary), tx("2026-11-10", 300, .food),
        ]
    }

    private func context(hidden: Bool = false, requestAvailable: Bool = true, goals: [SavingsGoalRecord] = [], plans: [InstallmentPlanRecord] = []) -> AdviserToolContext {
        AdviserToolContext(
            data: AdviserDataSet(transactions: transactions, budgets: [], goals: goals, plans: plans, currency: .sgd, todayKey: today, salaryHidden: hidden),
            currentMemberID: "me",
            members: [HouseholdMember(id: "me", name: "Alex"), HouseholdMember(id: "p", name: "Sam")],
            salaryRequestAvailable: requestAvailable
        )
    }

    private func decode(_ name: String, _ input: JSONValue = [:]) -> Result<AdviserQuery, AssistantToolDecodeError> {
        AdviserToolCatalog.decode(ClaudeToolUse(id: "t", name: name, input: input), currency: .sgd, todayKey: today)
    }

    private func message(_ result: Result<AdviserQuery, AssistantToolDecodeError>) -> String? {
        if case .failure(.invalidArguments(let text)) = result { return text }
        return nil
    }

    private func run(_ name: String, _ input: JSONValue = [:], context: AdviserToolContext? = nil) throws -> (output: AdviserToolOutput, json: [String: Any]) {
        let output = AdviserToolCatalog.run(ClaudeToolUse(id: "t", name: name, input: input), context: context ?? self.context())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.text.utf8)) as? [String: Any], output.text)
        return (output, json)
    }

    // MARK: Catalog

    func testCatalogExposesAdviserAndSalaryToolsOnce() {
        let names = AssistantToolCatalog.allTools.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        for name in AdviserToolCatalog.names.union([SalaryAccessTool.name]) {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertEqual(AdviserToolCatalog.tools.count, AdviserToolCatalog.names.count)
    }

    // MARK: Parsing

    func testDecodesInputs() {
        XCTAssertEqual(try decode(AdviserToolCatalog.cashFlowName).get(), .cashFlow(months: 12))
        XCTAssertEqual(try decode(AdviserToolCatalog.cashFlowName, ["months": 3]).get(), .cashFlow(months: 3))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.cashFlowName, ["months": 13])))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.cashFlowName, ["months": 2.5])))

        XCTAssertEqual(try decode(AdviserToolCatalog.budgetsName, ["category": "food"]).get(), .budgets(category: .food))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.budgetsName, ["category": "salary"])))

        XCTAssertEqual(
            try decode(AdviserToolCatalog.affordabilityName, ["amount": 10_000, "months": 12, "annual_rate_percent": 6]).get(),
            .affordability(AffordabilityInput(amountMinor: 1_000_000, months: 12, annualRatePercent: 6))
        )
        XCTAssertEqual(
            try decode(AdviserToolCatalog.affordabilityName, ["amount": "2500.5", "months": 6, "monthly_payment": 430]).get(),
            .affordability(AffordabilityInput(amountMinor: 250_050, months: 6, monthlyPaymentMinor: 43_000))
        )
        XCTAssertTrue(message(decode(AdviserToolCatalog.affordabilityName, ["months": 12]))?.contains("amount is required") == true)
        XCTAssertTrue(message(decode(AdviserToolCatalog.affordabilityName, ["amount": 100]))?.contains("months is required") == true)
        XCTAssertNotNil(message(decode(AdviserToolCatalog.affordabilityName, ["amount": -1, "months": 2])))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.affordabilityName, ["amount": 100, "months": 2, "annual_rate_percent": 400])))

        XCTAssertEqual(
            try decode(AdviserToolCatalog.goalPlanName, ["goal_name": "Japan", "target_date": "2027-05-31", "monthly_contribution": 800]).get(),
            .goalPlan(.init(goalName: "Japan", targetMonthKey: "2027-05", contributionMinor: 80_000))
        )
        XCTAssertEqual(try decode(AdviserToolCatalog.goalPlanName, ["target_amount": 5_000, "target_date": "2027-01"]).get(),
                       .goalPlan(.init(targetMinor: 500_000, targetMonthKey: "2027-01")))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.goalPlanName, ["target_date": "2027-01"])))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.goalPlanName, ["goal_id": "g", "target_date": "next May"])))

        XCTAssertEqual(try decode(AdviserToolCatalog.earlySettlementName, ["plan_id": "car"]).get(), .earlySettlement(planID: "car", dayKey: nil))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.earlySettlementName, ["plan_id": "car", "settle_date": "2026-02-30"])))

        XCTAssertEqual(try decode(AdviserToolCatalog.runwayName, ["cash_amount": 0]).get(), .runway(cashMinor: 0))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.runwayName)))

        XCTAssertEqual(try decode(AdviserToolCatalog.periodName, ["month": "2026-10"]).get(),
                       .period(startDayKey: "2026-10-01", endDayKey: "2026-10-31", category: nil, member: nil))
        XCTAssertEqual(try decode(AdviserToolCatalog.periodName, ["start_date": "2026-11-20"]).get(),
                       .period(startDayKey: "2026-11-20", endDayKey: today, category: nil, member: nil), "end defaults to today")
        XCTAssertEqual(try decode(AdviserToolCatalog.periodName, ["start_date": "2026-11-20", "end_date": "2026-11-01", "category": "food", "member": "partner"]).get(),
                       .period(startDayKey: "2026-11-01", endDayKey: "2026-11-20", category: .food, member: "partner"), "a reversed range is swapped")
        XCTAssertNotNil(message(decode(AdviserToolCatalog.periodName)))
        XCTAssertNotNil(message(decode(AdviserToolCatalog.periodName, ["month": "2026-13"])))
    }

    func testVNDAmountsUseWholeDongStorage() {
        let result = AdviserToolCatalog.decode(
            ClaudeToolUse(id: "t", name: AdviserToolCatalog.runwayName, input: ["cash_amount": 50_000_000]),
            currency: .vnd, todayKey: today
        )
        XCTAssertEqual(try result.get(), .runway(cashMinor: 5_000_000_000))
    }

    // MARK: Rendering

    func testCashFlowResultCarriesComputedFiguresAndNotes() throws {
        let (output, json) = try run(AdviserToolCatalog.cashFlowName)
        XCTAssertFalse(output.isError)
        XCTAssertFalse(output.salaryLocked)
        XCTAssertNil(json["salary_locked"])
        let averages = try XCTUnwrap(json["averages"] as? [String: Any])
        // Spending 2,500 / 2,750 / 3,200 -> 2,816.67; income 5,000; net 2,183.33; rate 43.7%.
        XCTAssertEqual(averages["spending"] as? String, MoneyFormat.format(minor: 281_667, currency: .sgd))
        XCTAssertEqual(averages["income"] as? String, MoneyFormat.format(minor: 500_000, currency: .sgd))
        XCTAssertEqual(averages["net"] as? String, MoneyFormat.format(minor: 218_333, currency: .sgd))
        XCTAssertEqual(averages["savings_rate"] as? String, "43.7%")
        XCTAssertEqual((json["months"] as? [Any])?.count, 3)
        XCTAssertEqual(json["complete_months_with_transactions"] as? Int, 3)
        XCTAssertTrue((json["notes"] as? [String])?.contains(AdviserRules.averagesRule) == true)
        XCTAssertEqual((json["top_category_movers"] as? [Any])?.count, 1, "food: Oct 3,200 vs earlier average 2,625")
    }

    func testHiddenSalaryIsLockedAndNeverRendered() throws {
        for name in [AdviserToolCatalog.cashFlowName, AdviserToolCatalog.debtName, AdviserToolCatalog.goalsName, AdviserToolCatalog.periodName] {
            let input: JSONValue = name == AdviserToolCatalog.periodName ? ["month": "2026-10"] : [:]
            let (output, json) = try run(name, input, context: context(hidden: true, goals: [SavingsGoalRecord(name: "Trip", targetMinor: 100_000)]))
            for secret in ["5,000.00", "15,000.00", "2,183.33", "43.7%"] {
                XCTAssertFalse(output.text.contains(secret), "\(name) leaked \(secret): \(output.text)")
            }
            if name != AdviserToolCatalog.debtName || output.text.contains(AdviserRenderer.lockedText) {
                XCTAssertTrue(output.salaryLocked, name)
                XCTAssertTrue((json["salary_locked"] as? String)?.contains("request_salary_access") == true, name)
            }
        }
        let (_, json) = try run(AdviserToolCatalog.cashFlowName, context: context(hidden: true))
        let averages = try XCTUnwrap(json["averages"] as? [String: Any])
        XCTAssertEqual(averages["income"] as? String, AdviserRenderer.lockedText)
        XCTAssertEqual(averages["spending"] as? String, MoneyFormat.format(minor: 281_667, currency: .sgd), "spending stays visible")

        let (_, again) = try run(AdviserToolCatalog.cashFlowName, context: context(hidden: true, requestAvailable: false))
        let note = try XCTUnwrap(again["salary_locked"] as? String)
        XCTAssertTrue(note.contains("already requested"))
        XCTAssertFalse(note.contains("call request_salary_access"))
    }

    func testCalculatorsAndErrors() throws {
        let (afford, json) = try run(AdviserToolCatalog.affordabilityName, ["amount": 10_000, "months": 12, "annual_rate_percent": 6])
        XCTAssertFalse(afford.isError)
        XCTAssertEqual(json["monthly_payment"] as? String, MoneyFormat.format(minor: 86_066, currency: .sgd))
        XCTAssertEqual(json["annual_rate"] as? String, "6.00%")

        let bad = AdviserToolCatalog.run(ClaudeToolUse(id: "t", name: AdviserToolCatalog.affordabilityName, input: ["amount": 10_000, "months": 12, "monthly_payment": 10]), context: context())
        XCTAssertTrue(bad.isError)
        XCTAssertTrue(bad.text.hasPrefix("Error: monthly_payment x months is less than the amount"))

        let goal = SavingsGoalRecord(id: "jp", name: "Japan trip", targetMinor: 1_000_000, savedMinor: 0)
        let (_, plan) = try run(AdviserToolCatalog.goalPlanName, ["goal_name": "japan", "target_date": "2027-05"], context: context(goals: [goal]))
        let byDate = try XCTUnwrap(plan["by_target_date"] as? [String: Any])
        XCTAssertEqual(byDate["monthly_contributions"] as? Int, 6)
        XCTAssertEqual(byDate["required_monthly_contribution"] as? String, MoneyFormat.format(minor: 166_667, currency: .sgd)) // 10,000 / 6 rounded up
        let missing = AdviserToolCatalog.run(ClaudeToolUse(id: "t", name: AdviserToolCatalog.goalPlanName, input: ["goal_name": "Car"]), context: context(goals: [goal]))
        XCTAssertTrue(missing.isError)

        let (_, runway) = try run(AdviserToolCatalog.runwayName, ["cash_amount": 10_000])
        XCTAssertEqual(runway["months_of_spending_covered"] as? String, "3.5")

        let loan = InstallmentPlanRecord.loan(id: "car", name: "Car", principalMinor: 1_000_000, monthlyPaymentMinor: 86_066, months: 12, firstPaymentDayKey: "2026-10-05")
        let (_, settle) = try run(AdviserToolCatalog.earlySettlementName, ["plan_id": "car"], context: context(plans: [loan]))
        XCTAssertNotNil((settle["settlement"] as? [String: Any])?["interest_saved"])
        XCTAssertTrue(AdviserToolCatalog.run(ClaudeToolUse(id: "t", name: AdviserToolCatalog.earlySettlementName, input: ["plan_id": "nope"]), context: context()).isError)

        let (_, debt) = try run(AdviserToolCatalog.debtName, context: context(plans: [loan]))
        XCTAssertEqual((debt["payoff_order_highest_rate_first"] as? [String])?.first?.hasPrefix("1. [id:car] Car"), true)
        XCTAssertEqual(debt["debt_service_to_income"] as? String, "17.2%") // 860.66 / 5,000
    }

    func testPeriodMemberResolution() throws {
        let (_, sam) = try run(AdviserToolCatalog.periodName, ["month": "2026-10", "member": "partner"])
        XCTAssertEqual(sam["spending"] as? String, MoneyFormat.format(minor: 30_000, currency: .sgd))
        let (_, me) = try run(AdviserToolCatalog.periodName, ["month": "2026-10", "member": "me", "category": "food"])
        XCTAssertEqual(me["spending"] as? String, MoneyFormat.format(minor: 290_000, currency: .sgd))
        let unknown = AdviserToolCatalog.run(ClaudeToolUse(id: "t", name: AdviserToolCatalog.periodName, input: ["month": "2026-10", "member": "Bob"]), context: context())
        XCTAssertTrue(unknown.isError)
    }

    // MARK: Context

    func testSnapshotLinesAreShortAndRespectSalary() {
        let lines = AdviserSnapshot.lines(data: context().data)
        XCTAssertLessThanOrEqual(lines.count, 4)
        XCTAssertTrue(lines[0].contains("3 complete month(s)"))
        XCTAssertTrue(lines[1].contains(MoneyFormat.format(minor: 281_667, currency: .sgd)))
        let hidden = AdviserSnapshot.lines(data: context(hidden: true).data)
        XCTAssertFalse(hidden.joined().contains("5,000.00"))
        XCTAssertTrue(hidden.joined().contains(AdviserRenderer.lockedText))
        let empty = AdviserSnapshot.lines(data: AdviserDataSet(transactions: [], budgets: [], goals: [], plans: [], currency: .sgd, todayKey: today, salaryHidden: false))
        XCTAssertTrue(empty[0].contains("no complete month"))
        XCTAssertFalse(empty.joined().contains("nan"))
    }

    func testDateContextResolvesRelativeDays() {
        let lines = AssistantDateContext.lines(todayKey: "2026-11-24")
        XCTAssertEqual(lines[0], "Today: 2026-11-24 (Tuesday). Tomorrow: 2026-11-25. Weeks start on Monday.")
        XCTAssertTrue(lines[1].hasPrefix("Previous 14 days: 2026-11-23 Monday (yesterday), 2026-11-22 Sunday, 2026-11-21 Saturday, 2026-11-20 Friday"))
        XCTAssertTrue(lines[1].contains("2026-11-10 Tuesday."))
        XCTAssertEqual(lines[2], "This week: 2026-11-23 to 2026-11-29; last week: 2026-11-16 to 2026-11-22.")
        XCTAssertEqual(lines[3], "This month: 2026-11 (2026-11-01 to 2026-11-30); last month: 2026-10 (2026-10-01 to 2026-10-31); next month: 2026-12.")
        XCTAssertEqual(AssistantDateContext.weekStart("2026-11-29"), "2026-11-23", "Sunday belongs to the week starting Monday")
        XCTAssertEqual(AssistantDateContext.weekStart("2026-03-02"), "2026-03-02")
        XCTAssertEqual(AssistantDateContext.lines(todayKey: "2026-03-01")[3], "This month: 2026-03 (2026-03-01 to 2026-03-31); last month: 2026-02 (2026-02-01 to 2026-02-28); next month: 2026-04.")
    }

    func testPromptIsAdviserWithDatesComputedBudgetsAndSnapshot() {
        let budgets = [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 25_000)]
        let snapshot = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: transactions, allBudgets: budgets, todayKey: today)
        let goal = SavingsGoalRecord(id: "g1", name: "Trip", targetMinor: 100_000, savedMinor: 40_000)
        let prompt = BudgetAssistantPrompt.systemPrompt(
            snapshot: snapshot, goals: [goal], currency: .usd, language: .english,
            now: DateKey.date(fromDayKey: today)!, adviserSnapshot: ["- History: test line"]
        )
        XCTAssertTrue(prompt.contains("financial adviser"))
        XCTAssertTrue(prompt.contains("request_salary_access"))
        XCTAssertTrue(prompt.contains("do not recommend specific securities"))
        XCTAssertTrue(prompt.contains("Today: 2026-11-24 (Tuesday)"))
        XCTAssertTrue(prompt.contains("- History: test line"))
        XCTAssertTrue(prompt.contains("$300.00 / $250.00 (120% used, over by $50.00)"), prompt)
        XCTAssertTrue(prompt.contains("still needed $600.00"))
        XCTAssertTrue(prompt.contains("NEVER invent"))
        XCTAssertTrue(prompt.contains("Savings rate: "))
    }

    // MARK: Helpers for record keeping

    func testBudgetStatusLineAfterSaving() {
        let budgets = [BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 25_000)]
        let line = AssistantBudgetStatus.line(category: .food, monthKey: "2026-11", transactions: transactions, budgets: budgets, currency: .sgd)
        XCTAssertEqual(line, "Budget food 2026-11: spent \(MoneyFormat.format(minor: 30_000, currency: .sgd)) of \(MoneyFormat.format(minor: 25_000, currency: .sgd)) (120.0% used), over by \(MoneyFormat.format(minor: 5_000, currency: .sgd)).")
        XCTAssertNil(AssistantBudgetStatus.line(category: .bills, monthKey: "2026-11", transactions: transactions, budgets: budgets, currency: .sgd))
    }

    func testStatedForeignCurrencyIsConvertedByCode() {
        let same = AssistantAmounts.storageMinor(amountMajor: 12.5, stated: .sgd, household: .sgd, note: "", language: .english)
        XCTAssertEqual(same.minor, 1_250)
        XCTAssertEqual(same.note, "")
        let converted = AssistantAmounts.storageMinor(amountMajor: 190_000, stated: .vnd, household: .sgd, note: "lunch", language: .english)
        XCTAssertEqual(converted.minor, 1_000) // 190,000 ₫ at the app's 19,000 ₫ per S$1
        XCTAssertTrue(converted.note.hasPrefix("lunch · Orig: "))

        let decoded = AssistantToolCatalog.decode(
            ClaudeToolUse(id: "t", name: AssistantToolCatalog.addTransactionsName, input: ["items": [["name": "Pho", "amount": 65_000, "type": "expense", "category": "food", "currency": "vnd"]]]),
            defaultDayKey: today, defaultMonthKey: "2026-11"
        )
        guard case .success(.addTransactions(let items)) = decoded else { return XCTFail() }
        XCTAssertEqual(items.first?.currency, .vnd)
    }

    // MARK: Salary access protocol

    func testSalaryAccessReasonAndResults() {
        XCTAssertNil(SalaryAccessTool.reason(from: [:]))
        XCTAssertNil(SalaryAccessTool.reason(from: ["reason": "  \n "]))
        XCTAssertEqual(SalaryAccessTool.reason(from: ["reason": "To check\nyour savings rate."]), "To check your savings rate.")
        XCTAssertEqual(SalaryAccessTool.reason(from: ["reason": .string(String(repeating: "a", count: 500))])?.count, SalaryAccessTool.maxReasonLength)

        XCTAssertTrue(SalaryAccessOutcome.granted.toolResult.hasPrefix("granted"))
        XCTAssertTrue(SalaryAccessOutcome.alreadyVisible.toolResult.hasPrefix("granted"))
        for outcome: SalaryAccessOutcome in [.declined, .authFailed, .cancelled, .alreadyRequested, .unavailable] {
            XCTAssertTrue(outcome.toolResult.hasPrefix("declined"), "\(outcome)")
            XCTAssertTrue(outcome.toolResult.contains("Do not estimate"), "\(outcome)")
            XCTAssertFalse(outcome.isGranted)
        }
        XCTAssertTrue(SalaryAccessOutcome.invalid.isError)
        XCTAssertEqual(SalaryConsentRecord.status(for: .granted), .allowed)
        XCTAssertEqual(SalaryConsentRecord.status(for: .authFailed), .authFailed)
        XCTAssertEqual(SalaryConsentRecord.status(for: .cancelled), .cancelled)
        XCTAssertEqual(SalaryConsentRecord.status(for: .declined), .declined)
        for language in [AppLanguage.english, .vietnamese, .chinese] {
            XCTAssertFalse(SalaryConsentRecord(reason: "r", status: .pending).title(in: language).isEmpty)
        }
    }

    func testConsentRecordRoundTrips() throws {
        let record = SalaryConsentRecord(reason: "To work out your savings rate.", status: .declined, askedAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(SalaryConsentRecord.self, from: data), record)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("Minor"), "a consent record holds no amounts")
    }
}
