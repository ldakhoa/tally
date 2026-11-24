import BudgetKit
import Foundation
import TallyCore

/// Which CloudKit database + custom zone this device syncs with.
/// - `.privateOwner`: this user owns the `TallyHousehold` zone in their privateCloudDatabase
///   (works solo and when sharing out to their partner via `CKShare`).
/// - `.sharedParticipant`: this user accepted an iCloud share link from their partner and syncs
///   read/write against that shared zone in `sharedCloudDatabase`.
public enum CloudZoneRole: Codable, Equatable, Hashable, Sendable {
    case privateOwner
    case sharedParticipant(zoneName: String, ownerName: String)

    public static let defaultZoneName = "TallyHousehold"

    public var isSharedParticipant: Bool {
        if case .sharedParticipant = self { return true }
        return false
    }
}

public enum SyncRecordKind: String, Codable, Hashable, Sendable {
    case transaction = "TallyTransaction"
    case budget = "TallyBudget"
    case goal = "TallyGoal"
    case plan = "TallyInstallmentPlan"
}

/// Pure, deterministic Last-Write-Wins merge rules for household sync between devices and partners.
/// Deletions are tombstones (`isDeleted = true`) stamped with `updatedAt` so a slower offline
/// device never resurrects a record the other partner already deleted. Every merge is a join
/// (commutative, associative and idempotent, ties included), so devices converge whatever order
/// and grouping records arrive in.
public enum SyncMerge {
    public static func mergeTransaction(local: TransactionRecord?, remote: TransactionRecord) -> TransactionRecord {
        guard let local else { return remote }
        if local.paymentState != nil || remote.paymentState != nil {
            return mergePlanPayment(local, remote)
        }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        // Deterministic tie-breaker: prefer deleted tombstone, then the larger name, then the
        // canonical encoding.
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        if remote.name != local.name { return remote.name > local.name ? remote : local }
        return canonicalTieBreak(local: local, remote: remote)
    }

    /// Plan payments merge as the join of their `PlanPaymentState`s (user operation and schedule
    /// state, each by its own order); the visible fields are derived from the result. A side
    /// without a state (older app version) counts as a user write at its `updatedAt`. The result
    /// is commutative, associative and idempotent, so devices converge whatever the order and
    /// grouping in which writes arrive, and an automatic write never overrides an explicit user
    /// operation.
    static func mergePlanPayment(_ a: TransactionRecord, _ b: TransactionRecord) -> TransactionRecord {
        let state = a.effectivePaymentState.joined(with: b.effectivePaymentState)
        // Identity: both sides share the deterministic id; take plan fields from the side that
        // has them (the larger value if both differ, which only a corrupt payload could cause).
        var base = a
        base.planID = [a.planID, b.planID].compactMap { $0 }.max()
        base.planPaymentIndex = [a.planPaymentIndex, b.planPaymentIndex].compactMap { $0 }.max()
        return base.applying(state)
    }

    public static func mergeBudget(local: BudgetLimitRecord?, remote: BudgetLimitRecord) -> BudgetLimitRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        if remote.limitMinor != local.limitMinor { return remote.limitMinor > local.limitMinor ? remote : local }
        return canonicalTieBreak(local: local, remote: remote)
    }

    public static func mergeGoal(local: SavingsGoalRecord?, remote: SavingsGoalRecord) -> SavingsGoalRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        if remote.savedMinor != local.savedMinor { return remote.savedMinor > local.savedMinor ? remote : local }
        return canonicalTieBreak(local: local, remote: remote)
    }

    public static func mergePlan(local: InstallmentPlanRecord?, remote: InstallmentPlanRecord) -> InstallmentPlanRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        if remote.totalMinor != local.totalMinor { return remote.totalMinor > local.totalMinor ? remote : local }
        if remote.name != local.name { return remote.name > local.name ? remote : local }
        return canonicalTieBreak(local: local, remote: remote)
    }

    /// Total order over every field: the record whose sorted-key JSON encoding is
    /// lexicographically larger wins. Only reached when timestamps and the cheap tie-breakers
    /// are equal.
    static func canonicalTieBreak<T: Encodable & Equatable>(local: T, remote: T) -> T {
        if local == remote { return remote }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let localData = try? encoder.encode(local),
              let remoteData = try? encoder.encode(remote)
        else { return remote }
        return remoteData.lexicographicallyPrecedes(localData) ? local : remote
    }

    /// Outcome of a `.serverRecordChanged` save conflict: the record to keep locally and whether
    /// the local revision won, so it must be saved again on top of the server's record.
    public struct ConflictResolution<Record: Equatable>: Equatable {
        public let merged: Record
        public let resendLocal: Bool
    }

    /// Resolves a save conflict with the same rules as fetched changes. `resendLocal` is `true`
    /// only when the merged result differs from what the server holds.
    public static func resolveConflict<Record: Equatable>(
        local: Record?,
        server: Record,
        merge: (Record?, Record) -> Record
    ) -> ConflictResolution<Record> {
        let merged = merge(local, server)
        return ConflictResolution(merged: merged, resendLocal: merged != server)
    }

    /// CloudKit record names must be unique per zone across record types.
    public static func cloudRecordName(kind: SyncRecordKind, id: String) -> String {
        switch kind {
        case .transaction: return "tx_\(id)"
        case .budget: return "bd_\(id.replacingOccurrences(of: "/", with: "_"))"
        case .goal: return "gl_\(id)"
        case .plan: return "pl_\(id)"
        }
    }
}
