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
}

/// Pure, deterministic Last-Write-Wins merge rules for household sync between devices and partners.
/// Deletions are tombstones (`isDeleted = true`) stamped with `updatedAt` so a slower offline
/// device never resurrects a record the other partner already deleted.
public enum SyncMerge {
    public static func mergeTransaction(local: TransactionRecord?, remote: TransactionRecord) -> TransactionRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        // Deterministic tie-breaker: prefer deleted tombstone or higher payload hash.
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        return remote.name >= local.name ? remote : local
    }

    public static func mergeBudget(local: BudgetLimitRecord?, remote: BudgetLimitRecord) -> BudgetLimitRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        return remote.limitMinor >= local.limitMinor ? remote : local
    }

    public static func mergeGoal(local: SavingsGoalRecord?, remote: SavingsGoalRecord) -> SavingsGoalRecord {
        guard let local else { return remote }
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        if remote.isDeleted != local.isDeleted { return remote.isDeleted ? remote : local }
        return remote.savedMinor >= local.savedMinor ? remote : local
    }

    /// CloudKit record names must be unique per zone across record types.
    public static func cloudRecordName(kind: SyncRecordKind, id: String) -> String {
        switch kind {
        case .transaction: return "tx_\(id)"
        case .budget: return "bd_\(id.replacingOccurrences(of: "/", with: "_"))"
        case .goal: return "gl_\(id)"
        }
    }
}
