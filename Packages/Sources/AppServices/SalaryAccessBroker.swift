import BudgetKit
import Foundation
import Observation
import TallyCore

/// Runs a `request_salary_access` tool call: shows the consent card (through `pending`), suspends
/// the tool loop until the user answers, and on Allow unlocks through the same gate as the eye
/// button. Allow always asks for Face ID / passcode, even when the Settings requirement is off
/// (a device with neither unlocks directly); re-locking follows the gate's rules.
///
/// - At most one request per turn (`turnID`, one user message); a repeat returns
///   `.alreadyRequested` without asking.
/// - Already visible salary returns `.alreadyVisible` without a card.
/// - Cancelling the waiting task (Stop, new chat) resolves as `.cancelled`; `declinePending()`
///   (Not now, or leaving the chat screen) as `.declined`.
/// - Waiting never blocks the main actor: the caller suspends on a continuation.
@MainActor
@Observable
public final class SalaryAccessBroker {
    public struct Request: Identifiable, Equatable, Sendable {
        public let id: UUID
        public let reason: String
        public let turnID: UUID
    }

    /// The card waiting for the user's answer, if any.
    public private(set) var pending: Request?

    @ObservationIgnored private var continuation: CheckedContinuation<Decision, Never>?
    @ObservationIgnored private var requestedTurns: Set<UUID> = []

    enum Decision {
        case allow
        case decline
        case cancel
    }

    public init() {}

    /// Asks for salary access for `turnID`. `onCard` is called once the card should be shown (with
    /// the record to persist) and again with the final status.
    public func request(
        reason: String?,
        turnID: UUID,
        gate: SalaryVisibilityGate,
        language: AppLanguage,
        onCard: (SalaryConsentRecord) -> Void = { _ in }
    ) async -> SalaryAccessOutcome {
        guard let reason else { return .invalid }
        guard !requestedTurns.contains(turnID) else { return .alreadyRequested }
        requestedTurns.insert(turnID)
        guard gate.isHidden else { return .alreadyVisible }
        guard pending == nil, continuation == nil else { return .alreadyRequested }

        var record = SalaryConsentRecord(reason: reason)
        let request = Request(id: record.id, reason: reason, turnID: turnID)
        pending = request
        onCard(record)

        let decision = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Decision, Never>) in
                self.continuation = continuation
                if Task.isCancelled { self.resolve(.cancel) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resolve(.cancel) }
        }

        let outcome: SalaryAccessOutcome
        switch decision {
        case .decline:
            outcome = .declined
        case .cancel:
            outcome = .cancelled
        case .allow:
            if Task.isCancelled {
                outcome = .cancelled
            } else {
                let revealed = await gate.reveal(reason: SalaryAuthPrompt.reveal(in: language), alwaysAuthenticate: true)
                outcome = revealed ? .granted : .authFailed
            }
        }
        record.status = SalaryConsentRecord.status(for: outcome)
        onCard(record)
        return outcome
    }

    /// Allow on the card (for request `id`; a stale id is ignored).
    public func allow(_ id: UUID) {
        guard pending?.id == id else { return }
        resolve(.allow)
    }

    /// Not now on the card (for request `id`; a stale id is ignored).
    public func decline(_ id: UUID) {
        guard pending?.id == id else { return }
        resolve(.decline)
    }

    /// Declines whatever is waiting (the user left the chat screen).
    public func declinePending() {
        resolve(.decline)
    }

    /// Forgets which turns already asked (a new chat).
    public func reset() {
        resolve(.cancel)
        requestedTurns.removeAll()
    }

    private func resolve(_ decision: Decision) {
        guard let continuation else { return }
        self.continuation = nil
        pending = nil
        continuation.resume(returning: decision)
    }
}

extension SalaryAccessBroker {
    /// `true` once `turnID` has asked (the model may not ask again in that message).
    public func hasRequested(turnID: UUID) -> Bool { requestedTurns.contains(turnID) }
}
