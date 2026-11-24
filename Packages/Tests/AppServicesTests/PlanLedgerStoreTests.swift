@testable import AppServices
import BudgetKit
import Persistence
import SwiftData
import TallyCore
import XCTest

/// Store-level ledger tests against an in-memory SwiftData container (never the app's store).
/// Dates are far enough in the past (or future) that the real "today" used by `reload()` cannot
/// change the outcome.
@MainActor
final class PlanLedgerStoreTests: XCTestCase {
    private var containers: [ModelContainer] = []

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    private func date(_ dayKey: String) -> Date {
        DateKey.date(fromDayKey: dayKey)!.addingTimeInterval(12 * 3600)
    }

    /// 12 monthly payments from 2025-08-15 (all due long before any real "today").
    private func pastPlan(id: String = "plan-past", updatedAt: Date? = nil) -> InstallmentPlanRecord {
        InstallmentPlanRecord(
            id: id,
            name: "Laptop IPP",
            totalMinor: 120_000,
            months: 12,
            firstPaymentDayKey: "2025-08-15",
            currency: .sgd,
            createdAt: date("2025-08-01"),
            updatedAt: updatedAt ?? date("2025-08-01")
        )
    }

    private func live(_ store: BudgetStore, planID: String) -> [TransactionRecord] {
        store.transactions
            .filter { $0.planID == planID && $0.isPlanPayment && !$0.isDeleted }
            .sorted { ($0.planPaymentIndex ?? -1) < ($1.planPaymentIndex ?? -1) }
    }

    // MARK: A — payments outliving their plan

    func testPaymentArrivingAfterSettledPlanIsWithdrawn() throws {
        let store = try makeStore()
        var plan = pastPlan()
        plan.settledDayKey = "2025-09-15"
        plan.updatedAt = date("2025-09-15")
        store.applyRemotePlans([plan])
        XCTAssertEqual(live(store, planID: plan.id).map(\.planPaymentIndex), [0, 1])

        // Another device booked October before it saw the settlement.
        let october = pastPlan().paymentTransaction(for: pastPlan().fullSchedule[2])
        store.applyRemoteTransactions([october])

        XCTAssertEqual(store.transactions.first { $0.id == october.id }?.isDeleted, true)
        XCTAssertEqual(live(store, planID: plan.id).map(\.planPaymentIndex), [0, 1])
    }

    func testPaymentDueAfterPlanDeletionIsWithdrawnWhenKeepingPayments() throws {
        let store = try makeStore()
        var deleted = pastPlan(updatedAt: date("2025-09-20"))
        deleted.isDeleted = true
        store.applyRemotePlans([deleted])

        let schedule = pastPlan().fullSchedule
        let september = pastPlan().paymentTransaction(for: schedule[1])
        let november = pastPlan().paymentTransaction(for: schedule[3])
        store.applyRemoteTransactions([september, november])

        // Booked before the deletion: kept as an ordinary expense. Due after it: withdrawn.
        XCTAssertEqual(store.transactions.first { $0.id == september.id }?.isDeleted, false)
        XCTAssertEqual(store.transactions.first { $0.id == november.id }?.isDeleted, true)
    }

    func testPaymentArrivingAfterPlanDeletedWithPaymentsIsRemoved() throws {
        let store = try makeStore()
        let plan = pastPlan()
        store.applyRemotePlans([plan])
        XCTAssertEqual(live(store, planID: plan.id).count, 12)
        store.deletePlan(id: plan.id, removePayments: true)
        XCTAssertTrue(live(store, planID: plan.id).isEmpty)

        // A device that had not seen the deletion re-books a payment later.
        let stale = plan.paymentTransaction(for: plan.fullSchedule[4])
        store.applyRemoteTransactions([stale])
        XCTAssertTrue(live(store, planID: plan.id).isEmpty)
    }

    func testRemoteDeletionWithPaymentsIsHonouredOnOtherDevice() throws {
        let deviceA = try makeStore()
        let deviceB = try makeStore()
        let plan = pastPlan()
        deviceA.applyRemotePlans([plan])
        deviceB.applyRemotePlans([plan])
        XCTAssertEqual(live(deviceB, planID: plan.id).count, 12)

        deviceA.deletePlan(id: plan.id, removePayments: true)
        // B receives only the plan tombstone (payment tombstones may arrive in a later batch).
        let tombstone = try XCTUnwrap(deviceA.plan(id: plan.id))
        deviceB.applyRemotePlans([tombstone])
        XCTAssertTrue(live(deviceB, planID: plan.id).isEmpty)
    }

    func testUserDeletedPaymentBeatsNewerAutomaticBooking() throws {
        let store = try makeStore()
        let plan = pastPlan()
        store.applyRemotePlans([plan])
        let paymentID = InstallmentPlanRecord.paymentTransactionID(planID: plan.id, index: 3)
        store.deleteTransaction(id: paymentID)
        XCTAssertEqual(store.transactions.first { $0.id == paymentID }?.isDeleted, true)

        // Device B never saw the deletion and books the same payment later (newer timestamp).
        var newerRevision = plan
        newerRevision.updatedAt = Date().addingTimeInterval(3600)
        let fresh = newerRevision.paymentTransaction(for: plan.fullSchedule[3])
        store.applyRemoteTransactions([fresh])
        XCTAssertEqual(store.transactions.first { $0.id == paymentID }?.isDeleted, true)
    }

