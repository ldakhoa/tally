@testable import AppServices
import BudgetKit
import ClaudeKit
import Persistence
import SwiftData
import TallyCore
import XCTest

/// Scripted stand-in for `LAContext`: no system prompt, results set by the test.
final class FakeAuthenticator: SalaryAuthenticating, @unchecked Sendable {
    var kind: DeviceAuthKind = .faceID
    var result = true
    var prompts: [String] = []
    /// Runs inside `authenticate`, i.e. while the system prompt would be on screen.
    var duringPrompt: (() -> Void)?
    /// Suspends once inside `authenticate`, like a real prompt waiting for the user.
    var suspends = false

    func availableKind() -> DeviceAuthKind { kind }

    func authenticate(reason: String) async -> Bool {
        prompts.append(reason)
        duringPrompt?()
        if suspends { await Task.yield() }
        return result
    }
}

@MainActor
final class SalaryVisibilityGateTests: XCTestCase {
    private var suites: [String] = []

    private func makeDefaults() -> UserDefaults {
        let name = "tally.test.\(UUID().uuidString)"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    override func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeGate(
        defaults: UserDefaults? = nil,
        hidden: Bool? = nil,
        requires: Bool? = nil,
        auth: FakeAuthenticator = FakeAuthenticator()
    ) -> (SalaryVisibilityGate, FakeAuthenticator, UserDefaults) {
        let defaults = defaults ?? makeDefaults()
        if let hidden { defaults.set(hidden, forKey: "tally.hideIncome") }
        if let requires { defaults.set(requires, forKey: "tally.salary.requireAuth") }
        return (SalaryVisibilityGate(defaults: defaults, authenticator: auth), auth, defaults)
    }

    // MARK: Without the requirement

    func testPlainToggleKeepsLastStateAndNeverAuthenticates() async {
        let (gate, auth, defaults) = makeGate(hidden: true)
        XCTAssertTrue(gate.isHidden, "the stored 'hide income' choice carries over")
        XCTAssertFalse(gate.requiresAuthentication)

        let ok1 = await gate.reveal(reason: "r")

        XCTAssertTrue(ok1)
        XCTAssertFalse(gate.isHidden)
        XCTAssertTrue(auth.prompts.isEmpty)

        // Last state persists across a relaunch, and backgrounding does not re-lock.
        gate.appDidEnterBackground()
        XCTAssertFalse(gate.isHidden)
        let relaunched = SalaryVisibilityGate(defaults: defaults, authenticator: auth)
        XCTAssertFalse(relaunched.isHidden)

        gate.hide()
        XCTAssertTrue(SalaryVisibilityGate(defaults: defaults, authenticator: auth).isHidden)
    }

    func testDefaultsAreVisibleAndUnlocked() {
        let (gate, _, _) = makeGate()
        XCTAssertFalse(gate.isHidden)
        XCTAssertFalse(gate.requiresAuthentication)
    }

    // MARK: With the requirement

    func testColdLaunchStartsHiddenRegardlessOfLastState() {
        let (gate, _, _) = makeGate(hidden: false, requires: true)
        XCTAssertTrue(gate.isHidden)
        XCTAssertTrue(gate.requiresAuthentication)
    }

    func testRevealNeedsAuthenticationAndFailureKeepsSalaryHidden() async {
        let (gate, auth, _) = makeGate(requires: true)
        auth.result = false
        let ok2 = await gate.reveal(reason: "Show your salary")
        XCTAssertFalse(ok2)
        XCTAssertTrue(gate.isHidden)
        XCTAssertEqual(auth.prompts, ["Show your salary"])
        XCTAssertNil(gate.notice, "no extra error beyond the system's own UI")

        auth.result = true
        let ok3 = await gate.reveal(reason: "Show your salary")
        XCTAssertTrue(ok3)
        XCTAssertFalse(gate.isHidden)
    }

    func testHidingNeverAsks() async {
        let (gate, auth, _) = makeGate(requires: true)
        _ = await gate.reveal(reason: "r")
        auth.result = false
        auth.prompts.removeAll()
        gate.hide()
        XCTAssertTrue(gate.isHidden)
        XCTAssertTrue(auth.prompts.isEmpty)
    }

    func testToggleHidesWhenVisibleAndRevealsWhenHidden() async {
        let (gate, auth, _) = makeGate(requires: true)
        await gate.toggle(reason: "r")
        XCTAssertFalse(gate.isHidden)
        await gate.toggle(reason: "r")
        XCTAssertTrue(gate.isHidden)
        XCTAssertEqual(auth.prompts.count, 1, "only the reveal asked")
    }

    func testRelocksOnBackgroundOnly() async {
        let (gate, _, defaults) = makeGate(requires: true)
        _ = await gate.reveal(reason: "r")
        XCTAssertFalse(gate.isHidden)
        // `.inactive` (Face ID sheet, Control Centre) never calls into the gate; only `.background` does.
        gate.appDidEnterBackground()
        XCTAssertTrue(gate.isHidden)
        XCTAssertEqual(defaults.object(forKey: "tally.hideIncome") as? Bool, true)
    }

    func testAuthenticationFinishingAfterBackgroundDoesNotReveal() async {
        let (gate, auth, _) = makeGate(requires: true)
        auth.duringPrompt = { gate.appDidEnterBackground() }
        let ok4 = await gate.reveal(reason: "r")
        XCTAssertFalse(ok4)
        XCTAssertTrue(gate.isHidden)
    }

    func testSecondRevealWhilePromptIsUpIsIgnored() async {
        let (gate, auth, _) = makeGate(requires: true)
        auth.suspends = true
        var nested: Bool?
        auth.duringPrompt = {
            XCTAssertTrue(gate.isAuthenticating)
            Task { @MainActor in nested = await gate.reveal(reason: "again") }
        }
        let ok = await gate.reveal(reason: "r")
        XCTAssertTrue(ok)
        XCTAssertEqual(nested, false, "a second request while the prompt is up is ignored")
        XCTAssertEqual(auth.prompts, ["r"])
    }

    func testRevealWithNoPasscodeExplainsAndStaysHidden() async {
        let (gate, auth, _) = makeGate(requires: true)
        auth.kind = .none
        let ok6 = await gate.reveal(reason: "r")
        XCTAssertFalse(ok6)
        XCTAssertTrue(gate.isHidden)
        XCTAssertEqual(gate.notice, .passcodeRequired)
        XCTAssertTrue(auth.prompts.isEmpty)
    }

    // MARK: Turning the requirement on and off

    func testTurningTheRequirementOnPersistsAndKeepsCurrentState() async {
        let (gate, auth, defaults) = makeGate()
        let ok7 = await gate.setRequiresAuthentication(true, reason: "r")
        XCTAssertTrue(ok7)
        XCTAssertTrue(gate.requiresAuthentication)
        XCTAssertFalse(gate.isHidden, "enabling does not hide salary that is already showing")
        XCTAssertTrue(auth.prompts.isEmpty)
        XCTAssertEqual(defaults.object(forKey: "tally.salary.requireAuth") as? Bool, true)
        // It takes effect at the next lock: cold launch is hidden.
        XCTAssertTrue(SalaryVisibilityGate(defaults: defaults, authenticator: auth).isHidden)
    }

    func testTurningTheRequirementOnWithoutPasscodeIsRefusedInline() async {
        let (gate, auth, defaults) = makeGate()
        auth.kind = .none
        let ok8 = await gate.setRequiresAuthentication(true, reason: "r")
        XCTAssertFalse(ok8)
        XCTAssertFalse(gate.requiresAuthentication)
        XCTAssertEqual(gate.notice, .passcodeRequired)
        XCTAssertNil(defaults.object(forKey: "tally.salary.requireAuth"))
    }

    func testTurningTheRequirementOffNeedsAuthentication() async {
        let (gate, auth, defaults) = makeGate(requires: true)
        auth.result = false
        let ok9 = await gate.setRequiresAuthentication(false, reason: "turn off")
        XCTAssertFalse(ok9)
        XCTAssertTrue(gate.requiresAuthentication)
        XCTAssertEqual(auth.prompts, ["turn off"])

        auth.result = true
        let ok10 = await gate.setRequiresAuthentication(false, reason: "turn off")
        XCTAssertTrue(ok10)
        XCTAssertFalse(gate.requiresAuthentication)
        XCTAssertEqual(defaults.object(forKey: "tally.salary.requireAuth") as? Bool, false)
        // Back to last-state-persists: hidden stays hidden, and a launch no longer forces anything.
        XCTAssertTrue(gate.isHidden)
        gate.hide()
        _ = await gate.reveal(reason: "r")
        XCTAssertFalse(SalaryVisibilityGate(defaults: defaults, authenticator: auth).isHidden)
    }

    func testRequirementCanBeDroppedWhenTheDeviceCannotAuthenticateAtAll() async {
        let (gate, auth, _) = makeGate(requires: true)
        auth.kind = .none
        let ok11 = await gate.setRequiresAuthentication(false, reason: "r")
        XCTAssertTrue(ok11)
        XCTAssertFalse(gate.requiresAuthentication)
        XCTAssertTrue(auth.prompts.isEmpty)
    }

    // MARK: Naming

    func testRequirementTitleNamesTheDeviceBiometry() {
        XCTAssertEqual(DeviceAuthKind.faceID.requirementTitle(in: .english), "Require Face ID to show salary")
        XCTAssertEqual(DeviceAuthKind.touchID.requirementTitle(in: .english), "Require Touch ID to show salary")
        XCTAssertEqual(DeviceAuthKind.opticID.requirementTitle(in: .english), "Require Optic ID to show salary")
        XCTAssertEqual(DeviceAuthKind.passcode.requirementTitle(in: .english), "Require passcode to show salary")
        XCTAssertEqual(DeviceAuthKind.none.requirementTitle(in: .english), "Require passcode to show salary")
        XCTAssertTrue(DeviceAuthKind.faceID.requirementTitle(in: .vietnamese).contains("Face ID"))
        XCTAssertTrue(DeviceAuthKind.faceID.requirementTitle(in: .chinese).contains("Face ID"))
    }
}

/// The assistant's tool results while salary is hidden (executed against an in-memory store).
@MainActor
final class SalaryToolResultTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var suites: [String] = []

