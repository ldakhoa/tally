import BudgetKit
import ClaudeKit
import TallyCore
import XCTest

final class AssistantPlanToolsTests: XCTestCase {
    private let today = "2026-11-24"

    private func decode(_ name: String, _ input: JSONValue) -> Result<AssistantCommand, AssistantToolDecodeError> {
        AssistantToolCatalog.decode(ClaudeToolUse(id: "t1", name: name, input: input), defaultDayKey: today, defaultMonthKey: "2026-11")
    }

    private func failureMessage(_ result: Result<AssistantCommand, AssistantToolDecodeError>) -> String? {
        if case .failure(.invalidArguments(let message)) = result { return message }
        return nil
    }

    private func date(_ dayKey: String) -> Date { DateKey.date(fromDayKey: dayKey)!.addingTimeInterval(12 * 3600) }

    // MARK: Catalog

    func testCatalogOffersPlanToolsWithSchemas() throws {
        let names = AssistantToolCatalog.allTools.map(\.name)
        for name in ["add_transactions", "create_installment_plan", "convert_transaction_to_installment", "update_installment_plan",
                     "settle_installment_plan", "undo_plan_settlement", "delete_installment_plan"] {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertEqual(Set(names).count, names.count, "tool names are unique")
        let create = try XCTUnwrap(AssistantToolCatalog.allTools.first { $0.name == "create_installment_plan" })
        XCTAssertEqual(create.inputSchema["required"], ["kind", "name", "months", "first_payment_date"])
        XCTAssertEqual(create.inputSchema["properties"]?["months"]?["type"], "integer")
        let delete = try XCTUnwrap(AssistantToolCatalog.allTools.first { $0.name == "delete_installment_plan" })
        XCTAssertEqual(delete.inputSchema["required"], ["plan_id", "remove_payments"])
    }

    // MARK: create_installment_plan

    func testCreateLoanParsesAllFields() {
        let result = decode("create_installment_plan", [
            "kind": "loan", "name": " Car loan ", "amount_borrowed": 20000, "monthly_payment": 450.5, "months": 48,
            "first_payment_date": "2026-03-15", "category": "transport", "member": "partner", "lender": "DBS",
            "link": "dbs.com.sg/loans", "note": "ref 123", "already_paid_payments": 8,
        ])
        guard case .success(.createPlan(let fields)) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(fields, AssistantCommand.PlanFields(
            kind: .loan, name: "Car loan", amountMajor: 20000, monthlyPaymentMajor: 450.5, months: 48,
            firstPaymentDayKey: "2026-03-15", category: .transport, memberHint: "partner", lender: "DBS",
            link: "dbs.com.sg/loans", note: "ref 123", alreadyPaidPayments: 8
        ))
    }

    func testCreateRejectsBadInputs() {
        XCTAssertNotNil(failureMessage(decode("create_installment_plan", ["name": "x", "months": 3, "first_payment_date": "2026-11-24"])))
        XCTAssertNotNil(failureMessage(decode("create_installment_plan", ["kind": "lease", "name": "x"])))
        XCTAssertEqual(
            failureMessage(decode("create_installment_plan", ["kind": "installment", "name": "x", "total_amount": 100, "months": 2.5, "first_payment_date": "2026-11-24"])),
            "months must be a whole number"
        )
        XCTAssertEqual(
            failureMessage(decode("create_installment_plan", ["kind": "installment", "name": "x", "total_amount": -5, "months": 2, "first_payment_date": "2026-11-24"])),
            "total_amount must be a positive number"
        )
        XCTAssertNotNil(failureMessage(decode("create_installment_plan", ["kind": "installment", "name": "x", "total_amount": 100, "months": 2, "first_payment_date": "15/03/2026"])))
        XCTAssertNotNil(failureMessage(decode("create_installment_plan", ["kind": "installment", "name": "x", "total_amount": 100, "months": 2, "first_payment_date": "2026-11-24", "category": "salary"])))
        XCTAssertNotNil(failureMessage(decode("create_installment_plan", ["kind": "installment", "name": "x", "total_amount": 100, "months": 2, "first_payment_date": "2026-11-24", "already_paid_payments": -1])))
        // A loan described only by its total repaid: the model must ask for the principal.
        let loanTotal = failureMessage(decode("create_installment_plan", ["kind": "loan", "name": "x", "total_amount": 100, "months": 2, "first_payment_date": "2026-11-24"]))
        XCTAssertTrue(loanTotal?.contains("amount_borrowed") == true)
    }

    func testCreateWithMissingFiguresIsDecodedThenRejectedByDraftValidation() {
        // Missing values are not guessed: the shared draft validation reports them.
        guard case .success(.createPlan(let fields)) = decode("create_installment_plan", ["kind": "loan", "name": "Personal loan", "amount_borrowed": 5000]) else {
            return XCTFail()
        }
        let draft = AssistantPlanDrafts.newDraft(fields, currency: .sgd, member: HouseholdMember(id: "me", name: "Alex"))
        XCTAssertEqual(draft.issues, [.invalidMonths, .invalidFirstPaymentDay, .missingMonthlyPayment])
        let message = AssistantPlanDrafts.issuesDescription(draft)
        XCTAssertTrue(message.hasPrefix("Not saved."))
        XCTAssertTrue(message.contains("monthly payment"))
        XCTAssertTrue(message.contains("first payment date"))
        XCTAssertTrue(message.contains("do not guess"))
    }

    func testCreateDraftMatchesManualEditorRules() throws {
        let fields = AssistantCommand.PlanFields(
            kind: .loan, name: "Car loan", amountMajor: 1000, monthlyPaymentMajor: 40, months: 24, firstPaymentDayKey: "2026-01-15"
        )
        let below = AssistantPlanDrafts.newDraft(fields, currency: .sgd, member: HouseholdMember(id: "me", name: "Alex"))
        XCTAssertEqual(below.issues, [.paymentsBelowPrincipal(shortfallMinor: 4_000)])
        XCTAssertTrue(AssistantPlanDrafts.issuesDescription(below).contains("less than the amount borrowed"))

        var ok = fields
        ok.monthlyPaymentMajor = 50
        ok.alreadyPaidPayments = 9
        let draft = AssistantPlanDrafts.newDraft(ok, currency: .sgd, member: HouseholdMember(id: "me", name: "Alex"))
        XCTAssertEqual(draft.category, .bills, "loans default to bills like the editor")
        let record = try XCTUnwrap(draft.makeRecord(now: date("2026-11-24")))
        XCTAssertEqual(record.monthlyPaymentMinor, 5_000)
        XCTAssertEqual(record.principalMinor, 100_000)
        XCTAssertEqual(record.totalMinor, 120_000)
        XCTAssertEqual(record.alreadyPaidPaymentCount, 9)
        XCTAssertEqual(record.memberName, "Alex")

        var tooMany = ok
        tooMany.alreadyPaidPayments = 30
        XCTAssertEqual(AssistantPlanDrafts.newDraft(tooMany, currency: .sgd, member: HouseholdMember(id: "me", name: "A")).issues, [.alreadyPaidOutOfRange(maxCount: 24)])
    }

    // MARK: convert / update / settle / undo / delete

    func testConvertParsing() {
        XCTAssertEqual(
            try? decode("convert_transaction_to_installment", ["transaction_id": "tx-1", "months": 12, "first_payment_date": "2026-12-01"]).get(),
            .convertTransactionToPlan(transactionID: "tx-1", months: 12, firstPaymentDayKey: "2026-12-01")
        )
        XCTAssertNotNil(failureMessage(decode("convert_transaction_to_installment", ["months": 12, "first_payment_date": "2026-12-01"])))
        XCTAssertTrue(failureMessage(decode("convert_transaction_to_installment", ["transaction_id": "tx-1", "first_payment_date": "2026-12-01"]))?.contains("ask the user") == true)
        XCTAssertTrue(failureMessage(decode("convert_transaction_to_installment", ["transaction_id": "tx-1", "months": 12]))?.contains("ask the user") == true)
    }

    func testUpdateParsingAndDraft() throws {
        guard case .success(.updatePlan(let id, let fields)) = decode("update_installment_plan", ["plan_id": "p1", "monthly_payment": 55, "already_paid_payments": 3]) else {
            return XCTFail()
        }
        XCTAssertEqual(id, "p1")
        XCTAssertEqual(fields.monthlyPaymentMajor, 55)
        XCTAssertNotNil(failureMessage(decode("update_installment_plan", ["plan_id": "p1"])), "nothing to change")
        XCTAssertNotNil(failureMessage(decode("update_installment_plan", ["monthly_payment": 55])))

        let plan = InstallmentPlanRecord.loan(id: "p1", name: "Car", principalMinor: 100_000, monthlyPaymentMinor: 5_000, months: 24, firstPaymentDayKey: "2026-01-15", currency: .sgd)
        let draft = AssistantPlanDrafts.updatedDraft(fields, plan: plan, member: nil)
        let record = try XCTUnwrap(draft.makeRecord(existing: plan, now: date("2026-11-24")))
        XCTAssertEqual(record.id, "p1")
        XCTAssertEqual(record.monthlyPaymentMinor, 5_500)
        XCTAssertEqual(record.alreadyPaidPaymentCount, 3)
        XCTAssertEqual(record.name, "Car")
    }

    func testSettleUndoDeleteParsing() {
        XCTAssertEqual(try? decode("settle_installment_plan", ["plan_id": "p1"]).get(), .settlePlan(planID: "p1", dayKey: today))
        XCTAssertEqual(try? decode("settle_installment_plan", ["plan_id": "p1", "settled_date": "2026-10-01"]).get(), .settlePlan(planID: "p1", dayKey: "2026-10-01"))
        XCTAssertNotNil(failureMessage(decode("settle_installment_plan", ["plan_id": "p1", "settled_date": "yesterday"])))
        XCTAssertEqual(try? decode("undo_plan_settlement", ["plan_id": "p1"]).get(), .undoPlanSettlement(planID: "p1"))
        XCTAssertNotNil(failureMessage(decode("undo_plan_settlement", [:])))
        XCTAssertEqual(try? decode("delete_installment_plan", ["plan_id": "p1", "remove_payments": false]).get(), .deletePlan(planID: "p1", removePayments: false))
        let missingChoice = failureMessage(decode("delete_installment_plan", ["plan_id": "p1"]))
        XCTAssertTrue(missingChoice?.contains("Ask the user") == true)
    }

    // MARK: Receipts

    func testReceiptLinesStateSavedValues() {
        let loan = InstallmentPlanRecord.loan(
            id: "p1", name: "Car loan", principalMinor: 100_000, monthlyPaymentMinor: 5_000, months: 24,
            firstPaymentDayKey: "2026-01-15", currency: .sgd, lender: "DBS", alreadyPaidPaymentCount: 9
        )
        let lines = AssistantPlanSummary.detailLines(for: loan, todayKey: today, language: .english)
        let text = lines.joined(separator: "\n")
        XCTAssertTrue(text.contains("× 24 months"), text)
        XCTAssertTrue(text.contains(MoneyFormat.format(minor: 5_000, currency: .sgd, language: .english)), text)
        XCTAssertTrue(text.contains("First payment"), text)
        XCTAssertTrue(text.contains(InstallmentRateFormat.percent(loan.effectiveAnnualRate, language: .english)), text)
        XCTAssertTrue(text.contains("9 payments already paid"), text)
        XCTAssertTrue(text.contains("DBS"))
        XCTAssertEqual(AssistantPlanSummary.detailLines(for: loan, todayKey: today, language: .vietnamese).count, lines.count)

        let summary = AssistantPlanSummary.modelSummary(for: loan, todayKey: today)
        XCTAssertTrue(summary.contains("[id:p1]"))
        XCTAssertTrue(summary.contains("24 months"))
        XCTAssertTrue(summary.contains("first payment 2026-01-15"))
        XCTAssertTrue(summary.contains("effective annual rate 18."), summary)
        XCTAssertTrue(summary.contains("9 payments already paid"))
    }

    // MARK: Plan context

    func testPlanContextListsPlansCompactly() {
        let loan = InstallmentPlanRecord.loan(
            id: "loan-1", name: "Car loan", principalMinor: 100_000, monthlyPaymentMinor: 5_000, months: 24,
            firstPaymentDayKey: "2026-01-15", currency: .sgd, lender: "DBS", alreadyPaidPaymentCount: 9
        )
        let phone = InstallmentPlanRecord(id: "ipp-1", name: "iPhone", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2025-06-01", currency: .sgd)
        var gone = phone
        gone.id = "gone"
        gone.isDeleted = true
        let lines = BudgetAssistantPrompt.planContextLines(plans: [phone, loan, gone], todayKey: today, currency: .sgd)
        XCTAssertEqual(lines.count, 3)
        let loanLine = lines[0]
        XCTAssertTrue(loanLine.hasPrefix("- [id:loan-1] Car loan · loan"), loanLine)
        XCTAssertTrue(loanLine.contains("paid 11/24"), loanLine)
        XCTAssertTrue(loanLine.contains("9 paid before/outside Tally"), loanLine)
        XCTAssertTrue(loanLine.contains("next 2026-12-15"), loanLine)
        XCTAssertTrue(loanLine.contains("lender DBS"), loanLine)
        XCTAssertTrue(loanLine.contains("active"), loanLine)
        XCTAssertTrue(lines[1].contains("[id:ipp-1]") && lines[1].contains("completed"), lines[1])
        XCTAssertFalse(lines.joined().contains("gone"))
        XCTAssertTrue(lines[2].hasPrefix("Total still to pay on active plans: "), lines[2])
    }

    func testPromptIncludesPlansAndKeepsSalaryHidden() {
        let txs = [
            TransactionRecord(name: "Acme payroll", amountMinor: 123_456_00, type: .income, category: .salary, dayKey: "2026-11-02", memberID: "a", memberName: "Alex"),
            TransactionRecord(name: "Lunch", amountMinor: 12_00, type: .expense, category: .food, dayKey: "2026-11-03", memberID: "a", memberName: "Alex"),
        ]
        let snapshot = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: txs, allBudgets: [], todayKey: "2026-11-03")
        let loan = InstallmentPlanRecord.loan(id: "loan-1", name: "Car loan", principalMinor: 100_000, monthlyPaymentMinor: 5_000, months: 24, firstPaymentDayKey: "2026-01-15", currency: .usd)
        let now = DateKey.date(fromDayKey: "2026-11-03")!
        let hidden = BudgetAssistantPrompt.systemPrompt(snapshot: snapshot, goals: [], plans: [loan], currency: .usd, language: .english, now: now, hideSalary: true)
        XCTAssertTrue(hidden.contains("[id:loan-1] Car loan"))
        XCTAssertTrue(hidden.contains("create_installment_plan"))
        XCTAssertTrue(hidden.contains("NEVER invent"))
        XCTAssertTrue(hidden.contains("already recorded in Tally"))
        XCTAssertFalse(hidden.contains(MoneyFormat.format(minor: 123_456_00, currency: .usd, language: .english)))
        XCTAssertFalse(hidden.contains("Acme payroll"))
        XCTAssertFalse(hidden.contains("Monthly income:"))

        let noPlans = BudgetAssistantPrompt.systemPrompt(snapshot: snapshot, goals: [], currency: .usd, language: .english, now: now)
        XCTAssertTrue(noPlans.contains("No plans"))
    }
}
