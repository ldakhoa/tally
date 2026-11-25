@testable import AppServices
import BudgetKit
import Persistence
import SwiftData
import TallyCore
import XCTest

@MainActor
final class CurrencySwitchTests: XCTestCase {
    private var suites: [String] = []
    private var containers: [ModelContainer] = []

    override func tearDown() async throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites = []
        containers = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "tally.tests.curr.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    private let rates = ExchangeRateTable(
        ratesPerSGD: ["SGD": 1.0, "VND": 19_000.0, "USD": 0.75],
        rateDate: "2026-11-25",
        fetchedAt: Date(timeIntervalSince1970: 1_764_000_000)
    )

    func testDisplayCurrencyPersistenceNormalizationAndFormatting() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)

        // Fresh settings has no householdSettingsRecord until explicitly set or received.
        XCTAssertEqual(settings.currency, .sgd)
        XCTAssertNil(settings.displayCurrency)
        XCTAssertEqual(settings.effectiveDisplayCurrency, .sgd)
        XCTAssertFalse(settings.isConvertingDisplay)
        XCTAssertNil(settings.householdSettingsRecord)

        // Setting display currency same as household normalizes back to nil.
        settings.displayCurrency = .sgd
        XCTAssertNil(settings.displayCurrency)
        XCTAssertFalse(settings.isConvertingDisplay)

        // Setting VND converts displayed minors, majors, strings, and daily calendar totals without mutating ledger currency.
        settings.displayCurrency = .vnd
        XCTAssertEqual(settings.currency, .sgd)
        XCTAssertEqual(settings.effectiveDisplayCurrency, .vnd)
        XCTAssertTrue(settings.isConvertingDisplay)

        XCTAssertEqual(settings.displayMinor(1_000, rates: rates), 19_000_000) // S$10 -> 190,000 VND
        XCTAssertEqual(settings.displayMajor(1_000, rates: rates), 190_000.0, accuracy: 0.01)
        XCTAssertEqual(settings.formatMoney(minor: 1_000, rates: rates), "190.000 ₫")

        let daily = [
            "2026-11-25": DailyCalendarTotal(dayKey: "2026-11-25", spendingMinor: 2_000, incomeMinor: 5_000, count: 2, includesSalary: false)
        ]
        let convertedDaily = settings.displayDailyTotals(daily, rates: rates)
        XCTAssertEqual(convertedDaily["2026-11-25"]?.spendingMinor, 38_000_000)
        XCTAssertEqual(convertedDaily["2026-11-25"]?.incomeMinor, 95_000_000)

        // Persists across relaunch
        let relaunched = AppSettings(defaults: defaults)
        XCTAssertEqual(relaunched.displayCurrency, .vnd)
        XCTAssertTrue(relaunched.isConvertingDisplay)
    }

    func testRemoteHouseholdSettingsMergeDoesNotEchoAndResolvesLWW() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        var emitted: [HouseholdSettingsRecord] = []
        settings.onHouseholdCurrencyChanged = { emitted.append($0) }

        let t1 = Date(timeIntervalSince1970: 1_000)
        settings.setHouseholdCurrency(.sgd, updatedAt: t1, notifyCloud: true)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(settings.householdSettingsRecord?.currency, .sgd)

        // Newer remote change applies without firing onHouseholdCurrencyChanged
        let t2 = Date(timeIntervalSince1970: 2_000)
        settings.applyRemoteHouseholdSettings(HouseholdSettingsRecord(currency: .vnd, updatedAt: t2))
        XCTAssertEqual(settings.currency, .vnd)
        XCTAssertEqual(settings.householdSettingsRecord?.updatedAt, t2)
        XCTAssertEqual(emitted.count, 1)

        // Older remote change is ignored
        settings.applyRemoteHouseholdSettings(HouseholdSettingsRecord(currency: .usd, updatedAt: Date(timeIntervalSince1970: 500)))
        XCTAssertEqual(settings.currency, .vnd)
    }

    func testBudgetStoreConvertCurrencyPersistsSyncsAndClearsMatchingDisplayCurrency() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.currency = .sgd
        settings.displayCurrency = .vnd

        let store = try makeStore()
        var localBatches: [[ChangedSyncRecord]] = []
        store.onLocalChanges = { localBatches.append($0) }
        var emittedHousehold: [HouseholdSettingsRecord] = []
        settings.onHouseholdCurrencyChanged = { emittedHousehold.append($0) }

        let t0 = Date(timeIntervalSince1970: 1_000)
        let tx = TransactionRecord(
            id: "tx-1", name: "FairPrice", amountMinor: 5_000, type: .expense, category: .food,
            dayKey: "2026-11-25", updatedAt: t0
        )
        let budget = BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 30_000, updatedAt: t0)
        let goal = SavingsGoalRecord(id: "g-1", name: "Emergency", targetMinor: 100_000, savedMinor: 25_000, updatedAt: t0)
        let plan = InstallmentPlanRecord(
            id: "p-1", name: "Bike", totalMinor: 60_000, months: 6,
            firstPaymentDayKey: "2026-11-10", currency: .sgd,
            createdAt: t0, updatedAt: t0
        )

        store.saveTransaction(tx, notifyCloud: false)
        store.saveBudget(budget, notifyCloud: false)
        store.saveGoal(goal, notifyCloud: false)
        XCTAssertTrue(store.savePlan(plan, todayKey: "2026-11-25", notifyCloud: false))
        XCTAssertTrue(store.hasActiveRecords)

        let tConvert = Date(timeIntervalSince1970: 5_000)
        let ok = store.convertCurrency(
            from: .sgd,
            to: .vnd,
            rates: rates,
            settings: settings,
            todayKey: "2026-11-25",
            now: tConvert,
            notifyCloud: true
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(settings.currency, .vnd)
        XCTAssertNil(settings.displayCurrency, "Matching display currency clears once household catches up")
        XCTAssertEqual(emittedHousehold.last?.currency, .vnd)
        XCTAssertEqual(emittedHousehold.last?.updatedAt, tConvert)

        // Reload cleanly from SwiftData context to ensure persistence
        store.reload()
        XCTAssertEqual(store.activeTransactions.first { $0.id == "tx-1" }?.amountMinor, 95_000_000)
        XCTAssertEqual(store.activeBudgets.first { $0.id == budget.id }?.limitMinor, 570_000_000)
        XCTAssertEqual(store.activeGoals.first { $0.id == "g-1" }?.targetMinor, 1_900_000_000)
        XCTAssertEqual(store.activeGoals.first { $0.id == "g-1" }?.savedMinor, 475_000_000)
        XCTAssertEqual(store.activePlans.first { $0.id == "p-1" }?.currency, .vnd)
        XCTAssertEqual(store.activePlans.first { $0.id == "p-1" }?.totalMinor, 1_140_000_000)

        let uploadedKinds = Set(localBatches.flatMap { $0 }.map(\.kind))
        XCTAssertTrue(uploadedKinds.contains(.transaction))
        XCTAssertTrue(uploadedKinds.contains(.budget))
        XCTAssertTrue(uploadedKinds.contains(.goal))
        XCTAssertTrue(uploadedKinds.contains(.plan))
    }

    func testImportBackupUpdatesHouseholdSettingsRecord() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        let store = try makeStore()
        var emitted: [HouseholdSettingsRecord] = []
        settings.onHouseholdCurrencyChanged = { emitted.append($0) }

        let data = try WebBackupCodec.encode(
            currency: .vnd,
            transactions: [],
            budgets: [],
            goals: [],
            plans: []
        )
        try store.importBackup(data, settings: settings)
        XCTAssertEqual(settings.currency, .vnd)
        XCTAssertEqual(settings.householdSettingsRecord?.currency, .vnd)
        XCTAssertEqual(emitted.last?.currency, .vnd)
    }
}
