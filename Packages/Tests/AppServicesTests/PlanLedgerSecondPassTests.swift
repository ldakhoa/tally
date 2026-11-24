@testable import AppServices
import BudgetKit
import Persistence
import SwiftData
import SyncKit
import TallyCore
import XCTest

/// Second review pass, items 2 and 4, against in-memory stores (never the app's store).
@MainActor
final class PlanLedgerSecondPassTests: XCTestCase {
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

    private func tx(_ store: BudgetStore, _ id: String) -> TransactionRecord? {
        store.transactions.first { $0.id == id }
    }

    // MARK: Item 2 — stale automatic writes

    func testStaleRevisionBookingCannotUndoPlanEdit() throws {
        let store = try makeStore()
        let old = InstallmentPlanRecord(id: "p2", name: "TV", totalMinor: 12_000, months: 12, firstPaymentDayKey: "2025-08-15", updatedAt: date("2025-08-01"))
        store.applyRemotePlans([old])
        var edited = old
        edited.totalMinor = 24_000
        store.savePlan(edited)
        let id = InstallmentPlanRecord.paymentTransactionID(planID: "p2", index: 2)
        XCTAssertEqual(tx(store, id)?.amountMinor, 2_000)

        // A device still on the old revision books the payment later (any wall-clock time).
        let stale = old.paymentTransaction(for: old.fullSchedule[2])
        store.applyRemoteTransactions([stale])
        XCTAssertEqual(tx(store, id)?.amountMinor, 2_000)
    }

    func testOlderRevisionBookingIsRewrittenToLocalPlan() throws {
        // This device holds revision 2 but had not booked the payment; another device on
        // revision 1 did. The arriving booking is reconciled against the local plan.
        let store = try makeStore()
        let old = InstallmentPlanRecord(id: "p5", name: "TV", totalMinor: 12_000, months: 12, firstPaymentDayKey: "2030-01-15", updatedAt: date("2029-12-01"))
        var newer = old
        newer.totalMinor = 24_000
        newer.updatedAt = date("2029-12-10")
        store.applyRemotePlans([newer], todayKey: "2029-12-31")
        var changes: [ChangedSyncRecord] = []
        store.onLocalChanges = { changes += $0 }
        store.applyRemoteTransactions([old.paymentTransaction(for: old.fullSchedule[0])], todayKey: "2030-01-20")
        let id = InstallmentPlanRecord.paymentTransactionID(planID: "p5", index: 0)
        XCTAssertEqual(tx(store, id)?.amountMinor, 2_000)
        XCTAssertEqual(changes.map(\.id), [id], "the rewrite is announced to CloudSync")
    }

    func testStaleSettledRevisionWithdrawalCannotHideDuePayment() throws {
        let store = try makeStore()
        let plan = InstallmentPlanRecord(id: "p3", name: "TV", totalMinor: 12_000, months: 12, firstPaymentDayKey: "2025-08-15", updatedAt: date("2025-08-01"))
        store.applyRemotePlans([plan])
        let id = InstallmentPlanRecord.paymentTransactionID(planID: "p3", index: 4)
        let booked = try XCTUnwrap(tx(store, id))
        store.settlePlan(id: "p3", on: "2025-09-20")
        let settledRevision = try XCTUnwrap(store.plan(id: "p3"))
        store.settlePlan(id: "p3", on: nil)
        XCTAssertEqual(tx(store, id)?.isDeleted, false)

        // A device still on the settled revision withdraws the payment afterwards.
        let staleWithdrawal = PlanPaymentLedger.reconcile(plan: settledRevision, payments: [booked], todayKey: "2026-01-01", bookMissing: false)
        XCTAssertEqual(staleWithdrawal.map(\.isDeleted), [true])
        store.applyRemoteTransactions(staleWithdrawal)
        XCTAssertEqual(tx(store, id)?.isDeleted, false)
        store.applyRemotePlans([try XCTUnwrap(store.plan(id: "p3"))])
        XCTAssertEqual(tx(store, id)?.isDeleted, false)
    }

