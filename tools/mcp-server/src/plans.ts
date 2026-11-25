import {
  dayKeyFromIsoTimestamp,
  dayKeyFromYearMonthDay,
  dayOfMonth,
  daysInMonth,
  formatMoney,
  isValidDayKey,
  isZeroDecimalCurrency,
  monthKeyFromDayKey,
  monthKeyFromYearMonth,
  parseMonthKey,
} from "./money.ts";
import type {
  CategoryID,
  CurrencyCode,
  InstallmentKind,
  InstallmentPlanRecord,
  PlanPaymentContent,
  PlanPaymentScheduleWrite,
  PlanPaymentState,
  TransactionRecord,
} from "./types.ts";

export const MAX_PLAN_MONTHS = 600;
export const MAX_PLAN_AMOUNT_MINOR = 1_000_000_000_000_000;

export interface InstallmentPayment {
  planID: string;
  index: number;
  dayKey: string;
  amountMinor: number;
}

export interface AmortizationRow {
  index: number;
  dayKey: string;
  paymentMinor: number;
  interestMinor: number;
  principalMinor: number;
  outstandingPrincipalMinor: number;
}

export interface InstallmentProgress {
  paymentCount: number;
  paidCount: number;
  paidMinor: number;
  remainingMinor: number;
  nextPayment: InstallmentPayment | null;
  isCompleted: boolean;
  isSettled: boolean;
  principalMinor: number;
  outstandingPrincipalMinor: number;
  interestPaidMinor: number;
  interestRemainingMinor: number;
  settlementPrincipalMinor: number | null;
  interestSavedMinor: number;
}

export function roundingStep(currency: CurrencyCode): number {
  return isZeroDecimalCurrency(currency) ? 100 : 1;
}

export function roundHalfUp(value: number, step: number): number {
  const s = Math.max(1, step);
  const quotient = Math.trunc(value / s);
  const remainder = value % s;
  const base = quotient * s;
  if (remainder > 0 && remainder >= s - remainder) {
    return base + s;
  }
  return base;
}

export function paymentAmounts(
  totalMinor: number,
  months: number,
  regularMinor: number | null = null,
  step = 1
): number[] {
  if (months < 1 || months > MAX_PLAN_MONTHS || totalMinor <= 0) return [];
  const safeStep = Math.max(1, step);
  if (months === 1) return [totalMinor];
  const others = months - 1;

  let regular = 0;
  if (regularMinor !== null && regularMinor > 0) {
    const rounded = roundHalfUp(regularMinor, safeStep);
    if (rounded > 0 && rounded * others < totalMinor) {
      regular = rounded;
    }
  }
  if (regular === 0) {
    const divisor = months * safeStep;
    const quotient = Math.trunc(totalMinor / divisor);
    const remainder = totalMinor % divisor;
    regular = quotient * safeStep;
    if (remainder >= divisor - remainder) {
      regular += safeStep;
    }
    if (regular * others >= totalMinor) {
      regular = quotient * safeStep;
    }
  }
  if (regular <= 0) return [];
  const last = totalMinor - regular * others;
  if (last <= 0) return [];
  const result = new Array<number>(months - 1).fill(regular);
  result.push(last);
  return result;
}

export function paymentDayKey(firstPaymentDayKey: string, index: number): string | null {
  if (index < 0 || index >= MAX_PLAN_MONTHS || !isValidDayKey(firstPaymentDayKey)) return null;
  const ym = parseMonthKey(monthKeyFromDayKey(firstPaymentDayKey));
  if (!ym) return null;
  const monthIndex = ym.month - 1 + index;
  const year = ym.year + Math.floor(monthIndex / 12);
  const month = (monthIndex % 12) + 1;
  const mKey = monthKeyFromYearMonth(year, month);
  const day = Math.min(dayOfMonth(firstPaymentDayKey), daysInMonth(mKey));
  return dayKeyFromYearMonthDay(year, month, day);
}

export function effectiveAlreadyPaidCount(plan: InstallmentPlanRecord): number {
  return Math.min(Math.max(0, plan.alreadyPaidPaymentCount ?? 0), Math.max(0, plan.months));
}

export function isPaidOutsidePlan(plan: InstallmentPlanRecord, index: number): boolean {
  return index >= 0 && index < effectiveAlreadyPaidCount(plan);
}

