import BudgetKit
import ClaudeKit
import TallyCore
import XCTest

private struct MockAIClient: AIClient {
    let responseJSON: String?
    func stream(_ request: ClaudeRequest) -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            if let responseJSON {
                continuation.yield(.text(responseJSON))
                continuation.yield(.finished(ClaudeCompletion(text: responseJSON, stopReason: "end_turn", model: "mock")))
                continuation.finish()
            } else {
                continuation.finish(throwing: ClaudeError.network("offline"))
            }
        }
    }
}

final class BudgetKitTests: XCTestCase {
    func testVietnameseBankSMSParsing() {
        let sms = "SD TK 190382910 -125,000 VND luc 09:15 tai HIGHLANDS COFFEE SD 12,400,000 VND"
        let draft = LocalTransactionParser.parse(sms, defaultCurrency: .vnd)
        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.amountMajor, 125_000)
        XCTAssertEqual(draft?.currency, .vnd)
        XCTAssertEqual(draft?.type, .expense)
        XCTAssertEqual(draft?.category, .food)
        XCTAssertTrue(draft?.name.lowercased().contains("highlands") == true)
    }

    func testVietnameseShorthandAndIncome() {
        let pho = LocalTransactionParser.parse("ăn phở 65k", defaultCurrency: .vnd)
        XCTAssertEqual(pho?.amountMajor, 65_000)
        XCTAssertEqual(pho?.category, .food)
        XCTAssertEqual(pho?.type, .expense)

        let salary = LocalTransactionParser.parse("Lương tháng +25tr", defaultCurrency: .vnd)
        XCTAssertEqual(salary?.amountMajor, 25_000_000)
        XCTAssertEqual(salary?.category, .salary)
        XCTAssertEqual(salary?.type, .income)
    }

    func testSingaporeBankEmailParsing() {
        let email = "DBS Alert: You have made a payment of SGD 18.50 to FAIRPRICE on 2026-11-20."
        let draft = LocalTransactionParser.parse(email, defaultCurrency: .sgd)
        XCTAssertEqual(draft?.amountMajor, 18.5)
        XCTAssertEqual(draft?.currency, .sgd)
        XCTAssertEqual(draft?.category, .food)
        XCTAssertEqual(draft?.dayKey, "2026-11-20")

        let paynowIn = LocalTransactionParser.parse("You have received SGD 120.00 via PayNow from ALEX TAN.", defaultCurrency: .sgd)
        XCTAssertEqual(paynowIn?.amountMajor, 120.0)
        XCTAssertEqual(paynowIn?.type, .income)

        let mrt = LocalTransactionParser.parse("A transaction of SGD 3.40 was made on your DBS Card at SIMPLYGO MRT.", defaultCurrency: .sgd)
        XCTAssertEqual(mrt?.amountMajor, 3.4)
        XCTAssertEqual(mrt?.category, .transport)
    }

    func testAIParserSuccessAndOfflineFallback() async {
        let json = """
        {"isTransaction":true,"name":"Phở Hòa","amount":75000,"currency":"VND","type":"expense","category":"food","date":"2026-11-23","note":"Lunch","confidence":0.95}
        """
        let aiDraft = await AITransactionParser.parse(
            text: "vợ ăn phở hòa 75k",
            source: .aiQuickAdd,
            defaultCurrency: .vnd,
            language: .vietnamese,
            client: MockAIClient(responseJSON: json)
        )
        XCTAssertEqual(aiDraft?.name, "Phở Hòa")
        XCTAssertEqual(aiDraft?.amountMajor, 75_000)
        XCTAssertEqual(aiDraft?.parsedByAI, true)

        // FX conversion: 50,000 VND into SGD budget must convert (~S$2.63), never S$50,000!
        if let aiDraft {
            let resolved = AITransactionParser.resolvedAmountAndNote(for: aiDraft, targetCurrency: .sgd, language: .english)
            XCTAssertLessThan(CurrencyCode.sgd.toMajor(resolved.amountMinor), 10.0)
            XCTAssertTrue(resolved.note.contains("75.000 ₫"))
        }

        // Promo email explicitly rejected by AI must return nil (no fallback to regex!).
        let promoJSON = """
        {"isTransaction":false,"name":"","amount":0,"currency":"VND","type":"expense","category":"other","date":"2026-11-23","note":"Marketing email","confidence":0.1}
        """
        let rejected = await AITransactionParser.parse(
            text: "Special Grab offer: get up to 50,000 VND off your weekend mall ride!",
            source: .bankEmail,
            defaultCurrency: .sgd,
            language: .english,
            client: MockAIClient(responseJSON: promoJSON)
        )
        XCTAssertNil(rejected)

        // Offline promotional guard also rejects Vietnamese Grab promo blasts.
        XCTAssertTrue(LocalTransactionParser.isLikelyPromotional("Cuối tuần đưa cả nhà đi chơi Mall Grab ưu đãi giảm ngay 50,000đ"))
        XCTAssertFalse(LocalTransactionParser.isLikelyPromotional("DBS Alert: A transaction of SGD 18.50 was made on your DBS Card at FAIRPRICE."))

        let fallbackDraft = await AITransactionParser.parse(
            text: "Grab 45k",
            source: .bankNotification,
            defaultCurrency: .vnd,
            language: .vietnamese,
            client: MockAIClient(responseJSON: nil)
        )
        XCTAssertEqual(fallbackDraft?.amountMajor, 45_000)
        XCTAssertEqual(fallbackDraft?.category, .transport)
        XCTAssertEqual(fallbackDraft?.parsedByAI, false)
    }

    func testMonthlySnapshotAndWebBackupRoundTrip() throws {
        let tx1 = TransactionRecord(id: "t1", name: "Salary", amountMinor: 480_000, type: .income, category: .salary, dayKey: "2026-11-02", memberID: "me", memberName: "Khoa")
        let tx2 = TransactionRecord(id: "t2", name: "Groceries", amountMinor: 92_400, type: .expense, category: .food, dayKey: "2026-11-10", memberID: "wife", memberName: "Wife")
        let budget = BudgetLimitRecord(monthKey: "2026-11", category: .food, limitMinor: 150_000)
        let goal = SavingsGoalRecord(id: "g1", name: "Emergency", icon: .shield, targetMinor: 1_000_000, savedMinor: 650_000)

        let snap = MonthlySnapshot.compute(monthKey: "2026-11", allTransactions: [tx1, tx2], allBudgets: [budget])
        XCTAssertEqual(snap.incomeMinor, 480_000)
        XCTAssertEqual(snap.spendingMinor, 92_400)
        XCTAssertEqual(snap.netSavingsMinor, 387_600)
        XCTAssertEqual(snap.budgetLeftMinor, 57_600)
        XCTAssertEqual(snap.memberBreakdown.count, 2)

        let data = try WebBackupCodec.encode(currency: .sgd, transactions: [tx1, tx2], budgets: [budget], goals: [goal])
        let decoded = try WebBackupCodec.decode(data)
        XCTAssertEqual(decoded.currency, .sgd)
        XCTAssertEqual(decoded.transactions.count, 2)
        XCTAssertEqual(decoded.budgets.count, 1)
        XCTAssertEqual(decoded.goals.count, 1)
    }

    func testPeriodSnapshotFilteringForDayAndRange() {
        let tx1 = TransactionRecord(id: "t1", name: "Coffee", amountMinor: 500, type: .expense, category: .food, dayKey: "2026-11-20")
        let tx2 = TransactionRecord(id: "t2", name: "Lunch", amountMinor: 1_200, type: .expense, category: .food, dayKey: "2026-11-22")
        let tx3 = TransactionRecord(id: "t3", name: "Bonus", amountMinor: 10_000, type: .income, category: .salary, dayKey: "2026-11-23")

        let daySnap = MonthlySnapshot.compute(period: .day("2026-11-22"), allTransactions: [tx1, tx2, tx3], allBudgets: [])
        XCTAssertEqual(daySnap.transactions.map(\.id), ["t2"])
        XCTAssertEqual(daySnap.spendingMinor, 1_200)
        XCTAssertEqual(daySnap.incomeMinor, 0)
        XCTAssertEqual(daySnap.weeklyCashFlow.count, 1)

        let rangeSnap = MonthlySnapshot.compute(period: .range(start: "2026-11-22", end: "2026-11-23"), allTransactions: [tx1, tx2, tx3], allBudgets: [])
        XCTAssertEqual(rangeSnap.transactions.map(\.id), ["t3", "t2"])
        XCTAssertEqual(rangeSnap.spendingMinor, 1_200)
        XCTAssertEqual(rangeSnap.incomeMinor, 10_000)
        XCTAssertEqual(rangeSnap.weeklyCashFlow.count, 2)
    }

    func testEmailInboxClientFetchAndAck() async throws {
        struct MockInboxTransport: InboxHTTPTransport {
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer top-secret")
                if request.url?.path.hasSuffix("/v1/inbox") == true {
                    let body = """
                    {"items":[{"id":"m1","subject":"DBS Transaction Alert","sender":"alerts@dbs.com","body":"SGD 12.50 at YA KUN","member":"Khoa","receivedAt":"2026-11-23T09:00:00Z"}]}
                    """
                    return (Data(body.utf8), 200)
                }
                return (Data(#"{"ok":true,"removed":1}"#.utf8), 200)
            }
        }

        let url = try EmailInboxClient.normalizeURL("tally-email-inbox.example.workers.dev")
        let client = EmailInboxClient(baseURL: url, secret: "top-secret", transport: MockInboxTransport())
        let items = try await client.fetchInbox()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.member, "Khoa")
        try await client.ack(ids: ["m1"])
    }
}
