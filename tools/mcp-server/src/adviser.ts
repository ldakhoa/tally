import {
  dateContextLines,
  dayOfMonth,
  dayRangeForMonth,
  daysBetween,
  daysInMonth,
  formatMoney,
  isValidDayKey,
  monthKeyFromDateOrMonthInput,
  monthKeyFromDayKey,
  parseMonthKey,
  shiftMonth,
  toMajor,
  toStorageMinor,
} from "./money.ts";
import {
  computeProgress,
  earlySettlementCompute,
  effectiveAnnualRate,
  isPlanPayment,
  MAX_PLAN_AMOUNT_MINOR,
  MAX_PLAN_MONTHS,
  paymentAmounts,
  planContextLines,
  planSchedule,
  roundingStep,
  solveMonthlyRate,
} from "./plans.ts";
import {
  ALL_CATEGORIES,
  EXPENSE_CATEGORIES,
  type AdviserContext,
  type CategoryID,
  type CurrencyCode,
  type InstallmentPlanRecord,
  type MCPToolDefinition,
  type MCPToolResult,
  type SavingsGoalRecord,
  type TransactionRecord,
  type TransactionType,
} from "./types.ts";

const HISTORY_MONTHS = 12;
const MIN_MONTHS_FOR_AVERAGE = 2;
const MIN_BASELINE_MONTHS_FOR_MOVERS = 2;
const MIN_MONTHS_FOR_SUGGESTED_LIMIT = 3;
const MOVERS_LIMIT = 5;
const FIXED_CATEGORIES = new Set<CategoryID>(["housing", "bills"]);
const NEAR_LIMIT_PERCENT = 80.0;

const LOCKED_TEXT = "locked (salary hidden)";
const AVERAGES_RULE =
  "Averages use complete calendar months that have at least one transaction (months with none are listed but excluded); the current month is month-to-date and never averaged.";
const SAVINGS_RATE_RULE =
  "Savings rate = net / income x 100. The average savings rate is total net / total income over the averaged months.";
const FIXED_RULE =
  "Fixed spending = installment and loan payments plus housing and bills; everything else is variable.";
const MOVERS_RULE =
  "Movers compare each category's spending in the latest complete month with its average over the earlier complete months with transactions, ranked by the size of the change.";
const DEBT_SERVICE_RULE =
  "Monthly debt service = the next scheduled payment of every active plan or loan. Debt-service-to-income = monthly debt service / average monthly income.";
const PAYOFF_RULE =
  "Highest rate first ranks by effective annual rate (ties: larger balance first). Smallest balance first ranks by outstanding principal (ties: higher rate first).";
const SUGGESTED_LIMIT_RULE =
  "Statistic, not advice: median monthly spending over the complete months with transactions, rounded up to 2 significant figures.";
const PROJECTION_RULE =
  "Linear projection: month-to-date spending / days elapsed x days in month.";
const GOAL_PACE_RULE =
  "Pace = average monthly net (income - spending) of the household, counting saving from next month. It is the household's whole surplus, not money set aside for this goal.";
const RUNWAY_RULE =
  "Runway = cash / average monthly spending, rounded down to 0.1 month.";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 500;

export const READ_TOOLS: MCPToolDefinition[] = [
  {
    name: "get_overview",
    description:
      "Read-only. Start here. Today's date and useful date ranges, the household currency and members, the category ids, a short computed financial snapshot, savings goals and installment plans & loans with their ids, and how much history is on record.",
    inputSchema: { type: "object", properties: {}, required: [] },
    readOnly: true,
  },
  {
    name: "list_transactions",
    description:
      "Read-only. Individual transactions, newest first, with their ids. Filter by month or date range, category, type, member, or text in the name or note. For totals, averages and breakdowns use summarize_period or get_cash_flow_history instead of adding rows up.",
    inputSchema: {
      type: "object",
      properties: {
        month: { type: "string", description: "A whole month, YYYY-MM (instead of start_date/end_date)." },
        start_date: { type: "string", description: "First day, YYYY-MM-DD." },
        end_date: { type: "string", description: "Last day, YYYY-MM-DD." },
        category: { type: "string", enum: ALL_CATEGORIES, description: "Optional category filter." },
        type: { type: "string", enum: ["expense", "income"], description: "Optional: only expenses or only income." },
        member: { type: "string", description: "Optional member filter: 'me', 'partner', or a member's display name." },
        search: { type: "string", description: "Optional text to find in the name or note (case-insensitive)." },
        limit: { type: "integer", description: `Rows to return (default ${DEFAULT_LIMIT}, max ${MAX_LIMIT}).` },
        offset: { type: "integer", description: "Rows to skip, for paging (default 0)." },
      },
      required: [],
    },
    readOnly: true,
  },
  {
    name: "get_cash_flow_history",
    description:
      "Read-only. Month-by-month income, spending, net, savings rate and spending per category for the last complete months (up to 12), with averages, the latest month-over-month change, the categories that moved most against their average, and the fixed vs variable split. Use for trends, 'how are we doing', savings rate and where money goes over time.",
    inputSchema: {
      type: "object",
      properties: {
        months: { type: "integer", description: "How many complete months to look back (1-12, default 12)." },
      },
      required: [],
    },
    readOnly: true,
  },
  {
    name: "get_debt_overview",
    description:
      "Read-only. Every active installment plan and loan with monthly payment, payments left, outstanding balance, effective annual rate, interest still to pay and the saving from settling it today; totals, monthly debt service, debt-service-to-income ratio, and two payoff orders (highest rate first, smallest balance first).",
    inputSchema: { type: "object", properties: {}, required: [] },
    readOnly: true,
  },
  {
    name: "get_budget_adherence",
    description:
      "Read-only. This month's budget limit vs actual per category (remaining, % used, status, linear month-end projection), how often each category went over in recent months, and a suggested limit computed as a statistic of past spending.",
    inputSchema: {
      type: "object",
      properties: {
        category: { type: "string", enum: EXPENSE_CATEGORIES, description: "Optional: only this expense category." },
      },
      required: [],
    },
    readOnly: true,
  },
  {
    name: "get_savings_goals",
    description:
      "Read-only. Every savings goal with amount still needed and months to reach it at the household's current average monthly net saving.",
    inputSchema: { type: "object", properties: {}, required: [] },
    readOnly: true,
  },
  {
    name: "plan_savings_goal",
    description:
      "Calculator. For an existing goal (goal_id or goal_name) or a hypothetical one (target_amount, saved_amount): the monthly contribution needed to reach it by target_date, and/or how long it takes at a stated monthly_contribution, compared with the current saving pace.",
    inputSchema: {
      type: "object",
      properties: {
        goal_id: { type: "string", description: "ID of an existing goal." },
        goal_name: { type: "string", description: "Name of an existing goal if the id is not known." },
        target_amount: { type: "number", description: "Hypothetical goal: target amount in the household currency's major units." },
        saved_amount: { type: "number", description: "Hypothetical goal: amount already saved (default 0)." },
        target_date: { type: "string", description: "Optional target month, YYYY-MM or YYYY-MM-DD." },
        monthly_contribution: { type: "number", description: "Optional monthly amount the user could set aside, in major units." },
      },
      required: [],
    },
    readOnly: true,
  },
  {
    name: "check_affordability",
    description:
      "Calculator. For a proposed new commitment (purchase in instalments or a loan): the monthly payment, total repaid and interest, the new monthly debt service and debt-service-to-income ratio, and the household's average monthly net after the payment. Pass monthly_payment if the lender quoted one, else annual_rate_percent (omit both for 0%).",
    inputSchema: {
      type: "object",
      properties: {
        amount: { type: "number", description: "Price or amount borrowed, in the household currency's major units." },
        months: { type: "integer", description: "Number of monthly payments." },
        annual_rate_percent: { type: "number", description: "Optional nominal annual interest rate in percent, e.g. 6.5." },
        monthly_payment: { type: "number", description: "Optional monthly payment quoted by the lender, in major units." },
      },
      required: ["amount", "months"],
    },
    readOnly: true,
  },
  {
    name: "early_settlement_saving",
    description:
      "Calculator. What settling an existing plan or loan early would cost and save: principal to pay off, interest saved and payments cancelled, on settle_date (default today). Does not change anything.",
    inputSchema: {
      type: "object",
      properties: {
        plan_id: { type: "string", description: "ID of the plan (from the plans list)." },
        settle_date: { type: "string", description: "Optional payoff date, YYYY-MM-DD (default today)." },
      },
      required: ["plan_id"],
    },
    readOnly: true,
  },
  {
    name: "emergency_runway",
    description:
      "Calculator. How many months a cash amount the user states would cover the household's average monthly spending, and its fixed spending only. Tally does not know cash balances; only call with an amount the user gave.",
    inputSchema: {
      type: "object",
      properties: {
        cash_amount: { type: "number", description: "Cash or savings amount in the household currency's major units." },
      },
      required: ["cash_amount"],
    },
    readOnly: true,
  },
  {
    name: "summarize_period",
    description:
      "Read-only. Totals for any date range: spending (by category with shares, by member, top merchants, per day), income and net, optionally for one category or member. Use this instead of adding up transactions yourself.",
    inputSchema: {
      type: "object",
      properties: {
        month: { type: "string", description: "A whole month, YYYY-MM (instead of start/end)." },
        start_date: { type: "string", description: "First day, YYYY-MM-DD." },
        end_date: { type: "string", description: "Last day, YYYY-MM-DD (default: today, or start_date's day if it is in the future)." },
        category: { type: "string", enum: ALL_CATEGORIES, description: "Optional category filter." },
        member: { type: "string", description: "Optional member filter: 'me', 'partner', or a member's display name." },
      },
      required: [],
    },
    readOnly: true,
  },
];