export function fullSchedule(plan: InstallmentPlanRecord): InstallmentPayment[] {
  if (
    plan.months < 1 ||
    plan.months > MAX_PLAN_MONTHS ||
    plan.totalMinor <= 0 ||
    !isValidDayKey(plan.firstPaymentDayKey)
  ) {
    return [];
  }
  const amounts = paymentAmounts(
    plan.totalMinor,
    plan.months,
    plan.monthlyPaymentMinor ?? null,
    roundingStep(plan.currency)
  );
  const rows: InstallmentPayment[] = [];
  for (let index = 0; index < amounts.length; index++) {
    const dk = paymentDayKey(plan.firstPaymentDayKey, index);
    if (dk) {
      rows.push({
        planID: plan.id,
        index,
        dayKey: dk,
        amountMinor: amounts[index],
      });
    }
  }
  return rows;
}

export function planSchedule(plan: InstallmentPlanRecord): InstallmentPayment[] {
  const all = fullSchedule(plan);
  if (!plan.settledDayKey) return all;
  const settled = plan.settledDayKey;
  return all.filter((item) => item.dayKey <= settled);
}

export function hasValidTerms(plan: InstallmentPlanRecord): boolean {
  if (
    plan.months < 1 ||
    plan.months > MAX_PLAN_MONTHS ||
    plan.totalMinor <= 0 ||
    plan.totalMinor > MAX_PLAN_AMOUNT_MINOR ||
    !isValidDayKey(plan.firstPaymentDayKey)
  ) {
    return false;
  }
  if (
    plan.monthlyPaymentMinor !== undefined &&
    plan.monthlyPaymentMinor !== null &&
    (plan.monthlyPaymentMinor < 0 || plan.monthlyPaymentMinor > MAX_PLAN_AMOUNT_MINOR)
  ) {
    return false;
  }
  if (
    plan.principalMinor !== undefined &&
    plan.principalMinor !== null &&
    (plan.principalMinor < 0 || plan.principalMinor > MAX_PLAN_AMOUNT_MINOR)
  ) {
    return false;
  }
  if (
    plan.alreadyPaidPaymentCount !== undefined &&
    plan.alreadyPaidPaymentCount !== null &&
    (plan.alreadyPaidPaymentCount < 0 || plan.alreadyPaidPaymentCount > plan.months)
  ) {
    return false;
  }
  return fullSchedule(plan).length === plan.months;
}

export function effectivePrincipalMinor(plan: InstallmentPlanRecord): number {
  if (!plan.principalMinor || plan.principalMinor <= 0) return plan.totalMinor;
  return Math.min(plan.principalMinor, plan.totalMinor);
}

export function totalInterestMinor(plan: InstallmentPlanRecord): number {
  return Math.max(0, plan.totalMinor - effectivePrincipalMinor(plan));
}

export function presentValue(payments: number[], rate: number): number {
  let discount = 1.0;
  let pv = 0.0;
  for (const payment of payments) {
    discount /= 1 + rate;
    pv += payment * discount;
  }
  return pv;
}

export function solveMonthlyRate(principalMinor: number, payments: number[]): number {
  const total = payments.reduce((sum, p) => sum + p, 0);
  if (principalMinor <= 0 || payments.length === 0 || total <= principalMinor) return 0;
  const target = principalMinor;
  let low = 0.0;
  let high = 0.05;
  while (presentValue(payments, high) > target) {
    low = high;
    high *= 2;
    if (!Number.isFinite(high) || high >= 1e20) return low;
  }
  for (let i = 0; i < 400; i++) {
    const mid = (low + high) / 2;
    if (presentValue(payments, mid) > target) {
      low = mid;
    } else {
      high = mid;
    }
    if (high - low <= 1e-13 * Math.max(1, high)) break;
  }
  return (low + high) / 2;
}

export function effectiveMonthlyRate(plan: InstallmentPlanRecord): number {
  return solveMonthlyRate(
    effectivePrincipalMinor(plan),
    fullSchedule(plan).map((p) => p.amountMinor)
  );
}

export function effectiveAnnualRate(plan: InstallmentPlanRecord): number {
  return effectiveMonthlyRate(plan) * 12;
}

