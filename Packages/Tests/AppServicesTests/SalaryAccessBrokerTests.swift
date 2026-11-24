@testable import AppServices
import BudgetKit
import ClaudeKit
import Foundation
import TallyCore
import XCTest

/// The consent state machine behind `request_salary_access`, driven with the gate's
/// `FakeAuthenticator` (no system prompt).
@MainActor
final class SalaryAccessBrokerTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func makeGate(hidden: Bool = true, requires: Bool = false, auth: FakeAuthenticator = FakeAuthenticator()) -> SalaryVisibilityGate {
        let name = "tally.test.\(UUID().uuidString)"
        suites.append(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(hidden, forKey: "tally.hideIncome")
        defaults.set(requires, forKey: "tally.salary.requireAuth")
        return SalaryVisibilityGate(defaults: defaults, authenticator: auth)
    }

    /// Starts a request and waits until its card is up.
    private func start(
        _ broker: SalaryAccessBroker,
        gate: SalaryVisibilityGate,
        turn: UUID = UUID(),
        cards: CardLog
    ) async throws -> Task<SalaryAccessOutcome, Never> {
        let task = Task { @MainActor in
            await broker.request(reason: "To work out your savings rate.", turnID: turn, gate: gate, language: .english) { cards.records.append($0) }
        }
        for _ in 0..<200 where broker.pending == nil { await Task.yield() }
        XCTAssertNotNil(broker.pending, "the card is shown")
        return task
    }

    @MainActor final class CardLog {
        var records: [SalaryConsentRecord] = []
        var statuses: [SalaryConsentRecord.Status] { records.map(\.status) }
    }