export const READ_TOOL_NAMES = new Set(READ_TOOLS.map((t) => t.name));

export function externalInstructions(currency: CurrencyCode, allowsChanges: boolean): string {
  return `Tally is a household budget tracker for a couple. These tools read the synced data in the Tally Cloud MCP server${
    allowsChanges ? " and can change it" : " (read-only: changes are turned off in Tally's settings)"
  }.
- Call get_overview first: it gives today's date, the members, category ids and the ids of goals and plans.
- Amounts are in ${currency} unless a figure says otherwise.
- Tally computes the figures. Take totals, averages, percentages, date ranges, loan maths and goal timelines from the tools (summarize_period, get_cash_flow_history, get_budget_adherence, get_debt_overview, get_savings_goals, plan_savings_goal, check_affordability, early_settlement_saving, emergency_runway) rather than adding up transactions yourself.
- Figures shown as "locked (salary hidden)" include salary, which the user is hiding. Do not estimate them or work them out from other figures. Only the user can reveal them, with the eye button in the Tally app.
- "not enough data" means Tally lacks the history for that figure; say so instead of guessing.${
    allowsChanges
      ? "\n- Changes are saved immediately and sync back to Tally on iPhone, iPad, and Mac. Confirm with the user before deleting anything."
      : ""
  }`;
}

// MARK: - Salary privacy

export function isSalaryTransaction(tx: TransactionRecord): boolean {
  return tx.type === "income" && tx.category === "salary";
}

// MARK: - Figure helpers

type AdviserFigure<T> =
  | { kind: "value"; value: T }
  | { kind: "insufficient"; reason: string }
  | { kind: "salaryLocked" };

function figValue<T>(value: T): AdviserFigure<T> {
  return { kind: "value", value };
}
function figInsufficient<T>(reason: string): AdviserFigure<T> {
  return { kind: "insufficient", reason };
}
function figLocked<T>(): AdviserFigure<T> {
  return { kind: "salaryLocked" };
}
function figMap<T, U>(fig: AdviserFigure<T>, fn: (v: T) => U): AdviserFigure<U> {
  if (fig.kind === "value") return figValue(fn(fig.value));
  return fig as AdviserFigure<U>;
}

function roundToStep(value: number, step: number): number {
  const s = Math.max(1, step);
  return Math.round(value / s) * s;
}

function roundUpToStep(value: number, step: number): number {
  const s = Math.max(1, step);
  return Math.ceil(value / s) * s;
}

function averageMinor(sum: number, count: number, step: number): number {
  if (count <= 0) return 0;
  return roundToStep(sum / count, step);
}

function calcPercent(part: number, whole: number): number | null {
  if (whole <= 0) return null;
  return Math.round((part / whole) * 1000) / 10;
}

