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

    func testRecognizedBankAlertAmountUsesTransactionNotBalance() {
        let debit = LocalTransactionParser.recognizedBankAlertAmount(
            "SD TK 190382910 -125,000 VND luc 09:15 tai HIGHLANDS COFFEE SD 12,400,000 VND"
        )
        XCTAssertEqual(debit?.amount, 125_000)
        XCTAssertEqual(debit?.currency, .vnd)
        XCTAssertEqual(debit?.type, .expense)

        let receipt = LocalTransactionParser.recognizedBankAlertAmount(
            "DBS Alert: You have made a payment of S$1,234.50 to FAIRPRICE on 2026-11-20. Available balance SGD 8,000.00."
        )
        XCTAssertEqual(receipt?.amount, 1_234.50)
        XCTAssertEqual(receipt?.currency, .sgd)
        XCTAssertEqual(receipt?.type, .expense)

        let credit = LocalTransactionParser.recognizedBankAlertAmount("You have received SGD 120.00 via PayNow from ALEX TAN.")
        XCTAssertEqual(credit?.amount, 120)
        XCTAssertEqual(credit?.type, .income)
        XCTAssertNotNil(BudgetAssistantPrompt.bankAlertHint(for: "A transaction of SGD 3.40 was made on your DBS Card at SIMPLYGO MRT."))
    }

    func testUnrecognizedOrIncompleteAlertsDoNotProduceAHint() {
        for message in [
            "Did I spend SGD 18.50 at FairPrice?",
            "DBS Alert: Your available balance is SGD 1,234.50.",
            "DBS Alert: You have made a payment of SGD 18.50 to FAIRPRICE. Status: pending.",
            "Your OTP is 543210 for a payment of SGD 18.50.",
            "SD TK 190382910 SD 12,400,000 VND",
            "DBS Alert: You have made a payment of SGD 0 to FAIRPRICE.",
        ] {
            XCTAssertNil(BudgetAssistantPrompt.bankAlertHint(for: message), message)
        }
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

    // MARK: Promotional email filtering

    func testSelfContradictingModelResultIsRejected() async {
        // The model flags a loan-offer mailer as a transaction while naming it "not a transaction".
        let json = """
        {"isTransaction":true,"name":"SC CashOne Promo (not a transaction)","amount":1,"currency":"SGD","type":"expense","category":"other","date":"2026-11-23","note":"Promotional email from Standard Chartered; no actual transaction.","confidence":0.6}
        """
        let draft = await AITransactionParser.parse(
            text: "Standard Chartered: Get cash with CashOne today. Enjoy low rates on your personal loan.",
            source: .bankEmail,
            defaultCurrency: .sgd,
            language: .english,
            client: MockAIClient(responseJSON: json)
        )
        XCTAssertNil(draft)
    }

    func testPromotionalWordingOnlyRejectsBankEmails() async {
        let json = """
        {"isTransaction":true,"name":"Bank newsletter","amount":5,"currency":"SGD","type":"expense","category":"other","date":"2026-11-23","note":"Marketing email","confidence":0.9}
        """
        let email = await AITransactionParser.parse(
            text: "Your monthly update from the bank", source: .bankEmail,
            defaultCurrency: .sgd, language: .english, client: MockAIClient(responseJSON: json)
        )
        XCTAssertNil(email)

        // A real receipt that mentions a promo code is still a transaction.
        let receiptJSON = """
        {"isTransaction":true,"name":"GrabFood","amount":12.5,"currency":"SGD","type":"expense","category":"food","date":"2026-11-23","note":"Promo code applied","confidence":0.95}
        """
        let receipt = await AITransactionParser.parse(
            text: "Your Grab E-Receipt. Total paid SGD 12.50", source: .bankEmail,
            defaultCurrency: .sgd, language: .english, client: MockAIClient(responseJSON: receiptJSON)
        )
        XCTAssertEqual(receipt?.amountMajor, 12.5)
    }

    func testDescribesNonTransaction() {
        XCTAssertTrue(LocalTransactionParser.describesNonTransaction(name: "SC CashOne Promo (not a transaction)", note: "", strict: false))
        XCTAssertTrue(LocalTransactionParser.describesNonTransaction(name: "Thông báo", note: "Không phải giao dịch", strict: false))
        XCTAssertFalse(LocalTransactionParser.describesNonTransaction(name: "Promo lunch", note: "", strict: false))
        XCTAssertFalse(LocalTransactionParser.describesNonTransaction(name: "FairPrice", note: "DBS card 1234", strict: true))
        XCTAssertTrue(LocalTransactionParser.describesNonTransaction(name: "Offer", note: "Email quảng cáo", strict: true))
    }

    func testLoanOfferMailersAreLikelyPromotional() {
        XCTAssertTrue(LocalTransactionParser.isLikelyPromotional("You are pre-approved for CashOne. Rates from 1.9% p.a. T&Cs apply."))
        XCTAssertTrue(LocalTransactionParser.isLikelyPromotional("Balance transfer offer valid till 31 Dec"))
        XCTAssertFalse(LocalTransactionParser.isLikelyPromotional("Transaction alert: SGD 42.00 at NTUC. T&Cs apply."))
    }

    func testTrustBankForeignCurrencyAlertAndConversion() async throws {
        let trustAlert = "0% FX fees! You've spent HKD 83.75 using Freedom credit card at PinDuoDuo HONG KONG HK on 25 Nov 2026 04:30SGT. You’ll receive estimated S$0.07 cashback*. Not you? Alert us via Trust app."

        XCTAssertFalse(LocalTransactionParser.isLikelyPromotional(trustAlert))
        let recognized = try XCTUnwrap(LocalTransactionParser.recognizedBankAlertAmount(trustAlert))
        XCTAssertEqual(recognized.amount, 83.75, accuracy: 0.001)
        XCTAssertEqual(recognized.currencyCode, "HKD")
        XCTAssertEqual(recognized.type, .expense)
        XCTAssertNotNil(BudgetAssistantPrompt.bankAlertHint(for: trustAlert))

        let draft = try XCTUnwrap(LocalTransactionParser.parse(trustAlert, defaultCurrency: .sgd))
        XCTAssertEqual(draft.amountMajor, 83.75, accuracy: 0.001)
        XCTAssertEqual(draft.currencyCode, "HKD")
        XCTAssertEqual(draft.currency, .hkd)
        XCTAssertEqual(draft.type, .expense)
        XCTAssertEqual(draft.category, .shopping)
        XCTAssertEqual(draft.dayKey, "2026-11-25")
        XCTAssertTrue(draft.name.lowercased().contains("pinduoduo"))

        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: draft,
            targetCurrency: .sgd,
            language: .english,
            rates: .fallback
        )
        XCTAssertEqual(CurrencyCode.sgd.toMajor(resolved.amountMinor), 14.32, accuracy: 0.02)
        XCTAssertEqual(resolved.originalAmountMinor, 8_375)
        XCTAssertEqual(resolved.originalCurrencyCode, "HKD")
        XCTAssertNotNil(resolved.exchangeRate)
        XCTAssertTrue(resolved.note.contains("HK$83.75"))

        // AI mock path returning HKD & unlisted ISO code AED
        let aiHKDJSON = """
        {"isTransaction":true,"name":"PinDuoDuo","amount":83.75,"currency":"HKD","type":"expense","category":"shopping","date":"2026-11-25","note":"Freedom credit card","confidence":0.98}
        """
        let aiDraftRaw = await AITransactionParser.parse(
            text: trustAlert,
            source: .bankNotification,
            defaultCurrency: .sgd,
            language: .english,
            client: MockAIClient(responseJSON: aiHKDJSON)
        )
        let aiDraft = try XCTUnwrap(aiDraftRaw)
        XCTAssertEqual(aiDraft.currencyCode, "HKD")
        XCTAssertEqual(aiDraft.amountMajor, 83.75, accuracy: 0.001)

        let aiAEDJSON = """
        {"isTransaction":true,"name":"Carrefour Dubai","amount":120.5,"currency":"AED","type":"expense","category":"food","date":"2026-11-25","note":"","confidence":0.95}
        """
        let aedDraftRaw = await AITransactionParser.parse(
            text: "Spent AED 120.50 at Carrefour",
            source: .bankNotification,
            defaultCurrency: .sgd,
            language: .english,
            client: MockAIClient(responseJSON: aiAEDJSON)
        )
        let aedDraft = try XCTUnwrap(aedDraftRaw)
        XCTAssertEqual(aedDraft.currencyCode, "AED")
        let aedResolved = AITransactionParser.resolvedAmountAndNote(for: aedDraft, targetCurrency: .sgd, language: .english, rates: .fallback)
        XCTAssertEqual(aedResolved.originalCurrencyCode, "AED")
        XCTAssertEqual(aedResolved.originalAmountMinor, 12_050)
        XCTAssertTrue(aedResolved.note.contains("AED 120.50"))
    }

    func testAdditionalForeignAlertsAndEdgeCases() {
        let jpy = LocalTransactionParser.parse("You've spent JPY 2,400.00 at Uniqlo Tokyo", defaultCurrency: .sgd)
        XCTAssertEqual(jpy?.amountMajor, 2_400)
        XCTAssertEqual(jpy?.currencyCode, "JPY")

        let rmb = LocalTransactionParser.parse("RMB 168.00 at Haidilao", defaultCurrency: .sgd)
        XCTAssertEqual(rmb?.amountMajor, 168)
        XCTAssertEqual(rmb?.currencyCode, "CNY")

        let thb = LocalTransactionParser.parse("Spent THB 350.00 at Pad Thai", defaultCurrency: .sgd)
        XCTAssertEqual(thb?.amountMajor, 350)
        XCTAssertEqual(thb?.currencyCode, "THB")

        let aed = LocalTransactionParser.parse("Paid AED 120.50 at Dubai Mall", defaultCurrency: .sgd)
        XCTAssertEqual(aed?.amountMajor, 120.5)
        XCTAssertEqual(aed?.currencyCode, "AED")

        // Lowercase English words that happen to match ISO codes ("try", "all") must NOT trigger currency detection.
        let englishWords = LocalTransactionParser.parse("Try 10", defaultCurrency: .sgd)
        XCTAssertNil(englishWords?.currencyCode)
        XCTAssertEqual(englishWords?.amountMajor, 10)

        let allCoffees = LocalTransactionParser.parse("All 5", defaultCurrency: .sgd)
        XCTAssertNil(allCoffees?.currencyCode)
        XCTAssertEqual(allCoffees?.amountMajor, 5)
    }

    func testExchangeRateClientFetchAndFallbacks() async throws {
        struct MockFXTransport: FXHTTPTransport {
            let handler: @Sendable (URL) throws -> (Data, Int)
            func send(_ request: URLRequest) async throws -> (Data, Int) {
                try handler(try XCTUnwrap(request.url))
            }
        }

        // Build 22 valid currencies for primary response
        var sgdRates: [String: Double] = ["sgd": 1.0, "hkd": 5.80, "usd": 0.74, "vnd": 18800, "jpy": 112.0, "cny": 5.35, "eur": 0.68, "gbp": 0.58, "aud": 1.14, "cad": 1.03, "myr": 3.25, "krw": 1030, "thb": 25.5, "twd": 24.0, "idr": 11800, "php": 43.0, "nzd": 1.25, "chf": 0.65, "inr": 63.0, "aed": 2.72]
        let primaryPayload = try JSONSerialization.data(withJSONObject: ["date": "2026-11-25", "sgd": sgdRates])
        let primaryClient = ExchangeRateClient(transport: MockFXTransport { url in
            if url.host?.contains("jsdelivr") == true { return (primaryPayload, 200) }
            return (Data(), 500)
        })
        let primaryTable = try await primaryClient.fetchLatest(now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(primaryTable.isLive)
        XCTAssertEqual(primaryTable.rateDate, "2026-11-25")
        XCTAssertEqual(primaryTable.ratesPerSGD["HKD"], 5.80)

        // Fallback to open.er-api.com when primary & mirror fail
        sgdRates["hkd"] = 5.91
        let openERPayload = try JSONSerialization.data(withJSONObject: [
            "result": "success",
            "base_code": "SGD",
            "time_last_update_unix": 1_764_028_800,
            "rates": Dictionary(uniqueKeysWithValues: sgdRates.map { ($0.key.uppercased(), $0.value) }),
        ])
        let fallbackClient = ExchangeRateClient(transport: MockFXTransport { url in
            if url.host?.contains("open.er-api.com") == true { return (openERPayload, 200) }
            return (Data("down".utf8), 503)
        })
        let fallbackTable = try await fallbackClient.fetchLatest()
        XCTAssertEqual(fallbackTable.ratesPerSGD["HKD"], 5.91)
    }

    func testForeignDeduplicationAndBackupRoundTrip() throws {
        let t0 = Date(timeIntervalSince1970: 1_764_000_000)
        let applePay = TransactionRecord(
            id: "ap-fx", name: "PinDuoDuo", amountMinor: 1_432, type: .expense, category: .shopping,
            dayKey: "2026-11-25", createdAt: t0, source: .applePay,
            originalAmountMinor: 8_375, originalCurrencyCode: "HKD", exchangeRate: 0.171
        )
        // Bank email converted at slightly different rate (14.40 vs 14.32) still deduplicates by original HKD amount!
        let email = TransactionRecord(
            id: "em-fx", name: "PINDUODUO HONG KONG", amountMinor: 1_440, type: .expense, category: .shopping,
            dayKey: "2026-11-25", createdAt: t0.addingTimeInterval(3600), source: .bankEmail,
            originalAmountMinor: 8_375, originalCurrencyCode: "HKD", exchangeRate: 0.172
        )
        XCTAssertNotNil(TransactionDeduplicator.findDuplicate(for: email, in: [applePay]))

        let data = try WebBackupCodec.encode(currency: .sgd, transactions: [applePay], budgets: [], goals: [])
        let decoded = try WebBackupCodec.decode(data)
        let roundTripped = try XCTUnwrap(decoded.transactions.first)
        XCTAssertEqual(roundTripped.originalAmountMinor, 8_375)
        XCTAssertEqual(roundTripped.originalCurrencyCode, "HKD")
        XCTAssertEqual(roundTripped.exchangeRate ?? 0, 0.171, accuracy: 0.0001)
    }

    func testAssistantToolDecodesForeignAndConvertedAmount() throws {
        let tool = ClaudeToolUse(
            id: "t-fx",
            name: AssistantToolCatalog.addTransactionsName,
            input: [
                "items": [
                    ["name": "PinDuoDuo", "amount": 83.75, "currency": "HKD", "type": "expense", "category": "shopping"],
                    ["name": "Dubai Mall", "amount": 120.5, "currency": "AED", "converted_amount": 44.0, "type": "expense", "category": "shopping"],
                ]
            ]
        )
        let cmd = try AssistantToolCatalog.decode(tool, defaultDayKey: "2026-11-25", defaultMonthKey: "2026-11").get()
        guard case .addTransactions(let items) = cmd else { return XCTFail() }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].currencyCode, "HKD")
        XCTAssertNil(items[0].convertedAmountMajor)
        XCTAssertEqual(items[1].currencyCode, "AED")
        XCTAssertEqual(items[1].convertedAmountMajor, 44.0)

        let exact = AssistantAmounts.resolve(
            amountMajor: 120.5,
            statedCurrencyCode: "AED",
            convertedAmountMajor: 44.0,
            household: .sgd,
            note: "",
            language: .english
        )
        XCTAssertEqual(exact.amountMinor, 4_400)
        XCTAssertEqual(exact.originalCurrencyCode, "AED")
        XCTAssertEqual(exact.originalAmountMinor, 12_050)
    }

    func testAssistantReceiptLookupAndBackwardCompatibleCodable() throws {
        let now = Date(timeIntervalSince1970: 1_764_000_000)
        let first = TransactionRecord(
            id: "tx-first",
            name: "PinDuoDuo",
            amountMinor: 1_379,
            type: .expense,
            category: .shopping,
            dayKey: "2026-11-25",
            createdAt: now.addingTimeInterval(-300)
        )
        let second = TransactionRecord(
            id: "tx-second",
            name: "PinDuoDuo",
            amountMinor: 6_571,
            type: .expense,
            category: .shopping,
            dayKey: "2026-11-25",
            createdAt: now
        )
        let deleted = TransactionRecord(
            id: "tx-deleted",
            name: "PinDuoDuo",
            amountMinor: 999,
            type: .expense,
            category: .shopping,
            dayKey: "2026-11-25",
            createdAt: now,
            isDeleted: true
        )

        // 1. Explicit recordID resolves directly to active match.
        let byID = AssistantActionReceipt(
            kind: .transactionAdded,
            emoji: "🛍️",
            title: "PinDuoDuo",
            subtitle: "Shopping · Today",
            amountText: "−S$65.71",
            recordID: "tx-second"
        )
        XCTAssertEqual(
            AssistantReceiptLookup.transaction(
                for: byID,
                timestamp: now,
                in: [first, second, deleted],
                currency: .sgd,
                language: .english,
                hideSalary: false
            )?.id,
            "tx-second"
        )

        // 2. Deleted explicit recordID returns nil (never falls back to another PinDuoDuo entry).
        let deletedByID = AssistantActionReceipt(
            kind: .transactionAdded,
            emoji: "🛍️",
            title: "PinDuoDuo",
            subtitle: "Shopping · Today",
            amountText: "−S$9.99",
            recordID: "tx-deleted"
        )
        XCTAssertNil(AssistantReceiptLookup.transaction(
            for: deletedByID,
            timestamp: now,
            in: [first, second, deleted],
            currency: .sgd,
            language: .english,
            hideSalary: false
        ))

        // 3. Deleted receipt kind or non-transaction kinds return nil.
        let deleteKind = AssistantActionReceipt(
            kind: .transactionDeleted,
            emoji: "🗑️",
            title: "PinDuoDuo",
            subtitle: "Deleted",
            recordID: "tx-second"
        )
        XCTAssertNil(AssistantReceiptLookup.transaction(
            for: deleteKind,
            timestamp: now,
            in: [first, second],
            currency: .sgd,
            language: .english,
            hideSalary: false
        ))

        let budgetKind = AssistantActionReceipt(kind: .budgetSet, emoji: "🍱", title: "Food", subtitle: "Budget")
        XCTAssertNil(AssistantReceiptLookup.transaction(
            for: budgetKind,
            timestamp: now,
            in: [first, second],
            currency: .sgd,
            language: .english,
            hideSalary: false
        ))

        // 4. Legacy receipt (recordID == nil) resolves by title, direction, formatted amount, and timestamp.
        let legacy = AssistantActionReceipt(
            kind: .transactionAdded,
            emoji: "🛍️",
            title: "PinDuoDuo",
            subtitle: "Shopping · Today",
            amountText: "−S$65.71"
        )
        XCTAssertEqual(
            AssistantReceiptLookup.transaction(
                for: legacy,
                timestamp: now.addingTimeInterval(15),
                in: [first, second],
                currency: .sgd,
                language: .english,
                hideSalary: false
            )?.id,
            "tx-second"
        )

        // 5. Legacy JSON without recordID decodes cleanly, and receipts with recordID round-trip.
        let legacyJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"transactionAdded","emoji":"🛍️","title":"PinDuoDuo","subtitle":"Shopping","amountText":"−S$65.71","isPositive":false}
        """
        let decodedLegacy = try JSONDecoder().decode(AssistantActionReceipt.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decodedLegacy.recordID)

        let encoded = try JSONEncoder().encode(byID)
        let decodedWithID = try JSONDecoder().decode(AssistantActionReceipt.self, from: encoded)
        XCTAssertEqual(decodedWithID.recordID, "tx-second")
    }
}
