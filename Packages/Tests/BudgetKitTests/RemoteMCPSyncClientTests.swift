@testable import BudgetKit
import TallyCore
import XCTest

private final class MockRemoteMCPTransport: RemoteMCPHTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (Data, Int))?
    private(set) var capturedRequests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        capturedRequests.append(request)
        guard let handler else {
            return (Data("{}".utf8), 200)
        }
        return try handler(request)
    }
}

final class RemoteMCPSyncClientTests: XCTestCase {
    private let baseURL = URL(string: "https://tally-mcp.example.workers.dev")!

    func testSyncEncodesAndDecodesFractionalISO8601DatesAndBearerHeader() async throws {
        let transport = MockRemoteMCPTransport()
        transport.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://tally-mcp.example.workers.dev/v1/sync")
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sync-secret")
            let responseJSON = """
            {
              "ok": true,
              "vaultRevision": 4,
              "remoteChanges": {
                "transactions": [
                  {
                    "id": "tx-remote",
                    "name": "Coffee",
                    "amountMinor": 450,
                    "type": "expense",
                    "category": "food",
                    "dayKey": "2026-11-25",
                    "createdAt": "2026-11-25T05:10:00.123Z",
                    "note": "",
                    "source": "aiQuickAdd",
                    "memberID": "member-primary",
                    "memberName": "Khoa",
                    "needsReview": false,
                    "updatedAt": "2026-11-25T05:10:00.123Z",
                    "isDeleted": false
                  }
                ],
                "budgets": [],
                "goals": [],
                "plans": []
              },
              "stats": {
                "transactionCount": 1,
                "budgetCount": 0,
                "goalCount": 0,
                "planCount": 0,
                "lastSyncedAt": "2026-11-25T05:10:01Z",
                "lastMCPCallAt": "2026-11-25T05:09:59.500Z",
                "lastMCPTool": "add_transactions"
              }
            }
            """
            return (Data(responseJSON.utf8), 200)
        }

        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: "sync-secret", transport: transport)
        let payload = RemoteMCPSyncPayload(
            currency: .sgd,
            language: "en",
            timeZoneOffsetMinutes: 480,
            currentMember: HouseholdMember(id: "member-primary", name: "Khoa"),
            members: [HouseholdMember(id: "member-primary", name: "Khoa")],
            salaryHidden: false,
            allowsChanges: true,
            mcpEnabled: true,
            mcpToken: "tok",
            transactions: [],
            budgets: [],
            goals: [],
            plans: [],
            sinceRevision: 2
        )

        let res = try await client.sync(payload)
        XCTAssertTrue(res.ok)
        XCTAssertEqual(res.vaultRevision, 4)
        XCTAssertEqual(res.remoteChanges.transactions.first?.id, "tx-remote")
        XCTAssertEqual(res.stats.lastMCPTool, "add_transactions")
        XCTAssertNotNil(res.stats.lastMCPCallAt)
    }

    func testUnauthorizedAndServerErrors() async {
        let transport = MockRemoteMCPTransport()
        transport.handler = { _ in (Data(), 401) }
        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: "bad", transport: transport)

        do {
            _ = try await client.health()
            XCTFail("Expected unauthorized error")
        } catch let error as RemoteMCPError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        transport.handler = { _ in (Data(), 503) }
        do {
            _ = try await client.requestPairingCode()
            XCTFail("Expected server error")
        } catch let error as RemoteMCPError {
            XCTAssertEqual(error, .serverError(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingSecretThrowsBeforeSendingRequest() async {
        let transport = MockRemoteMCPTransport()
        let client = RemoteMCPSyncClient(baseURL: baseURL, syncSecret: "  ", transport: transport)
        do {
            _ = try await client.updateConfig(RemoteMCPConfigPatch(mcpEnabled: false))
            XCTFail("Expected missingSecret")
        } catch let error as RemoteMCPError {
            XCTAssertEqual(error, .missingSecret)
            XCTAssertTrue(transport.capturedRequests.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
