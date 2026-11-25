@testable import AppServices
import BudgetKit
import ClaudeKit
import Persistence
import SwiftData
import TallyCore
import XCTest

@MainActor
final class ExchangeRateServiceTests: XCTestCase {
    private var suites: [String] = []
    private var containers: [ModelContainer] = []

    override func tearDown() async throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites = []
        containers = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "tally.tests.fx.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    func testServiceCachesRatesAndRespectsMaxAge() async throws {
        struct CountingTransport: FXHTTPTransport {
            let payload: Data
            let counter: LockCounter
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                await counter.increment()
                return (payload, 200)
            }
        }
        actor LockCounter {
            var count = 0
            func increment() { count += 1 }
        }

        let rates: [String: Double] = [
            "sgd": 1.0, "hkd": 5.82, "usd": 0.74, "vnd": 18900, "jpy": 113, "cny": 5.4,
            "eur": 0.68, "gbp": 0.59, "aud": 1.15, "cad": 1.04, "myr": 3.3, "krw": 1040,
            "thb": 25.8, "twd": 24.2, "idr": 11900, "php": 43.5, "nzd": 1.26, "chf": 0.66,
            "inr": 63.5, "aed": 2.75,
        ]
        let payload = try JSONSerialization.data(withJSONObject: ["date": "2026-11-25", "sgd": rates])
        let defaults = try makeDefaults()
        let counter = LockCounter()
        let client = ExchangeRateClient(transport: CountingTransport(payload: payload, counter: counter))
        let service = ExchangeRateService(defaults: defaults, client: client, updatesSharedCurrent: false)

        XCTAssertFalse(service.table.isLive)

        let t0 = Date(timeIntervalSince1970: 1_764_000_000)
        await service.refreshIfStale(maxAge: 3600, now: t0)
        XCTAssertTrue(service.table.isLive)
        XCTAssertEqual(service.table.ratesPerSGD["HKD"], 5.82)
        let firstCount = await counter.count
        XCTAssertEqual(firstCount, 1)

        // Within maxAge: does not re-fetch
        await service.refreshIfStale(maxAge: 3600, now: t0.addingTimeInterval(60))
        let secondCount = await counter.count
        XCTAssertEqual(secondCount, 1)

        // New instance restores cached table from UserDefaults without hitting network
        let restored = ExchangeRateService(defaults: defaults, client: client, updatesSharedCurrent: false)
        XCTAssertTrue(restored.table.isLive)
        XCTAssertEqual(restored.table.ratesPerSGD["HKD"], 5.82)

        // Network failure preserves cached live table rather than wiping it
        struct FailingTransport: FXHTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                throw URLError(.notConnectedToInternet)
            }
        }
        let offlineService = ExchangeRateService(
            defaults: defaults,
            client: ExchangeRateClient(transport: FailingTransport()),
            updatesSharedCurrent: false
        )
        await offlineService.refreshNow()
        XCTAssertNotNil(offlineService.lastError)
        XCTAssertTrue(offlineService.table.isLive)
        XCTAssertEqual(offlineService.table.ratesPerSGD["HKD"], 5.82)
    }

    func testAssistantForeignTransactionPersistsThroughSwiftData() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.currency = .sgd
        settings.language = .english
        let store = try makeStore()

        let tool = ClaudeToolUse(
            id: "fx-save",
            name: AssistantToolCatalog.addTransactionsName,
            input: [
                "items": [
                    [
                        "name": "PinDuoDuo",
                        "amount": 83.75,
                        "currency": "HKD",
                        "type": "expense",
                        "category": "shopping",
                        "day_key": "2026-11-25",
                        "note": "Freedom card",
                    ]
                ]
            ]
        )
        let outcome = AssistantService.execute(toolUse: tool, settings: settings, store: store)
        XCTAssertFalse(outcome.isError)
        XCTAssertEqual(outcome.receipts.count, 1)
        XCTAssertTrue(outcome.receipts.first?.details?.first?.contains("HK$83.75") == true)
        XCTAssertTrue(outcome.toolOutput.contains("HK$83.75"))

        store.reload()
        let saved = try XCTUnwrap(store.activeTransactions.first)
        XCTAssertEqual(outcome.receipts.first?.recordID, saved.id)
        XCTAssertEqual(saved.originalAmountMinor, 8_375)
        XCTAssertEqual(saved.originalCurrencyCode, "HKD")
        XCTAssertNotNil(saved.exchangeRate)
        XCTAssertEqual(CurrencyCode.sgd.toMajor(saved.amountMinor), 14.32, accuracy: 0.05)
    }
}
