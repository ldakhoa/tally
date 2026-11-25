import Foundation
import TallyCore

public struct CurrencyConversionResult: Equatable, Sendable {
    public let transactions: [TransactionRecord]
    public let budgets: [BudgetLimitRecord]
    public let goals: [SavingsGoalRecord]
    public let plans: [InstallmentPlanRecord]
    public let rate: Double
    public let changedTransactionIDs: [String]
    public let changedBudgetIDs: [String]
    public let changedGoalIDs: [String]
    public let changedPlanIDs: [String]

    public init(
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord],
        plans: [InstallmentPlanRecord],
        rate: Double,
        changedTransactionIDs: [String],
        changedBudgetIDs: [String],
        changedGoalIDs: [String],
        changedPlanIDs: [String]
    ) {
        self.transactions = transactions
        self.budgets = budgets
        self.goals = goals
        self.plans = plans
        self.rate = rate
        self.changedTransactionIDs = changedTransactionIDs
        self.changedBudgetIDs = changedBudgetIDs
        self.changedGoalIDs = changedGoalIDs
        self.changedPlanIDs = changedPlanIDs
    }
}

/// Pure, deterministic converter that migrates an entire household ledger from one canonical
/// currency to another while preserving original foreign-currency transaction details and
/// keeping installment schedules & CRDT payment states valid.
public enum CurrencyLedgerConverter {
    public static func convert(
        from oldCurrency: CurrencyCode,
        to newCurrency: CurrencyCode,
        rates: ExchangeRateTable,
        transactions: [TransactionRecord],
        budgets: [BudgetLimitRecord],
        goals: [SavingsGoalRecord],
        plans: [InstallmentPlanRecord],
        todayKey: String,
        now: Date = Date()
    ) -> CurrencyConversionResult? {
        guard oldCurrency != newCurrency,
              let rateInfo = rates.conversionRate(from: oldCurrency.rawValue, to: newCurrency.rawValue)
        else { return nil }

        let step = InstallmentPlanRecord.roundingStep(for: newCurrency)

        func convertPositive(_ minor: Int64, from src: CurrencyCode) -> Int64 {
            guard minor > 0 else { return step }
            if src == newCurrency {
                let adjusted = newCurrency.isZeroDecimal
                    ? InstallmentPlanRecord.roundHalfUp(minor, step: step)
                    : minor
                return max(step, adjusted)
            }
            return max(step, rates.convertMinor(minor, from: src, to: newCurrency))
        }

        func monotonicStamp(after existing: Date) -> Date {
            now > existing ? now : existing.addingTimeInterval(0.001)
        }

        // 1. Convert installment & loan plans first so non-user-edited payments reconcile cleanly.
        var convertedPlans = plans
        var changedPlanIDs: [String] = []
        var convertedPlansByID: [String: InstallmentPlanRecord] = [:]

        for idx in convertedPlans.indices {
            var plan = convertedPlans[idx]
            guard !plan.isDeleted else { continue }
            let planSource = plan.currency
            guard planSource != newCurrency else { continue }

            let months = max(1, plan.months)
            let minTotal = step * Int64(months)
            let convertedTotal = convertPositive(plan.totalMinor, from: planSource)
            let newTotal = min(InstallmentPlanRecord.maxAmountMinor, max(minTotal, convertedTotal))
            plan.totalMinor = newTotal

            if let oldMonthly = plan.monthlyPaymentMinor, oldMonthly > 0 {
                if months == 1 {
                    plan.monthlyPaymentMinor = newTotal
                } else {
                    let convertedMonthly = InstallmentPlanRecord.roundHalfUp(
                        convertPositive(oldMonthly, from: planSource),
                        step: step
                    )
                    let others = Int64(months - 1)
                    let (product, overflow) = convertedMonthly.multipliedReportingOverflow(by: others)
                    if convertedMonthly > 0, !overflow, product < newTotal {
                        plan.monthlyPaymentMinor = convertedMonthly
                    } else {
                        plan.monthlyPaymentMinor = nil
                    }
                }
            } else if plan.monthlyPaymentMinor != nil {
                plan.monthlyPaymentMinor = nil
            }

            if let oldPrincipal = plan.principalMinor, oldPrincipal > 0 {
                plan.principalMinor = min(newTotal, convertPositive(oldPrincipal, from: planSource))
            } else if plan.principalMinor != nil {
                plan.principalMinor = nil
            }

            plan.currency = newCurrency
            plan.updatedAt = monotonicStamp(after: plan.updatedAt)
            if !plan.hasValidTerms {
                plan.monthlyPaymentMinor = nil
            }

            convertedPlans[idx] = plan
            changedPlanIDs.append(plan.id)
            convertedPlansByID[plan.id] = plan
        }

        // Reconcile active schedule payments for converted plans (`bookMissing: false` leaves
        // tombstones and user-decided payments untouched).
        let activePaymentsByPlan = Dictionary(
            grouping: transactions.filter { !$0.isDeleted && $0.isPlanPayment },
            by: { $0.planID ?? "" }
        )
        var reconciledPaymentsByID: [String: TransactionRecord] = [:]
        for (planID, convertedPlan) in convertedPlansByID {
            let planTxs = activePaymentsByPlan[planID] ?? []
            let revisions = PlanPaymentLedger.reconcile(
                plan: convertedPlan,
                payments: planTxs,
                todayKey: todayKey,
                bookMissing: false
            )
            for rev in revisions {
                reconciledPaymentsByID[rev.id] = rev
            }
        }

        // 2. Convert active transactions.
        let activePlansByID = Dictionary(
            convertedPlans.filter { !$0.isDeleted }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var convertedTransactions = transactions
        var changedTransactionIDs: [String] = []

        for idx in convertedTransactions.indices {
            var tx = convertedTransactions[idx]
            guard !tx.isDeleted else { continue }

            if tx.isPlanPayment {
                if let reconciled = reconciledPaymentsByID[tx.id] {
                    convertedTransactions[idx] = reconciled
                    changedTransactionIDs.append(tx.id)
                } else {
                    let isAlreadyNativeTargetPlanSchedule: Bool = {
                        guard !tx.hasUserPaymentWrite,
                              let planID = tx.planID,
                              convertedPlansByID[planID] == nil,
                              let existingPlan = activePlansByID[planID]
                        else { return false }
                        return existingPlan.currency == newCurrency
                    }()
                    if !isAlreadyNativeTargetPlanSchedule {
                        tx.amountMinor = convertPositive(tx.amountMinor, from: oldCurrency)
                        convertedTransactions[idx] = tx.recordingUserWrite(at: monotonicStamp(after: tx.updatedAt))
                        changedTransactionIDs.append(tx.id)
                    }
                }
                continue
            }

            if tx.isForeignCurrency,
               let origMinor = tx.originalAmountMinor,
               origMinor > 0,
               let origCode = tx.originalCurrencyCode,
               CurrencyCode.normalizeCode(origCode) == newCurrency.rawValue {
                let restored = newCurrency.isZeroDecimal
                    ? InstallmentPlanRecord.roundHalfUp(origMinor, step: step)
                    : origMinor
                tx.amountMinor = max(step, restored)
                tx.originalAmountMinor = nil
                tx.originalCurrencyCode = nil
                tx.exchangeRate = nil
                tx.updatedAt = monotonicStamp(after: tx.updatedAt)
                convertedTransactions[idx] = tx
                changedTransactionIDs.append(tx.id)
            } else if tx.isForeignCurrency,
                      let origMinor = tx.originalAmountMinor,
                      origMinor > 0 {
                let newMinor = convertPositive(tx.amountMinor, from: oldCurrency)
                let origMajor = CurrencyCode.toMajor(origMinor)
                let newMajor = newCurrency.toMajor(newMinor)
                tx.amountMinor = newMinor
                if origMajor > 0, newMajor > 0 {
                    tx.exchangeRate = newMajor / origMajor
                }
                tx.updatedAt = monotonicStamp(after: tx.updatedAt)
                convertedTransactions[idx] = tx
                changedTransactionIDs.append(tx.id)
            } else {
                let newMinor = convertPositive(tx.amountMinor, from: oldCurrency)
                tx.originalAmountMinor = tx.amountMinor
                tx.originalCurrencyCode = oldCurrency.rawValue
                tx.exchangeRate = rateInfo.rate
                tx.amountMinor = newMinor
                tx.updatedAt = monotonicStamp(after: tx.updatedAt)
                convertedTransactions[idx] = tx
                changedTransactionIDs.append(tx.id)
            }
        }

        // 3. Convert active monthly budgets.
        var convertedBudgets = budgets
        var changedBudgetIDs: [String] = []
        for idx in convertedBudgets.indices {
            var budget = convertedBudgets[idx]
            guard !budget.isDeleted else { continue }
            budget.limitMinor = convertPositive(budget.limitMinor, from: oldCurrency)
            budget.updatedAt = monotonicStamp(after: budget.updatedAt)
            convertedBudgets[idx] = budget
            changedBudgetIDs.append(budget.id)
        }

        // 4. Convert active savings goals.
        var convertedGoals = goals
        var changedGoalIDs: [String] = []
        for idx in convertedGoals.indices {
            var goal = convertedGoals[idx]
            guard !goal.isDeleted else { continue }
            goal.targetMinor = convertPositive(goal.targetMinor, from: oldCurrency)
            goal.savedMinor = goal.savedMinor > 0 ? convertPositive(goal.savedMinor, from: oldCurrency) : 0
            goal.updatedAt = monotonicStamp(after: goal.updatedAt)
            convertedGoals[idx] = goal
            changedGoalIDs.append(goal.id)
        }

        return CurrencyConversionResult(
            transactions: convertedTransactions,
            budgets: convertedBudgets,
            goals: convertedGoals,
            plans: convertedPlans,
            rate: rateInfo.rate,
            changedTransactionIDs: changedTransactionIDs,
            changedBudgetIDs: changedBudgetIDs,
            changedGoalIDs: changedGoalIDs,
            changedPlanIDs: changedPlanIDs
        )
    }
}
