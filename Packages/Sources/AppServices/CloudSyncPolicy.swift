import CloudKit
import Foundation
import TallyCore

/// Pure decisions behind `CloudSync`'s CloudKit error and zone handling, kept apart so they can
/// be unit-tested without a CloudKit round trip.
enum CloudSyncPolicy {
    /// Why sync was paused. Local budget data is never deleted automatically; the user decides
    /// whether to turn iCloud sync back on (which re-uploads everything to a fresh zone).
    enum PauseReason: Equatable {
        /// The owner's zone was deleted (another device of this Apple ID, or an unknown cause).
        case zoneDeleted
        /// The user deleted the app's iCloud data in Settings (`.purged`, `.userDeletedZone`).
        case purged
        /// The user reset their encrypted iCloud data (`.encryptedDataReset`).
        case encryptedDataReset
        /// The shared household zone is gone for this participant (owner stopped sharing,
        /// removed this participant or deleted the zone).
        case sharedHouseholdUnavailable
    }

    enum ZoneLossAction: Equatable {
        /// Not the zone this device syncs: nothing to do.
        case ignore
        /// Stop syncing the zone, cancel its pending changes, clear its system fields and keep
        /// local data; surface `reason` and turn the iCloud toggle off.
        case pauseSync(PauseReason)
        /// The owner's zone is missing for a recoverable reason: save the zone and retry.
        case recreateZone
    }

    /// Apple's contract (`CKSyncEngineZoneDeletionReason` in CloudKit's headers):
    /// - `.deleted`: "Your app deleted the record zone" (here: another device or the share's
    ///   owner). Apple's sample deletes the zone's local data.
    /// - `.purged`: the user purged the app's data in Settings; "you must delete any locally
    ///   cached data and not resend it to iCloud".
    /// - `.encryptedDataReset`: the user reset their encrypted data; same requirement as
    ///   `.purged` in the `CKSyncEngine` header (the older `CKFetchDatabaseChangesOperation`
    ///   documentation suggests re-uploading instead).
    ///
    /// Deliberate deviation: local budget data is never deleted. Every reason pauses sync (no
    /// resend, pending changes dropped, system fields cleared) and asks the user.
    static func actionForZoneDeletion(
        zoneID: CKRecordZone.ID,
        reason: CKDatabase.DatabaseChange.Deletion.Reason,
        activeZoneID: CKRecordZone.ID?,
        isOwner: Bool
    ) -> ZoneLossAction {
        guard let activeZoneID, zoneID == activeZoneID else { return .ignore }
        switch reason {
        case .purged: return .pauseSync(.purged)
        case .encryptedDataReset: return .pauseSync(.encryptedDataReset)
        case .deleted: return .pauseSync(isOwner ? .zoneDeleted : .sharedHouseholdUnavailable)
        @unknown default: return .pauseSync(isOwner ? .zoneDeleted : .sharedHouseholdUnavailable)
        }
    }

    /// A save failed with `.zoneNotFound` (or `.userDeletedZone`). Recreating the zone is only
    /// for the recoverable case: this device owns the zone, the user did not reset or purge
    /// their data, and the failed record had never been saved there (no server change tag), so
    /// nothing suggests the zone existed and was deliberately removed.
    static func actionForMissingZone(
        isOwner: Bool,
        errorCode: CKError.Code,
        userDidResetEncryptedData: Bool,
        recordHadServerChangeTag: Bool
    ) -> ZoneLossAction {
        if errorCode == .userDeletedZone { return .pauseSync(.purged) }
        if userDidResetEncryptedData { return .pauseSync(.encryptedDataReset) }
        guard isOwner else { return .pauseSync(.sharedHouseholdUnavailable) }
        if recordHadServerChangeTag { return .pauseSync(.zoneDeleted) }
        return .recreateZone
    }