export function amortizationSchedule(plan: InstallmentPlanRecord): AmortizationRow[] {
  const payments = fullSchedule(plan);
  if (payments.length === 0) return [];
  const rate = effectiveMonthlyRate(plan);
  let outstanding = effectivePrincipalMinor(plan);
  const rows: AmortizationRow[] = [];

  for (let offset = 0; offset < payments.length; offset++) {
    const payment = payments[offset];
    const isLast = offset === payments.length - 1;
    let interest: number;
    let principalPart: number;
    if (isLast) {
      principalPart = outstanding;
      interest = payment.amountMinor - principalPart;
    } else {
      interest = rate > 0 ? Math.round(outstanding * rate) : 0;
      interest = Math.min(Math.max(0, interest), payment.amountMinor);
      principalPart = Math.min(payment.amountMinor - interest, outstanding);
      interest = payment.amountMinor - principalPart;
    }
    outstanding -= principalPart;
    rows.push({
      index: payment.index,
      dayKey: payment.dayKey,
      paymentMinor: payment.amountMinor,
      interestMinor: interest,
      principalMinor: principalPart,
      outstandingPrincipalMinor: outstanding,
    });
  }

  let deficit = rows.length > 0 ? -rows[rows.length - 1].interestMinor : 0;
  if (deficit > 0) {
    for (let offset = rows.length - 2; offset >= 0 && deficit > 0; offset--) {
      const take = Math.min(rows[offset].interestMinor, deficit);
      rows[offset].interestMinor -= take;
      rows[offset].principalMinor += take;
      deficit -= take;
    }
    let remaining = effectivePrincipalMinor(plan);
    for (let offset = 0; offset < rows.length; offset++) {
      if (offset === rows.length - 1) {
        rows[offset].principalMinor = remaining;
        rows[offset].interestMinor = rows[offset].paymentMinor - remaining;
      }
      remaining -= rows[offset].principalMinor;
      rows[offset].outstandingPrincipalMinor = remaining;
    }
  }
  return rows;
}

export function computeProgress(plan: InstallmentPlanRecord, todayKey: string): InstallmentProgress {
  const owed = planSchedule(plan);
  const rows = amortizationSchedule(plan);
  const dueCount = owed.filter((item) => item.dayKey <= todayKey).length;
  const paidPrefix = Math.max(dueCount, Math.min(effectiveAlreadyPaidCount(plan), owed.length));
  const paid = owed.slice(0, paidPrefix);
  const settled = plan.settledDayKey ? plan.settledDayKey <= todayKey : false;

  const paymentCount = owed.length;
  const paidCount = paid.length;
  const paidMinor = paid.reduce((sum, p) => sum + p.amountMinor, 0);
  const principalMinor = effectivePrincipalMinor(plan);

  const paidRows = rows.slice(0, paid.length);
  const interestPaidMinor = paidRows.reduce((sum, r) => sum + r.interestMinor, 0);
  const outstandingAfterPaid =
    paidRows.length > 0 ? paidRows[paidRows.length - 1].outstandingPrincipalMinor : principalMinor;

  if (settled) {
    return {
      paymentCount,
      paidCount,
      paidMinor,
      remainingMinor: 0,
      nextPayment: null,
      isCompleted: true,
      isSettled: true,
      principalMinor,
      outstandingPrincipalMinor: 0,
      interestPaidMinor,
      interestRemainingMinor: 0,
      settlementPrincipalMinor: rows.length === 0 ? 0 : outstandingAfterPaid,
      interestSavedMinor: Math.max(0, totalInterestMinor(plan) - interestPaidMinor),
    };
  }

  const upcoming = owed.slice(paid.length);
  const remainingMinor = upcoming.reduce((sum, p) => sum + p.amountMinor, 0);
  const nextPayment = upcoming[0] ?? null;
  const isCompleted = owed.length > 0 && upcoming.length === 0;
  let outstandingPrincipalMinor = 0;
  let interestRemainingMinor = 0;

  if (!(isCompleted && !plan.settledDayKey)) {
    outstandingPrincipalMinor = rows.length === 0 ? 0 : outstandingAfterPaid;
    interestRemainingMinor = rows
      .slice(0, owed.length)
      .slice(paid.length)
      .reduce((sum, r) => sum + r.interestMinor, 0);
  }

  return {
    paymentCount,
    paidCount,
    paidMinor,
    remainingMinor,
    nextPayment,
    isCompleted,
    isSettled: false,
    principalMinor,
    outstandingPrincipalMinor,
    interestPaidMinor,
    interestRemainingMinor,
    settlementPrincipalMinor: null,
    interestSavedMinor: 0,
  };
}