function medianValue(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

function roundUpToTwoSignificant(minor: number): number {
  if (minor <= 0) return 0;
  const major = minor / 100;
  const exponent = Math.floor(Math.log10(major)) - 1;
  const stepMajor = Math.max(1, Math.pow(10, exponent));
  const roundedMajor = Math.ceil(major / stepMajor) * stepMajor;
  return Math.round(roundedMajor * 100);
}

function monthsBetween(fromMonth: string, toMonth: string): number | null {
  const a = parseMonthKey(fromMonth);
  const b = parseMonthKey(toMonth);
  if (!a || !b) return null;
  return b.year * 12 + b.month - (a.year * 12 + a.month);
}

// MARK: - Dataset & Cash Flow

interface MonthTotals {
  count: number;
  spendingMinor: number;
  incomeMinor: number;
  nonSalaryIncomeMinor: number;
  includesSalary: boolean;
  byCategory: Record<string, number>;
  planPaymentsMinor: number;
  fixedCategoryMinor: number;
}

function emptyMonthTotals(): MonthTotals {
  return {
    count: 0,
    spendingMinor: 0,
    incomeMinor: 0,
    nonSalaryIncomeMinor: 0,
    includesSalary: false,
    byCategory: {},
    planPaymentsMinor: 0,
    fixedCategoryMinor: 0,
  };
}

interface DataSet {
  transactions: TransactionRecord[];
  budgets: AdBudget[];
  goals: SavingsGoalRecord[];
  plans: InstallmentPlanRecord[];
  currency: CurrencyCode;
  todayKey: string;
  currentMonthKey: string;
  step: number;
  salaryHidden: boolean;
  monthTotals: Map<string, MonthTotals>;
  firstDataMonthKey: string | null;
}

type AdBudget = AdviserContext["budgets"][number];

function buildDataSet(ctx: AdviserContext): DataSet {
  const liveTx = ctx.transactions.filter(
    (tx) => !tx.isDeleted && tx.dayKey <= ctx.todayKey && isValidDayKey(tx.dayKey)
  );
  const liveBudgets = ctx.budgets.filter((b) => !b.isDeleted);
  const liveGoals = ctx.goals.filter((g) => !g.isDeleted);
  const livePlans = ctx.plans.filter((p) => !p.isDeleted);

  const monthTotals = new Map<string, MonthTotals>();
  let firstDataMonthKey: string | null = null;

  for (const tx of liveTx) {
    const mk = monthKeyFromDayKey(tx.dayKey);
    if (!firstDataMonthKey || mk < firstDataMonthKey) firstDataMonthKey = mk;
    let m = monthTotals.get(mk);
    if (!m) {
      m = emptyMonthTotals();
      monthTotals.set(mk, m);
    }
    m.count += 1;
    if (tx.type === "income") {
      m.incomeMinor += tx.amountMinor;
      if (isSalaryTransaction(tx)) {
        m.includesSalary = true;
      } else {
        m.nonSalaryIncomeMinor += tx.amountMinor;
      }
    } else {
      m.spendingMinor += tx.amountMinor;
      m.byCategory[tx.category] = (m.byCategory[tx.category] ?? 0) + tx.amountMinor;
      if (isPlanPayment(tx)) {
        m.planPaymentsMinor += tx.amountMinor;
      } else if (FIXED_CATEGORIES.has(tx.category)) {
        m.fixedCategoryMinor += tx.amountMinor;
      }
    }
  }

  return {
    transactions: liveTx,
    budgets: liveBudgets,
    goals: liveGoals,
    plans: livePlans,
    currency: ctx.currency,
    todayKey: ctx.todayKey,
    currentMonthKey: monthKeyFromDayKey(ctx.todayKey),
    step: roundingStep(ctx.currency),
    salaryHidden: ctx.salaryHidden,
    monthTotals,
    firstDataMonthKey,
  };
}

function gate<T>(data: DataSet, value: T, includesSalary: boolean): AdviserFigure<T> {
  return data.salaryHidden && includesSalary ? figLocked() : figValue(value);
}

function completeMonthKeys(data: DataSet, count = HISTORY_MONTHS): string[] {
  if (!data.firstDataMonthKey) return [];
  const current = data.currentMonthKey;
  const clampedCount = Math.max(1, Math.min(count, HISTORY_MONTHS));
  const windowStart = shiftMonth(current, -clampedCount);
  let key = windowStart > data.firstDataMonthKey ? windowStart : data.firstDataMonthKey;
  const keys: string[] = [];
  while (key < current && keys.length < HISTORY_MONTHS) {
    keys.push(key);
    const next = shiftMonth(key, 1);
    if (next <= key) break;
    key = next;
  }
  return keys;
}

function averagedMonthKeys(data: DataSet, count = HISTORY_MONTHS): string[] {
  return completeMonthKeys(data, count).filter((k) => (data.monthTotals.get(k)?.count ?? 0) > 0);
}

interface CashFlowComputed {
  months: Array<{
    monthKey: string;
    transactionCount: number;
    hasData: boolean;
    spendingMinor: number;
    income: AdviserFigure<number>;
    nonSalaryIncomeMinor: number;
    net: AdviserFigure<number>;
    savingsRatePercent: AdviserFigure<number>;
    spendingByCategory: Record<string, number>;
    fixedMinor: number;
    variableMinor: number;
    spendingChangeMinor: number | null;
  }>;
  monthsWithData: number;
  currentMonth: {
    monthKey: string;
    transactionCount: number;
    hasData: boolean;
    spendingMinor: number;
    income: AdviserFigure<number>;
    nonSalaryIncomeMinor: number;
    net: AdviserFigure<number>;
    savingsRatePercent: AdviserFigure<number>;
    spendingByCategory: Record<string, number>;
    fixedMinor: number;
    variableMinor: number;
  };
  daysElapsedInCurrentMonth: number;
  daysInCurrentMonth: number;
  averageSpendingMinor: AdviserFigure<number>;
  averageIncomeMinor: AdviserFigure<number>;
  averageNonSalaryIncomeMinor: AdviserFigure<number>;
  averageNetMinor: AdviserFigure<number>;
  averageSavingsRatePercent: AdviserFigure<number>;
  averageSpendingByCategory: AdviserFigure<Record<string, number>>;
  latestChange: AdviserFigure<{
    fromMonthKey: string;
    toMonthKey: string;
    spendingChangeMinor: number;
    spendingChangePercent: number | null;
    incomeChange: AdviserFigure<number>;
    netChange: AdviserFigure<number>;
  }>;
  movers: AdviserFigure<
    Array<{
      category: CategoryID;
      latestMinor: number;
      baselineAverageMinor: number;
      changeMinor: number;
      changePercent: number | null;
    }>
  >;
  fixedVariable: AdviserFigure<{
    averageFixedMinor: number;
    averagePlanPaymentsMinor: number;
    averageFixedCategoryMinor: number;
    averageVariableMinor: number;
    fixedSharePercent: number | null;
  }>;
  notes: string[];
}

function buildAdviserMonth(
  monthKey: string,
  data: DataSet,
  previous?: MonthTotals
) {
  const t = data.monthTotals.get(monthKey) ?? emptyMonthTotals();
  const fixedMinor = t.planPaymentsMinor + t.fixedCategoryMinor;
  let savingsRatePercent: AdviserFigure<number>;
  if (data.salaryHidden && t.includesSalary) {
    savingsRatePercent = figLocked();
  } else {
    const rate = calcPercent(t.incomeMinor - t.spendingMinor, t.incomeMinor);
    savingsRatePercent =
      rate !== null ? figValue(rate) : figInsufficient(`no income recorded in ${monthKey}`);
  }
  return {
    monthKey,
    transactionCount: t.count,
    hasData: t.count > 0,
    spendingMinor: t.spendingMinor,
    income: gate(data, t.incomeMinor, t.includesSalary),
    nonSalaryIncomeMinor: t.nonSalaryIncomeMinor,
    net: gate(data, t.incomeMinor - t.spendingMinor, t.includesSalary),
    savingsRatePercent,
    spendingByCategory: t.byCategory,
    fixedMinor,
    variableMinor: t.spendingMinor - fixedMinor,
    spendingChangeMinor:
      previous && previous.count > 0 && t.count > 0
        ? t.spendingMinor - previous.spendingMinor
        : null,
  };
}

function computeCashFlowHistory(data: DataSet, requested = HISTORY_MONTHS): CashFlowComputed {
  const keys = completeMonthKeys(data, requested);
  const months = keys.map((key, offset) =>
    buildAdviserMonth(
      key,
      data,
      offset > 0 ? data.monthTotals.get(keys[offset - 1]) ?? emptyMonthTotals() : undefined
    )
  );
  const averaged = keys.filter((k) => (data.monthTotals.get(k)?.count ?? 0) > 0);
  const currentMonth = buildAdviserMonth(data.currentMonthKey, data);
  const daysElapsed = dayOfMonth(data.todayKey);
  const daysInCurr = daysInMonth(data.currentMonthKey);

  const totals = averaged.map((k) => data.monthTotals.get(k) ?? emptyMonthTotals());
  const anySalary = totals.some((t) => t.includesSalary);
  const shortHistory = `only ${averaged.length} complete month(s) with transactions; averages need at least ${MIN_MONTHS_FOR_AVERAGE}`;
  const enough = averaged.length >= MIN_MONTHS_FOR_AVERAGE;

  let averageSpendingMinor: AdviserFigure<number>;
  let averageNonSalaryIncomeMinor: AdviserFigure<number>;
  let averageIncomeMinor: AdviserFigure<number>;
  let averageNetMinor: AdviserFigure<number>;
  let averageSavingsRatePercent: AdviserFigure<number>;
  let averageSpendingByCategory: AdviserFigure<Record<string, number>>;
  let fixedVariable: CashFlowComputed["fixedVariable"];

  if (enough) {
    const n = totals.length;
    const spending = totals.reduce((s, t) => s + t.spendingMinor, 0);
    const income = totals.reduce((s, t) => s + t.incomeMinor, 0);
    const nonSalary = totals.reduce((s, t) => s + t.nonSalaryIncomeMinor, 0);
    averageSpendingMinor = figValue(averageMinor(spending, n, data.step));
    averageNonSalaryIncomeMinor = figValue(averageMinor(nonSalary, n, data.step));
    averageIncomeMinor = gate(data, averageMinor(income, n, data.step), anySalary);
    averageNetMinor = gate(data, averageMinor(income - spending, n, data.step), anySalary);
    if (data.salaryHidden && anySalary) {
      averageSavingsRatePercent = figLocked();
    } else {
      const rate = calcPercent(income - spending, income);
      averageSavingsRatePercent =
        rate !== null ? figValue(rate) : figInsufficient("no income recorded in the averaged months");
    }
    const byCat: Record<string, number> = {};
    for (const cat of EXPENSE_CATEGORIES) {
      const sum = totals.reduce((s, t) => s + (t.byCategory[cat] ?? 0), 0);
      if (sum > 0) byCat[cat] = averageMinor(sum, n, data.step);
    }
    averageSpendingByCategory = figValue(byCat);
    const fixed = totals.reduce((s, t) => s + t.planPaymentsMinor + t.fixedCategoryMinor, 0);
    const plan = totals.reduce((s, t) => s + t.planPaymentsMinor, 0);
    const fixedCat = totals.reduce((s, t) => s + t.fixedCategoryMinor, 0);
    fixedVariable = figValue({
      averageFixedMinor: averageMinor(fixed, n, data.step),
      averagePlanPaymentsMinor: averageMinor(plan, n, data.step),
      averageFixedCategoryMinor: averageMinor(fixedCat, n, data.step),
      averageVariableMinor: averageMinor(spending - fixed, n, data.step),
      fixedSharePercent: calcPercent(fixed, spending),
    });
  } else {
    averageSpendingMinor = figInsufficient(shortHistory);
    averageNonSalaryIncomeMinor = figInsufficient(shortHistory);
    averageIncomeMinor =
      data.salaryHidden && anySalary ? figLocked() : figInsufficient(shortHistory);
    averageNetMinor =
      data.salaryHidden && anySalary ? figLocked() : figInsufficient(shortHistory);
    averageSavingsRatePercent =
      data.salaryHidden && anySalary ? figLocked() : figInsufficient(shortHistory);
    averageSpendingByCategory = figInsufficient(shortHistory);
    fixedVariable = figInsufficient(shortHistory);
  }

  let latestChange: CashFlowComputed["latestChange"];
  if (keys.length >= 2) {
    const last = keys[keys.length - 1];
    const prior = keys[keys.length - 2];
    const a = data.monthTotals.get(prior) ?? emptyMonthTotals();
    const b = data.monthTotals.get(last) ?? emptyMonthTotals();
    if (a.count > 0 && b.count > 0) {
      const locked = a.includesSalary || b.includesSalary;
      latestChange = figValue({
        fromMonthKey: prior,
        toMonthKey: last,
        spendingChangeMinor: b.spendingMinor - a.spendingMinor,
        spendingChangePercent: calcPercent(b.spendingMinor - a.spendingMinor, a.spendingMinor),
        incomeChange: gate(data, b.incomeMinor - a.incomeMinor, locked),
        netChange: gate(
          data,
          b.incomeMinor - b.spendingMinor - (a.incomeMinor - a.spendingMinor),
          locked
        ),
      });
    } else {
      latestChange = figInsufficient(`${a.count === 0 ? prior : last} has no transactions`);
    }
  } else {
    latestChange = figInsufficient(`needs two complete months; ${keys.length} available`);
  }

  let movers: CashFlowComputed["movers"];
  const latestKey = averaged[averaged.length - 1];
  if (!latestKey) {
    movers = figInsufficient("no complete month with transactions");
  } else {
    const baselineKeys = averaged.slice(0, -1);
    if (baselineKeys.length < MIN_BASELINE_MONTHS_FOR_MOVERS) {
      movers = figInsufficient(
        `needs ${MIN_BASELINE_MONTHS_FOR_MOVERS} earlier complete months with transactions before ${latestKey}; ${baselineKeys.length} available`
      );
    } else {
      const latestMap = data.monthTotals.get(latestKey)?.byCategory ?? {};
      const baselineMaps = baselineKeys.map((k) => data.monthTotals.get(k)?.byCategory ?? {});
      const list = EXPENSE_CATEGORIES.map((category) => {
        const sum = baselineMaps.reduce((s, m) => s + (m[category] ?? 0), 0);
        const latestMinor = latestMap[category] ?? 0;
        const baselineAverageMinor = averageMinor(sum, baselineMaps.length, data.step);
        const changeMinor = latestMinor - baselineAverageMinor;
        return {
          category,
          latestMinor,
          baselineAverageMinor,
          changeMinor,
          changePercent: calcPercent(changeMinor, baselineAverageMinor),
        };
      }).filter((m) => m.changeMinor !== 0);
      list.sort((a, b) => {
        const da = Math.abs(a.changeMinor);
        const db = Math.abs(b.changeMinor);
        if (da !== db) return db - da;
        return EXPENSE_CATEGORIES.indexOf(a.category) - EXPENSE_CATEGORIES.indexOf(b.category);
      });
      movers = figValue(list.slice(0, MOVERS_LIMIT));
    }
  }

  const notes: string[] = [];
  if (!data.firstDataMonthKey) {
    notes.push("No transactions recorded yet.");
  } else if (keys.length === 0) {
    notes.push(`No complete month yet: history starts in the current month ${data.currentMonthKey}.`);
  } else {
    notes.push(
      `History: ${averaged.length} complete month(s) with transactions between ${keys[0]} and ${keys[keys.length - 1]}.`
    );
  }
  const empty = keys.filter((k) => (data.monthTotals.get(k)?.count ?? 0) === 0);
  if (empty.length > 0) {
    notes.push(`Months with no transactions (excluded from averages): ${empty.join(", ")}.`);
  }
  notes.push(
    `Current month ${data.currentMonthKey} is month-to-date (day ${daysElapsed} of ${daysInCurr}) and not averaged.`
  );
  notes.push(AVERAGES_RULE);

  return {
    months,
    monthsWithData: averaged.length,
    currentMonth,
    daysElapsedInCurrentMonth: daysElapsed,
    daysInCurrentMonth: daysInCurr,
    averageSpendingMinor,
    averageIncomeMinor,
    averageNonSalaryIncomeMinor,
    averageNetMinor,
    averageSavingsRatePercent,
    averageSpendingByCategory,
    latestChange,
    movers,
    fixedVariable,
    notes,
  };
}

// MARK: - Debt

function computeDebtOverview(data: DataSet, history?: CashFlowComputed) {
  const h = history ?? computeCashFlowHistory(data);
  const livePlans = data.plans.filter((p) => !p.isDeleted);
  const entries = livePlans
    .map((p) => ({ plan: p, progress: computeProgress(p, data.todayKey) }))
    .filter((e) => !e.progress.isCompleted)
    .sort((a, b) => {
      const da = a.progress.nextPayment?.dayKey ?? null;
      const db = b.progress.nextPayment?.dayKey ?? null;
      if (da && db && da !== db) return da < db ? -1 : 1;
      if (da && !db) return -1;
      if (!da && db) return 1;
      return a.plan.name.localeCompare(b.plan.name, undefined, { sensitivity: "base" });
    });

  const figures = entries.map(({ plan, progress }) => ({
    planID: plan.id,
    name: plan.name,
    kind: plan.kind,
    lender: plan.lender || null,
    currency: plan.currency,
    nextPaymentMinor: progress.nextPayment?.amountMinor ?? 0,
    nextPaymentDayKey: progress.nextPayment?.dayKey ?? null,
    lastPaymentDayKey: earlyLastPaymentDay(plan),
    remainingPayments: progress.paymentCount - progress.paidCount,
    remainingScheduledMinor: progress.remainingMinor,
    outstandingPrincipalMinor: progress.outstandingPrincipalMinor,
    effectiveAnnualRatePercent: Math.round(effectiveAnnualRate(plan) * 10000) / 100,
    interestRemainingMinor: progress.interestRemainingMinor,
    settleToday: earlySettlementCompute(plan, data.todayKey, data.todayKey),
  }));

  const totalRemainingScheduledMinor = figures.reduce((s, p) => s + p.remainingScheduledMinor, 0);
  const totalOutstandingPrincipalMinor = figures.reduce((s, p) => s + p.outstandingPrincipalMinor, 0);
  const totalInterestRemainingMinor = figures.reduce((s, p) => s + p.interestRemainingMinor, 0);
  const monthlyDebtServiceMinor = figures.reduce((s, p) => s + p.nextPaymentMinor, 0);

  const ratioFigure = (incomeFig: AdviserFigure<number>): AdviserFigure<number> => {
    if (incomeFig.kind !== "value") return incomeFig as AdviserFigure<number>;
    const pct = calcPercent(monthlyDebtServiceMinor, incomeFig.value);
    return pct !== null ? figValue(pct) : figInsufficient("average monthly income is 0");
  };

  const highestRateFirst = [...figures]
    .sort((a, b) => {
      if (a.effectiveAnnualRatePercent !== b.effectiveAnnualRatePercent) {
        return b.effectiveAnnualRatePercent - a.effectiveAnnualRatePercent;
      }
      if (a.outstandingPrincipalMinor !== b.outstandingPrincipalMinor) {
        return b.outstandingPrincipalMinor - a.outstandingPrincipalMinor;
      }
      return a.name < b.name ? -1 : 1;
    })
    .map((p) => p.planID);

  const smallestBalanceFirst = [...figures]
    .sort((a, b) => {
      if (a.outstandingPrincipalMinor !== b.outstandingPrincipalMinor) {
        return a.outstandingPrincipalMinor - b.outstandingPrincipalMinor;
      }
      if (a.effectiveAnnualRatePercent !== b.effectiveAnnualRatePercent) {
        return b.effectiveAnnualRatePercent - a.effectiveAnnualRatePercent;
      }
      return a.name < b.name ? -1 : 1;
    })
    .map((p) => p.planID);

  const notes = [DEBT_SERVICE_RULE, PAYOFF_RULE];
  if (figures.length === 0) notes.unshift("No active installment plans or loans.");
  if (figures.some((f) => f.currency !== data.currency)) {
    notes.push("Some plans are in another currency; totals add their amounts as recorded.");
  }

  return {
    plans: figures,
    totalRemainingScheduledMinor,
    totalOutstandingPrincipalMinor,
    totalInterestRemainingMinor,
    monthlyDebtServiceMinor,
    averageIncomeMinor: h.averageIncomeMinor,
    debtServiceToIncomePercent: ratioFigure(h.averageIncomeMinor),
    highestRateFirst,
    smallestBalanceFirst,
    notes,
  };
}

function earlyLastPaymentDay(plan: InstallmentPlanRecord): string | null {
  const sched = planSchedule(plan);
  return sched.length > 0 ? sched[sched.length - 1].dayKey : null;
}

// MARK: - Rendering helpers

class Renderer {
  currency: CurrencyCode;
  locked = false;

  constructor(currency: CurrencyCode) {
    this.currency = currency;
  }

  money(minor: number, currency?: CurrencyCode): string {
    return formatMoney(minor, currency ?? this.currency);
  }

  signed(minor: number, currency?: CurrencyCode): string {
    return formatMoney(minor, currency ?? this.currency, { signed: true });
  }

  percent(value: number): string {
    return `${value.toFixed(1)}%`;
  }

  optionalPercent(value: number | null): string {
    return value !== null ? this.percent(value) : "n/a (base is 0)";
  }

  fig<T, U>(f: AdviserFigure<T>, mapFn: (v: T) => U): U | string {
    if (f.kind === "value") return mapFn(f.value);
    if (f.kind === "insufficient") return `not enough data: ${f.reason}`;
    this.locked = true;
    return LOCKED_TEXT;
  }

  figMoney(f: AdviserFigure<number>): string {
    return this.fig(f, (v) => this.money(v));
  }

  figPercent(f: AdviserFigure<number>): string {
    return this.fig(f, (v) => this.percent(v));
  }
}

function renderOutput(r: Renderer, obj: Record<string, unknown>): MCPToolResult {
  if (r.locked) {
    obj.salary_locked =
      "Figures marked 'locked' include salary, which stays hidden for this message (access was already requested). Do not estimate them or work them out from other figures; answer with the unlocked figures only.";
  }
  return { text: JSON.stringify(obj), isError: false };
}

function errorResult(message: string): MCPToolResult {
  return { text: `Error: ${message}`, isError: true };
}

function resolveMember(hint: string, ctx: AdviserContext): string | null {
  const lowered = hint.toLowerCase();
  if (lowered === "me") return ctx.currentMemberID;
  if (lowered === "partner") {
    return ctx.members.find((m) => m.id !== ctx.currentMemberID)?.id ?? null;
  }
  const match = ctx.members.find(
    (m) => m.name.toLowerCase() === lowered || m.id.toLowerCase() === lowered
  );
  if (match) return match.id;
  return (
    ctx.transactions.find((tx) => !tx.isDeleted && tx.memberName.toLowerCase() === lowered)
      ?.memberID ?? null
  );
}

export function matchGoal(
  id: string | null,
  name: string | null,
  goals: SavingsGoalRecord[]
): SavingsGoalRecord | null {
  const live = goals.filter((g) => !g.isDeleted);
  if (id) {
    const exact = live.find((g) => g.id === id);
    if (exact) return exact;
  }
  if (!name) return null;
  const needle = name.trim().toLowerCase();
  if (!needle) return null;
  const exact = live.find((g) => g.name.toLowerCase() === needle);
  if (exact) return exact;
  return (
    live.find(
      (g) => g.name.toLowerCase().includes(needle) || needle.includes(g.name.toLowerCase())
    ) ?? null
  );
}

function trimStr(val: unknown): string | null {
  if (typeof val !== "string") return null;
  const s = val.trim();
  return s.length > 0 ? s : null;
}

function wholeNum(
  val: unknown,
  field: string
): { ok: true; value: number | null } | { ok: false; error: string } {
  if (val === undefined || val === null) return { ok: true, value: null };
  if (
    typeof val !== "number" ||
    !Number.isFinite(val) ||
    !Number.isInteger(val) ||
    val < 0 ||
    val > 2_147_483_647
  ) {
    return { ok: false, error: `${field} must be a whole number` };
  }
  return { ok: true, value: val };
}

function moneyArg(
  val: unknown,
  field: string,
  currency: CurrencyCode,
  allowZero = false
): { ok: true; value: number | null } | { ok: false; error: string } {
  if (val === undefined || val === null) return { ok: true, value: null };
  if (
    typeof val !== "number" ||
    !Number.isFinite(val) ||
    !(allowZero ? val >= 0 : val > 0) ||
    val >= MAX_PLAN_AMOUNT_MINOR / 100
  ) {
    return {
      ok: false,
      error: `${field} must be a ${allowZero ? "non-negative" : "positive"} number`,
    };
  }
  return { ok: true, value: toStorageMinor(val, currency) };
}

function folded(text: string): string {
  return text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D")
    .toLowerCase();
}

export function snapshotLines(data: DataSet): string[] {
  const h = computeCashFlowHistory(data);
  const d = computeDebtOverview(data, h);
  const r = new Renderer(data.currency);
  const lines: string[] = [];
  if (h.monthsWithData === 0) {
    lines.push("- History: no complete month with transactions yet.");
  } else {
    lines.push(
      `- History: ${h.monthsWithData} complete month(s) with transactions; current month day ${h.daysElapsedInCurrentMonth} of ${h.daysInCurrentMonth}.`
    );
  }
  lines.push(
    `- Average monthly spending: ${r.figMoney(h.averageSpendingMinor)}; average income: ${r.figMoney(h.averageIncomeMinor)}; average net: ${r.figMoney(h.averageNetMinor)}; average savings rate: ${r.figPercent(h.averageSavingsRatePercent)}.`
  );
  if (d.plans.length === 0) {
    lines.push("- Active plans & loans: none.");
  } else {
    lines.push(
      `- Active plans & loans: ${d.plans.length}; monthly debt service ${r.money(d.monthlyDebtServiceMinor)}; debt-service-to-income ${r.figPercent(d.debtServiceToIncomePercent)}.`
    );
  }
  if (r.locked) {
    lines.push(
      "- Figures marked locked include salary, which the user hides on this device (see the salary rules)."
    );
  }
  return lines;
}

// MARK: - Tool dispatch

export function runReadTool(
  name: string,
  args: Record<string, unknown>,
  ctx: AdviserContext
): MCPToolResult | null {
  if (!READ_TOOL_NAMES.has(name)) return null;
  const data = buildDataSet(ctx);
  const r = new Renderer(data.currency);

  switch (name) {
    case "get_overview": {
      const sections: string[] = [];
      sections.push(`Tally household budget. Currency: ${data.currency}.`);
      sections.push(dateContextLines(data.todayKey).join("\n"));

      const memberLines = ctx.members.map(
        (m) => `- ${m.name}${m.id === ctx.currentMemberID ? ' ("me": the primary user)' : ""}`
      );
      sections.push(
        "Household members:\n" + (memberLines.length ? memberLines.join("\n") : "- none recorded")
      );
      sections.push(
        `Categories (ids):\n- expense: ${EXPENSE_CATEGORIES.join(", ")}\n- income: salary, freelance, income`
      );
      sections.push(
        "Snapshot (computed by Tally; call the tools for details):\n" +
          snapshotLines(data).join("\n")
      );

      const goalLines = data.goals.map((g) => {
        const pct = g.targetMinor > 0 ? Math.floor((g.savedMinor * 100) / g.targetMinor) : 0;
        const needed = Math.max(0, g.targetMinor - g.savedMinor);
        return `- [id:${g.id}] ${g.name}: ${r.money(g.savedMinor)} / ${r.money(g.targetMinor)} (${pct}%), still needed ${r.money(needed)}`;
      });
      sections.push("Savings goals:\n" + (goalLines.length ? goalLines.join("\n") : "- none"));

      const planLines = planContextLines(data.plans, data.todayKey, data.currency);
      sections.push(
        "Installment plans & loans (paid = payments made so far, remaining = scheduled payments still to come):\n" +
          (planLines.length ? planLines.join("\n") : "- none")
      );

      const days = data.transactions.map((t) => t.dayKey);
      if (days.length > 0) {
        const minDay = days.reduce((a, b) => (a < b ? a : b));
        const maxDay = days.reduce((a, b) => (a > b ? a : b));
        sections.push(`Transactions on record: ${days.length}, from ${minDay} to ${maxDay}.`);
      } else {
        sections.push("Transactions on record: none.");
      }

      sections.push(
        data.salaryHidden
          ? `Salary: hidden by the user. Salary transactions are left out of list_transactions and figures that include salary read "${LOCKED_TEXT}".`
          : "Salary: visible."
      );
      return { text: sections.join("\n\n"), isError: false };
    }

    case "list_transactions": {
      let startDayKey: string | null = null;
      let endDayKey: string | null = null;
      const month = trimStr(args.month);
      if (month) {
        if (month.length !== 7 || !parseMonthKey(month)) {
          return errorResult("month must be YYYY-MM");
        }
        const range = dayRangeForMonth(month);
        startDayKey = range.start;
        endDayKey = range.end;
      } else {
        const s = trimStr(args.start_date);
        if (s) {
          if (!isValidDayKey(s)) {
            return errorResult("start_date must be a valid date in YYYY-MM-DD format");
          }
          startDayKey = s;
        }
        const e = trimStr(args.end_date);
        if (e) {
          if (!isValidDayKey(e)) {
            return errorResult("end_date must be a valid date in YYYY-MM-DD format");
          }
          endDayKey = e;
        }
        if (startDayKey && endDayKey && startDayKey > endDayKey) {
          return errorResult("start_date must not be after end_date");
        }
      }

      let categoryFilter: CategoryID | null = null;
      const rawCat = trimStr(args.category);
      if (rawCat) {
        const lc = rawCat.toLowerCase() as CategoryID;
        if (!ALL_CATEGORIES.includes(lc)) {
          return errorResult(`category must be one of: ${ALL_CATEGORIES.join(", ")}`);
        }
        categoryFilter = lc;
      }

      let typeFilter: TransactionType | null = null;
      const rawType = trimStr(args.type);
      if (rawType) {
        const lt = rawType.toLowerCase();
        if (lt !== "expense" && lt !== "income") {
          return errorResult("type must be expense or income");
        }
        typeFilter = lt;
      }

      let memberFilter: string | null = null;
      const rawMember = trimStr(args.member);
      if (rawMember) {
        const resolved = resolveMember(rawMember, ctx);
        if (!resolved) return errorResult(`no household member matches '${rawMember}'`);
        memberFilter = resolved;
      }

      const rawSearch = trimStr(args.search);
      const needle = rawSearch ? folded(rawSearch) : null;

      const limitRes = wholeNum(args.limit, "limit");
      if (!limitRes.ok) return errorResult("limit must be a whole number from 1 to 500");
      if (limitRes.value !== null && limitRes.value < 1) {
        return errorResult(`limit must be a whole number from 1 to ${MAX_LIMIT}`);
      }
      const limit = Math.min(limitRes.value ?? DEFAULT_LIMIT, MAX_LIMIT);

      const offsetRes = wholeNum(args.offset, "offset");
      if (!offsetRes.ok) return errorResult("offset must be a whole number, 0 or more");
      const offset = offsetRes.value ?? 0;

      const matching = data.transactions.filter((tx) => {
        if (startDayKey && tx.dayKey < startDayKey) return false;
        if (endDayKey && tx.dayKey > endDayKey) return false;
        if (categoryFilter && tx.category !== categoryFilter) return false;
        if (typeFilter && tx.type !== typeFilter) return false;
        if (memberFilter && tx.memberID !== memberFilter) return false;
        if (needle) {
          const origFmt =
            tx.originalAmountMinor != null && tx.originalCurrencyCode
              ? formatMoney(tx.originalAmountMinor, tx.originalCurrencyCode)
              : "";
          if (
            !folded(tx.name).includes(needle) &&
            !folded(tx.note).includes(needle) &&
            !folded(tx.originalCurrencyCode ?? "").includes(needle) &&
            !folded(origFmt).includes(needle)
          ) {
            return false;
          }
        }
        return true;
      });

      const visible = (
        data.salaryHidden ? matching.filter((tx) => !isSalaryTransaction(tx)) : matching
      ).sort((a, b) => {
        if (a.dayKey !== b.dayKey) return a.dayKey > b.dayKey ? -1 : 1;
        return a.createdAt > b.createdAt ? -1 : a.createdAt < b.createdAt ? 1 : 0;
      });

      const page = visible.slice(offset, offset + limit);
      const rows = page.map((tx) => {
        const signedMinor = tx.type === "income" ? tx.amountMinor : -tx.amountMinor;
        const row: Record<string, unknown> = {
          id: tx.id,
          date: tx.dayKey,
          name: tx.name,
          amount: formatMoney(signedMinor, data.currency, { signed: tx.type === "income" }),
          amount_value: toMajor(tx.amountMinor),
          type: tx.type,
          category: tx.category,
        };
        if (tx.memberName) row.member = tx.memberName;
        if (tx.note) row.note = tx.note;
        if (tx.originalAmountMinor != null && tx.originalCurrencyCode) {
          row.original_currency = tx.originalCurrencyCode;
          row.original_amount = formatMoney(tx.originalAmountMinor, tx.originalCurrencyCode);
          row.original_amount_value = toMajor(tx.originalAmountMinor);
          if (tx.exchangeRate != null) row.exchange_rate = tx.exchangeRate;
        }
        if (tx.needsReview) row.needs_review = true;
        if (tx.planID) row.plan_id = tx.planID;
        return row;
      });

      const payload: Record<string, unknown> = {
        total_matching: visible.length,
        returned: rows.length,
        offset,
        transactions: rows,
      };
      const nextOffset = offset + rows.length;
      if (nextOffset < visible.length) payload.next_offset = nextOffset;
      if (visible.length !== matching.length) {
        payload.salary_hidden =
          "Salary transactions in this range are left out because the user hides salary. Do not estimate them; only the user can reveal them, with the eye button in the Tally app.";
      }
      return { text: JSON.stringify(payload), isError: false };
    }

    case "get_cash_flow_history": {
      const mRes = wholeNum(args.months, "months");
      if (!mRes.ok) return errorResult(mRes.error);
      const n = mRes.value ?? HISTORY_MONTHS;
      if (n < 1 || n > HISTORY_MONTHS) {
        return errorResult(`months must be 1-${HISTORY_MONTHS}`);
      }
      const h = computeCashFlowHistory(data, n);
      const renderMonth = (m: CashFlowComputed["months"][number]) => {
        const obj: Record<string, unknown> = {
          month: m.monthKey,
          transactions: m.transactionCount,
        };
        if (!m.hasData) {
          obj.note = "no transactions";
          return obj;
        }
        obj.spending = r.money(m.spendingMinor);
        obj.income = r.figMoney(m.income);
        obj.income_excluding_salary = r.money(m.nonSalaryIncomeMinor);
        obj.net = r.figMoney(m.net);
        obj.savings_rate = r.figPercent(m.savingsRatePercent);
        obj.fixed = r.money(m.fixedMinor);
        obj.variable = r.money(m.variableMinor);
        if (m.spendingChangeMinor !== null) {
          obj.spending_change_vs_previous_month = r.signed(m.spendingChangeMinor);
        }
        const cats = Object.entries(m.spendingByCategory)
          .filter(([, v]) => v > 0)
          .sort((a, b) => b[1] - a[1]);
        obj.spending_by_category = Object.fromEntries(cats.map(([k, v]) => [k, r.money(v)]));
        return obj;
      };

      const curr = renderMonth({ ...h.currentMonth, spendingChangeMinor: null });
      curr.days_elapsed = `${h.daysElapsedInCurrentMonth} of ${h.daysInCurrentMonth}`;
      delete curr.spending_change_vs_previous_month;

      return renderOutput(r, {
        complete_months_listed: h.months.length,
        complete_months_with_transactions: h.monthsWithData,
        months: h.months.map(renderMonth),
        current_month_to_date: curr,
        averages: {
          spending: r.figMoney(h.averageSpendingMinor),
          income: r.figMoney(h.averageIncomeMinor),
          income_excluding_salary: r.figMoney(h.averageNonSalaryIncomeMinor),
          net: r.figMoney(h.averageNetMinor),
          savings_rate: r.figPercent(h.averageSavingsRatePercent),
          spending_by_category: r.fig(h.averageSpendingByCategory, (dict) =>
            Object.fromEntries(Object.entries(dict).map(([k, v]) => [k, r.money(v)]))
          ),
        },
        latest_month_change: r.fig(h.latestChange, (c) => ({
          from: c.fromMonthKey,
          to: c.toMonthKey,
          spending_change: r.signed(c.spendingChangeMinor),
          spending_change_percent: r.optionalPercent(c.spendingChangePercent),
          income_change: r.fig(c.incomeChange, (v) => r.signed(v)),
          net_change: r.fig(c.netChange, (v) => r.signed(v)),
        })),
        top_category_movers: r.fig(h.movers, (movers) =>
          movers.length === 0
            ? "no category changed"
            : movers.map((m) => ({
                category: m.category,
                latest_month: r.money(m.latestMinor),
                earlier_average: r.money(m.baselineAverageMinor),
                change: r.signed(m.changeMinor),
                change_percent: r.optionalPercent(m.changePercent),
              }))
        ),
        fixed_vs_variable: r.fig(h.fixedVariable, (s) => ({
          average_fixed: r.money(s.averageFixedMinor),
          of_which_plan_payments: r.money(s.averagePlanPaymentsMinor),
          of_which_housing_and_bills: r.money(s.averageFixedCategoryMinor),
          average_variable: r.money(s.averageVariableMinor),
          fixed_share_of_spending: r.optionalPercent(s.fixedSharePercent),
        })),
        notes: [...h.notes, SAVINGS_RATE_RULE, FIXED_RULE, MOVERS_RULE],
      });
    }

    case "get_debt_overview": {
      const d = computeDebtOverview(data);
      const byID = new Map(d.plans.map((p) => [p.planID, p]));
      const ranking = (ids: string[]) =>
        ids
          .map((id, idx) => {
            const p = byID.get(id);
            if (!p) return null;
            return `${idx + 1}. [id:${id}] ${p.name}: rate ${p.effectiveAnnualRatePercent.toFixed(2)}%, outstanding principal ${formatMoney(p.outstandingPrincipalMinor, p.currency)}`;
          })
          .filter(Boolean);

      return renderOutput(r, {
        active_plans: d.plans.map((p) => {
          const obj: Record<string, unknown> = {
            plan_id: p.planID,
            name: p.name,
            kind: p.kind,
            monthly_payment: r.money(p.nextPaymentMinor, p.currency),
            payments_left: p.remainingPayments,
            scheduled_payments_left: r.money(p.remainingScheduledMinor, p.currency),
            outstanding_principal: r.money(p.outstandingPrincipalMinor, p.currency),
            effective_annual_rate: `${p.effectiveAnnualRatePercent.toFixed(2)}%`,
            interest_still_to_pay: r.money(p.interestRemainingMinor, p.currency),
            settle_today: p.settleToday.ok
              ? {
                  principal_to_pay_off: r.money(p.settleToday.value.payoffPrincipalMinor, p.currency),
                  interest_saved: r.money(p.settleToday.value.interestSavedMinor, p.currency),
                }
              : `not enough data: ${p.settleToday.reason}`,
          };
          if (p.nextPaymentDayKey) obj.next_payment_date = p.nextPaymentDayKey;
          if (p.lastPaymentDayKey) obj.last_payment_date = p.lastPaymentDayKey;
          if (p.lender) obj.lender = p.lender;
          return obj;
        }),
        totals: {
          scheduled_payments_left: r.money(d.totalRemainingScheduledMinor),
          outstanding_principal: r.money(d.totalOutstandingPrincipalMinor),
          interest_still_to_pay: r.money(d.totalInterestRemainingMinor),
          monthly_debt_service: r.money(d.monthlyDebtServiceMinor),
        },
        average_monthly_income: r.figMoney(d.averageIncomeMinor),
        debt_service_to_income: r.figPercent(d.debtServiceToIncomePercent),
        payoff_order_highest_rate_first: ranking(d.highestRateFirst),
        payoff_order_smallest_balance_first: ranking(d.smallestBalanceFirst),
        notes: d.notes,
      });
    }

    case "get_budget_adherence": {
      let only: CategoryID | null = null;
      const rawCat = trimStr(args.category);
      if (rawCat) {
        if (!EXPENSE_CATEGORIES.includes(rawCat as CategoryID)) {
          return errorResult(`category must be one of ${EXPENSE_CATEGORIES.join(", ")}`);
        }
        only = rawCat as CategoryID;
      }

      const mk = data.currentMonthKey;
      const elapsed = dayOfMonth(data.todayKey);
      const totalDays = daysInMonth(mk);
      const current = data.monthTotals.get(mk) ?? emptyMonthTotals();
      const thisMonthBudgets = new Map<CategoryID, number>();
      for (const b of data.budgets) {
        if (b.monthKey === mk && !thisMonthBudgets.has(b.category)) {
          thisMonthBudgets.set(b.category, b.limitMinor);
        }
      }
      const averaged = averagedMonthKeys(data);
      const budgetsByMonth = new Map<string, AdBudget[]>();
      for (const b of data.budgets) {
        const list = budgetsByMonth.get(b.monthKey) ?? [];
        list.push(b);
        budgetsByMonth.set(b.monthKey, list);
      }

      const categories: Array<Record<string, unknown> & { _hasLimit: boolean; _spent: number }> = [];
      let totalLimitMinor = 0;
      let totalSpentInBudgeted = 0;

      for (const cat of EXPENSE_CATEGORIES) {
        if (only && only !== cat) continue;
        const limit = thisMonthBudgets.get(cat) ?? null;
        const spent = current.byCategory[cat] ?? 0;
        const history = averaged.map((k) => data.monthTotals.get(k)?.byCategory[cat] ?? 0);
        const hasHistory = history.some((v) => v > 0);
        if (limit === null && spent === 0 && !hasHistory && !only) continue;

        let monthsWithBudget = 0;
        let monthsOver = 0;
        for (const k of averaged) {
          const b = budgetsByMonth.get(k)?.find((x) => x.category === cat);
          if (!b) continue;
          monthsWithBudget += 1;
          if ((data.monthTotals.get(k)?.byCategory[cat] ?? 0) > b.limitMinor) monthsOver += 1;
        }
        const projected = elapsed > 0 ? roundToStep((spent * totalDays) / elapsed, data.step) : spent;

        let suggestionText: string;
        if (averaged.length >= MIN_MONTHS_FOR_SUGGESTED_LIMIT) {
          const med = roundToStep(medianValue(history), data.step);
          if (med > 0) {
            const suggested = roundUpToTwoSignificant(med);
            suggestionText = `${r.money(suggested)} (median ${r.money(med)} over ${averaged.length} months)`;
          } else {
            suggestionText = `not enough data: median monthly spending in ${cat} is 0`;
          }
        } else {
          suggestionText = `not enough data: needs ${MIN_MONTHS_FOR_SUGGESTED_LIMIT} complete months with transactions; ${averaged.length} available`;
        }

        const row: Record<string, unknown> & { _hasLimit: boolean; _spent: number } = {
          _hasLimit: limit !== null,
          _spent: spent,
          category: cat,
          spent_this_month: r.money(spent),
          projected_month_end: r.money(projected),
          suggested_limit_statistic: suggestionText,
        };
        if (limit !== null) {
          totalLimitMinor += limit;
          totalSpentInBudgeted += spent;
          const pct = calcPercent(spent, limit);
          row.limit = r.money(limit);
          row.remaining = r.money(limit - spent);
          row.percent_used = r.optionalPercent(pct);
          row.status =
            spent > limit ? "over" : pct !== null && pct >= NEAR_LIMIT_PERCENT ? "near" : "under";
          row.projected_over_limit = projected > limit;
          row.recent_months_above_this_limit = `${history.filter((v) => v > limit).length} of ${averaged.length}`;
        } else {
          row.limit = "no budget this month";
        }
        if (monthsWithBudget > 0) {
          row.recent_months_over_their_budget = `${monthsOver} of ${monthsWithBudget} months that had a budget`;
        }
        categories.push(row);
      }

      categories.sort((a, b) => {
        if (a._hasLimit !== b._hasLimit) return a._hasLimit ? -1 : 1;
        return b._spent - a._spent;
      });
      const renderedCats = categories.map(({ _hasLimit, _spent, ...rest }) => {
        void _hasLimit;
        void _spent;
        return rest;
      });

      const notes = [
        `Month-to-date for ${mk}: day ${elapsed} of ${totalDays}.`,
        PROJECTION_RULE,
        SUGGESTED_LIMIT_RULE,
      ];
      if (thisMonthBudgets.size === 0) notes.unshift(`No budgets are set for ${mk}.`);
      if (averaged.length < MIN_MONTHS_FOR_SUGGESTED_LIMIT) {
        notes.push(
          `Only ${averaged.length} complete month(s) with transactions, so history-based figures are limited.`
        );
      }

      return renderOutput(r, {
        month: mk,
        days_elapsed: `${elapsed} of ${totalDays}`,
        categories: renderedCats,
        total_limit: r.money(totalLimitMinor),
        total_spent_in_budgeted_categories: r.money(totalSpentInBudgeted),
        notes,
      });
    }

    case "get_savings_goals": {
      const h = computeCashFlowHistory(data);
      const outlooks = data.goals.map((g) => goalOutlook(g, data, h));
      return renderOutput(r, {
        goals: outlooks.length === 0 ? "no savings goals" : outlooks.map((o) => renderGoalOutlook(o, r)),
        average_monthly_net_saving: r.figMoney(h.averageNetMinor),
        notes: [GOAL_PACE_RULE, AVERAGES_RULE],
      });
    }

    case "plan_savings_goal": {
      const goalID = trimStr(args.goal_id);
      const goalName = trimStr(args.goal_name);
      const tRes = moneyArg(args.target_amount, "target_amount", data.currency);
      if (!tRes.ok) return errorResult(tRes.error);
      const sRes = moneyArg(args.saved_amount, "saved_amount", data.currency, true);
      if (!sRes.ok) return errorResult(sRes.error);
      const cRes = moneyArg(args.monthly_contribution, "monthly_contribution", data.currency);
      if (!cRes.ok) return errorResult(cRes.error);

      let targetMonthKey: string | null = null;
      const rawDate = trimStr(args.target_date);
      if (rawDate) {
        targetMonthKey = monthKeyFromDateOrMonthInput(rawDate);
        if (!targetMonthKey) return errorResult("target_date must be YYYY-MM or YYYY-MM-DD");
      }

      if (!goalID && !goalName && tRes.value === null) {
        return errorResult(
          "give goal_id or goal_name for an existing goal, or target_amount for a hypothetical one"
        );
      }

      const h = computeCashFlowHistory(data);
      let gRecord: { id: string | null; name: string; targetMinor: number; savedMinor: number };
      if (goalID || goalName) {
        const matched = matchGoal(goalID, goalName, data.goals);
        if (!matched) {
          return errorResult(
            "no savings goal matches; use an id from the goals list, or pass target_amount for a hypothetical goal"
          );
        }
        gRecord = {
          id: matched.id,
          name: matched.name,
          targetMinor: tRes.value ?? matched.targetMinor,
          savedMinor: sRes.value ?? matched.savedMinor,
        };
      } else {
        gRecord = {
          id: null,
          name: "hypothetical goal",
          targetMinor: tRes.value!,
          savedMinor: sRes.value ?? 0,
        };
      }

      const outlook = goalOutlook(
        {
          id: gRecord.id ?? "",
          name: gRecord.name,
          icon: "target",
          targetMinor: gRecord.targetMinor,
          savedMinor: gRecord.savedMinor,
          updatedAt: "",
          isDeleted: false,
        },
        data,
        h,
        gRecord.id === null
      );

      const out: Record<string, unknown> = {
        goal: renderGoalOutlook(outlook, r),
        current_pace_average_monthly_net: r.figMoney(outlook.paceMinor),
        notes: [
          `Contributions are counted from next month (${shiftMonth(data.currentMonthKey, 1)}) through the target month; the required amount is rounded up.`,
          GOAL_PACE_RULE,
        ],
      };

      if (targetMonthKey) {
        const n = monthsBetween(data.currentMonthKey, targetMonthKey);
        if (n === null || n < 1) {
          return errorResult(
            `target_date must be in a later month than the current month ${data.currentMonthKey}`
          );
        }
        const perMonth = roundUpToStep(outlook.neededMinor / n, data.step);
        const shortfall = figMap(outlook.paceMinor, (pace) => perMonth - pace);
        out.by_target_date = {
          target_month: targetMonthKey,
          monthly_contributions: n,
          required_monthly_contribution: r.money(perMonth),
          required_minus_current_pace: r.fig(shortfall, (v) => r.signed(v)),
        };
      }

      if (cRes.value !== null) {
        const m = outlook.neededMinor === 0 ? 0 : Math.ceil(outlook.neededMinor / cRes.value);
        out.at_stated_contribution = {
          monthly_contribution: r.money(cRes.value),
          months_needed: m,
          reached_in_month: shiftMonth(data.currentMonthKey, m),
        };
      }

      return renderOutput(r, out);
    }

    case "check_affordability": {
      const aRes = moneyArg(args.amount, "amount", data.currency);
      if (!aRes.ok) return errorResult(aRes.error);
      if (aRes.value === null) {
        return errorResult("amount is required; ask the user for the price or amount borrowed");
      }
      const mRes = wholeNum(args.months, "months");
      if (!mRes.ok) return errorResult(mRes.error);
      if (mRes.value === null || mRes.value < 1) {
        return errorResult("months is required; ask the user how many monthly payments");
      }
      if (mRes.value > MAX_PLAN_MONTHS) {
        return errorResult(`months must be a whole number from 1 to ${MAX_PLAN_MONTHS}`);
      }
      const pRes = moneyArg(args.monthly_payment, "monthly_payment", data.currency);
      if (!pRes.ok) return errorResult(pRes.error);

      let ratePercent: number | null = null;
      if (args.annual_rate_percent !== undefined && args.annual_rate_percent !== null) {
        const v = args.annual_rate_percent;
        if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 100) {
          return errorResult("annual_rate_percent must be a number from 0 to 100");
        }
        ratePercent = v;
      }

      const amountMinor = aRes.value;
      const months = mRes.value;
      const step = data.step;
      const notes: string[] = [];
      let basis: string;
      let payment: number;
      let totalRepaid: number;
      let rate: number;

      if (pRes.value !== null && pRes.value > 0) {
        const rounded = roundToStep(pRes.value, step);
        // Match InstallmentPlanRecord.roundHalfUp
        const total = rounded * months;
        if (total < amountMinor) {
          return errorResult(
            "monthly_payment x months is less than the amount, so the figures are inconsistent; ask the user to check them"
          );
        }
        basis = "monthly payment as given";
        payment = rounded;
        totalRepaid = total;
        const monthlyRate = solveMonthlyRate(amountMinor, new Array(months).fill(rounded));
        rate = Math.round(monthlyRate * 12 * 10000) / 100;
        if (ratePercent !== null) {
          notes.push(
            "annual_rate_percent was ignored because monthly_payment was given; the rate shown is the one implied by the payment."
          );
        }
      } else if (ratePercent !== null && ratePercent > 0) {
        const mr = ratePercent / 100 / 12;
        const exact = (amountMinor * mr) / (1 - Math.pow(1 + mr, -months));
        basis = "annuity payment at the given nominal annual rate";
        payment = roundToStep(exact, step);
        totalRepaid = payment * months;
        rate = ratePercent;
        notes.push("Total repaid = monthly payment x months; a lender's last payment may differ slightly.");
      } else {
        const amounts = paymentAmounts(amountMinor, months, null, step);
        if (amounts.length === 0) return errorResult("amount must be a positive number");
        basis = "interest-free split of the amount";
        payment = amounts[0];
        totalRepaid = amountMinor;
        rate = 0;
        const last = amounts[amounts.length - 1];
        if (amounts.length > 1 && last !== payment) {
          notes.push(`The last payment is ${r.money(last)}.`);
        }
      }

      const h = computeCashFlowHistory(data);
      const d = computeDebtOverview(data, h);
      const currentService = d.monthlyDebtServiceMinor;
      const newService = currentService + payment;
      const ratio = (svc: number): AdviserFigure<number> => {
        if (h.averageIncomeMinor.kind !== "value") return h.averageIncomeMinor as AdviserFigure<number>;
        const pct = calcPercent(svc, h.averageIncomeMinor.value);
        return pct !== null ? figValue(pct) : figInsufficient("average monthly income is 0");
      };

      return renderOutput(r, {
        amount: r.money(amountMinor),
        months,
        payment_basis: basis,
        monthly_payment: r.money(payment),
        total_repaid: r.money(totalRepaid),
        total_interest: r.money(Math.max(0, totalRepaid - amountMinor)),
        annual_rate: `${rate.toFixed(2)}%`,
        monthly_debt_service_now: r.money(currentService),
        monthly_debt_service_after: r.money(newService),
        average_monthly_income: r.figMoney(h.averageIncomeMinor),
        debt_service_to_income_now: r.figPercent(ratio(currentService)),
        debt_service_to_income_after: r.figPercent(ratio(newService)),
        average_monthly_net_now: r.figMoney(h.averageNetMinor),
        average_monthly_net_after_payment: r.fig(
          figMap(h.averageNetMinor, (v) => v - payment),
          (v) => r.money(v)
        ),
        average_monthly_spending_now: r.figMoney(h.averageSpendingMinor),
        average_monthly_spending_with_payment: r.fig(
          figMap(h.averageSpendingMinor, (v) => v + payment),
          (v) => r.money(v)
        ),
        notes: [...notes, DEBT_SERVICE_RULE, AVERAGES_RULE],
      });
    }

    case "early_settlement_saving": {
      const planID = trimStr(args.plan_id);
      if (!planID) return errorResult("plan_id is required");
      const plan = data.plans.find((p) => p.id === planID);
      if (!plan) return errorResult(`no installment plan or loan with id ${planID}; use an id from the plans list`);
      let settleDay = data.todayKey;
      const rawDate = trimStr(args.settle_date);
      if (rawDate) {
        if (!isValidDayKey(rawDate)) {
          return errorResult("settle_date must be a valid date in YYYY-MM-DD format");
        }
        settleDay = rawDate;
      }
      const progress = computeProgress(plan, data.todayKey);
      const settlement = earlySettlementCompute(plan, settleDay, data.todayKey);
      return renderOutput(r, {
        plan_id: plan.id,
        name: plan.name,
        settle_date: settleDay,
        if_not_settled: {
          payments_left: progress.paymentCount - progress.paidCount,
          scheduled_payments_left: r.money(progress.remainingMinor, plan.currency),
          interest_still_to_pay: r.money(progress.interestRemainingMinor, plan.currency),
        },
        effective_annual_rate: r.percent(Math.round(effectiveAnnualRate(plan) * 10000) / 100),
        settlement: settlement.ok
          ? {
              principal_to_pay_off: r.money(settlement.value.payoffPrincipalMinor, plan.currency),
              interest_saved: r.money(settlement.value.interestSavedMinor, plan.currency),
              payments_cancelled: settlement.value.cancelledPaymentCount,
              scheduled_amount_cancelled: r.money(settlement.value.cancelledPaymentsMinor, plan.currency),
            }
          : `not enough data: ${settlement.reason}`,
        notes: ["Settling is not recorded by this calculator; settle_installment_plan does that when the user asks."],
      });
    }

    case "emergency_runway": {
      const cashRes = moneyArg(args.cash_amount, "cash_amount", data.currency, true);
      if (!cashRes.ok) return errorResult(cashRes.error);
      if (cashRes.value === null) {
        return errorResult("cash_amount is required; ask the user how much cash or savings they mean");
      }
      const cash = cashRes.value;
      const h = computeCashFlowHistory(data);
      const avgFixed = figMap(h.fixedVariable, (fv) => fv.averageFixedMinor);
      const monthsFor = (per: AdviserFigure<number>, label: string): AdviserFigure<number> => {
        if (per.kind !== "value") return per;
        if (per.value <= 0) return figInsufficient(`${label} is 0`);
        return figValue(Math.floor((cash / per.value) * 10) / 10);
      };
      return renderOutput(r, {
        cash: r.money(cash),
        average_monthly_spending: r.figMoney(h.averageSpendingMinor),
        months_of_spending_covered: r.fig(
          monthsFor(h.averageSpendingMinor, "average monthly spending"),
          (v) => v.toFixed(1)
        ),
        average_monthly_fixed_spending: r.figMoney(avgFixed),
        months_of_fixed_spending_covered: r.fig(
          monthsFor(avgFixed, "average monthly fixed spending"),
          (v) => v.toFixed(1)
        ),
        notes: [RUNWAY_RULE, FIXED_RULE, AVERAGES_RULE],
      });
    }

    case "summarize_period": {
      let start: string;
      let end: string;
      const rawMonth = trimStr(args.month);
      if (rawMonth) {
        if (rawMonth.length !== 7 || !parseMonthKey(rawMonth)) {
          return errorResult("month must be YYYY-MM");
        }
        const range = dayRangeForMonth(rawMonth);
        start = range.start;
        end = range.end;
      } else {
        const rawStart = trimStr(args.start_date);
        if (!rawStart) return errorResult("give month (YYYY-MM) or start_date (YYYY-MM-DD)");
        if (!isValidDayKey(rawStart)) {
          return errorResult("start_date must be a valid date in YYYY-MM-DD format");
        }
        start = rawStart;
        end = rawStart > data.todayKey ? rawStart : data.todayKey;
        const rawEnd = trimStr(args.end_date);
        if (rawEnd) {
          if (!isValidDayKey(rawEnd)) {
            return errorResult("end_date must be a valid date in YYYY-MM-DD format");
          }
          end = rawEnd;
        }
      }
      if (end < start) [start, end] = [end, start];

      let categoryFilter: CategoryID | null = null;
      const rawCat = trimStr(args.category);
      if (rawCat) {
        if (!ALL_CATEGORIES.includes(rawCat as CategoryID)) {
          return errorResult(`unknown category ${rawCat}`);
        }
        categoryFilter = rawCat as CategoryID;
      }

      let memberID: string | null = null;
      const rawMember = trimStr(args.member);
      if (rawMember) {
        memberID = resolveMember(rawMember, ctx);
        if (!memberID) return errorResult(`no household member matches '${rawMember}'`);
      }

      const txs = data.transactions.filter(
        (tx) =>
          tx.dayKey >= start &&
          tx.dayKey <= end &&
          (!categoryFilter || tx.category === categoryFilter) &&
          (!memberID || tx.memberID === memberID)
      );

      const expenses = txs.filter((tx) => tx.type === "expense");
      const spending = expenses.reduce((s, tx) => s + tx.amountMinor, 0);
      const byCat = new Map<CategoryID, number>();
      for (const tx of expenses) {
        byCat.set(tx.category, (byCat.get(tx.category) ?? 0) + tx.amountMinor);
      }
      const catShares = [...byCat.entries()]
        .sort((a, b) => (a[1] !== b[1] ? b[1] - a[1] : a[0] < b[0] ? -1 : 1))
        .map(([cat, minor]) => {
          const share = calcPercent(minor, spending);
          return `${cat}: ${r.money(minor)} (${share !== null ? `${share.toFixed(1)}%` : "n/a"})`;
        });

      const incomeTxs = txs.filter((tx) => tx.type === "income");
      const incomeTotal = incomeTxs.reduce((s, tx) => s + tx.amountMinor, 0);
      const hasSalary = incomeTxs.some(isSalaryTransaction);
      const nonSalaryIncome = incomeTxs
        .filter((tx) => !isSalaryTransaction(tx))
        .reduce((s, tx) => s + tx.amountMinor, 0);

      const memberAgg = new Map<string, { name: string; spendingMinor: number; count: number }>();
      for (const tx of expenses) {
        const old = memberAgg.get(tx.memberID);
        const name = old?.name || tx.memberName || tx.memberID;
        memberAgg.set(tx.memberID, {
          name,
          spendingMinor: (old?.spendingMinor ?? 0) + tx.amountMinor,
          count: (old?.count ?? 0) + 1,
        });
      }
      const members = [...memberAgg.values()].sort((a, b) => b.spendingMinor - a.spendingMinor);

      const merchantAgg = new Map<string, { name: string; totalMinor: number; count: number }>();
      for (const tx of expenses) {
        const key = tx.name.trim().toLowerCase();
        const old = merchantAgg.get(key);
        merchantAgg.set(key, {
          name: old?.name ?? tx.name,
          totalMinor: (old?.totalMinor ?? 0) + tx.amountMinor,
          count: (old?.count ?? 0) + 1,
        });
      }
      const topMerchants = [...merchantAgg.values()]
        .sort((a, b) =>
          a.totalMinor !== b.totalMinor ? b.totalMinor - a.totalMinor : a.name < b.name ? -1 : 1
        )
        .slice(0, 5);

      const dayCount = daysBetween(start, end) + 1;
      const avgPerDay = averageMinor(spending, Math.max(1, dayCount), data.step);

      const obj: Record<string, unknown> = {
        from: start,
        to: end,
        days: dayCount,
        transactions: txs.length,
        spending: r.money(spending),
        spending_per_day: r.money(avgPerDay),
        income: r.figMoney(gate(data, incomeTotal, hasSalary)),
        income_excluding_salary: r.money(nonSalaryIncome),
        net: r.figMoney(gate(data, incomeTotal - spending, hasSalary)),
        spending_by_category: catShares,
        spending_by_member: members.map((m) => `${m.name}: ${r.money(m.spendingMinor)} (${m.count} tx)`),
        top_merchants: topMerchants.map((m) => `${m.name}: ${r.money(m.totalMinor)} (${m.count} tx)`),
      };
      const filters: string[] = [];
      if (categoryFilter) filters.push(`category ${categoryFilter}`);
      if (rawMember) filters.push(`member ${rawMember}`);
      if (filters.length) obj.filters = filters.join(", ");
      if (txs.length === 0) obj.note = "no transactions in this range";
      return renderOutput(r, obj);
    }

    default:
      return null;
  }
}

