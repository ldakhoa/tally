import { applyPaymentState, effectivePaymentState, joinPaymentState } from "./plans.ts";
import type {
  BudgetLimitRecord,
  InstallmentPlanRecord,
  SavingsGoalRecord,
  TransactionRecord,
} from "./types.ts";

function compareIsoTimestamps(a: string, b: string): number {
  const ma = Date.parse(a);
  const mb = Date.parse(b);
  if (Number.isFinite(ma) && Number.isFinite(mb) && ma !== mb) {
    return ma < mb ? -1 : 1;
  }
  return a === b ? 0 : a < b ? -1 : 1;
}

function canonicalPick<T>(local: T, remote: T): T {
  const sLocal = JSON.stringify(local);
  const sRemote = JSON.stringify(remote);
  if (sLocal === sRemote) return remote;
  return sRemote < sLocal ? local : remote;
}

export function mergeTransaction(
  local: TransactionRecord | null,
  remote: TransactionRecord
): TransactionRecord {
  if (!local) return remote;
  if (local.paymentState || remote.paymentState) {
    const state = joinPaymentState(effectivePaymentState(local), effectivePaymentState(remote));
    const planID =
      [local.planID, remote.planID].filter((v): v is string => typeof v === "string").sort().pop() ??
      null;
    const planPaymentIndex =
      [local.planPaymentIndex, remote.planPaymentIndex]
        .filter((v): v is number => typeof v === "number")
        .sort((a, b) => a - b)
        .pop() ?? null;
    const base: TransactionRecord = {
      ...local,
      planID,
      planPaymentIndex,
    };
    return applyPaymentState(base, state);
  }
  const cmp = compareIsoTimestamps(remote.updatedAt, local.updatedAt);
  if (cmp > 0) return remote;
  if (cmp < 0) return local;
  if (remote.isDeleted !== local.isDeleted) return remote.isDeleted ? remote : local;
  if (remote.name !== local.name) return remote.name > local.name ? remote : local;
  return canonicalPick(local, remote);
}

export function mergeBudget(
  local: BudgetLimitRecord | null,
  remote: BudgetLimitRecord
): BudgetLimitRecord {
  if (!local) return remote;
  const cmp = compareIsoTimestamps(remote.updatedAt, local.updatedAt);
  if (cmp > 0) return remote;
  if (cmp < 0) return local;
  if (remote.isDeleted !== local.isDeleted) return remote.isDeleted ? remote : local;
  if (remote.limitMinor !== local.limitMinor) {
    return remote.limitMinor > local.limitMinor ? remote : local;
  }
  return canonicalPick(local, remote);
}

export function mergeGoal(
  local: SavingsGoalRecord | null,
  remote: SavingsGoalRecord
): SavingsGoalRecord {
  if (!local) return remote;
  const cmp = compareIsoTimestamps(remote.updatedAt, local.updatedAt);
  if (cmp > 0) return remote;
  if (cmp < 0) return local;
  if (remote.isDeleted !== local.isDeleted) return remote.isDeleted ? remote : local;
  if (remote.savedMinor !== local.savedMinor) {
    return remote.savedMinor > local.savedMinor ? remote : local;
  }
  return canonicalPick(local, remote);
}

export function mergePlan(
  local: InstallmentPlanRecord | null,
  remote: InstallmentPlanRecord
): InstallmentPlanRecord {
  if (!local) return remote;
  const cmp = compareIsoTimestamps(remote.updatedAt, local.updatedAt);
  if (cmp > 0) return remote;
  if (cmp < 0) return local;
  if (remote.isDeleted !== local.isDeleted) return remote.isDeleted ? remote : local;
  if (remote.totalMinor !== local.totalMinor) {
    return remote.totalMinor > local.totalMinor ? remote : local;
  }
  if (remote.name !== local.name) return remote.name > local.name ? remote : local;
  return canonicalPick(local, remote);
}