export interface EarlySettlementResult {
  settleDayKey: string;
  payoffPrincipalMinor: number;
  interestSavedMinor: number;
  cancelledPaymentCount: number;
  cancelledPaymentsMinor: number;
  bookedPaymentsRemovedCount: number;
}

export function earlySettlementCompute(
  plan: InstallmentPlanRecord,
  settleDayKey: string,
  todayKey: string
): { ok: true; value: EarlySettlementResult } | { ok: false; reason: string } {
  if (settleDayKey < plan.firstPaymentDayKey) {
    return {
      ok: false,
      reason: `a plan can only be settled on or after its first payment date ${plan.firstPaymentDayKey}`,
    };
  }
  const progressAtSettle = computeProgress(plan, settleDayKey);
  if (progressAtSettle.isCompleted) {
    return {
      ok: false,
      reason: `the plan is already completed or settled by ${settleDayKey}`,
    };
  }
  const settledPlan: InstallmentPlanRecord = { ...plan, settledDayKey: settleDayKey };
  const progress = computeProgress(settledPlan, settleDayKey);
  const cancelled = fullSchedule(plan).filter((p) => p.dayKey > settleDayKey);
  return {
    ok: true,
    value: {
      settleDayKey,
      payoffPrincipalMinor: progress.settlementPrincipalMinor ?? 0,
      interestSavedMinor: progress.interestSavedMinor,
      cancelledPaymentCount: cancelled.length,
      cancelledPaymentsMinor: cancelled.reduce((s, p) => s + p.amountMinor, 0),
      bookedPaymentsRemovedCount: cancelled.filter(
        (p) => p.dayKey <= todayKey && !isPaidOutsidePlan(plan, p.index)
      ).length,
    },
  };
}

export function commitmentsOverview(plans: InstallmentPlanRecord[], todayKey: string) {
  const live = plans.filter((p) => !p.isDeleted);
  const entries = live.map((plan) => ({
    plan,
    progress: computeProgress(plan, todayKey),
  }));

  const active = entries
    .filter((e) => !e.progress.isCompleted)
    .sort((a, b) => {
      const da = a.progress.nextPayment?.dayKey ?? null;
      const db = b.progress.nextPayment?.dayKey ?? null;
      if (da && db && da !== db) return da < db ? -1 : 1;
      if (da && !db) return -1;
      if (!da && db) return 1;
      return a.plan.name.localeCompare(b.plan.name, undefined, { sensitivity: "base" });
    });

  const finishDayKey = (p: InstallmentPlanRecord): string => {
    const sched = planSchedule(p);
    return p.settledDayKey ?? sched[sched.length - 1]?.dayKey ?? p.firstPaymentDayKey;
  };

  const completed = entries
    .filter((e) => e.progress.isCompleted)
    .sort((a, b) => (finishDayKey(a.plan) > finishDayKey(b.plan) ? -1 : 1));

  const thisMonth = monthKeyFromDayKey(todayKey);
  const committedThisMonthMinor = active.reduce((sum, e) => {
    return (
      sum +
      planSchedule(e.plan)
        .filter((p) => monthKeyFromDayKey(p.dayKey) === thisMonth)
        .reduce((s, p) => s + p.amountMinor, 0)
    );
  }, 0);
  const remainingDebtMinor = active.reduce((sum, e) => sum + e.progress.remainingMinor, 0);

  return { active, completed, committedThisMonthMinor, remainingDebtMinor };
}