    static func message(for reason: PauseReason, language: AppLanguage) -> String {
        let resume = L10n.text(
            language,
            en: " Your budget is still on this device. Turn on Sync with iCloud to upload it again; if you share the household, invite your partner again afterwards.",
            vi: " Dữ liệu vẫn còn trên thiết bị này. Bật Đồng bộ iCloud để tải lên lại; nếu đang dùng sổ chung, hãy mời lại người thân sau đó.",
            zh: " 预算数据仍保留在本设备上。打开 iCloud 同步即可重新上传；如果与伴侣共享，之后需要重新邀请。"
        )
        switch reason {
        case .zoneDeleted:
            return L10n.text(language, en: "Tally's data was removed from iCloud, so sync is paused.", vi: "Dữ liệu Tally đã bị xoá khỏi iCloud nên đồng bộ đã tạm dừng.", zh: "Tally 的数据已从 iCloud 中删除，同步已暂停。") + resume
        case .purged:
            return L10n.text(language, en: "Tally's iCloud data was deleted in Settings, so sync is paused.", vi: "Dữ liệu iCloud của Tally đã bị xoá trong Cài đặt nên đồng bộ đã tạm dừng.", zh: "已在“设置”中删除 Tally 的 iCloud 数据，同步已暂停。") + resume
        case .encryptedDataReset:
            return L10n.text(language, en: "Your encrypted iCloud data was reset, so sync is paused.", vi: "Dữ liệu iCloud mã hoá đã được đặt lại nên đồng bộ đã tạm dừng.", zh: "你的 iCloud 加密数据已被重置，同步已暂停。") + resume
        case .sharedHouseholdUnavailable:
            return L10n.text(
                language,
                en: "The shared household is no longer available in iCloud, so sync is paused. Your data is still on this device. Ask your partner for a new invite, or leave the shared household to sync on your own.",
                vi: "Sổ chung không còn trên iCloud nên đồng bộ đã tạm dừng. Dữ liệu vẫn còn trên thiết bị này. Hãy xin lời mời mới hoặc rời sổ chung để tự đồng bộ.",
                zh: "共享家庭账本已不在 iCloud 中，同步已暂停。数据仍保留在本设备上。请向伴侣索取新邀请，或退出共享账本单独同步。"
            )
        }
    }

    static func recreatedZoneMessage(language: AppLanguage) -> String {
        L10n.text(
            language,
            en: "Tally recreated its iCloud zone. The previous household share no longer exists: invite your partner again.",
            vi: "Tally đã tạo lại vùng dữ liệu iCloud. Lời mời chia sẻ cũ không còn hiệu lực: hãy mời lại người thân.",
            zh: "Tally 已重新创建 iCloud 区域。原有的家庭共享已失效，请重新邀请伴侣。"
        )
    }

    static func conflictLoopMessage(language: AppLanguage) -> String {
        L10n.text(
            language,
            en: "Some changes keep conflicting with iCloud. Tally will retry them later.",
            vi: "Một số thay đổi liên tục xung đột với iCloud. Tally sẽ thử lại sau.",
            zh: "部分更改与 iCloud 反复冲突，Tally 稍后会重试。"
        )
    }

    // MARK: Records

    /// Only records of the zone this device currently syncs are applied.
    static func isInActiveZone(_ recordID: CKRecord.ID, activeZoneID: CKRecordZone.ID?) -> Bool {
        guard let activeZoneID else { return false }
        return recordID.zoneID == activeZoneID
    }

    /// Pending saves the engine may send now: inside `scope` and the active zone, at most
    /// `limit` of them (Apple's sample filters by scope before taking a batch).
    static func batch(
        _ pending: [CKSyncEngine.PendingRecordZoneChange],
        scope: CKSyncEngine.SendChangesOptions.Scope,
        activeZoneID: CKRecordZone.ID?,
        limit: Int
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        let eligible = pending.lazy.filter { change in
            guard scope.contains(change) else { return false }
            switch change {
            case .saveRecord(let id), .deleteRecord(let id):
                return isInActiveZone(id, activeZoneID: activeZoneID)
            @unknown default:
                return false
            }
        }
        return Array(eligible.prefix(max(1, limit)))
    }
}

/// Bounds re-sending a record that keeps being rejected with `.serverRecordChanged`: the first
/// few conflicts retry immediately, later ones back off exponentially (capped) until a save of
/// that record succeeds.
struct ConflictRetryGuard {
    static let immediateRetries = 3
    static let baseBackoff: TimeInterval = 30
    static let maxBackoff: TimeInterval = 3600

    enum Decision: Equatable {
        case retryNow
        case backOff(TimeInterval)
    }

    private(set) var conflicts: [CloudRecordKey: Int] = [:]

    mutating func noteConflict(_ key: CloudRecordKey) -> Decision {
        let count = (conflicts[key] ?? 0) + 1
        conflicts[key] = count
        guard count > Self.immediateRetries else { return .retryNow }
        let exponent = min(count - Self.immediateRetries - 1, 10)
        return .backOff(min(Self.baseBackoff * pow(2, Double(exponent)), Self.maxBackoff))
    }

    /// `true` while some record is past its immediate retries.
    var isBackingOff: Bool { conflicts.values.contains { $0 > Self.immediateRetries } }

    mutating func noteSaved(_ key: CloudRecordKey) {
        conflicts.removeValue(forKey: key)
    }

    mutating func reset() {
        conflicts = [:]
    }
}

/// Batch size for `nextRecordZoneChangeBatch`: halved on `.limitExceeded` (CloudKit's guidance
/// is to split the request in half and retry), grown back after successful sends.
struct BatchSizer {
    static let maximum = 100
    private(set) var limit = BatchSizer.maximum

    mutating func noteLimitExceeded() { limit = max(1, limit / 2) }
    mutating func noteSuccess() { limit = min(Self.maximum, limit * 2) }
}
