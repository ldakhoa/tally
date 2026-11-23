import BudgetKit
import ClaudeKit
import Foundation
import Observation
import Persistence
import SwiftData
import SyncKit
import TallyCore

public struct ChangedSyncRecord: Hashable, Sendable {
    public let kind: SyncRecordKind
    public let id: String

    public init(kind: SyncRecordKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

public enum ActivityTypeFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all, expense, income, auto
    public var id: String { rawValue }
}

/// Central reactive store for transactions, monthly budgets, and savings goals.
/// Persists to SwiftData and notifies CloudSync whenever a local write occurs.
@MainActor
@Observable
public final class BudgetStore {
    public static weak var current: BudgetStore?

    public private(set) var transactions: [TransactionRecord] = []
    public private(set) var budgets: [BudgetLimitRecord] = []
    public private(set) var goals: [SavingsGoalRecord] = []

    public var selectedPeriod: DatePeriod = .currentMonth()
    /// Convenience accessor for the active `YYYY-MM` month (synchronized with `selectedPeriod`).
    public var selectedMonth: String {
        get { selectedPeriod.primaryMonthKey }
        set { selectedPeriod = .month(newValue) }
    }
    /// `nil` means all household members.
    public var selectedMemberID: String? = nil
    /// Active Activity tab filters (also driven by tapping tiles/categories on Overview).
    public var activityTypeFilter: ActivityTypeFilter = .all
    public var activityCategoryFilter: CategoryID? = nil

    @ObservationIgnored public var onLocalChanges: (([ChangedSyncRecord]) -> Void)?
    @ObservationIgnored private let context: ModelContext

    public init(context: ModelContext? = nil) {
        self.context = context ?? AppStore.container.mainContext
        Self.current = self
        reload()
    }

    public func reload() {
        let txDescriptor = FetchDescriptor<SDTransaction>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        let budgetDescriptor = FetchDescriptor<SDBudgetLimit>()
        let goalDescriptor = FetchDescriptor<SDSavingsGoal>(sortBy: [SortDescriptor(\.name)])

        transactions = (try? context.fetch(txDescriptor).map(\.record)) ?? []
        budgets = (try? context.fetch(budgetDescriptor).map(\.record)) ?? []
        goals = (try? context.fetch(goalDescriptor).map(\.record)) ?? []
    }

    public var activeTransactions: [TransactionRecord] {
        transactions.filter { !$0.isDeleted }
    }

    public var activeBudgets: [BudgetLimitRecord] {
        budgets.filter { !$0.isDeleted }
    }

    public var activeGoals: [SavingsGoalRecord] {
        goals.filter { !$0.isDeleted }
    }

    public var pendingReviewTransactions: [TransactionRecord] {
        activeTransactions.filter(\.needsReview).sorted { $0.createdAt > $1.createdAt }
    }