    func testAllowWithoutRequirementStillAuthenticates() async throws {
        let auth = FakeAuthenticator()
        let gate = makeGate(auth: auth)
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)
        XCTAssertEqual(broker.pending?.reason, "To work out your savings rate.")
        XCTAssertTrue(gate.isHidden, "nothing changes while waiting")

        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .granted)
        XCTAssertFalse(gate.isHidden)
        XCTAssertEqual(auth.prompts, [SalaryAuthPrompt.reveal(in: .english)], "Allow in chat always authenticates")
        XCTAssertNil(broker.pending)
        XCTAssertEqual(cards.statuses, [.pending, .allowed])
        XCTAssertEqual(Set(cards.records.map(\.id)).count, 1, "one card, updated in place")
    }

    func testAllowWithoutRequirementFailsWhenAuthenticationFails() async throws {
        let auth = FakeAuthenticator()
        auth.result = false
        let gate = makeGate(auth: auth)
        let broker = SalaryAccessBroker()
        let task = try await start(broker, gate: gate, cards: CardLog())

        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .authFailed)
        XCTAssertTrue(gate.isHidden)
    }

    func testAllowOnDeviceWithNoPasscodeUnlocksDirectly() async throws {
        let auth = FakeAuthenticator()
        auth.kind = .none
        let gate = makeGate(auth: auth)
        let broker = SalaryAccessBroker()
        let task = try await start(broker, gate: gate, cards: CardLog())

        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .granted)
        XCTAssertTrue(auth.prompts.isEmpty)
        XCTAssertFalse(gate.isHidden)
    }

    func testAllowWithRequirementAuthenticatesThroughTheGate() async throws {
        let auth = FakeAuthenticator()
        auth.suspends = true
        let gate = makeGate(requires: true, auth: auth)
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)

        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .granted)
        XCTAssertEqual(auth.prompts, [SalaryAuthPrompt.reveal(in: .english)])
        XCTAssertFalse(gate.isHidden)
        // Re-locks under the gate's own rules.
        gate.appDidEnterBackground()
        XCTAssertTrue(gate.isHidden)
    }

    func testFailedAuthenticationKeepsSalaryHidden() async throws {
        let auth = FakeAuthenticator()
        auth.result = false
        let gate = makeGate(requires: true, auth: auth)
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)

        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .authFailed)
        XCTAssertTrue(gate.isHidden)
        XCTAssertEqual(auth.prompts.count, 1)
        XCTAssertEqual(cards.statuses, [.pending, .authFailed])
        XCTAssertTrue(outcome.toolResult.hasPrefix("declined"))
    }

    func testNotNowDeclines() async throws {
        let auth = FakeAuthenticator()
        let gate = makeGate(requires: true, auth: auth)
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)

        broker.decline(try XCTUnwrap(broker.pending?.id))
        let outcome = await task.value

        XCTAssertEqual(outcome, .declined)
        XCTAssertTrue(gate.isHidden)
        XCTAssertTrue(auth.prompts.isEmpty)
        XCTAssertEqual(cards.statuses, [.pending, .declined])
    }

    func testLeavingTheChatDeclinesAndStaleButtonsAreIgnored() async throws {
        let gate = makeGate()
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)
        let id = try XCTUnwrap(broker.pending?.id)

        broker.allow(UUID()) // a button from another card
        XCTAssertNotNil(broker.pending)
        broker.declinePending()
        let outcome = await task.value
        broker.allow(id) // too late

        XCTAssertEqual(outcome, .declined)
        XCTAssertTrue(gate.isHidden)
    }

    func testCancellingTheReplyResolvesAsCancelled() async throws {
        let gate = makeGate()
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)

        task.cancel()
        let outcome = await task.value

        XCTAssertEqual(outcome, .cancelled)
        XCTAssertTrue(gate.isHidden)
        XCTAssertNil(broker.pending)
        XCTAssertEqual(cards.statuses, [.pending, .cancelled])
    }

    func testOneRequestPerUserMessage() async throws {
        let gate = makeGate()
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let turn = UUID()
        let first = try await start(broker, gate: gate, turn: turn, cards: cards)
        broker.decline(try XCTUnwrap(broker.pending?.id))
        _ = await first.value
        XCTAssertTrue(broker.hasRequested(turnID: turn))

        let repeated = await broker.request(reason: "Again", turnID: turn, gate: gate, language: .english) { cards.records.append($0) }
        XCTAssertEqual(repeated, .alreadyRequested)
        XCTAssertEqual(cards.records.count, 2, "no second card")
        XCTAssertNil(broker.pending)

        // The next user message may ask again.
        let next = try await start(broker, gate: gate, turn: UUID(), cards: cards)
        broker.allow(try XCTUnwrap(broker.pending?.id))
        let outcome = await next.value
        XCTAssertEqual(outcome, .granted)

        // A new chat forgets earlier turns.
        broker.reset()
        XCTAssertFalse(broker.hasRequested(turnID: turn))
    }

    func testAlreadyVisibleAndMissingReasonNeverShowACard() async {
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let visible = await broker.request(reason: "r", turnID: UUID(), gate: makeGate(hidden: false), language: .english) { cards.records.append($0) }
        XCTAssertEqual(visible, .alreadyVisible)
        XCTAssertTrue(visible.isGranted)
        let invalid = await broker.request(reason: nil, turnID: UUID(), gate: makeGate(), language: .english) { cards.records.append($0) }
        XCTAssertEqual(invalid, .invalid)
        XCTAssertTrue(cards.records.isEmpty)
    }

    func testResetWhileWaitingCancels() async throws {
        let gate = makeGate()
        let broker = SalaryAccessBroker()
        let cards = CardLog()
        let task = try await start(broker, gate: gate, cards: cards)
        broker.reset()
        let outcome = await task.value
        XCTAssertEqual(outcome, .cancelled)
    }

    // MARK: Chat history

    func testChatEntriesWithoutConsentsStillDecodeAndConsentsRoundTrip() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"assistant","text":"Hi","actions":[],"timestamp":0}"#
        let entry = try JSONDecoder().decode(ChatEntry.self, from: Data(old.utf8))
        XCTAssertNil(entry.consents)
        XCTAssertFalse(entry.hasConsents)

        var withCard = ChatEntry(role: .assistant, text: "")
        XCTAssertFalse(withCard.hasContent)
        var record = SalaryConsentRecord(reason: "To check your savings rate.")
        withCard.upsertConsent(record)
        record.status = .declined
        withCard.upsertConsent(record)
        XCTAssertEqual(withCard.consents, [record], "updated in place")
        XCTAssertTrue(withCard.hasContent, "a reply holding only a consent card is kept in history")
        let decoded = try JSONDecoder().decode(ChatEntry.self, from: JSONEncoder().encode(withCard))
        XCTAssertEqual(decoded.consents?.first?.status, .declined)
    }
}
