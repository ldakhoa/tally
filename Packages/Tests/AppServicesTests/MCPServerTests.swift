@testable import AppServices
import BudgetKit
import MCPKit
import Persistence
import SwiftData
import TallyCore
import XCTest

/// The MCP server end to end: a real loopback listener, real HTTP requests, an in-memory store.
@MainActor
final class MCPServerTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var suites: [String] = []
    private var servers: [MCPServer] = []
    private let token = "test-token"

    override func tearDown() async throws {
        servers.forEach { $0.stop() }
        servers = []
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

    private func makeSettings() throws -> AppSettings {
        let suite = "tally.tests.mcp.\(UUID().uuidString)"
        suites.append(suite)
        let settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        settings.currency = .sgd
        settings.language = .english
        return settings
    }

    /// Starts a server on a free port and returns its URL once it is listening.
    private func startServer(settings: AppSettings, store: BudgetStore) async throws -> URL {
        let server = MCPServer()
        servers.append(server)
        server.start(port: 0, token: token, host: TallyMCPTools.host(settings: settings, store: store))
        for _ in 0..<200 {
            if case .running(let port) = server.state {
                XCTAssertGreaterThan(port, 0)
                return try XCTUnwrap(URL(string: MCPServer.url(port: port)))
            }
            if case .failed(let message) = server.state { XCTFail(message) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw XCTSkip("listener did not become ready")
    }

    private func post(_ url: URL, _ body: String, token: String? = nil) async throws -> (status: Int, json: [String: Any]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let token = token ?? Optional(self.token), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }

    private func callTool(_ url: URL, _ name: String, _ arguments: String = "{}") async throws -> (text: String, isError: Bool) {
        let reply = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
        XCTAssertEqual(reply.status, 200)
        let result = try XCTUnwrap(reply.json["result"] as? [String: Any], "\(reply.json)")
        let text = ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        return (text, result["isError"] as? Bool ?? false)
    }

    private func toolNames(_ url: URL) async throws -> [String] {
        let reply = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((reply.json["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        return tools.compactMap { $0["name"] as? String }
    }

    private func seed(_ store: BudgetStore) {
        store.saveTransaction(TransactionRecord(name: "Salary", amountMinor: 500_000, type: .income, category: .salary, dayKey: DateKey.dayKey(from: Date())), notifyCloud: false)
        store.saveTransaction(TransactionRecord(name: "Lunch", amountMinor: 1_250, type: .expense, category: .food, dayKey: DateKey.dayKey(from: Date())), notifyCloud: false)
    }

    func testHandshakeListAndReadOverHTTP() async throws {
        let settings = try makeSettings()
        let store = try makeStore()
        seed(store)
        let url = try await startServer(settings: settings, store: store)

        let initialize = try await post(url, #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#)
        XCTAssertEqual(initialize.status, 200)
        let result = try XCTUnwrap(initialize.json["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-06-18")
        XCTAssertTrue((result["instructions"] as? String ?? "").contains("read-only"))

        let initialized = try await post(url, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        XCTAssertEqual(initialized.status, 202)

        let names = try await toolNames(url)
        XCTAssertEqual(Set(names), ExternalToolCatalog.readNames)

        let listed = try await callTool(url, "list_transactions")
        XCTAssertFalse(listed.isError, listed.text)
        XCTAssertTrue(listed.text.contains("Lunch"), listed.text)

        let summary = try await callTool(url, "summarize_period", #"{"month":"\#(DateKey.monthKey(from: Date()))"}"#)
        XCTAssertFalse(summary.isError, summary.text)
        XCTAssertTrue(summary.text.contains("12.50"), summary.text)

        let overview = try await callTool(url, "get_overview")
        XCTAssertTrue(overview.text.contains("Currency: SGD"), overview.text)
    }

    func testRequestsWithoutTheTokenAreRefused() async throws {
        let url = try await startServer(settings: try makeSettings(), store: try makeStore())
        let wrong = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#, token: "nope")
        XCTAssertEqual(wrong.status, 401)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
    }

    func testChangesAreRefusedUntilAllowed() async throws {
        let settings = try makeSettings()
        let store = try makeStore()
        let url = try await startServer(settings: settings, store: store)
        let add = #"{"items":[{"name":"Coffee","amount":4.5,"type":"expense","category":"food"}]}"#

        let refused = try await callTool(url, "add_transactions", add)
        XCTAssertTrue(refused.isError)
        XCTAssertTrue(refused.text.contains("changes are turned off"), refused.text)
        XCTAssertTrue(store.activeTransactions.isEmpty)

        // The switch takes effect on the next request, without restarting the server.
        settings.mcpAllowsChanges = true
        let names = try await toolNames(url)
        XCTAssertEqual(Set(names), ExternalToolCatalog.readNames.union(ExternalToolCatalog.writeNames))

        let added = try await callTool(url, "add_transactions", add)
        XCTAssertFalse(added.isError, added.text)
        XCTAssertEqual(store.activeTransactions.map(\.name), ["Coffee"])
        XCTAssertEqual(store.activeTransactions.first?.amountMinor, 450)
    }

    func testHiddenSalaryStaysHiddenFromClients() async throws {
        let settings = try makeSettings()
        let store = try makeStore()
        seed(store)
        settings.salaryGate.hide()
        XCTAssertTrue(settings.hideSalary)
        let url = try await startServer(settings: settings, store: store)

        let listed = try await callTool(url, "list_transactions")
        XCTAssertFalse(listed.text.contains("Salary\""), listed.text)
        XCTAssertFalse(listed.text.contains("5,000"), listed.text)
        XCTAssertTrue(listed.text.contains("salary_hidden"), listed.text)

        let summary = try await callTool(url, "summarize_period", #"{"month":"\#(DateKey.monthKey(from: Date()))"}"#)
        XCTAssertFalse(summary.text.contains("5,000"), summary.text)
        XCTAssertTrue(summary.text.contains("locked (salary hidden)"), summary.text)

        // There is no tool to ask for it.
        let reply = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"request_salary_access","arguments":{"reason":"x"}}}"#)
        XCTAssertNotNil(reply.json["error"])
    }

    func testStopClosesTheListener() async throws {
        let url = try await startServer(settings: try makeSettings(), store: try makeStore())
        servers.forEach { $0.stop() }
        XCTAssertEqual(servers.first?.state, .stopped)
        do {
            let reply = try await post(url, #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
            XCTFail("expected the connection to fail, got \(reply.status)")
        } catch {}
    }
}