export function planContextLines(
  plans: InstallmentPlanRecord[],
  todayKey: string,
  currency: CurrencyCode,
  limit = 30
): string[] {
  const live = plans.filter((p) => !p.isDeleted);
  const overview = commitmentsOverview(live, todayKey);
  const ordered = [...overview.active, ...overview.completed].slice(0, limit);
  const lines = ordered.map((entry) => {
    const { plan, progress } = entry;
    const money = (m: number) => formatMoney(m, plan.currency);
    const parts = [
      `[id:${plan.id}] ${plan.name}`,
      plan.kind,
      `monthly ${money(fullSchedule(plan)[0]?.amountMinor ?? 0)}`,
      `paid ${progress.paidCount}/${progress.paymentCount}`,
    ];
    const paidOutside = effectiveAlreadyPaidCount(plan);
    if (paidOutside > 0) {
      parts.push(`${paidOutside} paid before/outside Tally`);
    }
    parts.push(`remaining ${money(progress.remainingMinor)}`);
    if ((plan.kind === "loan" || totalInterestMinor(plan) > 0) && !progress.isCompleted) {
      parts.push(`principal owed ${money(progress.outstandingPrincipalMinor)}`);
      parts.push(`rate ${(effectiveAnnualRate(plan) * 100).toFixed(2)}% p.a.`);
    }
    if (progress.nextPayment) {
      parts.push(`next ${progress.nextPayment.dayKey} ${money(progress.nextPayment.amountMinor)}`);
    }
    if (plan.lender) parts.push(`lender ${plan.lender}`);
    if (progress.isSettled && plan.settledDayKey) {
      parts.push(`settled ${plan.settledDayKey}`);
    } else if (plan.settledDayKey) {
      parts.push(`settles ${plan.settledDayKey}`);
    } else if (progress.isCompleted) {
      parts.push("completed");
    } else {
      parts.push("active");
    }
    return `- ${parts.join(" · ")}`;
  });

  if (live.length > limit) {
    lines.push(`- … ${live.length - limit} more plans not listed`);
  }
  if (overview.active.length > 0) {
    lines.push(
      `Total still to pay on active plans: ${formatMoney(overview.remainingDebtMinor, currency)}; due this month: ${formatMoney(overview.committedThisMonthMinor, currency)}`
    );
  }
  return lines;
}

// MARK: - Plan Payment Ledger & Join (matches PlanPaymentState.swift & PlanPaymentLedger.swift)

export function isPlanPayment(tx: TransactionRecord): boolean {
  if (!tx.planID) return false;
  return (
    (tx.planPaymentIndex !== undefined && tx.planPaymentIndex !== null) ||
    tx.id.startsWith(`${tx.planID}#`)
  );
}

export function paymentIndexFromID(transactionID: string, planID: string): number | null {
  const prefix = `${planID}#`;
  if (!transactionID.startsWith(prefix)) return null;
  const num = Number(transactionID.slice(prefix.length));
  return Number.isInteger(num) && num >= 0 ? num : null;
}

export function planPaymentContentFromRecord(tx: TransactionRecord): PlanPaymentContent {
  return {
    name: tx.name,
    amountMinor: tx.amountMinor,
    type: tx.type,
    category: tx.category,
    dayKey: tx.dayKey,
    createdAt: tx.createdAt,
    note: tx.note,
    source: tx.source,
    rawSourceText: tx.rawSourceText ?? null,
    memberID: tx.memberID,
    memberName: tx.memberName,
    needsReview: tx.needsReview,
    isDeleted: tx.isDeleted,
  };
}

export function effectivePaymentState(tx: TransactionRecord): PlanPaymentState {
  if (tx.paymentState) return tx.paymentState;
  return {
    user: {
      at: tx.updatedAt,
      content: planPaymentContentFromRecord(tx),
    },
    schedule: null,
  };
}

export function applyPaymentState(tx: TransactionRecord, state: PlanPaymentState): TransactionRecord {
  const visible = state.user?.content ?? state.schedule?.content;
  const userMs = state.user ? Date.parse(state.user.at) : NaN;
  const schedMs = state.schedule ? Date.parse(state.schedule.planRevision) : NaN;
  let stamp = tx.updatedAt;
  if (Number.isFinite(userMs) && Number.isFinite(schedMs)) {
    stamp = userMs >= schedMs ? state.user!.at : state.schedule!.planRevision;
  } else if (Number.isFinite(userMs)) {
    stamp = state.user!.at;
  } else if (Number.isFinite(schedMs)) {
    stamp = state.schedule!.planRevision;
  }
  return {
    ...tx,
    paymentState: state,
    ...(visible
      ? {
          name: visible.name,
          amountMinor: visible.amountMinor,
          type: visible.type,
          category: visible.category,
          dayKey: visible.dayKey,
          createdAt: visible.createdAt,
          note: visible.note,
          source: visible.source,
          rawSourceText: visible.rawSourceText ?? null,
          memberID: visible.memberID,
          memberName: visible.memberName,
          needsReview: visible.needsReview,
          isDeleted: visible.isDeleted,
        }
      : {}),
    updatedAt: stamp,
  };
}

