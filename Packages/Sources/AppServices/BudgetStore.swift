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

    public private(set) var transactions: [TransactionRecord] = [] {
        didSet { invalidateAllCaches() }
    }
    public private(set) var budgets: [BudgetLimitRecord] = [] {
        didSet { invalidateAllCaches() }
    }
    public private(set) var goals: [SavingsGoalRecord] = [] {
        didSet { _activeGoals = nil }
    }
    /// Installment & loan plans (including tombstones). Plans never count as spending by
    /// themselves; their due payments are materialized into `transactions`.
    public private(set) var plans: [InstallmentPlanRecord] = [] {
        didSet { _activePlans = nil }
    }

    public var selectedPeriod: DatePeriod = .currentMonth() {
        didSet {
            if oldValue != selectedPeriod {
                invalidatePeriodCaches()
            }
        }
    }
    /// Convenience accessor for the active `YYYY-MM` month (synchronized with `selectedPeriod`).
    public var selectedMonth: String {
        get { selectedPeriod.primaryMonthKey }
        set { selectedPeriod = .month(newValue) }
    }
    /// `nil` means all household members.
    public var selectedMemberID: String? = nil {
        didSet {
            if oldValue != selectedMemberID {
                invalidateMemberCaches()
            }
        }
    }
    /// Active Activity tab filters (also driven by tapping tiles/categories on Overview).
    public var activityTypeFilter: ActivityTypeFilter = .all
    public var activityCategoryFilter: CategoryID? = nil

    @ObservationIgnored public var onLocalChanges: (([ChangedSyncRecord]) -> Void)?
    @ObservationIgnored private let context: ModelContext

    // Memoized analytics caches (O(1) reads during 120fps tab switches & scrolling)
    @ObservationIgnored private var _activeTransactions: [TransactionRecord]?
    @ObservationIgnored private var _activeBudgets: [BudgetLimitRecord]?
    @ObservationIgnored private var _activeGoals: [SavingsGoalRecord]?
    @ObservationIgnored private var _activePlans: [InstallmentPlanRecord]?
    @ObservationIgnored private var isMaterializingPlans = false
    @ObservationIgnored private var _pendingReviewTransactions: [TransactionRecord]?
    @ObservationIgnored private var _snapshot: MonthlySnapshot?
    @ObservationIgnored private var _monthlySnapshot: MonthlySnapshot?
    @ObservationIgnored private var _underBudgetMonthStreak: Int?
    @ObservationIgnored private var _statisticsSnapshot: StatisticsSnapshot?
    @ObservationIgnored private var _dailyCalendarTotals: [String: DailyCalendarTotal]?

    private func invalidateAllCaches() {
        _activeTransactions = nil
        _activeBudgets = nil
        _pendingReviewTransactions = nil
        _snapshot = nil
        _monthlySnapshot = nil
        _underBudgetMonthStreak = nil
        _statisticsSnapshot = nil
        _dailyCalendarTotals = nil
    }

    private func invalidatePeriodCaches() {
        _snapshot = nil
        _monthlySnapshot = nil
        _underBudgetMonthStreak = nil
        _statisticsSnapshot = nil
    }

    private func invalidateMemberCaches() {
        _snapshot = nil
        _monthlySnapshot = nil
        _underBudgetMonthStreak = nil
        _statisticsSnapshot = nil
        _dailyCalendarTotals = nil
    }

    public init(context: ModelContext? = nil) {
        self.context = context ?? AppStore.container.mainContext
        Self.current = self
        reload()
    }

    @ObservationIgnored private var lastReloadDayKey: String = ""

    public func reload() {
        let txDescriptor = FetchDescriptor<SDTransaction>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        let budgetDescriptor = FetchDescriptor<SDBudgetLimit>()
        let goalDescriptor = FetchDescriptor<SDSavingsGoal>(sortBy: [SortDescriptor(\.name)])
        let planDescriptor = FetchDescriptor<SDInstallmentPlan>(sortBy: [SortDescriptor(\.firstPaymentDayKey)])

        let newTransactions = (try? context.fetch(txDescriptor).map(\.record)) ?? []
        let newBudgets = (try? context.fetch(budgetDescriptor).map(\.record)) ?? []
        let newGoals = (try? context.fetch(goalDescriptor).map(\.record)) ?? []
        let newPlans = (try? context.fetch(planDescriptor).map(\.record)) ?? []

        // Only publish arrays that actually changed. Every assignment to an observed property
        // invalidates all analytics caches and re-renders every live tab (Charts included), so
        // no-op reloads (launch, scene activation, empty sync batches) used to cause a burst of
        // main-thread work right while the user started scrolling. A day rollover still forces a
        // refresh so "today" figures stay correct.
        let todayKey = DateKey.dayKey(from: Date())
        let dayChanged = todayKey != lastReloadDayKey
        lastReloadDayKey = todayKey

        if dayChanged || newTransactions != transactions { transactions = newTransactions }
        if dayChanged || newBudgets != budgets { budgets = newBudgets }
        if newGoals != goals { goals = newGoals }
        if newPlans != plans { plans = newPlans }

        // Launch, foreground (`TallyApp` reloads on scene activation) and day rollover: book any
        // installment/loan payments that fell due since the last run.
        if dayChanged && !isMaterializingPlans && !activePlans.isEmpty {
            materializeDuePlanPayments(todayKey: todayKey)
        }
    }

    public var activeTransactions: [TransactionRecord] {
        _ = transactions
        if let cached = _activeTransactions { return cached }
        let computed = transactions.filter { !$0.isDeleted }
        _activeTransactions = computed
        return computed
    }

    public var activeBudgets: [BudgetLimitRecord] {
        _ = budgets
        if let cached = _activeBudgets { return cached }
        let computed = budgets.filter { !$0.isDeleted }
        _activeBudgets = computed
        return computed
    }

    public var activeGoals: [SavingsGoalRecord] {
        _ = goals
        if let cached = _activeGoals { return cached }
        let computed = goals.filter { !$0.isDeleted }
        _activeGoals = computed
        return computed
    }

    /// Non-deleted plans (completed and settled ones included).
    public var activePlans: [InstallmentPlanRecord] {
        _ = plans
        if let cached = _activePlans { return cached }
        let computed = plans.filter { !$0.isDeleted }
        _activePlans = computed
        return computed
    }

    public var pendingReviewTransactions: [TransactionRecord] {
        _ = transactions
        if let cached = _pendingReviewTransactions { return cached }
        let computed = activeTransactions.filter(\.needsReview).sorted { $0.createdAt > $1.createdAt }
        _pendingReviewTransactions = computed
        return computed
    }

    public var snapshot: MonthlySnapshot {
        _ = transactions; _ = budgets; _ = selectedPeriod; _ = selectedMemberID
        if let cached = _snapshot { return cached }
        let computed = MonthlySnapshot.compute(
            period: selectedPeriod,
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
        _snapshot = computed
        return computed
    }

    /// Full-month snapshot for `selectedPeriod.primaryMonthKey` (used by monthly Budgets).
    public var monthlySnapshot: MonthlySnapshot {
        _ = transactions; _ = budgets; _ = selectedPeriod; _ = selectedMemberID
        if let cached = _monthlySnapshot { return cached }
        let computed = MonthlySnapshot.compute(
            period: .month(selectedPeriod.primaryMonthKey),
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
        _monthlySnapshot = computed
        return computed
    }

    /// Consecutive months right before the selected month that closed at or under budget.
    public var underBudgetMonthStreak: Int {
        _ = transactions; _ = budgets; _ = selectedPeriod; _ = selectedMemberID
        if let cached = _underBudgetMonthStreak { return cached }
        let computed = BudgetMomentum.underBudgetMonthStreak(
            before: selectedPeriod.primaryMonthKey,
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
        _underBudgetMonthStreak = computed
        return computed
    }

    /// Rich multi-month & breakdown analytics for the Statistics tab.
    public var statisticsSnapshot: StatisticsSnapshot {
        _ = transactions; _ = budgets; _ = selectedPeriod; _ = selectedMemberID
        if let cached = _statisticsSnapshot { return cached }
        let computed = StatisticsSnapshot.compute(
            period: selectedPeriod,
            allTransactions: transactions,
            allBudgets: budgets,
            memberFilter: selectedMemberID
        )
        _statisticsSnapshot = computed
        return computed
    }

    /// Per-day spending & income totals keyed by `YYYY-MM-DD` (respects active member filter).
    public var dailyCalendarTotals: [String: DailyCalendarTotal] {
        _ = transactions; _ = selectedMemberID
        if let cached = _dailyCalendarTotals { return cached }
        let computed = MonthlySnapshot.dailyTotals(
            allTransactions: transactions,
            memberFilter: selectedMemberID
        )
        _dailyCalendarTotals = computed
        return computed
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
        // Explicit write (editor, assistant, capture): for a plan payment it becomes the latest
        // user operation, which automatic schedule writes never override.
        let stamped = Self.keepingPlanIdentity(record, stored: transactions.first { $0.id == record.id })
            .recordingUserWrite(at: Date())
        upsertTransaction(stamped)
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: stamped.id)])
        }
    }

    /// Editors rebuild a transaction from its visible fields; a plan payment must keep its plan
    /// identity and merge state, or it would stop being a payment and be booked again.
    static func keepingPlanIdentity(_ record: TransactionRecord, stored: TransactionRecord?) -> TransactionRecord {
        guard let stored, stored.isPlanPayment, record.planID == nil else { return record }
        var kept = record
        kept.planID = stored.planID
        kept.planPaymentIndex = stored.planPaymentIndex
        kept.paymentState = stored.paymentState
        return kept
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
            // Same alert as a transaction the user deleted or converted into an installment
            // plan: keep the tombstone, never resurrect the full amount.
            if match.existing.isDeleted { return (match.existing, true) }
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
            upsertTransaction(dup.recordingUserWrite(at: now))
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

        // The same person on another device (iPhone + Mac) starts with a different random ID.
        // Every device adopts the same one of them, so they stop claiming records from each other.
        let canonicalID = MemberIdentity.canonicalID(
            currentID: settings.myMemberID,
            name: trimmedMyName,
            records: activeTransactions.map { ($0.memberID, $0.memberName) }
                + activePlans.map { ($0.memberID, $0.memberName) }
        )
        let previousMemberID = settings.myMemberID
        if canonicalID != previousMemberID {
            settings.myMemberID = canonicalID
            if selectedMemberID == previousMemberID { selectedMemberID = canonicalID }
        }

        let me = settings.currentMember
        let syntheticMeID = "member-\(trimmedMyName.lowercased())"
        let now = Date()
        var changed: [ChangedSyncRecord] = []
        var mergedAwayIDs: Set<String> = []

        // Plans first: saving a plan rewrites its booked payments to the plan's member.
        var mergedPlanCount = 0
        for var plan in activePlans where plan.memberID != me.id {
            guard plan.memberID == syntheticMeID
                    || plan.memberName.caseInsensitiveCompare(me.name) == .orderedSame
            else { continue }
            mergedAwayIDs.insert(plan.memberID)
            plan.memberID = me.id
            plan.memberName = me.name
            if savePlan(plan, notifyCloud: notifyCloud) { mergedPlanCount += 1 }
        }

        for var tx in activeTransactions {
            if tx.memberID == me.id {
                if tx.memberName != me.name {
                    tx.memberName = me.name
                    upsertTransaction(tx.recordingUserWrite(at: now))
                    changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
                }
            } else if tx.memberID == syntheticMeID
                        || tx.memberName.caseInsensitiveCompare(me.name) == .orderedSame {
                mergedAwayIDs.insert(tx.memberID)
                tx.memberID = me.id
                tx.memberName = me.name
                upsertTransaction(tx.recordingUserWrite(at: now))
                changed.append(ChangedSyncRecord(kind: .transaction, id: tx.id))
            }
        }

        if let selected = selectedMemberID, mergedAwayIDs.contains(selected) {
            selectedMemberID = me.id
        }
        guard !changed.isEmpty else { return mergedPlanCount }
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?(changed)
        }
        return changed.count + mergedPlanCount
    }

    public func deleteTransaction(id: String) {
        guard var existing = transactions.first(where: { $0.id == id }) else { return }
        existing.isDeleted = true
        existing.needsReview = false
        // An explicit deletion: for a plan payment it outranks automatic re-booking elsewhere.
        upsertTransaction(existing.recordingUserWrite(at: Date()))
        try? context.save()
        reload()
        onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: id)])
    }

    public func confirmReviewed(id: String) {
        guard var existing = transactions.first(where: { $0.id == id }) else { return }
        existing.needsReview = false
        upsertTransaction(existing.recordingUserWrite(at: Date()))
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
            upsertTransaction(tx.recordingUserWrite(at: now))
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

    // MARK: - Installment & Loan Plans

    /// Live (non-deleted) payment transactions of a plan, ordered by schedule index.
    public func payments(forPlanID planID: String) -> [TransactionRecord] {
        activeTransactions
            .filter { $0.planID == planID && $0.planPaymentIndex != nil }
            .sorted { ($0.planPaymentIndex ?? 0) < ($1.planPaymentIndex ?? 0) }
    }

    public func plan(id: String) -> InstallmentPlanRecord? {
        plans.first { $0.id == id }
    }

    /// Creates or edits a plan. Editing rewrites the plan's already-materialized, non-deleted
    /// payments to the new schedule (amount, day, name, category, member, note), withdraws
    /// payments that no longer fall inside it (shortened schedule, early settlement) or are not
    /// due yet as of `todayKey` (start moved later); then books any payments now due. Returns
    /// `false` without saving when a live plan's terms are invalid (`hasValidTerms`).
    @discardableResult
    public func savePlan(
        _ record: InstallmentPlanRecord,
        todayKey: String = DateKey.dayKey(from: Date()),
        notifyCloud: Bool = true
    ) -> Bool {
        guard record.isDeleted || record.hasValidTerms else { return false }
        var stamped = record
        stamped.updatedAt = Date()
        upsertPlan(stamped)
        var changed: [ChangedSyncRecord] = [ChangedSyncRecord(kind: .plan, id: stamped.id)]
        changed += applyLedger(PlanPaymentLedger.reconcile(
            plan: stamped,
            payments: planPayments(planID: stamped.id),
            todayKey: todayKey,
            bookMissing: true
        ))
        try? context.save()
        isMaterializingPlans = true
        reload()
        isMaterializingPlans = false
        if notifyCloud {
            onLocalChanges?(changed)
        }
        materializeDuePlanPayments(todayKey: todayKey, notifyCloud: notifyCloud)
        return true
    }

    /// Settles a plan early on `dayKey`: payments due after it are tombstoned / never booked and
    /// the plan reports as completed. Pass `nil` to undo a settlement.
    public func settlePlan(id: String, on dayKey: String?, todayKey: String = DateKey.dayKey(from: Date())) {
        guard var plan = plans.first(where: { $0.id == id && !$0.isDeleted }) else { return }
        plan.settledDayKey = dayKey
        savePlan(plan, todayKey: todayKey)
    }

    /// Deletes a plan. With `removePayments` its booked payments are deleted too (they stop
    /// counting as spending); otherwise they stay as ordinary expenses. The choice and the
    /// deletion day are stored on the plan so every device applies them to payments it booked
    /// or receives later.
    public func deletePlan(id: String, removePayments: Bool, todayKey: String = DateKey.dayKey(from: Date())) {
        guard var existing = plans.first(where: { $0.id == id }) else { return }
        let now = Date()
        existing.isDeleted = true
        existing.deletionRemovesPayments = removePayments
        existing.deletedDayKey = todayKey
        existing.updatedAt = now
        upsertPlan(existing)
        var changed: [ChangedSyncRecord] = [ChangedSyncRecord(kind: .plan, id: id)]
        changed += applyLedger(PlanPaymentLedger.reconcile(
            plan: existing,
            payments: planPayments(planID: existing.id),
            todayKey: todayKey,
            bookMissing: false
        ))
        try? context.save()
        reload()
        onLocalChanges?(changed)
    }

    /// Turns an existing expense (e.g. a bank alert for the full instalment price) into a plan:
    /// the plan takes its name, amount (as total), category and member, the original is
    /// tombstoned (and marked with `planID`, so a re-delivered alert for it is recognized as a
    /// duplicate), and payments due by today are booked.
    ///
    /// The plan id is derived from the transaction id (`convertedPlanID(sourceTransactionID:)`), so
    /// converting the same expense on two devices yields one plan. When that plan already exists
    /// and is live (e.g. another device's conversion arrived before the source's tombstone), no
    /// second plan is created: the source is tombstoned into the existing plan, which is
    /// returned. Only when it exists as deleted does a new conversion proceed, under the next
    /// deterministic id (`conv-<id>-2`, `conv-<id>-3`, ...). Returns `nil` if the transaction is
    /// missing, deleted, income, already a plan payment, or the inputs are invalid.
    @discardableResult
    public func convertTransactionToPlan(
        transactionID: String,
        months: Int,
        firstPaymentDayKey: String,
        kind: InstallmentKind = .installment,
        currency: CurrencyCode,
        todayKey: String = DateKey.dayKey(from: Date())
    ) -> InstallmentPlanRecord? {
        guard months >= 1,
              DateKey.date(fromDayKey: firstPaymentDayKey) != nil,
              var original = transactions.first(where: { $0.id == transactionID }),
              !original.isDeleted,
              original.type == .expense,
              !original.isPlanPayment,
              original.amountMinor > 0
        else { return nil }

        let now = Date()
        let target = InstallmentPlanRecord.conversionTarget(
            sourceTransactionID: original.id,
            existingPlans: Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        )
        original.isDeleted = true
        original.needsReview = false
        original.planPaymentIndex = nil

        if case .existing(let live) = target {
            // Another device already converted this expense: fold the source into that plan.
            original.planID = live.id
            upsertTransaction(original.recordingUserWrite(at: now))
            try? context.save()
            reload()
            onLocalChanges?([ChangedSyncRecord(kind: .transaction, id: original.id)])
            return live
        }
        guard case .new(let planID) = target else { return nil }
        let plan = InstallmentPlanRecord(
            id: planID,
            name: original.name,
            kind: kind,
            totalMinor: original.amountMinor,
            months: months,
            firstPaymentDayKey: firstPaymentDayKey,
            category: original.category,
            memberID: original.memberID,
            memberName: original.memberName,
            note: original.note,
            currency: currency,
            sourceTransactionID: original.id,
            createdAt: now,
            updatedAt: now
        )
        guard plan.hasValidTerms else { return nil }
        original.planID = plan.id

        upsertPlan(plan)
        upsertTransaction(original.recordingUserWrite(at: now))
        try? context.save()
        isMaterializingPlans = true
        reload()
        isMaterializingPlans = false
        onLocalChanges?([
            ChangedSyncRecord(kind: .plan, id: plan.id),
            ChangedSyncRecord(kind: .transaction, id: original.id),
        ])
        materializeDuePlanPayments(todayKey: todayKey)
        return plan
    }

    /// Aligns every active plan's payments with the plan (`PlanPaymentLedger.reconcile` with
    /// `bookMissing`): books each owed payment due by `todayKey` that does not exist yet or was
    /// withdrawn by the schedule, and rewrites payments derived from an older plan revision.
    /// Payment ids are deterministic (`"<planID>#<index>"`), so devices converge on the same
    /// records. A payment decided by a user operation (edited or deleted) is never touched. Idempotent; called on launch / foreground / day rollover
    /// (`reload()`), after saving or converting a plan, after remote plans arrive and after a
    /// backup import. Returns the number of payments booked.
    @discardableResult
    public func materializeDuePlanPayments(
        todayKey: String = DateKey.dayKey(from: Date()),
        notifyCloud: Bool = true
    ) -> Int {
        guard !isMaterializingPlans else { return 0 }
        let candidates = activePlans
        guard !candidates.isEmpty else { return 0 }
        isMaterializingPlans = true
        defer { isMaterializingPlans = false }

        let paymentsByPlan = Dictionary(grouping: transactions.filter(\.isPlanPayment), by: { $0.planID ?? "" })
        var changed: [ChangedSyncRecord] = []
        for plan in candidates {
            changed += applyLedger(PlanPaymentLedger.reconcile(
                plan: plan,
                payments: paymentsByPlan[plan.id] ?? [],
                todayKey: todayKey,
                bookMissing: true
            ))
        }
        guard !changed.isEmpty else { return 0 }
        try? context.save()
        reload()
        if notifyCloud {
            onLocalChanges?(changed)
        }
        return changed.count
    }

    /// Payment transactions of `planID` in any state (live, withdrawn, deleted).
    private func planPayments(planID: String) -> [TransactionRecord] {
        transactions.filter { $0.planID == planID && $0.isPlanPayment }
    }

    /// Upserts ledger revisions (without saving) and returns them as sync changes.
    private func applyLedger(_ revisions: [TransactionRecord]) -> [ChangedSyncRecord] {
        revisions.map { tx in
            upsertTransaction(tx)
            return ChangedSyncRecord(kind: .transaction, id: tx.id)
        }
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
            goals: goals,
            plans: plans
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
        for p in decoded.plans {
            upsertPlan(p)
            changed.append(ChangedSyncRecord(kind: .plan, id: p.id))
        }
        try? context.save()
        reload()
        if let latest = decoded.transactions.map(\.monthKey).max() {
            selectedMonth = latest
        }
        onLocalChanges?(changed)
        materializeDuePlanPayments()
    }

    public func resetAllLocalData() {
        let now = Date()
        var changed: [ChangedSyncRecord] = []
        for var tx in activeTransactions {
            tx.isDeleted = true; upsertTransaction(tx.recordingUserWrite(at: now))
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
        // Plans too, otherwise their payments would be re-materialized right away.
        for var p in activePlans {
            p.isDeleted = true; p.updatedAt = now; upsertPlan(p)
            changed.append(ChangedSyncRecord(kind: .plan, id: p.id))
        }
        try? context.save()
        reload()
        onLocalChanges?(changed)
    }

    // MARK: - Cloud Merge (does not re-trigger outbound sync)

    /// Merges transactions from iCloud (`SyncMerge`). Plan payments that arrive for a plan this
    /// device already knows are reconciled against the locally winning plan revision: one
    /// derived from an older revision is rewritten or withdrawn and the revision is announced to
    /// CloudSync. Payments for plans not seen yet are reconciled when the plan arrives
    /// (`applyRemotePlans`).
    public func applyRemoteTransactions(_ incoming: [TransactionRecord], todayKey: String = DateKey.dayKey(from: Date())) {
        guard !incoming.isEmpty else { return }
        let localByID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var didChange = false
        var touchedPayments: [String: [String: TransactionRecord]] = [:]
        for remote in incoming {
            let local = localByID[remote.id]
            let merged = SyncMerge.mergeTransaction(local: local, remote: remote)
            guard merged != local else { continue }
            upsertTransaction(merged)
            didChange = true
            if merged.isPlanPayment, let planID = merged.planID {
                touchedPayments[planID, default: [:]][merged.id] = merged
            }
        }
        guard didChange else { return }
        try? context.save()
        isMaterializingPlans = true
        reload()
        isMaterializingPlans = false

        // Reconcile arriving payments against the locally winning plan revision: a payment
        // derived from an older revision is rewritten or withdrawn (the result is a join, so a
        // payment from the same or a newer revision is left alone and nothing ping-pongs).
        var withdrawn: [ChangedSyncRecord] = []
        for planID in touchedPayments.keys.sorted() {
            guard let plan = plans.first(where: { $0.id == planID }) else { continue }
            withdrawn += applyLedger(PlanPaymentLedger.reconcile(
                plan: plan,
                payments: touchedPayments[planID].map { Array($0.values) } ?? [],
                todayKey: todayKey,
                bookMissing: false
            ))
        }
        if !withdrawn.isEmpty {
            try? context.save()
            reload()
            onLocalChanges?(withdrawn)
        }
        deduplicateExistingTransactions(notifyCloud: true)
    }

    public func applyRemoteBudgets(_ incoming: [BudgetLimitRecord]) {
        guard !incoming.isEmpty else { return }
        let localByID = Dictionary(budgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var didChange = false
        for remote in incoming {
            let local = localByID[remote.id]
            let merged = SyncMerge.mergeBudget(local: local, remote: remote)
            guard merged != local else { continue }
            upsertBudget(merged)
            didChange = true
        }
        guard didChange else { return }
        try? context.save()
        reload()
    }

    public func applyRemoteGoals(_ incoming: [SavingsGoalRecord]) {
        guard !incoming.isEmpty else { return }
        let localByID = Dictionary(goals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var didChange = false
        for remote in incoming {
            let local = localByID[remote.id]
            let merged = SyncMerge.mergeGoal(local: local, remote: remote)
            guard merged != local else { continue }
            upsertGoal(merged)
            didChange = true
        }
        guard didChange else { return }
        try? context.save()
        reload()
    }

    /// Merges plans from iCloud (LWW + tombstones), then books payments that are due. Plans
    /// with invalid terms (e.g. corrupt or hostile payloads) are ignored. Payments this device
    /// holds are aligned with the merged plan revision (`PlanPaymentLedger.reconcile`: rewritten,
    /// withdrawn when outside the owed schedule or not yet due here, removed when the plan was
    /// deleted with its payments; user-decided payments are left alone). Only those payment revisions and newly booked payments are announced to
    /// CloudSync; the merged plans themselves are not echoed back, so there is no loop.
    public func applyRemotePlans(_ incoming: [InstallmentPlanRecord], todayKey: String = DateKey.dayKey(from: Date())) {
        let valid = incoming.filter { $0.isDeleted || $0.hasValidTerms }
        guard !valid.isEmpty else { return }
        let localByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changedPlans: [InstallmentPlanRecord] = []
        for remote in valid {
            let local = localByID[remote.id]
            let merged = SyncMerge.mergePlan(local: local, remote: remote)
            guard merged != local else { continue }
            upsertPlan(merged)
            changedPlans.append(merged)
        }
        guard !changedPlans.isEmpty else { return }
        var changedPayments: [ChangedSyncRecord] = []
        for plan in changedPlans {
            changedPayments += applyLedger(PlanPaymentLedger.reconcile(
                plan: plan,
                payments: planPayments(planID: plan.id),
                todayKey: todayKey,
                bookMissing: false
            ))
        }
        try? context.save()
        isMaterializingPlans = true
        reload()
        isMaterializingPlans = false
        if !changedPayments.isEmpty {
            onLocalChanges?(changedPayments)
        }
        materializeDuePlanPayments(todayKey: todayKey, notifyCloud: true)
    }

    public var allChangedRecordsForFullUpload: [ChangedSyncRecord] {
        transactions.map { ChangedSyncRecord(kind: .transaction, id: $0.id) }
        + budgets.map { ChangedSyncRecord(kind: .budget, id: $0.id) }
        + goals.map { ChangedSyncRecord(kind: .goal, id: $0.id) }
        + plans.map { ChangedSyncRecord(kind: .plan, id: $0.id) }
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
                if match.existing.isDeleted { return match.existing }
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

    private func upsertPlan(_ record: InstallmentPlanRecord) {
        let targetID = record.id
        let predicate = #Predicate<SDInstallmentPlan> { $0.recordID == targetID }
        if let existing = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first {
            existing.apply(record)
        } else {
            context.insert(SDInstallmentPlan(from: record))
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
