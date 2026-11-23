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

    func testCrossSourceDeduplication() {
        let t0 = Date(timeIntervalSince1970: 1_763_900_000)
        let t2min = t0.addingTimeInterval(120)
        let t5hrs = t0.addingTimeInterval(5 * 3600)

        let applePay = TransactionRecord(
            id: "ap-1", name: "FairPrice", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t0, source: .applePay, memberID: "khoa", memberName: "Khoa"
        )

        // 1. SMS arrives 2 minutes later for the exact same purchase with slightly different bank merchant string.
        let sms = TransactionRecord(
            id: "sms-1", name: "FAIRPRICE FINEST", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t2min, source: .bankNotification, memberID: "khoa", memberName: "Khoa"
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: sms, in: [applePay]))

        // 2. Bank email arrives hours later (or next morning past midnight) with NTUC FairPrice.
        let delayedEmail = TransactionRecord(
            id: "email-1", name: "NTUC FairPrice", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-24", createdAt: t5hrs, source: .bankEmail, memberID: "khoa", memberName: "Khoa"
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: delayedEmail, in: [applePay]))

        // 3. Different merchant string from Apple Pay vs corporate entity in DBS email within 20 minutes -> duplicate!
        let corpEmail = TransactionRecord(
            id: "email-2", name: "COFFEE CONCEPT PTE LTD", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t2min, source: .bankEmail, memberID: "khoa", memberName: "Khoa"
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: corpEmail, in: [applePay]))

        // 4. Two genuinely separate same-amount Apple Pay purchases 5 hours apart -> NOT a duplicate!
        let secondTrip = TransactionRecord(
            id: "ap-2", name: "FairPrice", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t5hrs, source: .applePay, memberID: "khoa", memberName: "Khoa"
        )
        XCTAssertNil(TransactionDeduplicator.findDuplicate(for: secondTrip, in: [applePay]))

        // 5. Wife taps Apple Pay for the same amount at the same store -> NOT a duplicate (same source, different memberID)!
        let wifeApplePay = TransactionRecord(
            id: "ap-wife", name: "FairPrice", amountMinor: 1_850, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t2min, source: .applePay, memberID: "wife", memberName: "Wife"
        )
        XCTAssertNil(TransactionDeduplicator.findDuplicate(for: wifeApplePay, in: [applePay]))

        // 6. Cross-member Apple Pay ("Me") + Bank Email ("Khoa") for the same purchase (mismatched member label or shared card) -> IS a duplicate!
        let guardianApplePay = TransactionRecord(
            id: "ap-guardian", name: "Guardian Hillview", amountMinor: 1_740, type: .expense, category: .health,
            dayKey: "2026-11-23", createdAt: t0, source: .applePay, memberID: "uuid-me", memberName: "Me"
        )
        let guardianEmail = TransactionRecord(
            id: "email-guardian", name: "Guardian Hillview", amountMinor: 1_740, type: .expense, category: .health,
            dayKey: "2026-11-23", createdAt: t5hrs, source: .bankEmail, rawSourceText: "DBS Alert SGD 17.40",
            memberID: "member-khoa", memberName: "Khoa"
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: guardianEmail, in: [guardianApplePay]))
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: guardianApplePay, in: [guardianEmail]))

        // 7. Deterministic sweep collapses already-stored Apple Pay + Bank Email duplicates regardless of order,
        //    keeps Apple Pay as winner, merges rawSourceText, and never deletes two identical manual entries.
        let sweepA = TransactionDeduplicator.findExistingDuplicates(in: [guardianApplePay, guardianEmail])
        let sweepB = TransactionDeduplicator.findExistingDuplicates(in: [guardianEmail, guardianApplePay])
        XCTAssertEqual(sweepA.duplicateIDsToDelete, ["email-guardian"])
        XCTAssertEqual(sweepB.duplicateIDsToDelete, ["email-guardian"])
        XCTAssertEqual(sweepA.updatedWinners.first?.id, "ap-guardian")
        XCTAssertEqual(sweepA.updatedWinners.first?.rawSourceText, "DBS Alert SGD 17.40")

        let manual1 = TransactionRecord(
            id: "m1", name: "Coffee", amountMinor: 500, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t0, source: .manual, memberID: "uuid-me", memberName: "Me"
        )
        let manual2 = TransactionRecord(
            id: "m2", name: "Coffee", amountMinor: 500, type: .expense, category: .food,
            dayKey: "2026-11-23", createdAt: t2min, source: .manual, memberID: "uuid-me", memberName: "Me"
        )
        let manualSweep = TransactionDeduplicator.findExistingDuplicates(in: [manual1, manual2])
        XCTAssertTrue(manualSweep.duplicateIDsToDelete.isEmpty)
    }

    func testDailyCalendarTotalsAndStatisticsSnapshot() {
        let txs = [
            TransactionRecord(id: "o1", name: "FairPrice", amountMinor: 8_000, type: .expense, category: .food, dayKey: "2026-10-15", memberID: "me", memberName: "Khoa"),
            TransactionRecord(id: "o2", name: "Salary", amountMinor: 500_000, type: .income, category: .salary, dayKey: "2026-10-01", memberID: "me", memberName: "Khoa"),
            TransactionRecord(id: "n1", name: "FairPrice", amountMinor: 2_000, type: .expense, category: .food, dayKey: "2026-11-10", memberID: "me", memberName: "Khoa"),
            TransactionRecord(id: "n2", name: "fairprice", amountMinor: 4_500, type: .expense, category: .food, dayKey: "2026-11-12", memberID: "wife", memberName: "Wife"),
            TransactionRecord(id: "n3", name: "Grab", amountMinor: 1_500, type: .expense, category: .transport, dayKey: "2026-11-10", memberID: "me", memberName: "Khoa"),
            TransactionRecord(id: "n4", name: "PayNow Refund", amountMinor: 10_000, type: .income, category: .other, dayKey: "2026-11-10", memberID: "me", memberName: "Khoa"),
            TransactionRecord(id: "del", name: "Deleted", amountMinor: 99_900, type: .expense, category: .shopping, dayKey: "2026-11-10", memberID: "me", memberName: "Khoa", isDeleted: true),
        ]

        let daily = MonthlySnapshot.dailyTotals(allTransactions: txs)
        XCTAssertEqual(daily["2026-11-10"]?.spendingMinor, 3_500)
        XCTAssertEqual(daily["2026-11-10"]?.incomeMinor, 10_000)
        XCTAssertEqual(daily["2026-11-10"]?.count, 3)

        let meOnlyDaily = MonthlySnapshot.dailyTotals(allTransactions: txs, memberFilter: "me")
        XCTAssertNil(meOnlyDaily["2026-11-12"])

        let stats = StatisticsSnapshot.compute(
            period: .month("2026-11"),
            allTransactions: txs,
            allBudgets: [],
            trendMonths: 6,
            todayKey: "2026-11-20"
        )
        XCTAssertEqual(stats.current.spendingMinor, 8_000)
        XCTAssertEqual(stats.previousSpendingMinor, 8_000)
        XCTAssertEqual(stats.spendingChangePercent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(stats.elapsedDaysCount, 20)
        XCTAssertEqual(stats.spendingDaysCount, 2)
        XCTAssertEqual(stats.averageDailySpendingMinor, 400)
        XCTAssertEqual(stats.highestSpendDay?.dayKey, "2026-11-12")
        XCTAssertEqual(stats.topMerchants.first?.normalizedKey, "fairprice")
        XCTAssertEqual(stats.topMerchants.first?.totalMinor, 6_500)
        XCTAssertEqual(stats.topMerchants.first?.count, 2)
        XCTAssertEqual(stats.monthlyTrend.count, 6)
        XCTAssertEqual(stats.monthlyTrend.last?.monthKey, "2026-11")
        XCTAssertEqual(stats.monthlyTrend.dropLast().last?.monthKey, "2026-10")
        XCTAssertEqual(stats.weekdayBreakdown.count, 7)

        XCTAssertEqual(MoneyFormat.formatCalendarAmount(minor: 2_000, currency: .sgd, language: .english, isIncome: false), "-$20")
        XCTAssertEqual(MoneyFormat.formatCalendarAmount(minor: 10_000, currency: .sgd, language: .english, isIncome: true), "+$100")
        XCTAssertEqual(MoneyFormat.formatCalendarAmount(minor: 450, currency: .sgd, language: .english, isIncome: false), "-$4.5")
        XCTAssertEqual(MoneyFormat.formatCalendarAmount(minor: 6_500_000, currency: .vnd, language: .vietnamese, isIncome: false), "-65k")
    }

    func testCrossAppAssistantToolDecodingAndChineseLocalization() throws {
        // 1. Multiple transactions in one call (rent + credit card)
        let addTxTool = ClaudeToolUse(
            id: "t1",
            name: AssistantToolCatalog.addTransactionsName,
            input: [
                "items": [
                    ["name": "Tiền nhà", "amount": 3000, "type": "expense", "category": "housing"],
                    ["name": "Trả thẻ tín dụng", "amount": 850.5, "type": "expense", "category": "bills", "member": "partner"],
                ]
            ]
        )
        let addDecoded = try AssistantToolCatalog.decode(addTxTool, defaultDayKey: "2026-11-23", defaultMonthKey: "2026-11").get()
        if case .addTransactions(let items) = addDecoded {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0].name, "Tiền nhà")
            XCTAssertEqual(items[0].category, .housing)
            XCTAssertEqual(items[0].dayKey, "2026-11-23")
            XCTAssertEqual(items[1].amountMajor, 850.5)
            XCTAssertEqual(items[1].category, .bills)
            XCTAssertEqual(items[1].memberHint, "partner")
        } else {
            XCTFail("Expected addTransactions command")
        }

        // 2. Setting monthly budgets
        let budgetTool = ClaudeToolUse(
            id: "t2",
            name: AssistantToolCatalog.setBudgetsName,
            input: [
                "items": [
                    ["category": "food", "limit": 1000],
                    ["category": "shopping", "limit": 500],
                ]
            ]
        )
        let budgetDecoded = try AssistantToolCatalog.decode(budgetTool, defaultDayKey: "2026-11-23", defaultMonthKey: "2026-11").get()
        if case .setBudgets(let monthKey, let items) = budgetDecoded {
            XCTAssertEqual(monthKey, "2026-11")
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0].category, .food)
            XCTAssertEqual(items[0].limitMajor, 1000)
        } else {
            XCTFail("Expected setBudgets command")
        }

        // 3. Creating a savings goal
        let goalTool = ClaudeToolUse(
            id: "t3",
            name: AssistantToolCatalog.createSavingsGoalName,
            input: [
                "name": "日本旅行",
                "target_amount": 5000,
                "saved_amount": 1000,
                "icon": "plane",
            ]
        )
        let goalDecoded = try AssistantToolCatalog.decode(goalTool, defaultDayKey: "2026-11-23", defaultMonthKey: "2026-11").get()
        XCTAssertEqual(goalDecoded, .createSavingsGoal(name: "日本旅行", targetMajor: 5000, savedMajor: 1000, icon: .plane))

        // 4. Chinese titles & prompts
        XCTAssertEqual(CategoryID.housing.title(in: .chinese), "住房")
        XCTAssertEqual(GoalIcon.plane.title(in: .chinese), "旅行")
        XCTAssertEqual(BudgetAssistantPrompt.suggestedPrompts(in: .chinese).count, 4)
    }
}
