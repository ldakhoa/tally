@testable import AppServices
import BudgetKit
import ClaudeKit
import Persistence
import SwiftData
import TallyCore
import XCTest

/// Plan tools executed against an in-memory store (no network, no `AppSettings`).
@MainActor
final class AssistantPlanExecutionTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private let today = "2026-11-24"

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    private var environment: PlanToolEnvironment {
        PlanToolEnvironment(language: .english, currency: .sgd, todayKey: today, resolveMember: { _ in HouseholdMember(id: "me", name: "Alex") })
    }

    private func run(_ name: String, _ input: JSONValue, store: BudgetStore) -> AssistantService.ToolExecutionOutcome {
        let command = try! AssistantToolCatalog.decode(
            ClaudeToolUse(id: "t", name: name, input: input), defaultDayKey: today, defaultMonthKey: "2026-11"
        ).get()
        return AssistantService.executePlan(command, environment: environment, store: store)
    }

    func testCreateLoanInProgressWithAlreadyPaidPayments() throws {
        let store = try makeStore()
        let outcome = run("create_installment_plan", [
            "kind": "loan", "name": "Car loan", "amount_borrowed": 1000, "monthly_payment": 50, "months": 24,
            "first_payment_date": "2026-01-15", "lender": "DBS", "already_paid_payments": 9,
        ], store: store)
        XCTAssertFalse(outcome.isError, outcome.toolOutput)
        let plan = try XCTUnwrap(store.activePlans.first)
        XCTAssertEqual(plan.alreadyPaidPaymentCount, 9)
        XCTAssertEqual(plan.lender, "DBS")
        // Only the two due payments not already recorded elsewhere are booked.
        XCTAssertEqual(store.payments(forPlanID: plan.id).compactMap(\.planPaymentIndex), [9, 10])

        let receipt = try XCTUnwrap(outcome.receipts.first)
        XCTAssertEqual(receipt.kind, .planCreated)
        let details = (receipt.details ?? []).joined(separator: "\n")
        XCTAssertTrue(details.contains("× 24 months"), details)
        XCTAssertTrue(details.contains("First payment"), details)
        XCTAssertTrue(details.contains("effective rate"), details)
        XCTAssertTrue(details.contains("9 payments already paid"), details)
        XCTAssertTrue(outcome.toolOutput.contains("[id:\(plan.id)]"))
        XCTAssertTrue(outcome.toolOutput.contains("2 payments due so far are recorded"), outcome.toolOutput)
    }

    func testAllDuePaymentsAlreadyRecordedIsCountedByCode() throws {
        let store = try makeStore()
        // Today 2026-11-24: payments on Jan 15 ... Nov 15 are due, i.e. 11.
        let outcome = run("create_installment_plan", [
            "kind": "loan", "name": "Car loan", "amount_borrowed": 1000, "monthly_payment": 50, "months": 24,
            "first_payment_date": "2026-01-15", "all_due_payments_already_recorded": true,
        ], store: store)
        XCTAssertFalse(outcome.isError, outcome.toolOutput)
        let plan = try XCTUnwrap(store.activePlans.first)
        XCTAssertEqual(plan.alreadyPaidPaymentCount, 11)
        XCTAssertTrue(store.payments(forPlanID: plan.id).filter { !$0.isDeleted }.isEmpty, "nothing due is booked twice")

        let update = run("update_installment_plan", ["plan_id": .string(plan.id), "months": 30, "all_due_payments_already_recorded": true], store: store)
        XCTAssertFalse(update.isError, update.toolOutput)
        XCTAssertEqual(store.plan(id: plan.id)?.alreadyPaidPaymentCount, 11)
    }

    func testCreateWithMissingFiguresReturnsToolErrorAndSavesNothing() throws {
        let store = try makeStore()
        let outcome = run("create_installment_plan", ["kind": "installment", "name": "Sofa", "months": 12], store: store)
        XCTAssertTrue(outcome.isError)
        XCTAssertTrue(outcome.toolOutput.contains("total amount"), outcome.toolOutput)
        XCTAssertTrue(outcome.toolOutput.contains("first payment date"), outcome.toolOutput)
        XCTAssertTrue(store.activePlans.isEmpty)
        XCTAssertTrue(outcome.receipts.isEmpty)
    }

    func testPastStartWithoutAlreadyPaidCountTellsModelToCheck() throws {
        let store = try makeStore()
        let outcome = run("create_installment_plan", [
            "kind": "installment", "name": "Laptop", "total_amount": 1200, "months": 12, "first_payment_date": "2026-09-01",
        ], store: store)
        XCTAssertFalse(outcome.isError)
        XCTAssertTrue(outcome.toolOutput.contains("already_paid_payments"), outcome.toolOutput)
    }

    func testUpdateSettleUndoAndDelete() throws {
        let store = try makeStore()
        _ = run("create_installment_plan", [
            "kind": "loan", "name": "Car loan", "amount_borrowed": 1000, "monthly_payment": 50, "months": 24,
            "first_payment_date": "2026-01-15",
        ], store: store)
        let id = try XCTUnwrap(store.activePlans.first?.id)
        XCTAssertEqual(store.payments(forPlanID: id).count, 11)

        // Raising the already-paid count later withdraws the automatic bookings it covers.
        let update = run("update_installment_plan", ["plan_id": .string(id), "already_paid_payments": 11], store: store)
        XCTAssertFalse(update.isError, update.toolOutput)
        XCTAssertEqual(update.receipts.first?.kind, .planUpdated)
        XCTAssertTrue(store.payments(forPlanID: id).isEmpty)

        let wrongKind = run("update_installment_plan", ["plan_id": .string(id), "kind": "installment", "name": "x"], store: store)
        XCTAssertTrue(wrongKind.isError)
        let badMonths = run("update_installment_plan", ["plan_id": .string(id), "months": 6], store: store)
        XCTAssertTrue(badMonths.isError, "11 already paid > 6 months, and 6 x 50 < 1000")
        XCTAssertTrue(run("update_installment_plan", ["plan_id": "missing", "name": "x"], store: store).isError)

        let early = run("settle_installment_plan", ["plan_id": .string(id), "settled_date": "2025-12-01"], store: store)
        XCTAssertTrue(early.isError, "before the first payment")
        let settle = run("settle_installment_plan", ["plan_id": .string(id), "settled_date": "2026-11-20"], store: store)
        XCTAssertFalse(settle.isError, settle.toolOutput)
        XCTAssertEqual(store.plan(id: id)?.settledDayKey, "2026-11-20")
        XCTAssertEqual(settle.receipts.first?.kind, .planSettled)
        XCTAssertTrue(settle.toolOutput.contains("interest saved"))

        let undo = run("undo_plan_settlement", ["plan_id": .string(id)], store: store)
        XCTAssertFalse(undo.isError)
        XCTAssertNil(store.plan(id: id)?.settledDayKey)
        XCTAssertTrue(run("undo_plan_settlement", ["plan_id": .string(id)], store: store).isError, "nothing to undo")

        let delete = run("delete_installment_plan", ["plan_id": .string(id), "remove_payments": true], store: store)
        XCTAssertFalse(delete.isError)
        XCTAssertEqual(store.plan(id: id)?.isDeleted, true)
        XCTAssertEqual(store.plan(id: id)?.deletionRemovesPayments, true)
    }

    func testConvertExpenseToInstallment() throws {
        let store = try makeStore()
        let tx = TransactionRecord(name: "SHOPEEPAY SG IPP", amountMinor: 120_000, type: .expense, category: .shopping, dayKey: "2026-11-02")
        store.saveTransaction(tx)
        let missing = run("convert_transaction_to_installment", ["transaction_id": "nope", "months": 6, "first_payment_date": "2026-12-02"], store: store)
        XCTAssertTrue(missing.isError)
        let outcome = run("convert_transaction_to_installment", ["transaction_id": .string(tx.id), "months": 6, "first_payment_date": "2026-12-02"], store: store)
        XCTAssertFalse(outcome.isError, outcome.toolOutput)
        XCTAssertEqual(outcome.receipts.first?.kind, .planConverted)
        let plan = try XCTUnwrap(store.activePlans.first)
        XCTAssertEqual(plan.sourceTransactionID, tx.id)
        XCTAssertEqual(plan.totalMinor, 120_000)
        XCTAssertTrue(store.activeTransactions.allSatisfy { $0.id != tx.id }, "the source expense is replaced")
    }
}