export function joinPaymentState(a: PlanPaymentState, b: PlanPaymentState): PlanPaymentState {
  const pickUser = () => {
    if (!a.user) return b.user ?? null;
    if (!b.user) return a.user;
    const ta = Date.parse(a.user.at);
    const tb = Date.parse(b.user.at);
    if (ta !== tb) return ta < tb ? b.user : a.user;
    if (a.user.content.isDeleted !== b.user.content.isDeleted) {
      return b.user.content.isDeleted ? b.user : a.user;
    }
    if (a.user.content.name !== b.user.content.name) {
      return a.user.content.name < b.user.content.name ? b.user : a.user;
    }
    return JSON.stringify(a.user.content) <= JSON.stringify(b.user.content) ? b.user : a.user;
  };

  const pickSchedule = () => {
    if (!a.schedule) return b.schedule ?? null;
    if (!b.schedule) return a.schedule;
    const ta = Date.parse(a.schedule.planRevision);
    const tb = Date.parse(b.schedule.planRevision);
    if (ta !== tb) return ta < tb ? b.schedule : a.schedule;
    const aBooked = !a.schedule.content.isDeleted;
    const bBooked = !b.schedule.content.isDeleted;
    if (aBooked !== bBooked) return bBooked ? b.schedule : a.schedule;
    return JSON.stringify(a.schedule.content) <= JSON.stringify(b.schedule.content)
      ? b.schedule
      : a.schedule;
  };

  return {
    user: pickUser(),
    schedule: pickSchedule(),
  };
}

export function scheduledPaymentContent(
  plan: InstallmentPlanRecord,
  dayKey: string,
  amountMinor: number,
  isDeleted: boolean
): PlanPaymentContent {
  return {
    name: plan.name,
    amountMinor,
    type: "expense",
    category: plan.category,
    dayKey,
    createdAt: `${dayKey}T04:00:00.000Z`,
    note: plan.note,
    source: "manual",
    rawSourceText: null,
    memberID: plan.memberID,
    memberName: plan.memberName,
    needsReview: false,
    isDeleted,
  };
}

export function reconcilePlanPayments(
  plan: InstallmentPlanRecord,
  existingPayments: TransactionRecord[],
  todayKey: string,
  bookMissing: boolean,
  offsetMinutes = 0
): TransactionRecord[] {
  const owed = new Map<number, InstallmentPayment>(planSchedule(plan).map((p) => [p.index, p]));
  const full = new Map<number, InstallmentPayment>(fullSchedule(plan).map((p) => [p.index, p]));

  const existingByIndex = new Map<number, TransactionRecord>();
  for (const tx of existingPayments) {
    if (tx.planID !== plan.id || !isPlanPayment(tx)) continue;
    const idx = tx.planPaymentIndex ?? paymentIndexFromID(tx.id, plan.id);
    if (idx !== null) existingByIndex.set(idx, tx);
  }

  const indexes = new Set<number>(existingByIndex.keys());
  if (bookMissing && !plan.isDeleted) {
    for (const p of owed.values()) {
      if (p.dayKey <= todayKey && !isPaidOutsidePlan(plan, p.index)) {
        indexes.add(p.index);
      }
    }
  }

  const cutoffDay = plan.deletedDayKey ?? dayKeyFromIsoTimestamp(plan.updatedAt, offsetMinutes);
  const revisions: TransactionRecord[] = [];
  for (const index of [...indexes].sort((a, b) => a - b)) {
    const existing = existingByIndex.get(index);
    const before: PlanPaymentState = existing
      ? effectivePaymentState(existing)
      : { user: null, schedule: null };
    let state: PlanPaymentState = { ...before };

    const entry = owed.get(index) ?? full.get(index);
    const dk = entry?.dayKey ?? paymentDayKey(plan.firstPaymentDayKey, index);
    if (!dk) continue;

    if (existing && plan.isDeleted && plan.deletionRemovesPayments === true) {
      state = joinPaymentState(state, {
        user: {
          at: plan.updatedAt,
          content: scheduledPaymentContent(plan, dk, entry?.amountMinor ?? 0, true),
        },
        schedule: null,
      });
    }

    let booked = false;
    if (isPaidOutsidePlan(plan, index)) {
      booked = false;
    } else if (plan.isDeleted) {
      booked =
        plan.deletionRemovesPayments !== true && owed.has(index) && dk <= cutoffDay;
    } else {
      booked = owed.has(index) && dk <= todayKey;
    }

    const schedWrite: PlanPaymentScheduleWrite = {
      planRevision: plan.updatedAt,
      content: scheduledPaymentContent(plan, dk, entry?.amountMinor ?? 0, !booked),
    };
    state = joinPaymentState(state, { user: null, schedule: schedWrite });

    let changed = false;
    if (!existing) {
      const vis = state.user?.content ?? state.schedule?.content;
      changed = vis?.isDeleted === false;
    } else if (state.user) {
      changed = JSON.stringify(state.user) !== JSON.stringify(before.user);
    } else {
      changed = JSON.stringify(state) !== JSON.stringify(before);
    }
    if (!changed) continue;

    const base: TransactionRecord = existing ?? {
      id: `${plan.id}#${index}`,
      name: "",
      amountMinor: 0,
      type: "expense",
      category: "other",
      dayKey: "",
      createdAt: "2001-01-01T00:00:00.000Z",
      note: "",
      source: "manual",
      rawSourceText: null,
      memberID: plan.memberID,
      memberName: plan.memberName,
      needsReview: false,
      updatedAt: "2001-01-01T00:00:00.000Z",
      isDeleted: false,
      planID: plan.id,
      planPaymentIndex: index,
      paymentState: null,
    };
    const revised = applyPaymentState(base, state);
    revised.planID = plan.id;
    revised.planPaymentIndex = index;
    revisions.push(revised);
  }

  return revisions;
}

