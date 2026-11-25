import BudgetKit
import CloudKit
import Foundation
import Observation
import SyncKit
import TallyCore

/// iCloud sync engine supporting BOTH:
/// 1. Private household zone (`TallyHousehold` in `privateCloudDatabase`) — owner & owner's devices
/// 2. Shared household zone (`sharedCloudDatabase` via `CKShare`) — wife / partner on their own Apple ID!
///
/// Follows Onsite's CloudKit discipline: never calls `engine.sendChanges` or `fetchChanges` inside
/// delegate callbacks; always schedules sends via a detached task (`sendSoon`).
@MainActor
@Observable
public final class CloudSync: CKSyncEngineDelegate {
    public static weak var current: CloudSync?

    public enum Phase: Equatable {
        case unavailable
        case off
        case checkingAccount
        case noAccount
        case accountUnavailable
        case running
    }

    public private(set) var phase: Phase = .off
    public private(set) var lastSynced: Date?
    public private(set) var problem: String?
    public private(set) var isSyncing = false
    public private(set) var activeShare: CKShare?
    public private(set) var participantNames: [String] = []

    @ObservationIgnored private weak var settings: AppSettings?
    @ObservationIgnored private weak var store: BudgetStore?
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var activeZoneID: CKRecordZone.ID?
    @ObservationIgnored private var sendKick: Task<Void, Never>?
    @ObservationIgnored private var accountObserver: NSObjectProtocol?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private lazy var systemFields = CloudSystemFieldsStore(fileURL: systemFieldsURL)
    @ObservationIgnored private var conflictGuard = ConflictRetryGuard()
    @ObservationIgnored private var batchSizer = BatchSizer()
    /// Records whose save conflicted without a usable server record: their cached fields were
    /// dropped and they are queued again after the next fetch brings the server's version.
    @ObservationIgnored private var repairAfterFetch: Set<CKRecord.ID> = []
    /// `true` while `problem` holds a notice that a successful save must not clear (the zone was
    /// recreated and the partner must be invited again). Cleared by Sync Now or a restart.
    @ObservationIgnored private var keepsProblem = false
    private static var pendingShareMetadata: CKShare.Metadata?

    public init() {}

    /// Safely accepts a CloudKit share even if the OS delivers `CKShare.Metadata` on cold launch
    /// before `CloudSync.start(...)` has connected `CloudSync.current`.
    public static func acceptShareWhenReady(_ metadata: CKShare.Metadata) {
        if let current {
            Task { @MainActor in
                await current.acceptShare(metadata: metadata)
            }
        } else {
            pendingShareMetadata = metadata
        }
    }

    public static var containerIdentifier: String? {
        let id = Bundle.main.object(forInfoDictionaryKey: "TallyCloudContainer") as? String
        return (id?.isEmpty == false) ? id : nil
    }

    public var isSharedHouseholdActive: Bool {
        if let settings, settings.cloudZoneRole.isSharedParticipant { return true }
        return activeShare != nil && !participantNames.isEmpty
    }

    public func start(settings: AppSettings, store: BudgetStore) {
        guard !hasStarted else { return }
        hasStarted = true
        Self.current = self
        self.settings = settings
        self.store = store

        store.onLocalChanges = { [weak self] changes in
            Task { @MainActor in
                self?.enqueueLocalChanges(changes)
            }
        }
        settings.onHouseholdCurrencyChanged = { [weak self] record in
            Task { @MainActor in
                self?.enqueueLocalChanges([ChangedSyncRecord(kind: .householdSettings, id: record.id)])
            }
        }

        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }

        reconcile()