    private func makeStore() throws -> BudgetStore {
        let config = ModelConfiguration(UUID().uuidString, schema: AppStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: AppStore.schema, configurations: [config])
        containers.append(container)
        return BudgetStore(context: ModelContext(container))
    }

    private func makeSettings(hidden: Bool) -> AppSettings {
        let name = "tally.test.\(UUID().uuidString)"
        suites.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(hidden, forKey: "tally.hideIncome")
        let settings = AppSettings(defaults: defaults)
        settings.currency = .usd
        return settings
    }

    override func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        super.tearDown()
    }

    private func run(_ name: String, _ input: JSONValue, settings: AppSettings, store: BudgetStore) -> AssistantService.ToolExecutionOutcome {
        AssistantService.execute(toolUse: ClaudeToolUse(id: "t", name: name, input: input), settings: settings, store: store)
    }

    func testUpdatingASalaryTransactionDoesNotEchoItsAmount() throws {
        let store = try makeStore()
        let settings = makeSettings(hidden: true)
        store.saveTransaction(TransactionRecord(id: "pay", name: "Payroll", amountMinor: 4_321_00, type: .income, category: .salary, dayKey: "2026-11-02"))

        let outcome = run("update_transaction", ["transaction_id": "pay", "amount": 7_654.0], settings: settings, store: store)
        XCTAssertFalse(outcome.isError)
        XCTAssertFalse(outcome.toolOutput.contains("7,654"), outcome.toolOutput)
        XCTAssertFalse(outcome.toolOutput.contains("4,321"), outcome.toolOutput)
        XCTAssertEqual(outcome.receipts.first?.amountText, MoneyFormat.hiddenPlaceholder)
    }

    func testMovingASalaryTransactionToAnotherCategoryStillMasksTheResult() throws {
        let store = try makeStore()
        let settings = makeSettings(hidden: true)
        store.saveTransaction(TransactionRecord(id: "pay", name: "Payroll", amountMinor: 4_321_00, type: .income, category: .salary, dayKey: "2026-11-02"))

        let outcome = run("update_transaction", ["transaction_id": "pay", "category": "freelance"], settings: settings, store: store)
        XCTAssertFalse(outcome.toolOutput.contains("4,321"), outcome.toolOutput)
        XCTAssertEqual(outcome.receipts.first?.amountText, MoneyFormat.hiddenPlaceholder)
    }

    func testNonSalaryIncomeAndSpendingAreStillEchoedWhileHidden() throws {
        let store = try makeStore()
        let settings = makeSettings(hidden: true)
        store.saveTransaction(TransactionRecord(id: "gig", name: "Gig", amountMinor: 100_00, type: .income, category: .freelance, dayKey: "2026-11-02"))
        store.saveTransaction(TransactionRecord(id: "lunch", name: "Lunch", amountMinor: 12_00, type: .expense, category: .food, dayKey: "2026-11-03"))

        let gig = run("update_transaction", ["transaction_id": "gig", "amount": 250.0], settings: settings, store: store)
        XCTAssertTrue(gig.toolOutput.contains("250"), gig.toolOutput)
        let lunch = run("update_transaction", ["transaction_id": "lunch", "amount": 15.0], settings: settings, store: store)
        XCTAssertTrue(lunch.toolOutput.contains("15"), lunch.toolOutput)
    }

    func testAddingSalaryWhileHiddenIsMaskedAndAddingFreelanceIsNot() throws {
        let store = try makeStore()
        let settings = makeSettings(hidden: true)
        let outcome = run("add_transactions", ["items": [
            ["name": "Payroll", "amount": 4_000.0, "type": "income", "category": "salary"],
            ["name": "Gig", "amount": 90.0, "type": "income", "category": "freelance"],
        ]], settings: settings, store: store)
        XCTAssertEqual(outcome.receipts.map(\.amountText), [MoneyFormat.hiddenPlaceholder, "+$90.00"])
        XCTAssertFalse(outcome.toolOutput.contains("4,000"), outcome.toolOutput)
    }

    func testNothingIsMaskedWhenSalaryIsVisible() throws {
        let store = try makeStore()
        let settings = makeSettings(hidden: false)
        store.saveTransaction(TransactionRecord(id: "pay", name: "Payroll", amountMinor: 4_321_00, type: .income, category: .salary, dayKey: "2026-11-02"))
        let outcome = run("update_transaction", ["transaction_id": "pay", "amount": 7_654.0], settings: settings, store: store)
        XCTAssertTrue(outcome.toolOutput.contains("7,654"), outcome.toolOutput)
    }
}