export function validateNewOrUpdatedPlan(params: {
  kind: InstallmentKind;
  name: string;
  amountMinor: number;
  monthlyPaymentMinor: number;
  months: number | null;
  firstPaymentDayKey: string;
  currency: CurrencyCode;
  alreadyPaidCount: number;
  category: CategoryID;
}): string[] {
  const issues: string[] = [];
  const trimmedName = params.name.trim();
  if (!trimmedName) issues.push("The plan needs a name.");

  const amountInRange = params.amountMinor > 0 && params.amountMinor <= MAX_PLAN_AMOUNT_MINOR;
  if (!amountInRange) {
    issues.push(
      params.kind === "loan"
        ? "The amount borrowed (principal) is missing or not positive."
        : "The total amount is missing or not positive."
    );
  }

  const monthsValid =
    params.months !== null &&
    Number.isInteger(params.months) &&
    params.months >= 1 &&
    params.months <= MAX_PLAN_MONTHS;
  if (!monthsValid) {
    issues.push(`The number of monthly payments is missing or outside 1-${MAX_PLAN_MONTHS}.`);
  }

  if (!isValidDayKey(params.firstPaymentDayKey)) {
    issues.push("The first payment date is missing or invalid.");
  }

  const step = roundingStep(params.currency);
  const roundedMonthly = roundHalfUp(params.monthlyPaymentMinor, step);
  if (params.kind === "loan") {
    if (roundedMonthly <= 0 || roundedMonthly > MAX_PLAN_AMOUNT_MINOR) {
      issues.push("The monthly payment of the loan is missing.");
    } else if (monthsValid && amountInRange && params.months !== null) {
      const loanTotal = roundedMonthly * params.months;
      if (loanTotal < params.amountMinor) {
        issues.push(
          `Monthly payment x months is ${formatMoney(loanTotal, params.currency)}, ${formatMoney(params.amountMinor - loanTotal, params.currency)} less than the amount borrowed, so these figures are inconsistent.`
        );
      }
    }
  } else if (monthsValid && amountInRange && params.months !== null) {
    if (paymentAmounts(params.amountMinor, params.months, null, step).length === 0) {
      issues.push(
        `The amount is too small to split into that many payments (minimum ${formatMoney(step * params.months, params.currency)}).`
      );
    }
  }

  if (
    params.alreadyPaidCount < 0 ||
    (monthsValid && params.months !== null && params.alreadyPaidCount > params.months)
  ) {
    issues.push(
      `already_paid_payments must be between 0 and the number of months (${monthsValid ? params.months : 0}).`
    );
  }

  return issues;
}
