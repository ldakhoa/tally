@testable import AppServices
import BudgetKit
import Persistence
import SwiftData
import TallyCore
import XCTest

/// One person using two devices (each with its own random member ID) ends up as one member.
@MainActor
final class MemberReconcileTests: XCTestCase {
    private let mac = "9E6595E6-FC66-45FB-81D5-B7E2135A132B"
    private let phone = "E616A422-11E6-43E7-80F6-853C270DCD40"
    private var containers: [ModelContainer] = []
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeDevice(memberID: String, name: String) throws -> (BudgetStore, AppSettings) {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        let suite = "tally.test.\(UUID().uuidString)"
        suites.append(suite)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.myMemberID = memberID
        settings.myDisplayName = name
        return (BudgetStore(context: ModelContext(container)), settings)
    }

    private func tx(_ id: String, member: String, name: String = "Khoa") -> TransactionRecord {
        TransactionRecord(
            id: id, name: "Lunch", amountMinor: 1_000, type: .expense, category: .food,
            dayKey: "2025-08-15", memberID: member, memberName: name,
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    func testBothDevicesSettleOnOneMemberAndStopRewriting() throws {
        let shared = [tx("a", member: mac), tx("b", member: phone), tx("c", member: "other-id", name: "Linh")]
        let (macStore, macSettings) = try makeDevice(memberID: mac, name: "Khoa")
        let (phoneStore, phoneSettings) = try makeDevice(memberID: phone, name: "Khoa")
        macStore.applyRemoteTransactions(shared)
        phoneStore.applyRemoteTransactions(shared)

        XCTAssertEqual(macStore.reconcileMemberIdentities(settings: macSettings, notifyCloud: false), 1)
        XCTAssertEqual(phoneStore.reconcileMemberIdentities(settings: phoneSettings, notifyCloud: false), 1)

        XCTAssertEqual(macSettings.myMemberID, mac)
        XCTAssertEqual(phoneSettings.myMemberID, mac, "the phone adopts the shared ID")
        for store in [macStore, phoneStore] {
            let byID = Dictionary(uniqueKeysWithValues: store.transactions.map { ($0.id, $0.memberID) })
            XCTAssertEqual(byID, ["a": mac, "b": mac, "c": "other-id"])
        }

        // Each device then sees the other's result and has nothing left to change.
        macStore.applyRemoteTransactions(phoneStore.transactions)
        phoneStore.applyRemoteTransactions(macStore.transactions)
        XCTAssertEqual(macStore.reconcileMemberIdentities(settings: macSettings, notifyCloud: false), 0)
        XCTAssertEqual(phoneStore.reconcileMemberIdentities(settings: phoneSettings, notifyCloud: false), 0)
        XCTAssertEqual(macStore.knownMembers(settings: macSettings).filter { $0.name == "Khoa" }.count, 1)
    }

    func testPlanAndItsPaymentsMoveToTheSharedMember() throws {
        let (store, settings) = try makeDevice(memberID: mac, name: "Khoa")
        let plan = InstallmentPlanRecord(
            id: "plan-1", name: "Laptop IPP", totalMinor: 120_000, months: 12,
            firstPaymentDayKey: "2025-08-15", memberID: phone, memberName: "Khoa", currency: .sgd,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        store.applyRemotePlans([plan])
        XCTAssertFalse(store.payments(forPlanID: "plan-1").isEmpty)

        store.reconcileMemberIdentities(settings: settings, notifyCloud: false)

        XCTAssertEqual(store.plan(id: "plan-1")?.memberID, mac)
        XCTAssertEqual(Set(store.payments(forPlanID: "plan-1").map(\.memberID)), [mac])
        XCTAssertEqual(store.reconcileMemberIdentities(settings: settings, notifyCloud: false), 0)
    }
}
