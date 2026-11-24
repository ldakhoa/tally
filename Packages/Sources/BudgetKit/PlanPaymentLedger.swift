import Foundation
import TallyCore

/// Pure rules that keep a plan's payment transactions consistent with the plan. `BudgetStore`
/// persists whatever these return; nothing here touches storage or sync.
///
/// Every payment (deterministic id `"<planID>#<index>"`) carries a `PlanPaymentState`: the latest
/// explicit user operation and the automatic schedule state, each merged by its own order. The
/// ledger only ever proposes a schedule write derived from the local plan revision (or, for a
/// plan deleted together with its payments, a user deletion stamped with the deletion revision)
/// and joins it into the payment's state, so its output is always a join and two devices can
/// never undo each other.
///
/// Booking-day rule: a payment of plan revision R is booked once it is due on the local day of
/// any device that holds R (`dayKey <= todayKey` there). Between two writes of the same revision
/// "booked" beats "withdrawn", so a device whose local day is earlier never withdraws a payment
/// another device already booked for that revision; it only withdraws payments it re-derives from
/// a newer revision (start moved later, shortened term, settlement, plan deletion).
public enum PlanPaymentLedger {
    /// Schedule write plan revision `plan` gives payment `index` as of `todayKey`, or `nil` when
    /// the index has no payment day.
    ///
    /// - Live plan: booked when `index` is owed (inside the term, not cut off by settlement), not
    ///   one of the plan's already-paid leading payments and due by `todayKey`; withdrawn otherwise.
    /// - Deleted plan: decided by the deleted revision's schedule and the index alone, never by
    ///   the payment's own (possibly stale) date: booked when payments are kept, `index` is owed
    ///   and its scheduled day is on or before the deletion day; withdrawn otherwise. Already-paid
    ///   leading payments are never booked.
    public static func scheduleWrite(
        plan: InstallmentPlanRecord,
        index: Int,
        todayKey: String,
        owed: [Int: InstallmentPayment]? = nil,
        full: [Int: InstallmentPayment]? = nil
    ) -> PlanPaymentScheduleWrite? {
        guard let dayKeyForIndex = plan.paymentDayKey(index: index) else { return nil }
        let owed = owed ?? byIndex(plan.schedule)
        let full = full ?? byIndex(plan.fullSchedule)
        let entry = owed[index] ?? full[index]
        let dayKey = entry?.dayKey ?? dayKeyForIndex
        let booked: Bool
        if plan.isPaidOutsidePlan(index: index) {
            booked = false
        } else if plan.isDeleted {
            booked = plan.deletionRemovesPayments != true
                && owed[index] != nil
                && dayKey <= plan.deletionCutoffDayKey
        } else {
            booked = owed[index] != nil && dayKey <= todayKey
        }
        return PlanPaymentScheduleWrite(
            planRevision: plan.updatedAt,
            content: plan.scheduledContent(dayKey: dayKey, amountMinor: entry?.amountMinor ?? 0, isDeleted: !booked)
        )
    }

    /// Revisions that align `plan`'s payments with plan revision `plan`.
    ///
    /// For each existing payment (and, with `bookMissing`, each owed payment of a live plan due by
    /// `todayKey` that has no record yet) the schedule write of this revision is joined into the
    /// payment's state. A plan deleted together with its payments also joins a user deletion
    /// stamped with the deletion revision. A revision is returned only when the join changes
    /// what the payment holds: for a payment decided by a user operation only a changed user
    /// operation counts, so automatic writes never touch it.
    ///
    /// Pass only the payments that just arrived from another device with `bookMissing: false` to
    /// reconcile them against the locally winning plan: a payment derived from an older plan
    /// revision is rewritten or withdrawn, one derived from the same or a newer revision is left
    /// alone.
    public static func reconcile(
        plan: InstallmentPlanRecord,
        payments: [TransactionRecord],
        todayKey: String,
        bookMissing: Bool
    ) -> [TransactionRecord] {
        let owed = byIndex(plan.schedule)
        let full = byIndex(plan.fullSchedule)
        var existingByIndex: [Int: TransactionRecord] = [:]
        for tx in payments where tx.planID == plan.id && tx.isPlanPayment {
            guard let index = tx.planPaymentIndex
                ?? InstallmentPlanRecord.paymentIndex(transactionID: tx.id, planID: plan.id)
            else { continue }
            existingByIndex[index] = tx
        }
        var indexes = Set(existingByIndex.keys)
        if bookMissing, !plan.isDeleted {
            for payment in owed.values where payment.dayKey <= todayKey && !plan.isPaidOutsidePlan(index: payment.index) {
                indexes.insert(payment.index)
            }
        }

        var revisions: [TransactionRecord] = []
        for index in indexes.sorted() {
            let existing = existingByIndex[index]
            let before = existing?.effectivePaymentState ?? PlanPaymentState()
            var state = before
            if existing != nil, plan.isDeleted, plan.deletionRemovesPayments == true,
               let dayKey = (owed[index] ?? full[index])?.dayKey ?? plan.paymentDayKey(index: index) {
                let content = plan.scheduledContent(
                    dayKey: dayKey,
                    amountMinor: (owed[index] ?? full[index])?.amountMinor ?? 0,
                    isDeleted: true
                )
                state = state.joined(with: PlanPaymentState(user: PlanPaymentUserWrite(at: plan.updatedAt, content: content)))
            }
            if let desired = scheduleWrite(plan: plan, index: index, todayKey: todayKey, owed: owed, full: full) {
                state = state.joined(with: PlanPaymentState(schedule: desired))
            }
            let changed: Bool
            if existing == nil {
                changed = state.visibleContent?.isDeleted == false
            } else if state.user != nil {
                changed = state.user != before.user
            } else {
                changed = state != before
            }
            guard changed else { continue }
            let base = existing ?? InstallmentPlanRecord.paymentRecord(planID: plan.id, index: index)
            var revised = base.applying(state)
            revised.planID = plan.id
            revised.planPaymentIndex = index
            revisions.append(revised)
        }
        return revisions
    }

    /// A plan payment restored from a backup: booked by `plan`'s schedule when it matches it,
    /// otherwise an explicit user write (the user edited it, or its plan is gone).
    public static func importedPayment(_ tx: TransactionRecord, plan: InstallmentPlanRecord?) -> TransactionRecord {
        guard tx.isPlanPayment else { return tx }
        if let plan, !plan.isDeleted,
           let index = tx.planPaymentIndex,
           !plan.isPaidOutsidePlan(index: index),
           let entry = byIndex(plan.schedule)[index] {
            let scheduled = plan.scheduledContent(dayKey: entry.dayKey, amountMinor: entry.amountMinor, isDeleted: false)
            // Backups do not carry every field (source, createdAt, review flag); compare what
            // the schedule controls.
            let matches = !tx.isDeleted
                && tx.amountMinor == scheduled.amountMinor && tx.dayKey == scheduled.dayKey
                && tx.name == scheduled.name && tx.category == scheduled.category && tx.type == scheduled.type
                && tx.memberID == scheduled.memberID && tx.memberName == scheduled.memberName
                && tx.note == scheduled.note
            if matches {
                return tx.applying(PlanPaymentState(schedule: PlanPaymentScheduleWrite(planRevision: plan.updatedAt, content: scheduled)))
            }
        }
        return tx.recordingUserWrite(at: tx.updatedAt)
    }

    private static func byIndex(_ payments: [InstallmentPayment]) -> [Int: InstallmentPayment] {
        Dictionary(payments.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