function goalOutlook(
  g: SavingsGoalRecord,
  data: DataSet,
  h: CashFlowComputed,
  isHypothetical = false
) {
  const neededMinor = Math.max(0, g.targetMinor - g.savedMinor);
  const percent = g.targetMinor > 0 ? Math.floor((g.savedMinor * 100) / g.targetMinor) : 0;
  let monthsToTarget: AdviserFigure<number>;
  if (neededMinor === 0) {
    monthsToTarget = figValue(0);
  } else if (h.averageNetMinor.kind !== "value") {
    monthsToTarget = h.averageNetMinor as AdviserFigure<number>;
  } else if (h.averageNetMinor.value <= 0) {
    monthsToTarget = figInsufficient(
      "average monthly net saving is not positive, so the target is not reached at this pace"
    );
  } else {
    monthsToTarget = figValue(Math.ceil(neededMinor / h.averageNetMinor.value));
  }
  const projectedMonthKey = figMap(monthsToTarget, (m) => shiftMonth(data.currentMonthKey, m));
  return {
    goalID: isHypothetical ? null : g.id || null,
    name: g.name,
    targetMinor: g.targetMinor,
    savedMinor: g.savedMinor,
    neededMinor,
    percent,
    paceMinor: h.averageNetMinor,
    monthsToTarget,
    projectedMonthKey,
  };
}

function renderGoalOutlook(o: ReturnType<typeof goalOutlook>, r: Renderer): Record<string, unknown> {
  const obj: Record<string, unknown> = {
    name: o.name,
    target: r.money(o.targetMinor),
    saved: r.money(o.savedMinor),
    still_needed: r.money(o.neededMinor),
    percent_saved: `${o.percent}%`,
    months_to_target_at_current_pace: r.fig(o.monthsToTarget, (v) => v),
    projected_month_at_current_pace: r.fig(o.projectedMonthKey, (v) => v),
  };
  if (o.goalID) obj.goal_id = o.goalID;
  return obj;
}