    // MARK: B — double conversion

    func testConvertingSameExpenseOnTwoDevicesYieldsOnePlan() throws {
        let expense = TransactionRecord(
            id: "tx-shopee",
            name: "SHOPEEPAY SG IPP",
            amountMinor: 51_500,
            type: .expense,
            category: .shopping,
            dayKey: "2025-08-10",
            updatedAt: date("2025-08-10")
        )
        let deviceA = try makeStore()
        let deviceB = try makeStore()
        deviceA.applyRemoteTransactions([expense])
        deviceB.applyRemoteTransactions([expense])

        let planA = try XCTUnwrap(deviceA.convertTransactionToPlan(
            transactionID: expense.id, months: 12, firstPaymentDayKey: "2025-08-15", currency: .sgd
        ))
        let planB = try XCTUnwrap(deviceB.convertTransactionToPlan(
            transactionID: expense.id, months: 6, firstPaymentDayKey: "2025-08-15", currency: .sgd
        ))
        XCTAssertEqual(planA.id, planB.id)

        // After exchanging records both devices hold one plan and one set of payments.
        deviceA.applyRemoteTransactions(deviceB.transactions)
        deviceA.applyRemotePlans(deviceB.plans)
        deviceB.applyRemoteTransactions(deviceA.transactions)
        deviceB.applyRemotePlans(deviceA.plans)
        XCTAssertEqual(deviceA.activePlans.count, 1)
        XCTAssertEqual(deviceB.activePlans.count, 1)
        let total = deviceA.activeTransactions.filter { $0.isPlanPayment }.reduce(Int64(0)) { $0 + $1.amountMinor }
        XCTAssertEqual(total, 51_500)
    }

    // MARK: C — start moved later

    func testMovingStartLaterWithdrawsBookedPaymentsUntilDue() throws {
        let store = try makeStore()
        var plan = InstallmentPlanRecord(
            id: "plan-future",
            name: "Sofa",
            totalMinor: 120_000,
            months: 12,
            firstPaymentDayKey: "2030-09-15",
            currency: .sgd
        )
        store.savePlan(plan, todayKey: "2030-11-24")
        XCTAssertEqual(live(store, planID: plan.id).count, 3)

        plan.firstPaymentDayKey = "2031-01-15"
        store.savePlan(plan, todayKey: "2030-11-24")
        XCTAssertTrue(live(store, planID: plan.id).isEmpty, "no payment may be dated in the future")

        store.materializeDuePlanPayments(todayKey: "2031-01-20")
        let booked = live(store, planID: plan.id)
        XCTAssertEqual(booked.map(\.planPaymentIndex), [0])
        XCTAssertEqual(booked.first?.dayKey, "2031-01-15")
    }
}

@MainActor
final class PlanValidationStoreTests: XCTestCase {
    func testInvalidRemotePlanIsIgnoredAndInvalidSaveRejected() throws {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        let store = BudgetStore(context: ModelContext(container))
        var bad = InstallmentPlanRecord(id: "bad", name: "Bad", totalMinor: 120_000, months: 12, firstPaymentDayKey: "2025-01-15")
        bad.months = Int.max
        store.applyRemotePlans([bad])
        XCTAssertNil(store.plan(id: "bad"))
        XCTAssertFalse(store.savePlan(bad))
        XCTAssertNil(store.plan(id: "bad"))
    }
}

extension PlanLedgerStoreTests {
    // MARK: Already-paid payments

    func testAlreadyPaidCountPersistsAndReconcilesThroughStore() throws {
        let store = try makeStore()
        // Added with no already-paid payments: all twelve (Aug 2025 - Jul 2026) are booked.
        XCTAssertTrue(store.savePlan(pastPlan(), todayKey: "2026-11-24"))
        XCTAssertEqual(live(store, planID: "plan-past").count, 12)

        // The user explicitly edits one booked payment.
        var edited = live(store, planID: "plan-past")[1]
        edited.note = "mine"
        store.saveTransaction(edited)

        // Raising the count withdraws automatic bookings 0..<4 but keeps the explicit edit.
        var raised = try XCTUnwrap(store.plan(id: "plan-past"))
        raised.alreadyPaidPaymentCount = 4
        XCTAssertTrue(store.savePlan(raised, todayKey: "2026-11-24"))
        XCTAssertEqual(store.plan(id: "plan-past")?.alreadyPaidPaymentCount, 4, "persisted in SwiftData")
        XCTAssertEqual(live(store, planID: "plan-past").compactMap(\.planPaymentIndex), [1] + Array(4..<12))

        // Lowering it books the newly uncovered due payments again.
        var lowered = try XCTUnwrap(store.plan(id: "plan-past"))
        lowered.alreadyPaidPaymentCount = 2
        XCTAssertTrue(store.savePlan(lowered, todayKey: "2026-11-24"))
        XCTAssertEqual(live(store, planID: "plan-past").compactMap(\.planPaymentIndex), Array(1..<12))
        XCTAssertEqual(store.materializeDuePlanPayments(todayKey: "2026-11-24"), 0, "idempotent")

        // Invalid counts are rejected on save.
        var invalid = try XCTUnwrap(store.plan(id: "plan-past"))
        invalid.alreadyPaidPaymentCount = 13
        XCTAssertFalse(store.savePlan(invalid, todayKey: "2026-11-24"))
    }
}
