@testable import AppServices
import BudgetKit
import Persistence
import SwiftData
import TallyCore
import XCTest

private final class MockSyncTransport: RemoteMCPHTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (Data, Int))?
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let handler else { return (Data("{\"ok\":true}".utf8), 200) }
        return try handler(request)
    }
}

@MainActor
final class RemoteMCPSyncTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var suites: [String] = []

    override func tearDown() async throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites = []
        containers = []
    }

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "tally.tests.remote-mcp.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testBidirectionalSyncAppliesRemoteChangesAndForwardsToCloudWithoutLoop() async throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.currency = .sgd
        settings.cloudMCPURL = "https://tally-mcp.example.workers.dev"

        let store = try makeStore()
        var cloudForwarded: [ChangedSyncRecord] = []
        store.onLocalChanges = { changes in
            cloudForwarded.append(contentsOf: changes)
        }

        let creds = KeychainStore.CloudMCPCredentials(
            url: "https://tally-mcp.example.workers.dev",
            syncSecret: "sync-secret",
            accessToken: "access-token"
        )
        let transport = MockSyncTransport()
        transport.handler = { req in
            XCTAssertEqual(req.url?.path, "/v1/sync")
            let body = try XCTUnwrap(req.httpBody)
            let decoded = try RemoteMCPSyncClient.makeDecoder().decode(RemoteMCPSyncPayload.self, from: body)
            XCTAssertEqual(decoded.transactions.count, 1)
            XCTAssertEqual(decoded.sinceRevision, 0)

            let remoteTx = TransactionRecord(
                id: "remote-tx-1",
                name: "MRT",
                amountMinor: 210,
                type: .expense,
                category: .transport,
                dayKey: DateKey.dayKey(from: Date()),
                source: .aiQuickAdd,
                memberID: settings.currentMember.id,
                memberName: settings.currentMember.name
            )
            let reply = RemoteMCPSyncResult(
                ok: true,
                vaultRevision: 7,
                remoteChanges: RemoteMCPRemoteChanges(transactions: [remoteTx]),
                stats: RemoteMCPStats(transactionCount: 2, lastMCPCallAt: Date(), lastMCPTool: "add_transactions")
            )
            return (try RemoteMCPSyncClient.makeEncoder().encode(reply), 200)
        }

        // Seed 1 local transaction
        store.saveTransaction(TransactionRecord(
            id: "local-tx-1",
            name: "Laksa",
            amountMinor: 650,
            type: .expense,
            category: .food,
            dayKey: DateKey.dayKey(from: Date())
        ), notifyCloud: false)

        // Inject a RemoteMCPSync with deterministic credentials override and isCloudMCPConfigured simulated
        // Note: AppSettings.hasCloudMCPCredentials reads Keychain, so use a custom settings or bypass via connectAndSync?
        // Instead let's test connectAndSync? No, saveCloudMCP writes Keychain in real tests — let's check if we should avoid Keychain writes in test:
        // Wait: AppSettings.isCloudMCPConfigured checks `hasCloudMCPCredentials`. Let's test `RemoteMCPSync.syncNow` when `settings` has credentials or expose a test seam?
        // Even better: let's test `RemoteMCPSync.pushConfig` & `syncNow` by testing `BudgetStore.applyRemoteTransactions(..., notifyCloud: true)` AND let's add a small `@testable` helper on AppSettings or check Keychain availability!
        // Let's check: in `swift test`, KeychainStore works on macOS without entitlements (falls back to `.local`)!
        // Still, we MUST clean up Keychain if touched, OR better: add `internal var testHasCloudMCPCredentialsOverride: Bool?` on `AppSettings` so tests NEVER touch the user's real iCloud Keychain!
        settings.testHasCloudMCPCredentialsOverride = true

        let sync = RemoteMCPSync(
            defaults: defaults,
            transport: transport,
            credentialsProvider: { creds }
        )
        var mutationCount = 0
        sync.attach(settings: settings, store: store)
        let obsID = store.addMutationObserver { mutationCount += 1 }
        defer { store.removeMutationObserver(obsID) }

        let ok = await sync.syncNow(settings: settings, store: store, exchangeRates: .fallback)
        XCTAssertTrue(ok)
        XCTAssertEqual(sync.vaultRevision, 7)
        XCTAssertEqual(sync.lastMCPTool, "add_transactions")
        XCTAssertEqual(store.activeTransactions.count, 2)
        XCTAssertTrue(store.activeTransactions.contains(where: { $0.id == "remote-tx-1" }))
        // Forwarded to CloudSync so iCloud receives the MCP-created transaction!
        XCTAssertTrue(cloudForwarded.contains(ChangedSyncRecord(kind: .transaction, id: "remote-tx-1")))
        XCTAssertEqual(mutationCount, 1)
    }

    func testPushConfigAndPairingCode() async throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.cloudMCPURL = "https://tally-mcp.example.workers.dev"
        settings.mcpAllowsChanges = true
        settings.cloudMCPEnabled = false
        settings.testHasCloudMCPCredentialsOverride = true

        let creds = KeychainStore.CloudMCPCredentials(
            url: "https://tally-mcp.example.workers.dev",
            syncSecret: "sync-secret",
            accessToken: "tok-999"
        )
        let transport = MockSyncTransport()
        transport.handler = { req in
            if req.url?.path == "/v1/config" {
                let patch = try RemoteMCPSyncClient.makeDecoder().decode(RemoteMCPConfigPatch.self, from: XCTUnwrap(req.httpBody))
                XCTAssertEqual(patch.mcpEnabled, false)
                XCTAssertEqual(patch.allowsChanges, true)
                XCTAssertEqual(patch.mcpToken, "tok-999")
                return (Data("{\"ok\":true}".utf8), 200)
            }
            if req.url?.path == "/v1/pairing-code" {
                return (Data("{\"code\":\"123456\",\"expiresAt\":\"2026-11-25T06:00:00.000Z\"}".utf8), 200)
            }
            return (Data("{}".utf8), 404)
        }

        let sync = RemoteMCPSync(defaults: defaults, transport: transport, credentialsProvider: { creds })
        let pushed = await sync.pushConfig(settings: settings)
        XCTAssertTrue(pushed)

        await sync.requestPairingCode(settings: settings)
        XCTAssertEqual(sync.pairingCode, "123456")
        XCTAssertNotNil(sync.pairingCodeExpiresAt)
    }
}