        if let pending = Self.pendingShareMetadata {
            Self.pendingShareMetadata = nil
            Task { @MainActor [weak self] in
                await self?.acceptShare(metadata: pending)
            }
        }
    }

    public func reconcile() {
        guard let settings else { return }
        guard Self.containerIdentifier != nil else {
            phase = .unavailable
            return
        }
        guard settings.syncsWithICloud else {
            Task { await stopEngine(clearState: false) }
            phase = .off
            return
        }
        if engine == nil {
            Task { await startEngine() }
        }
    }

    public func syncNow() {
        guard let engine else {
            reconcile()
            return
        }
        Task {
            isSyncing = true
            defer { isSyncing = false }
            do {
                try await engine.fetchChanges()
                if let store {
                    enqueueLocalChanges(fullUploadRecords(store: store), scheduleSend: false)
                }
                try await engine.sendChanges()
                lastSynced = Date()
                keepsProblem = false
                problem = nil
                await refreshShareSummary()
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    public func appBecameActive() {
        guard let engine else { return }
        Task {
            do {
                try await engine.fetchChanges()
                lastSynced = Date()
                await refreshShareSummary()
            } catch {
                // Silent on foreground refresh unless user hits Sync Now
            }
        }
    }

    // MARK: - Household Sharing (Husband <-> Wife via CKShare)

    /// Creates or fetches the zone-wide `CKShare` on `TallyHousehold` so the owner can invite
    /// their wife via Apple's native `UICloudSharingController` (Messages, AirDrop, Mail, etc.).
    public func prepareHouseholdShare() async throws -> (CKShare, CKContainer) {
        guard let identifier = Self.containerIdentifier else {
            throw NSError(domain: "TallyCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud container is not configured for this build."])
        }
        let container = self.container ?? CKContainer(identifier: identifier)
        self.container = container
        let zoneID = CKRecordZone.ID(zoneName: CloudZoneRole.defaultZoneName, ownerName: CKCurrentUserDefaultName)
        let db = container.privateCloudDatabase

        // Ensure custom zone exists before creating the zone-wide share.
        _ = try await db.save(CKRecordZone(zoneID: zoneID))

        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await db.record(for: shareRecordID) as? CKShare {
            activeShare = existing
            await refreshShareSummary()
            return (existing, container)
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Tally Household Budget"
        share.publicPermission = .none
        let saved = try await db.save(share) as? CKShare ?? share
        activeShare = saved
        await refreshShareSummary()
        return (saved, container)
    }

    /// Called by the AppDelegate/SceneDelegate when the wife taps the iCloud invitation link.
    public func acceptShare(metadata: CKShare.Metadata) async {
        guard let identifier = Self.containerIdentifier, let settings else { return }
        let container = self.container ?? CKContainer(identifier: identifier)
        self.container = container
        isSyncing = true
        defer { isSyncing = false }

        do {
            _ = try await container.accept(metadata)
            // Discover the shared zone in sharedCloudDatabase.
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            if let sharedZone = zones.first(where: { $0.zoneID.zoneName == CloudZoneRole.defaultZoneName }) ?? zones.first {
                settings.cloudZoneRole = .sharedParticipant(
                    zoneName: sharedZone.zoneID.zoneName,
                    ownerName: sharedZone.zoneID.ownerName
                )
                settings.syncsWithICloud = true
                await stopEngine(clearState: true)
                await startEngine()
                problem = nil
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Leaves the shared household and returns this device to its own private iCloud zone.
    public func switchToPrivateHousehold() async {
        guard let settings else { return }
        settings.cloudZoneRole = .privateOwner
        activeShare = nil
        participantNames = []
        await stopEngine(clearState: true)
        if settings.syncsWithICloud {
            await startEngine()
        }
    }

    public func refreshShareSummary() async {
        guard let container, let settings else { return }
        switch settings.cloudZoneRole {
        case .privateOwner:
            let zoneID = CKRecordZone.ID(zoneName: CloudZoneRole.defaultZoneName, ownerName: CKCurrentUserDefaultName)
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            if let share = try? await container.privateCloudDatabase.record(for: shareID) as? CKShare {
                activeShare = share
                participantNames = share.participants
                    .filter { $0.role != .owner }
                    .compactMap { $0.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .short) } }
            } else {
                activeShare = nil
                participantNames = []
            }
        case .sharedParticipant(let zoneName, let ownerName):
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
            if let share = try? await container.sharedCloudDatabase.record(for: shareID) as? CKShare {
                activeShare = share
                if let ownerComp = share.owner.userIdentity.nameComponents {
                    participantNames = [PersonNameComponentsFormatter.localizedString(from: ownerComp, style: .short)]
                }
            }
        }
    }

    // MARK: - Engine Lifecycle

    private func startEngine() async {
        guard let settings, let identifier = Self.containerIdentifier else { return }
        let container = self.container ?? CKContainer(identifier: identifier)
        self.container = container
        phase = .checkingAccount

        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            problem = error.localizedDescription
            phase = .accountUnavailable
            return
        }

        switch status {
        case .available: break
        case .noAccount:
            phase = .noAccount
            return
        default:
            phase = .accountUnavailable
            return
        }

        let database: CKDatabase
        let zoneID: CKRecordZone.ID
        switch settings.cloudZoneRole {
        case .privateOwner:
            database = container.privateCloudDatabase
            zoneID = CKRecordZone.ID(zoneName: CloudZoneRole.defaultZoneName, ownerName: CKCurrentUserDefaultName)
        case .sharedParticipant(let zoneName, let ownerName):
            database = container.sharedCloudDatabase
            zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }

        self.activeZoneID = zoneID
        let saved = loadEngineState()
        var config = CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self)
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        phase = .running
        problem = nil

        if saved == nil, !settings.cloudZoneRole.isSharedParticipant {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }

        if let store {
            enqueueLocalChanges(fullUploadRecords(store: store), scheduleSend: false)
        }
        await refreshShareSummary()
        sendSoon()
    }

    private func fullUploadRecords(store: BudgetStore) -> [ChangedSyncRecord] {
        var changes = store.allChangedRecordsForFullUpload
        if let hs = settings?.householdSettingsRecord {
            changes.append(ChangedSyncRecord(kind: .householdSettings, id: hs.id))
        }
        return changes
    }

    private func stopEngine(clearState: Bool) async {
        let old = detachEngine(clearState: clearState)
        await old?.cancelOperations()
    }

    /// Synchronously drops the current engine, so every later callback from it is ignored as
    /// stale (see `handleEvent`). With `clearState`, its serialized state (including pending
    /// changes) and the cached system fields are deleted too.
    @discardableResult
    private func detachEngine(clearState: Bool) -> CKSyncEngine? {
        sendKick?.cancel()
        sendKick = nil
        let old = engine
        engine = nil
        repairAfterFetch = []
        keepsProblem = false
        conflictGuard.reset()
        batchSizer = BatchSizer()
        if clearState {
            activeZoneID = nil
            try? FileManager.default.removeItem(at: engineStateURL)
            // Change tags belong to the old zone / account; never reuse them.
            systemFields.removeAll()
        }
        return old
    }

    /// Stops syncing after the zone was lost for a reason the user must decide on (purge,
    /// encrypted-data reset, deletion by another device or the share's owner). Pending changes
    /// and system fields are dropped, local data is kept, the iCloud toggle is turned off and
    /// `problem` explains how to resume (turning sync back on re-uploads everything).
    private func pauseSync(_ reason: CloudSyncPolicy.PauseReason) {
        let old = detachEngine(clearState: true)
        old?.state.remove(pendingRecordZoneChanges: old?.state.pendingRecordZoneChanges ?? [])
        old?.state.remove(pendingDatabaseChanges: old?.state.pendingDatabaseChanges ?? [])
        settings?.syncsWithICloud = false
        phase = .off
        isSyncing = false
        problem = CloudSyncPolicy.message(for: reason, language: settings?.language ?? .english)
        Task { await old?.cancelOperations() }
    }

    private func enqueueLocalChanges(_ changes: [ChangedSyncRecord], scheduleSend: Bool = true) {
        guard let engine, let zoneID = activeZoneID, !changes.isEmpty else { return }
        let pending = changes.map { item in
            let recordName = SyncMerge.cloudRecordName(kind: item.kind, id: item.id)
            return CKSyncEngine.PendingRecordZoneChange.saveRecord(CKRecord.ID(recordName: recordName, zoneID: zoneID))
        }
        engine.state.add(pendingRecordZoneChanges: pending)
        if scheduleSend { sendSoon() }
    }

    private func sendSoon() {
        sendKick?.cancel()
        sendKick = Task.detached { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let engine = self.engine else { return }
            self.sendKick = nil
            guard !engine.state.pendingRecordZoneChanges.isEmpty else { return }
            try? await engine.sendChanges()
        }
    }

    // MARK: - CKSyncEngineDelegate

    nonisolated public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        let engineID = ObjectIdentifier(syncEngine)
        await MainActor.run {
            // Events from an engine that was replaced or stopped (zone switch, account change,
            // paused sync) must not touch the current state, files or store.
            guard self.isCurrentEngine(engineID) else { return }
            self.processEvent(event)
        }
    }

    private func isCurrentEngine(_ id: ObjectIdentifier) -> Bool {
        engine.map(ObjectIdentifier.init) == id
    }

    private func processEvent(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let update):
            saveEngineState(update.stateSerialization)
        case .accountChange:
            Task {
                await stopEngine(clearState: true)
                reconcile()
            }
        case .fetchedRecordZoneChanges(let changes):
            var txs: [TransactionRecord] = []
            var budgets: [BudgetLimitRecord] = []
            var goals: [SavingsGoalRecord] = []
            var plans: [InstallmentPlanRecord] = []
            let zone = activeZoneID
            for mod in changes.modifications {
                let record = mod.record
                // Only the zone this device currently syncs (never a previous household's).
                guard CloudSyncPolicy.isInActiveZone(record.recordID, activeZoneID: zone) else { continue }
                if SyncRecordKind(rawValue: record.recordType) != nil {
                    systemFields.remember(record)
                }
                switch record.recordType {
                case SyncRecordKind.transaction.rawValue:
                    if let tx = decodeTransaction(from: record) { txs.append(tx) }
                case SyncRecordKind.budget.rawValue:
                    if let b = decodeBudget(from: record) { budgets.append(b) }
                case SyncRecordKind.goal.rawValue:
                    if let g = decodeGoal(from: record) { goals.append(g) }
                case SyncRecordKind.plan.rawValue:
                    if let p = decodePlan(from: record) { plans.append(p) }
                case SyncRecordKind.householdSettings.rawValue:
                    if let hs = decodeHouseholdSettings(from: record) {
                        settings?.applyRemoteHouseholdSettings(hs)
                    }
                default:
                    break
                }
            }
            store?.applyRemoteTransactions(txs)
            store?.applyRemoteBudgets(budgets)
            store?.applyRemoteGoals(goals)
            // Plans last: applying them materializes due payments, which needs the latest
            // transaction tombstones from this batch so user-deleted payments stay deleted.
            // Newly created payments are queued through `onLocalChanges` -> `sendSoon()`
            // (detached task); the engine is never driven from inside this callback.
            store?.applyRemotePlans(plans)
            // Records from this person's other device may carry that device's member ID.
            if let store, let settings { store.reconcileMemberIdentities(settings: settings, notifyCloud: true) }
            for deletion in changes.deletions where CloudSyncPolicy.isInActiveZone(deletion.recordID, activeZoneID: zone) {
                systemFields.forget(deletion.recordID)
            }
            systemFields.saveIfNeeded()
            lastSynced = Date()
        case .fetchedDatabaseChanges(let changes):
            // Zone deletions follow Apple's per-reason contract (see `CloudSyncPolicy`), except
            // that local budget data is never deleted: sync pauses and the user decides.
            let isOwner = settings?.cloudZoneRole.isSharedParticipant != true
            for deletion in changes.deletions {
                let action = CloudSyncPolicy.actionForZoneDeletion(
                    zoneID: deletion.zoneID,
                    reason: deletion.reason,
                    activeZoneID: activeZoneID,
                    isOwner: isOwner
                )
                if case .pauseSync(let reason) = action {
                    pauseSync(reason)
                    return
                }
            }
        case .sentRecordZoneChanges(let sent):
            let saved = sent.savedRecords.filter { CloudSyncPolicy.isInActiveZone($0.recordID, activeZoneID: activeZoneID) }
            if !saved.isEmpty {
                lastSynced = Date()
                if !keepsProblem && !conflictGuard.isBackingOff { problem = nil }
            }
            for record in saved {
                systemFields.remember(record)
                conflictGuard.noteSaved(CloudRecordKey(record.recordID))
            }
            if !saved.isEmpty, !sent.failedRecordSaves.contains(where: { $0.error.code == .limitExceeded }) {
                batchSizer.noteSuccess()
            }
            handleFailedSaves(sent.failedRecordSaves.filter { CloudSyncPolicy.isInActiveZone($0.record.recordID, activeZoneID: activeZoneID) })
            systemFields.saveIfNeeded()
        case .willFetchChanges, .willSendChanges:
            isSyncing = true
        case .didFetchChanges:
            isSyncing = false
            requeueRepairedRecords()
        case .didSendChanges:
            isSyncing = false
        default:
            break
        }
    }

    /// Mirrors Apple's CKSyncEngine sample. The engine drops failed saves from its pending
    /// changes, so anything that must still reach the server is re-added here (state edits only;
    /// sending happens via `sendSoon()`'s detached task, never from inside this callback).
    private func handleFailedSaves(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) {
        guard !failures.isEmpty else { return }
        var resave: [CKSyncEngine.PendingRecordZoneChange] = []
        var databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
        var conflicts: [CKRecord] = []
        var needsFetch = false
        let isOwner = settings?.cloudZoneRole.isSharedParticipant != true
        for failed in failures {
            let recordID = failed.record.recordID
            switch failed.error.code {
            case .serverRecordChanged:
                guard let serverRecord = failed.error.serverRecord,
                      serverRecord.recordID == recordID,
                      serverRecord.recordType == failed.record.recordType
                else {
                    // No usable server record: drop our cached fields and let the next fetch
                    // bring the server's version before saving again.
                    systemFields.forget(recordID)
                    if case .retryNow = conflictGuard.noteConflict(CloudRecordKey(recordID)) {
                        repairAfterFetch.insert(recordID)
                        needsFetch = true
                    } else {
                        problem = CloudSyncPolicy.conflictLoopMessage(language: settings?.language ?? .english)
                    }
                    continue
                }
                // The server's change tag is the one the next save must carry: store it
                // unconditionally, merge its content with the usual rules, and send ours again
                // only if the local revision won.
                systemFields.replace(with: serverRecord)
                conflicts.append(serverRecord)
            case .unknownItem:
                // The server no longer has the record: drop the stale tag and recreate it.
                systemFields.forget(recordID)
                resave.append(.saveRecord(recordID))
            case .zoneNotFound, .userDeletedZone:
                systemFields.forget(recordID)
                let resetFlag = (failed.error.userInfo[CKErrorUserDidResetEncryptedDataKey] as? NSNumber)?.boolValue ?? false
                let action = CloudSyncPolicy.actionForMissingZone(
                    isOwner: isOwner,
                    errorCode: failed.error.code,
                    userDidResetEncryptedData: resetFlag,
                    recordHadServerChangeTag: failed.record.recordChangeTag != nil
                )
                switch action {
                case .pauseSync(let reason):
                    pauseSync(reason)
                    return
                case .recreateZone:
                    if databaseChanges.isEmpty {
                        databaseChanges.append(.saveZone(CKRecordZone(zoneID: recordID.zoneID)))
                        // A new zone has no share: a partner who had joined must be invited again.
                        if activeShare != nil {
                            activeShare = nil
                            participantNames = []
                            problem = CloudSyncPolicy.recreatedZoneMessage(language: settings?.language ?? .english)
                            keepsProblem = true
                        }
                    }
                    resave.append(.saveRecord(recordID))
                case .ignore:
                    break
                }
            case .limitExceeded:
                // Too large a request: send smaller batches and retry this record.
                batchSizer.noteLimitExceeded()
                resave.append(.saveRecord(recordID))
            case .batchRequestFailed:
                // Failed only because another record in the batch did; retry as is.
                resave.append(.saveRecord(recordID))
            default:
                // Network / throttling / auth errors are retried by CKSyncEngine itself.
                break
            }
        }
        var backOff: [(CKRecord.ID, TimeInterval)] = []
        for recordID in mergeConflicts(conflicts) {
            switch conflictGuard.noteConflict(CloudRecordKey(recordID)) {
            case .retryNow:
                resave.append(.saveRecord(recordID))
            case .backOff(let delay):
                backOff.append((recordID, delay))
            }
        }
        if !backOff.isEmpty {
            problem = CloudSyncPolicy.conflictLoopMessage(language: settings?.language ?? .english)
            for (recordID, delay) in backOff { requeueLater(recordID, after: delay) }
        }
        if needsFetch { fetchSoon() }
        guard let engine, !(resave.isEmpty && databaseChanges.isEmpty) else { return }
        if !databaseChanges.isEmpty {
            engine.state.add(pendingDatabaseChanges: databaseChanges)
        }
        if !resave.isEmpty {
            engine.state.add(pendingRecordZoneChanges: resave)
        }
        sendSoon()
    }

    /// Re-queues `recordID` after `delay` from a detached task (never from inside a delegate
    /// callback), unless the engine was replaced meanwhile.
    private func requeueLater(_ recordID: CKRecord.ID, after delay: TimeInterval) {
        guard let engine else { return }
        let engineID = ObjectIdentifier(engine)
        Task.detached { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isCurrentEngine(engineID), let engine = self.engine else { return }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            self.sendSoon()
        }
    }

    /// Fetches from a detached task (never from inside a delegate callback). Records waiting in
    /// `repairAfterFetch` are queued again on `.didFetchChanges`.
    private func fetchSoon() {
        guard let engine else { return }
        let engineID = ObjectIdentifier(engine)
        Task.detached { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.isCurrentEngine(engineID), let engine = self.engine else { return }
            try? await engine.fetchChanges()
        }
    }

    private func requeueRepairedRecords() {
        guard let engine, !repairAfterFetch.isEmpty else { return }
        let ids = repairAfterFetch.filter { CloudSyncPolicy.isInActiveZone($0, activeZoneID: activeZoneID) }
        repairAfterFetch = []
        guard !ids.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        sendSoon()
    }

    /// Applies conflicting server records locally (one store merge per record type, so the
    /// one-off conflict wave after upgrading does not reload the store per record). Returns the
    /// IDs whose local revision won the merge and must be saved again.
    private func mergeConflicts(_ serverRecords: [CKRecord]) -> [CKRecord.ID] {
        guard let store, !serverRecords.isEmpty else { return [] }
        var resend: [CKRecord.ID] = []
        var txs: [TransactionRecord] = []
        var budgets: [BudgetLimitRecord] = []
        var goals: [SavingsGoalRecord] = []
        var plans: [InstallmentPlanRecord] = []

        let localTx = Dictionary(store.transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localBudgets = Dictionary(store.budgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localGoals = Dictionary(store.goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let localPlans = Dictionary(store.plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for record in serverRecords {
            switch record.recordType {
            case SyncRecordKind.transaction.rawValue:
                guard let server = decodeTransaction(from: record) else { continue }
                if SyncMerge.resolveConflict(local: localTx[server.id], server: server, merge: SyncMerge.mergeTransaction).resendLocal {
                    resend.append(record.recordID)
                }
                txs.append(server)
            case SyncRecordKind.budget.rawValue:
                guard let server = decodeBudget(from: record) else { continue }
                if SyncMerge.resolveConflict(local: localBudgets[server.id], server: server, merge: SyncMerge.mergeBudget).resendLocal {
                    resend.append(record.recordID)
                }
                budgets.append(server)
            case SyncRecordKind.goal.rawValue:
                guard let server = decodeGoal(from: record) else { continue }
                if SyncMerge.resolveConflict(local: localGoals[server.id], server: server, merge: SyncMerge.mergeGoal).resendLocal {
                    resend.append(record.recordID)
                }
                goals.append(server)
            case SyncRecordKind.plan.rawValue:
                guard let server = decodePlan(from: record) else { continue }
                let local = localPlans[server.id]
                // An invalid server plan is ignored by the store; keep our revision on the server.
                guard server.isDeleted || server.hasValidTerms else {
                    if local != nil { resend.append(record.recordID) }
                    continue
                }
                if SyncMerge.resolveConflict(local: local, server: server, merge: SyncMerge.mergePlan).resendLocal {
                    resend.append(record.recordID)
                }
                plans.append(server)
            case SyncRecordKind.householdSettings.rawValue:
                guard let server = decodeHouseholdSettings(from: record) else { continue }
                if SyncMerge.resolveConflict(
                    local: settings?.householdSettingsRecord,
                    server: server,
                    merge: SyncMerge.mergeHouseholdSettings
                ).resendLocal {
                    resend.append(record.recordID)
                }
                settings?.applyRemoteHouseholdSettings(server)
            default:
                continue
            }
        }
        // Same order as fetched changes: plans last so their reconciliation sees the payments.
        store.applyRemoteTransactions(txs)
        store.applyRemoteBudgets(budgets)
        store.applyRemoteGoals(goals)
        store.applyRemotePlans(plans)
        return resend
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let engineID = ObjectIdentifier(syncEngine)
        let (isCurrent, zoneID, limit) = await MainActor.run {
            (self.isCurrentEngine(engineID), self.activeZoneID, self.batchSizer.limit)
        }
        guard isCurrent else { return nil }
        // Only what this send was asked for (`context.options.scope`, as Apple's sample does),
        // in the active zone, at most `limit` records (halved after `.limitExceeded`).
        let batchChanges = CloudSyncPolicy.batch(
            syncEngine.state.pendingRecordZoneChanges,
            scope: context.options.scope,
            activeZoneID: zoneID,
            limit: limit
        )
        guard !batchChanges.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batchChanges) { recordID in
            let record = await MainActor.run { self.encodeRecord(for: recordID) }
            if record == nil {
                // The local record no longer exists: drop the pending save (Apple's sample).
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
            return record
        }
    }

    // MARK: - Record Serialization

    private func encodeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let store else { return nil }
        let name = recordID.recordName
        if name.hasPrefix("tx_") {
            let id = String(name.dropFirst(3))
            guard let tx = store.transactions.first(where: { $0.id == id }) else { return nil }
            let record = systemFields.record(for: recordID, recordType: SyncRecordKind.transaction.rawValue)
            record["payload"] = (try? JSONEncoder().encode(tx)) as CKRecordValue?
            record["updatedAt"] = tx.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("bd_") {
            let suffix = String(name.dropFirst(3))
            guard let b = store.budgets.first(where: { SyncMerge.cloudRecordName(kind: .budget, id: $0.id) == name || $0.id == suffix }) else { return nil }
            let record = systemFields.record(for: recordID, recordType: SyncRecordKind.budget.rawValue)
            record["payload"] = (try? JSONEncoder().encode(b)) as CKRecordValue?
            record["updatedAt"] = b.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("gl_") {
            let id = String(name.dropFirst(3))
            guard let g = store.goals.first(where: { $0.id == id }) else { return nil }
            let record = systemFields.record(for: recordID, recordType: SyncRecordKind.goal.rawValue)
            record["payload"] = (try? JSONEncoder().encode(g)) as CKRecordValue?
            record["updatedAt"] = g.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("pl_") {
            let id = String(name.dropFirst(3))
            guard let p = store.plans.first(where: { $0.id == id }) else { return nil }
            let record = systemFields.record(for: recordID, recordType: SyncRecordKind.plan.rawValue)
            record["payload"] = (try? JSONEncoder().encode(p)) as CKRecordValue?
            record["updatedAt"] = p.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("hs_") {
            let id = String(name.dropFirst(3))
            guard let hs = settings?.householdSettingsRecord, hs.id == id else { return nil }
            let record = systemFields.record(for: recordID, recordType: SyncRecordKind.householdSettings.rawValue)
            record["payload"] = (try? JSONEncoder().encode(hs)) as CKRecordValue?
            record["updatedAt"] = hs.updatedAt as CKRecordValue
            return record
        }
        return nil
    }

    private func decodeHouseholdSettings(from record: CKRecord) -> HouseholdSettingsRecord? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(HouseholdSettingsRecord.self, from: data)
    }

    private func decodePlan(from record: CKRecord) -> InstallmentPlanRecord? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(InstallmentPlanRecord.self, from: data)
    }

    private func decodeTransaction(from record: CKRecord) -> TransactionRecord? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(TransactionRecord.self, from: data)
    }

    private func decodeBudget(from record: CKRecord) -> BudgetLimitRecord? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(BudgetLimitRecord.self, from: data)
    }

    private func decodeGoal(from record: CKRecord) -> SavingsGoalRecord? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SavingsGoalRecord.self, from: data)
    }

    // MARK: - Engine State Storage

    private var engineStateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TallyCloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("EngineState.json")
    }

    private var systemFieldsURL: URL {
        engineStateURL.deletingLastPathComponent().appendingPathComponent("SystemFields.plist")
    }

    private func loadEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: engineStateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveEngineState(_ state: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: engineStateURL, options: .atomic)
        }
    }
}