    public var snapshot: MonthlySnapshot {
        MonthlySnapshot.compute(
            period: selectedPeriod,
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
    }

    /// Full-month snapshot for `selectedPeriod.primaryMonthKey` (used by monthly Budgets).
    public var monthlySnapshot: MonthlySnapshot {
        MonthlySnapshot.compute(
            period: .month(selectedPeriod.primaryMonthKey),
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
    }

    /// Rich multi-month & breakdown analytics for the Statistics tab.
    public var statisticsSnapshot: StatisticsSnapshot {
        StatisticsSnapshot.compute(
            period: selectedPeriod,
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
    }

    /// Per-day spending & income totals keyed by `YYYY-MM-DD` (respects active member filter).
    public var dailyCalendarTotals: [String: DailyCalendarTotal] {
        MonthlySnapshot.dailyTotals(
            allTransactions: transactions,
            memberFilter: selectedMemberID
        )
    }

    /// Set of `YYYY-MM-DD` keys that have at least one active transaction.
    public var transactionDayKeys: Set<String> {
        Set(dailyCalendarTotals.keys)
    }

    /// Distinct household members seen in transactions plus the current device's profile.
    public func knownMembers(settings: AppSettings) -> [HouseholdMember] {
        var map: [String: HouseholdMember] = [:]
        let me = settings.currentMember
        map[me.id] = me
        for tx in activeTransactions {
            if map[tx.memberID] == nil {
                let fallback = tx.memberName.isEmpty
                    ? L10n.text(settings.language, en: "Partner", vi: "Người thân", zh: "伴侣")
                    : tx.memberName
                map[tx.memberID] = HouseholdMember(id: tx.memberID, name: fallback)
            }
        }
        return map.values.sorted { lhs, rhs in
            if lhs.id == me.id { return true }
            if rhs.id == me.id { return false }
            return lhs.name < rhs.name
        }
    }

    // MARK: - Period & Month navigation

    public func shiftPeriod(by delta: Int) {
        selectedPeriod = selectedPeriod.shifted(by: delta)
    }

    public func shiftMonth(by delta: Int) {
        selectedPeriod = .month(DateKey.shiftMonth(selectedMonth, by: delta))
    }

    public func ensureVisible(dayKey: String) {
        guard !selectedPeriod.contains(dayKey: dayKey) else { return }
        if case .day = selectedPeriod {
            selectedPeriod = .day(dayKey)
        } else {
            selectedPeriod = .month(DateKey.monthKey(fromDayKey: dayKey))
        }
    }

    // MARK: - Transactions CRUD

    public func saveTransaction(_ record: TransactionRecord, notifyCloud: Bool = true) {
        var stamped = record
        stamped.updatedAt = Date()
        upsertTransaction(stamped)
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: stamped.id)])
        }
    }

    /// Saves an auto-captured transaction (Apple Pay, Bank Email, SMS, Paste) only if no
    /// cross-source duplicate already exists; otherwise merges useful metadata into the existing
    /// transaction without double-counting.
    @discardableResult
    public func saveAutoCapturedTransaction(
        _ record: TransactionRecord,
        notifyCloud: Bool = true
    ) -> (saved: TransactionRecord, wasDuplicate: Bool) {
        if let match = TransactionDeduplicator.findDuplicate(for: record, in: transactions) {
            let merged = TransactionDeduplicator.mergeMetadata(existing: match.existing, duplicate: record)
            if merged != match.existing {
                saveTransaction(merged, notifyCloud: notifyCloud)
            }
            return (merged, true)
        }
        saveTransaction(record, notifyCloud: notifyCloud)
        return (record, false)
    }