    /// Two devices hold the same plan revision but their local days differ (time zones): the
    /// payment due on the later device's day is booked there; the earlier device keeps it and
    /// neither device writes again after the exchange.
    func testSameRevisionDevicesOnDifferentDaysDoNotPingPong() throws {
        let ahead = try makeStore()   // local day 2030-03-15
        let behind = try makeStore()  // local day 2030-03-14
        let plan = InstallmentPlanRecord(id: "p6", name: "Sofa", totalMinor: 12_000, months: 12, firstPaymentDayKey: "2030-01-15", updatedAt: date("2025-01-01"))
        ahead.applyRemotePlans([plan], todayKey: "2030-03-15")
        behind.applyRemotePlans([plan], todayKey: "2030-03-14")
        let id = InstallmentPlanRecord.paymentTransactionID(planID: "p6", index: 2)
        XCTAssertEqual(tx(ahead, id)?.isDeleted, false)
        XCTAssertNil(tx(behind, id))

        var aheadOut: [ChangedSyncRecord] = []
        var behindOut: [ChangedSyncRecord] = []
        ahead.onLocalChanges = { aheadOut += $0 }
        behind.onLocalChanges = { behindOut += $0 }
        for _ in 0..<3 {
            behind.applyRemoteTransactions(ahead.transactions, todayKey: "2030-03-14")
            behind.applyRemotePlans(ahead.plans, todayKey: "2030-03-14")
            ahead.applyRemoteTransactions(behind.transactions, todayKey: "2030-03-15")
            ahead.applyRemotePlans(behind.plans, todayKey: "2030-03-15")
        }
        XCTAssertTrue(aheadOut.isEmpty, "\(aheadOut)")
        XCTAssertTrue(behindOut.isEmpty, "\(behindOut)")
        XCTAssertEqual(tx(behind, id), tx(ahead, id))
        XCTAssertEqual(tx(behind, id)?.isDeleted, false)

        // Moving the start later on the behind device withdraws it there at a newer revision;
        // the ahead device adopts the withdrawal and re-derives the same result.
        var moved = try XCTUnwrap(behind.plan(id: "p6"))
        moved.firstPaymentDayKey = "2030-04-15"
        behind.savePlan(moved, todayKey: "2030-03-14")
        ahead.applyRemotePlans(behind.plans, todayKey: "2030-03-15")
        ahead.applyRemoteTransactions(behind.transactions, todayKey: "2030-03-15")
        behind.applyRemoteTransactions(ahead.transactions, todayKey: "2030-03-14")
        XCTAssertEqual(tx(ahead, id), tx(behind, id))
        XCTAssertEqual(tx(ahead, id)?.isDeleted, true)
    }

    // MARK: Item 4 — conversion

    private func expense() -> TransactionRecord {
        TransactionRecord(id: "tx-c", name: "IPP", amountMinor: 51_500, type: .expense, category: .shopping, dayKey: "2025-08-10", updatedAt: date("2025-08-10"))
    }

    func testConversionReusesCanonicalPlanThatArrivedBeforeSourceTombstone() throws {
        let a = try makeStore()
        let b = try makeStore()
        a.applyRemoteTransactions([expense()])
        b.applyRemoteTransactions([expense()])
        let planA = try XCTUnwrap(a.convertTransactionToPlan(transactionID: "tx-c", months: 12, firstPaymentDayKey: "2025-08-15", currency: .sgd))
        // B receives the plan (and its payments) but not yet the source's tombstone.
        b.applyRemotePlans([planA])
        XCTAssertEqual(tx(b, "tx-c")?.isDeleted, false)

        let planB = try XCTUnwrap(b.convertTransactionToPlan(transactionID: "tx-c", months: 6, firstPaymentDayKey: "2025-08-15", currency: .sgd))
        XCTAssertEqual(planB, planA)
        XCTAssertEqual(b.plans.count, 1)
        XCTAssertEqual(tx(b, "tx-c")?.isDeleted, true)
        XCTAssertEqual(tx(b, "tx-c")?.planID, planA.id)
        XCTAssertTrue(tx(b, "tx-c")?.isConvertedPlanSource ?? false)
    }

    func testConversionAfterDeletedCanonicalPlanUsesNextDeterministicID() throws {
        let deleted = InstallmentPlanRecord(id: "conv-tx-c", name: "IPP", totalMinor: 51_500, months: 12, firstPaymentDayKey: "2025-08-15", updatedAt: date("2025-09-01"), isDeleted: true)
        var ids: [String] = []
        for _ in 0..<2 {
            let store = try makeStore()
            store.applyRemoteTransactions([expense()])
            store.applyRemotePlans([deleted])
            let plan = try XCTUnwrap(store.convertTransactionToPlan(transactionID: "tx-c", months: 6, firstPaymentDayKey: "2025-08-15", currency: .sgd))
            ids.append(plan.id)
            XCTAssertEqual(store.activePlans.map(\.id), [plan.id])
        }
        XCTAssertEqual(ids, ["conv-tx-c-2", "conv-tx-c-2"])
    }
}

@MainActor
final class PlanPaymentEditTests: XCTestCase {
    func testEditorSaveKeepsPaymentIdentityAndIsNotRebooked() throws {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        let store = BudgetStore(context: ModelContext(container))
        let plan = InstallmentPlanRecord(id: "pe", name: "Phone", totalMinor: 12_000, months: 12, firstPaymentDayKey: "2025-08-15", updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
        store.applyRemotePlans([plan])
        let id = InstallmentPlanRecord.paymentTransactionID(planID: "pe", index: 0)
        let booked = try XCTUnwrap(store.transactions.first { $0.id == id })

        // The editor builds a fresh record from the visible fields only.
        let edited = TransactionRecord(
            id: id, name: "Phone (adjusted)", amountMinor: 1_050, type: .expense, category: booked.category,
            dayKey: booked.dayKey, createdAt: booked.createdAt, memberID: booked.memberID
        )
        store.saveTransaction(edited)
        store.materializeDuePlanPayments()
        let saved = try XCTUnwrap(store.transactions.first { $0.id == id })
        XCTAssertEqual(saved.planID, "pe")
        XCTAssertEqual(saved.planPaymentIndex, 0)
        XCTAssertTrue(saved.hasUserPaymentWrite)
        XCTAssertEqual(saved.amountMinor, 1_050)
    }
}
