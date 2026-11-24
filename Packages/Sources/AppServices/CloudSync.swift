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
                    enqueueLocalChanges(store.allChangedRecordsForFullUpload, scheduleSend: false)
                }
                try await engine.sendChanges()
                lastSynced = Date()
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
            enqueueLocalChanges(store.allChangedRecordsForFullUpload, scheduleSend: false)
        }
        await refreshShareSummary()
        sendSoon()
    }

    private func stopEngine(clearState: Bool) async {
        sendKick?.cancel()
        sendKick = nil
        let old = engine
        engine = nil
        await old?.cancelOperations()
        if clearState {
            try? FileManager.default.removeItem(at: engineStateURL)
        }
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
        await MainActor.run {
            self.processEvent(event)
        }
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
            for mod in changes.modifications {
                let record = mod.record
                switch record.recordType {
                case SyncRecordKind.transaction.rawValue:
                    if let tx = decodeTransaction(from: record) { txs.append(tx) }
                case SyncRecordKind.budget.rawValue:
                    if let b = decodeBudget(from: record) { budgets.append(b) }
                case SyncRecordKind.goal.rawValue:
                    if let g = decodeGoal(from: record) { goals.append(g) }
                default:
                    break
                }
            }
            store?.applyRemoteTransactions(txs)
            store?.applyRemoteBudgets(budgets)
            store?.applyRemoteGoals(goals)
            lastSynced = Date()
        case .sentRecordZoneChanges(let sent):
            if !sent.savedRecords.isEmpty {
                lastSynced = Date()
                problem = nil
            }
            for failed in sent.failedRecordSaves {
                if failed.error.code == .serverRecordChanged, let serverRecord = failed.error.serverRecord {
                    // Merge server version locally, then re-send if needed.
                    if let tx = decodeTransaction(from: serverRecord) {
                        store?.applyRemoteTransactions([tx])
                    } else if let b = decodeBudget(from: serverRecord) {
                        store?.applyRemoteBudgets([b])
                    } else if let g = decodeGoal(from: serverRecord) {
                        store?.applyRemoteGoals([g])
                    }
                    sendSoon()
                }
            }
        case .willFetchChanges, .willSendChanges:
            isSyncing = true
        case .didFetchChanges, .didSendChanges:
            isSyncing = false
        default:
            break
        }
    }

    nonisolated public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges
        guard !pending.isEmpty else { return nil }
        let batchChanges = Array(pending.prefix(100))
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: batchChanges) { recordID in
            await MainActor.run {
                self.encodeRecord(for: recordID)
            }
        }
    }

    // MARK: - Record Serialization

    private func encodeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let store else { return nil }
        let name = recordID.recordName
        if name.hasPrefix("tx_") {
            let id = String(name.dropFirst(3))
            guard let tx = store.transactions.first(where: { $0.id == id }) else { return nil }
            let record = CKRecord(recordType: SyncRecordKind.transaction.rawValue, recordID: recordID)
            record["payload"] = (try? JSONEncoder().encode(tx)) as CKRecordValue?
            record["updatedAt"] = tx.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("bd_") {
            let suffix = String(name.dropFirst(3))
            guard let b = store.budgets.first(where: { SyncMerge.cloudRecordName(kind: .budget, id: $0.id) == name || $0.id == suffix }) else { return nil }
            let record = CKRecord(recordType: SyncRecordKind.budget.rawValue, recordID: recordID)
            record["payload"] = (try? JSONEncoder().encode(b)) as CKRecordValue?
            record["updatedAt"] = b.updatedAt as CKRecordValue
            return record
        }
        if name.hasPrefix("gl_") {
            let id = String(name.dropFirst(3))
            guard let g = store.goals.first(where: { $0.id == id }) else { return nil }
            let record = CKRecord(recordType: SyncRecordKind.goal.rawValue, recordID: recordID)
            record["payload"] = (try? JSONEncoder().encode(g)) as CKRecordValue?
            record["updatedAt"] = g.updatedAt as CKRecordValue
            return record
        }
        return nil
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