    /// Sweeps active transactions to deterministically remove cross-source auto-captured duplicates
    /// (e.g., Apple Pay + Bank Email with different member labels or synced concurrently from two devices).
    @discardableResult
    public func deduplicateExistingTransactions(notifyCloud: Bool = true) -> Int {
        let sweep = TransactionDeduplicator.findExistingDuplicates(in: transactions)
        guard sweep.hasChanges else { return 0 }

        var changed: [ChangedSyncRecord] = []
        let now = Date()

        for winner in sweep.updatedWinners {
            upsertTransaction(winner)
            changed.append(ChangedSyncRecord(kind: .transaction, id: winner.id))
        }

        for dupID in sweep.duplicateIDsToDelete {
            guard var dup = transactions.first(where: { $0.id == dupID && !$0.isDeleted }) else { continue }
            dup.isDeleted = true
            dup.needsReview = false
            dup.updatedAt = now
            upsertTransaction(dup)
            changed.append(ChangedSyncRecord(kind: .transaction, id: dupID))
        }

        guard !changed.isEmpty else { return 0 }
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?(changed)
        }
        return sweep.duplicateIDsToDelete.count
    }

    private static let genericPartnerLabels: Set<String> = [
        "wife", "partner", "husband", "spouse", "vợ", "vo", "chồng", "chong", "người thân"
    ]

    /// Merges split member identities for the current user (e.g., local `"Me"` UUID + synthetic
    /// `"member-khoa"` created by Email Inbox Sync before `myDisplayName` was set) into one
    /// unified `(currentMember.id, currentMember.name)` profile and syncs updates to iCloud.
    @discardableResult
    public func reconcileMemberIdentities(settings: AppSettings, notifyCloud: Bool = true) -> Int {
        let partnerTrimmed = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)

        // If this is the household owner's device and myDisplayName was never set, adopt the sole
        // non-partner synthetic email member (e.g. "member-khoa" -> "Khoa") as the owner's name.
        if settings.myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !settings.cloudZoneRole.isSharedParticipant {
            var syntheticMembers: [String: String] = [:]
            for tx in activeTransactions {
                guard tx.memberID.hasPrefix("member-"),
                      tx.memberID != HouseholdMember.defaultMeID,
                      tx.memberID != HouseholdMember.defaultPartnerID
                else { continue }
                let name = tx.memberName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if !partnerTrimmed.isEmpty && name.caseInsensitiveCompare(partnerTrimmed) == .orderedSame {
                    continue
                }
                if Self.genericPartnerLabels.contains(name.lowercased()) {
                    continue
                }
                syntheticMembers[tx.memberID] = name
            }
            if syntheticMembers.count == 1, let onlyName = syntheticMembers.values.first {
                settings.myDisplayName = onlyName
            }
        }

        let trimmedMyName = settings.myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMyName.isEmpty else { return 0 }

        let me = settings.currentMember
        let syntheticMeID = "member-\(trimmedMyName.lowercased())"
        let now = Date()
        var changed: [ChangedSyncRecord] = []
        var mergedAwayIDs: Set<String> = []

        for var tx in activeTransactions {
            if tx.memberID == me.id {
                if tx.memberName != me.name {
                    tx.memberName = me.name
                    tx.updatedAt = now
                    upsertTransaction(tx)
                    changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
                }
            } else if tx.memberID == syntheticMeID
                        || tx.memberName.caseInsensitiveCompare(me.name) == .orderedSame {
                mergedAwayIDs.insert(tx.memberID)
                tx.memberID = me.id
                tx.memberName = me.name
                tx.updatedAt = now
                upsertTransaction(tx)
                changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
            }
        }

        guard !changed.isEmpty else { return 0 }
        if let selected = selectedMemberID, mergedAwayIDs.contains(selected) {
            selectedMemberID = me.id
        }
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?(changed)
        }
        return changed.count
    }

    public func deleteTransaction(id: String) {
        guard var existing = transactions.first(where: { $0.id == id }) else { return }
        existing.isDeleted = true
        existing.needsReview = false
        existing.updatedAt = Date()
        upsertTransaction(existing)
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: id)])
    }

    public func confirmReviewed(id: String) {
        guard var existing = transactions.first(where: { $0.id == id }) else { return }
        existing.needsReview = false
        existing.updatedAt = Date()
        upsertTransaction(existing)
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: id)])
    }

    public func confirmAllReviewed() {
        let pending = pendingReviewTransactions
        guard !pending.isEmpty else { return }
        var changed: [ChangedSyncRecord] = []
        let now = Date()
        for var tx in pending {
            tx.needsReview = false
            tx.updatedAt = now
            upsertTransaction(tx)
            changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
        }
        try? context.save()
        reload()
        onLocalChanges?(changed)
    }

    // MARK: - Budgets CRUD

    public func saveBudget(_ record: BudgetLimitRecord, notifyCloud: Bool = true) {
        var stamped = record
        stamped.updatedAt = Date()
        upsertBudget(stamped)
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?([ChangedSyncRecord(kind: .budget, id: stamped.id)])
        }
    }

    public func deleteBudget(id: String) {
        guard var existing = budgets.first(where: { $0.id == id }) else { return }
        existing.isDeleted = true
        existing.updatedAt = Date()
        upsertBudget(existing)
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .budget, id: id)])
    }

    public func copyBudgetsFromPreviousMonth() -> Int {
        let prevMonth = DateKey.shiftMonth(selectedMonth, by: -1)
        let prevBudgets = activeBudgets.filter { $0.monthKey == prevMonth }
        let existingCategories = Set(activeBudgets.filter { $0.monthKey == selectedMonth }.map(\.category))
        var changed: [ChangedSyncRecord] = []
        let now = Date()
        for prev in prevBudgets where !existingCategories.contains(prev.category) {
            let copied = BudgetLimitRecord(monthKey: selectedMonth, category: prev.category, limitMinor: prev.limitMinor, updatedAt: now)
            upsertBudget(copied)
            changed.append(ChangedSyncRecord(kind: .budget, id: copied.id))
        }
        guard !changed.isEmpty else { return 0 }
        try? context.save()
        reload()
        onLocalChanges?(changed)
        return changed.count
    }

    // MARK: - Goals CRUD

    public func saveGoal(_ record: SavingsGoalRecord, notifyCloud: Bool = true) {
        var stamped = record
        stamped.updatedAt = Date()
        upsertGoal(stamped)
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?([ChangedSyncRecord(kind: .goal, id: stamped.id)])
        }
    }

    public func addContribution(goalID: String, amountMinor: Int64) {
        guard amountMinor > 0, var goal = goals.first(where: { $0.id == goalID && !$0.isDeleted }) else { return }
        goal.savedMinor += amountMinor
        goal.updatedAt = Date()
        upsertGoal(goal)
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .goal, id: goalID)])
    }

    public func deleteGoal(id: String) {
        guard var existing = goals.first(where: { $0.id == id }) else { return }
        existing.isDeleted = true
        existing.updatedAt = Date()
        upsertGoal(existing)
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .goal, id: id)])
    }

    // MARK: - Sample Data & Backup

    public func loadSampleData(settings: AppSettings) {
        let partner = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sample = SampleBudgetData.make(
            monthKey: selectedMonth,
            currency: settings.currency,
            language: settings.language,
            myName: settings.currentMember.name,
            partnerName: partner.isEmpty ? L10n.text(settings.language, en: "Wife", vi: "Vợ", zh: "妻子") : partner
        )
        var changed: [ChangedSyncRecord] = []
        for tx in sample.transactions {
            upsertTransaction(tx)
            changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
        }
        for b in sample.budgets {
            upsertBudget(b)
            changed.append(ChangedSyncRecord(kind: .budget, id: b.id))
        }
        for g in sample.goals {
            upsertGoal(g)
            changed.append(ChangedSyncRecord(kind: .goal, id: g.id))
        }
        try? context.save()
        reload()
        onLocalChanges?(changed)
    }

    public func exportBackup(currency: CurrencyCode) throws -> Data {
        try WebBackupCodec.encode(
            currency: currency,
            transactions: transactions,
            budgets: budgets,
            goals: goals
        )
    }

    public func importBackup(_ data: Data, settings: AppSettings) throws {
        let decoded = try WebBackupCodec.decode(data)
        settings.currency = decoded.currency
        var changed: [ChangedSyncRecord] = []
        for tx in decoded.transactions {
            upsertTransaction(tx)
            changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
        }
        for b in decoded.budgets {
            upsertBudget(b)
            changed.append(ChangedSyncRecord(kind: .budget, id: b.id))
        }
        for g in decoded.goals {
            upsertGoal(g)
            changed.append(ChangedSyncRecord(kind: .goal, id: g.id))
        }
        try? context.save()
        reload()
        if let latest = decoded.transactions.map(\.monthKey).max() {
            selectedMonth = latest
        }
        onLocalChanges?(changed)
    }

    public func resetAllLocalData() {
        let now = Date()
        var changed: [ChangedSyncRecord] = []
        for var tx in activeTransactions {
            tx.isDeleted = true; tx.updatedAt = now; upsertTransaction(tx)
            changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
        }
        for var b in activeBudgets {
            b.isDeleted = true; b.updatedAt = now; upsertBudget(b)
            changed.append(ChangedSyncRecord(kind: .budget, id: b.id))
        }
        for var g in activeGoals {
            g.isDeleted = true; g.updatedAt = now; upsertGoal(g)
            changed.append(ChangedSyncRecord(kind: .goal, id: g.id))
        }
        try? context.save()
        reload()
        onLocalChanges?(changed)
    }

    // MARK: - Cloud Merge (does not re-trigger outbound sync)

    public func applyRemoteTransactions(_ incoming: [TransactionRecord]) {
        guard !incoming.isEmpty else { return }
        for remote in incoming {
            let local = transactions.first(where: { $0.id == remote.id })
            let merged = SyncMerge.mergeTransaction(local: local, remote: remote)
            upsertTransaction(merged)
        }
        try? context.save()
        reload()
        deduplicateExistingTransactions(notifyCloud: true)
    }

    public func applyRemoteBudgets(_ incoming: [BudgetLimitRecord]) {
        guard !incoming.isEmpty else { return }
        for remote in incoming {
            let local = budgets.first(where: { $0.id == remote.id })
            let merged = SyncMerge.mergeBudget(local: local, remote: remote)
            upsertBudget(merged)
        }
        try? context.save()
        reload()
    }

    public func applyRemoteGoals(_ incoming: [SavingsGoalRecord]) {
        guard !incoming.isEmpty else { return }
        for remote in incoming {
            let local = goals.first(where: { $0.id == remote.id })
            let merged = SyncMerge.mergeGoal(local: local, remote: remote)
            upsertGoal(merged)
        }
        try? context.save()
        reload()
    }

    public var allChangedRecordsForFullUpload: [ChangedSyncRecord] {
        transactions.map { ChangedSyncRecord(kind: .transaction, id: $0.id) }
        + budgets.map { ChangedSyncRecord(kind: .budget, id: $0.id) }
        + goals.map { ChangedSyncRecord(kind: .goal, id: $0.id) }
    }

    // MARK: - App Intents / Apple Shortcuts Ingestion

    /// Saves a transaction created by an Apple Shortcut (Apple Pay, Bank Email, SMS, Siri),
    /// updating the live UI store if running and queuing iCloud sync.
    @discardableResult
    public static func ingestFromShortcut(
        name: String,
        amountMajor: Double,
        type: TransactionType,
        category: CategoryID,
        dayKey: String = DateKey.dayKey(from: Date()),
        note: String = "",
        source: TransactionSource,
        rawSourceText: String? = nil
    ) -> TransactionRecord {
        let settings = AppSettings()
        let member = settings.currentMember
        let amountMinor = settings.currency.toStorageMinor(abs(amountMajor))
        let record = TransactionRecord(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transaction" : name,
            amountMinor: max(1, amountMinor),
            type: type,
            category: category,
            dayKey: dayKey,
            createdAt: Date(),
            note: note,
            source: source,
            rawSourceText: rawSourceText,
            memberID: member.id,
            memberName: member.name,
            needsReview: settings.flagAutoCapturedForReview,
            updatedAt: Date(),
            isDeleted: false
        )

        if let live = BudgetStore.current {
            return live.saveAutoCapturedTransaction(record, notifyCloud: true).saved
        } else {
            let ctx = AppStore.container.mainContext
            let existing = (try? ctx.fetch(FetchDescriptor<SDTransaction>()).map(\.record)) ?? []
            if let match = TransactionDeduplicator.findDuplicate(for: record, in: existing) {
                let merged = TransactionDeduplicator.mergeMetadata(existing: match.existing, duplicate: record)
                if merged != match.existing {
                    let targetID = merged.id
                    let predicate = #Predicate<SDTransaction> { $0.recordID == targetID }
                    if let row = (try? ctx.fetch(FetchDescriptor(predicate: predicate)))?.first {
                        row.apply(merged)
                        try? ctx.save()
                    }
                }
                return merged
            }
            ctx.insert(SDTransaction(from: record))
            try? ctx.save()
        }
        return record
    }

    // MARK: - SwiftData Upserts

    private func upsertTransaction(_ record: TransactionRecord) {
        let targetID = record.id
        let predicate = #Predicate<SDTransaction> { $0.recordID == targetID }
        if let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first {
            existing.apply(record)
        } else {
            context.insert(SDTransaction(from: record))
        }
    }

    private func upsertBudget(_ record: BudgetLimitRecord) {
        let targetID = record.id
        let predicate = #Predicate<SDBudgetLimit> { $0.recordID == targetID }
        if let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first {
            existing.apply(record)
        } else {
            context.insert(SDBudgetLimit(from: record))
        }
    }

    private func upsertGoal(_ record: SavingsGoalRecord) {
        let targetID = record.id
        let predicate = #Predicate<SDSavingsGoal> { $0.recordID == targetID }
        if let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first {
            existing.apply(record)
        } else {
            context.insert(SDSavingsGoal(from: record))
        }
    }
}
