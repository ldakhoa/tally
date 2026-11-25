import { matchGoal, isSalaryTransaction } from "./adviser.ts";
import {
  formatExchangeRate,
  formatMoney,
  isValidDayKey,
  monthKeyFromDayKey,
  normalizeCurrencyCode,
  parseMonthKey,
  resolveTransactionAmount,
  toStorageMinor,
} from "./money.ts";
import {
  computeProgress,
  earlySettlementCompute,
  effectiveAlreadyPaidCount,
  effectiveAnnualRate,
  effectivePrincipalMinor,
  fullSchedule,
  hasValidTerms,
  isPlanPayment,
  MAX_PLAN_MONTHS,
  planSchedule,
  reconcilePlanPayments,
  roundHalfUp,
  roundingStep,
  totalInterestMinor,
  validateNewOrUpdatedPlan,
} from "./plans.ts";
import {
  ALL_CATEGORIES,
  EXPENSE_CATEGORIES,
  GOAL_ICONS,
  type BudgetLimitRecord,
  type CategoryID,
  type GoalIcon,
  type HouseholdMember,
  type InstallmentKind,
  type InstallmentPlanRecord,
  type MCPToolDefinition,
  type MCPToolResult,
  type SavingsGoalRecord,
  type TransactionRecord,
  type VaultConfig,
} from "./types.ts";

export interface VaultWriteStore {
  getConfig(): VaultConfig;
  listTransactions(): TransactionRecord[];
  listBudgets(): BudgetLimitRecord[];
  listGoals(): SavingsGoalRecord[];
  listPlans(): InstallmentPlanRecord[];
  upsertTransaction(record: TransactionRecord): void;
  upsertBudget(record: BudgetLimitRecord): void;
  upsertGoal(record: SavingsGoalRecord): void;
  upsertPlan(record: InstallmentPlanRecord): void;
}

const PLAN_FIELD_PROPS: Record<string, unknown> = {
  name: { type: "string", description: "Short plan name, e.g. 'iPhone 17', 'Car loan', 'Vay mua xe'." },
  total_amount: { type: "number", description: "Installments only: total price being split, in the household currency's major units." },
  amount_borrowed: { type: "number", description: "Loans only: principal borrowed (not the total repaid), in major units." },
  monthly_payment: { type: "number", description: "Loans only: regular monthly payment as quoted by the lender, in major units." },
  months: { type: "integer", description: `Number of monthly payments in the whole term (1-${MAX_PLAN_MONTHS}).` },
  first_payment_date: { type: "string", description: "Date of the FIRST payment of the whole term, YYYY-MM-DD (may be in the past for a plan already in progress)." },
  category: { type: "string", enum: EXPENSE_CATEGORIES, description: "Expense category for the monthly payments (installments default to 'shopping', loans to 'bills')." },
  member: { type: "string", description: "Optional household member who pays: 'me', 'partner', or their display name." },
  lender: { type: "string", description: "Loans only: lender or bank, e.g. 'DBS', 'Trust'." },
  link: { type: "string", description: "Loans only: optional URL of the loan in the bank's app or website." },
  note: { type: "string", description: "Optional short note (card, account, reference)." },
  already_paid_payments: { type: "integer", description: "How many of the first payments were already paid AND are already recorded in Tally (or were paid before the user started using Tally and should not count as spending)." },
  all_due_payments_already_recorded: { type: "boolean", description: "true when the user said every payment due up to today is already recorded in Tally (or was paid before using Tally): Tally counts them from the schedule." },
};

export const WRITE_TOOLS: MCPToolDefinition[] = [
  {
    name: "add_transactions",
    description:
      "Record one or more completed expenses or income transactions into Tally. Use this whenever the user says they paid for something, spent money, paid a bill/credit card/rent, or received salary/income.",
    inputSchema: {
      type: "object",
      properties: {
        items: {
          type: "array",
          description: "List of one or more transactions to add.",
          items: {
            type: "object",
            properties: {
              name: { type: "string", description: "Short, clear merchant or description." },
              amount: { type: "number", description: "Positive amount in major units, exactly as stated in the transaction's currency." },
              currency: { type: "string", description: "3-letter uppercase ISO 4217 currency code ONLY when stated in a currency other than the household's." },
              converted_amount: { type: "number", description: "ONLY if the user or receipt explicitly states the exact billed amount in the household currency alongside the foreign amount." },
              type: { type: "string", enum: ["expense", "income"], description: "Whether this is an expense or income." },
              category: { type: "string", enum: ALL_CATEGORIES, description: "Best matching category ID." },
              day_key: { type: "string", description: "Optional transaction date in YYYY-MM-DD format. Defaults to today if omitted." },
              note: { type: "string", description: "Optional short note." },
              member: { type: "string", description: "Optional household member: 'me', 'partner', or their display name." },
            },
            required: ["name", "amount", "type", "category"],
          },
        },
      },
      required: ["items"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "update_transaction",
    description: "Update an existing transaction's amount, name, category, date, or note by its ID.",
    inputSchema: {
      type: "object",
      properties: {
        transaction_id: { type: "string", description: "ID of the transaction to update." },
        name: { type: "string", description: "Optional new name." },
        amount: { type: "number", description: "Optional new positive amount in active currency major units." },
        category: { type: "string", enum: ALL_CATEGORIES, description: "Optional new category ID." },
        day_key: { type: "string", description: "Optional new date in YYYY-MM-DD format." },
        note: { type: "string", description: "Optional new note." },
      },
      required: ["transaction_id"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "delete_transaction",
    description: "Delete an existing transaction by its ID.",
    inputSchema: {
      type: "object",
      properties: {
        transaction_id: { type: "string", description: "ID of the transaction to delete." },
      },
      required: ["transaction_id"],
    },
    readOnly: false,
    destructive: true,
  },
  {
    name: "set_budgets",
    description: "Set or update one or more monthly spending budget limits by category.",
    inputSchema: {
      type: "object",
      properties: {
        month_key: { type: "string", description: "Optional YYYY-MM month key. Defaults to the current month." },
        items: {
          type: "array",
          description: "One or more category budget limits to set.",
          items: {
            type: "object",
            properties: {
              category: { type: "string", enum: EXPENSE_CATEGORIES, description: "Expense category ID." },
              limit: { type: "number", description: "Positive monthly limit amount in active currency major units." },
            },
            required: ["category", "limit"],
          },
        },
      },
      required: ["items"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "delete_budget",
    description: "Remove a monthly budget limit for a specific expense category.",
    inputSchema: {
      type: "object",
      properties: {
        month_key: { type: "string", description: "Optional YYYY-MM month key. Defaults to the current month." },
        category: { type: "string", enum: EXPENSE_CATEGORIES, description: "Expense category ID to remove." },
      },
      required: ["category"],
    },
    readOnly: false,
    destructive: true,
  },
  {
    name: "create_savings_goal",
    description: "Create a new savings goal.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "Clear goal name." },
        target_amount: { type: "number", description: "Positive target amount to save in active currency major units." },
        saved_amount: { type: "number", description: "Optional amount already saved (defaults to 0)." },
        icon: { type: "string", enum: GOAL_ICONS, description: "Best fitting icon." },
      },
      required: ["name", "target_amount"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "update_savings_goal",
    description: "Contribute money to an existing savings goal or update its target/saved amount or name.",
    inputSchema: {
      type: "object",
      properties: {
        goal_id: { type: "string", description: "Optional ID of the goal if known." },
        goal_name: { type: "string", description: "Name of the goal to match if goal_id is omitted." },
        add_amount: { type: "number", description: "Optional positive amount to add/contribute to the goal's saved total." },
        new_target_amount: { type: "number", description: "Optional new target amount." },
        new_saved_amount: { type: "number", description: "Optional absolute new saved amount." },
        new_name: { type: "string", description: "Optional renamed goal title." },
      },
      required: [],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "delete_savings_goal",
    description: "Delete an existing savings goal by ID or name.",
    inputSchema: {
      type: "object",
      properties: {
        goal_id: { type: "string", description: "Optional ID of the goal." },
        goal_name: { type: "string", description: "Optional name of the goal to delete." },
      },
      required: [],
    },
    readOnly: false,
    destructive: true,
  },
  {
    name: "create_installment_plan",
    description: "Create an installment plan or a loan. Tally books each monthly payment as an expense when it falls due.",
    inputSchema: {
      type: "object",
      properties: {
        kind: { type: "string", enum: ["installment", "loan"], description: "'installment' or 'loan'." },
        ...PLAN_FIELD_PROPS,
      },
      required: ["kind", "name", "months", "first_payment_date"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "convert_transaction_to_installment",
    description: "Turn an existing expense into an installment plan.",
    inputSchema: {
      type: "object",
      properties: {
        transaction_id: { type: "string", description: "ID of the expense to convert." },
        months: { type: "integer", description: "Number of monthly payments." },
        first_payment_date: { type: "string", description: "First payment date, YYYY-MM-DD." },
      },
      required: ["transaction_id", "months", "first_payment_date"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "update_installment_plan",
    description: "Change an existing installment plan or loan by its plan id.",
    inputSchema: {
      type: "object",
      properties: {
        plan_id: { type: "string", description: "ID of the plan." },
        ...PLAN_FIELD_PROPS,
      },
      required: ["plan_id"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "settle_installment_plan",
    description: "Mark a plan as paid off early (settled).",
    inputSchema: {
      type: "object",
      properties: {
        plan_id: { type: "string", description: "ID of the plan." },
        settled_date: { type: "string", description: "Date it was paid off, YYYY-MM-DD. Defaults to today." },
      },
      required: ["plan_id"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "undo_plan_settlement",
    description: "Undo an early settlement so the plan's remaining payments are owed again.",
    inputSchema: {
      type: "object",
      properties: {
        plan_id: { type: "string", description: "ID of the plan." },
      },
      required: ["plan_id"],
    },
    readOnly: false,
    destructive: false,
  },
  {
    name: "delete_installment_plan",
    description: "Delete a plan. Confirm whether to keep or remove already recorded payments.",
    inputSchema: {
      type: "object",
      properties: {
        plan_id: { type: "string", description: "ID of the plan." },
        remove_payments: { type: "boolean", description: "true to also delete the payments already recorded as expenses; false to keep them." },
      },
      required: ["plan_id", "remove_payments"],
    },
    readOnly: false,
    destructive: true,
  },
];

export const WRITE_TOOL_NAMES = new Set(WRITE_TOOLS.map((t) => t.name));

function err(message: string): MCPToolResult {
  return { text: message, isError: true };
}

function categoryType(cat: CategoryID): "income" | "expense" {
  return cat === "salary" || cat === "freelance" || cat === "income" ? "income" : "expense";
}

function resolveWriteMember(hint: string | null, config: VaultConfig): HouseholdMember {
  const raw = hint?.trim();
  if (!raw) return config.currentMember;
  const lowered = raw.toLowerCase();
  const partnerTokens = new Set([
    "partner",
    "wife",
    "husband",
    "spouse",
    "vợ",
    "vo",
    "chồng",
    "chong",
    "老婆",
    "妻子",
    "老公",
    "伴侣",
  ]);
  const partnerName = config.partnerDisplayName?.trim() ?? "";
  if (partnerTokens.has(lowered) || (partnerName && lowered === partnerName.toLowerCase())) {
    const existingPartner = config.members.find((m) => m.id !== config.currentMember.id);
    if (existingPartner) return existingPartner;
    return {
      id: "member-partner",
      name: partnerName || "Partner",
      avatarSymbol: "person.fill",
    };
  }
  const matched = config.members.find((m) => m.name.toLowerCase() === lowered);
  return matched ?? config.currentMember;
}

function maskIfSalary(formatted: string, hidden: boolean, storedSalary: boolean, resultSalary: boolean): string {
  return hidden && (storedSalary || resultSalary) ? "•••" : formatted;
}

function normalizeLink(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const trimmed = raw.trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  let candidate = trimmed;
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(candidate) && !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(candidate)) {
    if (!candidate.includes(".") || candidate.startsWith(".") || candidate.startsWith("/")) return null;
    candidate = `https://${candidate}`;
  }
  try {
    const u = new URL(candidate);
    const scheme = u.protocol.replace(":", "").toLowerCase();
    if (["javascript", "data", "file", "vbscript", "about", "blob"].includes(scheme)) return null;
    if ((scheme === "http" || scheme === "https") && !u.hostname.includes(".") && u.hostname !== "localhost") {
      return null;
    }
    return candidate;
  } catch {
    return null;
  }
}

function stampUserWrite(tx: TransactionRecord, nowISO: string): TransactionRecord {
  if (!isPlanPayment(tx)) {
    return { ...tx, updatedAt: nowISO };
  }
  const state = tx.paymentState ?? {};
  const userWrite = {
    at: nowISO,
    content: {
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
    },
  };
  return {
    ...tx,
    paymentState: { ...state, user: userWrite },
    updatedAt: nowISO,
  };
}

function saveAndReconcilePlan(
  store: VaultWriteStore,
  plan: InstallmentPlanRecord,
  todayKey: string,
  nowISO: string,
  bookMissing: boolean
): InstallmentPlanRecord {
  const stamped: InstallmentPlanRecord = { ...plan, updatedAt: nowISO };
  store.upsertPlan(stamped);
  const existingPayments = store
    .listTransactions()
    .filter((tx) => tx.planID === stamped.id && isPlanPayment(tx));
  const revisions = reconcilePlanPayments(
    stamped,
    existingPayments,
    todayKey,
    bookMissing,
    store.getConfig().timeZoneOffsetMinutes
  );
  for (const rev of revisions) {
    store.upsertTransaction(rev);
  }
  return stamped;
}

function modelPlanSummary(plan: InstallmentPlanRecord, todayKey: string): string {
  const money = (m: number) => formatMoney(m, plan.currency);
  const sched = fullSchedule(plan);
  const progress = computeProgress(plan, todayKey);
  const parts = [
    `[id:${plan.id}] ${plan.kind} '${plan.name}'`,
    `monthly payment ${money(sched[0]?.amountMinor ?? 0)}`,
    `${plan.months} months`,
    `first payment ${plan.firstPaymentDayKey}`,
    `last payment ${sched[sched.length - 1]?.dayKey ?? plan.firstPaymentDayKey}`,
    `total ${money(plan.totalMinor)}`,
    `category ${plan.category}`,
  ];
  if (plan.kind === "loan" || totalInterestMinor(plan) > 0) {
    parts.push(`borrowed ${money(effectivePrincipalMinor(plan))}`);
    parts.push(`effective annual rate ${(effectiveAnnualRate(plan) * 100).toFixed(2)}%`);
    parts.push(`total interest ${money(totalInterestMinor(plan))}`);
  }
  if (plan.lender) parts.push(`lender ${plan.lender}`);
  if (effectiveAlreadyPaidCount(plan) > 0) {
    parts.push(`${effectiveAlreadyPaidCount(plan)} payments already paid (not booked as expenses)`);
  }
  if (plan.settledDayKey) parts.push(`settled ${plan.settledDayKey}`);
  parts.push(`paid ${progress.paidCount}/${progress.paymentCount}`);
  parts.push(`remaining ${money(progress.remainingMinor)}`);
  return parts.join(", ");
}

function planSaveOutput(
  plan: InstallmentPlanRecord,
  verb: string,
  todayKey: string,
  store: VaultWriteStore
): string {
  let output = `${verb} ${modelPlanSummary(plan, todayKey)}.`;
  const booked = store
    .listTransactions()
    .filter(
      (tx) =>
        !tx.isDeleted &&
        tx.planID === plan.id &&
        isPlanPayment(tx) &&
        tx.dayKey <= todayKey
    ).length;
  if (booked > 0) {
    output += ` ${booked} payments due so far are recorded as expenses by this plan.`;
  }
  if (plan.firstPaymentDayKey < todayKey && effectiveAlreadyPaidCount(plan) === 0 && booked > 0) {
    output +=
      " The first payment is in the past: if those payments were already recorded in Tally, call update_installment_plan with all_due_payments_already_recorded (or already_paid_payments if only some were) so they are not counted twice.";
  }
  return output;
}

export function runWriteTool(
  name: string,
  args: Record<string, unknown>,
  store: VaultWriteStore,
  todayKey: string,
  nowISO = new Date().toISOString()
): MCPToolResult | null {
  if (!WRITE_TOOL_NAMES.has(name)) return null;
  const config = store.getConfig();
  if (!config.allowsChanges) {
    return err(
      "Error: changes are turned off. The user can allow them in Tally > Settings > MCP & AI Assistants > Allow changes."
    );
  }

  const currency = config.currency;
  const activeMonth = monthKeyFromDayKey(todayKey);

  switch (name) {
    case "add_transactions": {
      if (!Array.isArray(args.items) || args.items.length === 0) {
        return err("Error: items must be a non-empty array");
      }
      const parsed: Array<{
        name: string;
        amountMajor: number;
        type: "expense" | "income";
        category: CategoryID;
        dayKey: string;
        note: string;
        memberHint: string | null;
        currencyCode: string | null;
        convertedAmountMajor: number | null;
      }> = [];
      for (const rawItem of args.items) {
        if (!rawItem || typeof rawItem !== "object") continue;
        const item = rawItem as Record<string, unknown>;
        const rawName = typeof item.name === "string" ? item.name.trim() : "";
        const amt = typeof item.amount === "number" ? item.amount : NaN;
        if (!rawName || !(amt > 0 && Number.isFinite(amt))) continue;
        const type = item.type === "income" ? "income" : "expense";
        let cat =
          typeof item.category === "string" && ALL_CATEGORIES.includes(item.category as CategoryID)
            ? (item.category as CategoryID)
            : type === "income"
              ? "income"
              : "other";
        if (categoryType(cat) !== type) {
          cat = type === "income" ? "income" : "other";
        }
        const dayKey =
          typeof item.day_key === "string" && isValidDayKey(item.day_key)
            ? item.day_key
            : todayKey;
        const note = typeof item.note === "string" ? item.note.trim() : "";
        const memberHint = typeof item.member === "string" && item.member.trim() ? item.member.trim() : null;
        const currencyCode =
          typeof item.currency === "string" ? normalizeCurrencyCode(item.currency) : null;
        const converted =
          typeof item.converted_amount === "number" &&
          item.converted_amount > 0 &&
          Number.isFinite(item.converted_amount)
            ? item.converted_amount
            : null;
        parsed.push({
          name: rawName,
          amountMajor: amt,
          type,
          category: cat,
          dayKey,
          note,
          memberHint,
          currencyCode,
          convertedAmountMajor: converted,
        });
      }
      if (parsed.length === 0) return err("Error: No valid transaction items provided");

      const summaries: string[] = [];
      const touchedBudgets: Array<{ category: CategoryID; monthKey: string }> = [];

      for (const item of parsed) {
        const member = resolveWriteMember(item.memberHint, config);
        const resolved = resolveTransactionAmount({
          amountMajor: item.amountMajor,
          statedCurrencyCode: item.currencyCode,
          convertedAmountMajor: item.convertedAmountMajor,
          household: currency,
          note: item.note,
          rates: config.exchangeRates,
        });
        const record: TransactionRecord = {
          id: crypto.randomUUID(),
          name: item.name,
          amountMinor: resolved.amountMinor,
          type: item.type,
          category: item.category,
          dayKey: item.dayKey,
          createdAt: nowISO,
          note: resolved.note,
          source: "aiQuickAdd",
          rawSourceText: null,
          memberID: member.id,
          memberName: member.name,
          needsReview: resolved.usedFallbackUnavailableRate,
          updatedAt: nowISO,
          isDeleted: false,
          originalAmountMinor: resolved.originalAmountMinor,
          originalCurrencyCode: resolved.originalCurrencyCode,
          exchangeRate: resolved.exchangeRate,
        };
        store.upsertTransaction(record);

        const signedMinor = item.type === "income" ? record.amountMinor : -record.amountMinor;
        const amtStr = maskIfSalary(
          formatMoney(signedMinor, currency, { signed: item.type === "income" }),
          config.salaryHidden,
          false,
          isSalaryTransaction(record)
        );
        let fxNote = "";
        if (record.originalCurrencyCode && record.originalAmountMinor != null) {
          const origText = formatMoney(record.originalAmountMinor, record.originalCurrencyCode);
          if (resolved.usedFallbackUnavailableRate) {
            fxNote = ` (foreign ${record.originalCurrencyCode} ${origText}; FX rate unavailable, flagged for review; note: ${record.note})`;
          } else {
            const ratePart =
              resolved.exchangeRate != null
                ? `, rate ${formatExchangeRate(resolved.exchangeRate, record.originalCurrencyCode, currency)}`
                : "";
            const srcNote = resolved.isLiveRate
              ? `live rate${resolved.rateDate ? ` ${resolved.rateDate}` : ""}`
              : item.convertedAmountMajor != null
                ? "stated billed amount"
                : "offline fallback rate";
            fxNote = ` (converted from ${origText} using ${srcNote}${ratePart}; note: ${record.note})`;
          }
        }
        summaries.push(
          `Added transaction [id:${record.id}] ${record.name} ${amtStr} in ${record.category} on ${record.dayKey}${fxNote}`
        );
        const mk = monthKeyFromDayKey(record.dayKey);
        if (
          record.type === "expense" &&
          !touchedBudgets.some((b) => b.category === record.category && b.monthKey === mk)
        ) {
          touchedBudgets.push({ category: record.category, monthKey: mk });
        }
      }

      const allTx = store.listTransactions();
      const allBudgets = store.listBudgets();
      for (const { category, monthKey } of touchedBudgets) {
        const budget = allBudgets.find(
          (b) => !b.isDeleted && b.monthKey === monthKey && b.category === category
        );
        if (!budget) continue;
        const spent = allTx
          .filter(
            (tx) =>
              !tx.isDeleted &&
              tx.type === "expense" &&
              tx.category === category &&
              monthKeyFromDayKey(tx.dayKey) === monthKey
          )
          .reduce((s, tx) => s + tx.amountMinor, 0);
        const pct = budget.limitMinor > 0 ? `${((spent / budget.limitMinor) * 100).toFixed(1)}%` : "n/a";
        const left = budget.limitMinor - spent;
        const tail =
          left >= 0
            ? `${formatMoney(left, currency)} left`
            : `over by ${formatMoney(-left, currency)}`;
        summaries.push(
          `Budget ${category} ${monthKey}: spent ${formatMoney(spent, currency)} of ${formatMoney(budget.limitMinor, currency)} (${pct} used), ${tail}.`
        );
      }

      return { text: summaries.join("\n"), isError: false };
    }

    case "update_transaction": {
      const id = typeof args.transaction_id === "string" ? args.transaction_id : "";
      if (!id) return err("Error: transaction_id is required");
      const existing = store.listTransactions().find((tx) => !tx.isDeleted && tx.id === id);
      if (!existing) return err(`Transaction not found with id ${id}.`);

      const storedSalary = isSalaryTransaction(existing);
      const updated: TransactionRecord = { ...existing };
      if (typeof args.name === "string" && args.name.trim()) updated.name = args.name.trim();
      if (typeof args.amount === "number" && args.amount > 0 && Number.isFinite(args.amount)) {
        updated.amountMinor = Math.max(1, toStorageMinor(args.amount, currency));
      }
      if (typeof args.category === "string" && ALL_CATEGORIES.includes(args.category as CategoryID)) {
        updated.category = args.category as CategoryID;
        updated.type = categoryType(updated.category);
      }
      if (typeof args.day_key === "string" && isValidDayKey(args.day_key)) {
        updated.dayKey = args.day_key;
      }
      if (typeof args.note === "string") {
        updated.note = args.note;
      }

      const stamped = stampUserWrite(updated, nowISO);
      store.upsertTransaction(stamped);
      const signedMinor = stamped.type === "income" ? stamped.amountMinor : -stamped.amountMinor;
      const amtStr = maskIfSalary(
        formatMoney(signedMinor, currency, { signed: stamped.type === "income" }),
        config.salaryHidden,
        storedSalary,
        isSalaryTransaction(stamped)
      );
      return {
        text: `Updated transaction ${stamped.id}: ${stamped.name} ${amtStr}.`,
        isError: false,
      };
    }

    case "delete_transaction": {
      const id = typeof args.transaction_id === "string" ? args.transaction_id : "";
      if (!id) return err("Error: transaction_id is required");
      const existing = store.listTransactions().find((tx) => !tx.isDeleted && tx.id === id);
      if (!existing) return err(`Transaction not found with id ${id}.`);
      const stamped = stampUserWrite(
        { ...existing, isDeleted: true, needsReview: false },
        nowISO
      );
      store.upsertTransaction(stamped);
      return { text: `Deleted transaction ${existing.name} (${id}).`, isError: false };
    }

    case "set_budgets": {
      if (!Array.isArray(args.items) || args.items.length === 0) {
        return err("Error: items must be a non-empty array");
      }
      const rawMonth = typeof args.month_key === "string" ? args.month_key : "";
      const monthKey = parseMonthKey(rawMonth) ? rawMonth : activeMonth;
      const summaries: string[] = [];

      for (const rawItem of args.items) {
        if (!rawItem || typeof rawItem !== "object") continue;
        const item = rawItem as Record<string, unknown>;
        const cat = item.category;
        const limit = item.limit;
        if (
          typeof cat !== "string" ||
          !EXPENSE_CATEGORIES.includes(cat as CategoryID) ||
          typeof limit !== "number" ||
          !(limit > 0 && Number.isFinite(limit))
        ) {
          continue;
        }
        const limitMinor = Math.max(1, toStorageMinor(limit, currency));
        const budget: BudgetLimitRecord = {
          id: `${monthKey}/${cat}`,
          monthKey,
          category: cat as CategoryID,
          limitMinor,
          updatedAt: nowISO,
          isDeleted: false,
        };
        store.upsertBudget(budget);
        summaries.push(`Set budget for ${cat} in ${monthKey} to ${formatMoney(limitMinor, currency)}`);
      }
      if (summaries.length === 0) return err("Error: No valid budget items provided");
      return { text: summaries.join("\n"), isError: false };
    }

    case "delete_budget": {
      const cat = args.category;
      if (typeof cat !== "string" || !EXPENSE_CATEGORIES.includes(cat as CategoryID)) {
        return err("Error: Valid expense category is required");
      }
      const rawMonth = typeof args.month_key === "string" ? args.month_key : "";
      const monthKey = parseMonthKey(rawMonth) ? rawMonth : activeMonth;
      const budgetID = `${monthKey}/${cat}`;
      const existing = store.listBudgets().find((b) => !b.isDeleted && b.id === budgetID);
      if (!existing) return err(`No budget found for ${cat} in ${monthKey}.`);
      store.upsertBudget({ ...existing, isDeleted: true, updatedAt: nowISO });
      return { text: `Deleted budget ${budgetID}.`, isError: false };
    }

    case "create_savings_goal": {
      const rawName = typeof args.name === "string" ? args.name.trim() : "";
      const target = typeof args.target_amount === "number" ? args.target_amount : NaN;
      if (!rawName || !(target > 0 && Number.isFinite(target))) {
        return err("Error: name and positive target_amount are required");
      }
      const saved =
        typeof args.saved_amount === "number" && Number.isFinite(args.saved_amount)
          ? Math.max(0, args.saved_amount)
          : 0;
      const icon: GoalIcon =
        typeof args.icon === "string" && GOAL_ICONS.includes(args.icon as GoalIcon)
          ? (args.icon as GoalIcon)
          : "target";
      const targetMinor = Math.max(1, toStorageMinor(target, currency));
      const savedMinor = Math.max(0, toStorageMinor(saved, currency));
      const goal: SavingsGoalRecord = {
        id: crypto.randomUUID(),
        name: rawName,
        icon,
        targetMinor,
        savedMinor,
        updatedAt: nowISO,
        isDeleted: false,
      };
      store.upsertGoal(goal);
      return {
        text: `Created savings goal [id:${goal.id}] '${goal.name}' target ${formatMoney(targetMinor, currency)}, saved ${formatMoney(savedMinor, currency)}.`,
        isError: false,
      };
    }

    case "update_savings_goal": {
      const goalID = typeof args.goal_id === "string" ? args.goal_id.trim() : "";
      const goalName = typeof args.goal_name === "string" ? args.goal_name.trim() : "";
      if (!goalID && !goalName) return err("Error: Either goal_id or goal_name is required");
      const matched = matchGoal(goalID || null, goalName || null, store.listGoals());
      if (!matched) return err("Could not find matching savings goal.");
      const updated = { ...matched, updatedAt: nowISO };
      if (typeof args.new_name === "string" && args.new_name.trim()) updated.name = args.new_name.trim();
      if (typeof args.new_target_amount === "number" && args.new_target_amount > 0) {
        updated.targetMinor = Math.max(1, toStorageMinor(args.new_target_amount, currency));
      }
      if (typeof args.new_saved_amount === "number" && args.new_saved_amount >= 0) {
        updated.savedMinor = Math.max(0, toStorageMinor(args.new_saved_amount, currency));
      }
      if (typeof args.add_amount === "number" && args.add_amount > 0) {
        updated.savedMinor += Math.max(1, toStorageMinor(args.add_amount, currency));
      }
      store.upsertGoal(updated);
      const pct = updated.targetMinor > 0 ? Math.floor((updated.savedMinor * 100) / updated.targetMinor) : 0;
      return {
        text: `Updated goal '${updated.name}': ${formatMoney(updated.savedMinor, currency)} / ${formatMoney(updated.targetMinor, currency)} (${pct}%).`,
        isError: false,
      };
    }

    case "delete_savings_goal": {
      const goalID = typeof args.goal_id === "string" ? args.goal_id.trim() : "";
      const goalName = typeof args.goal_name === "string" ? args.goal_name.trim() : "";
      if (!goalID && !goalName) return err("Error: Either goal_id or goal_name is required");
      const matched = matchGoal(goalID || null, goalName || null, store.listGoals());
      if (!matched) return err("Could not find matching savings goal.");
      store.upsertGoal({ ...matched, isDeleted: true, updatedAt: nowISO });
      return { text: `Deleted savings goal '${matched.name}'.`, isError: false };
    }

    case "create_installment_plan": {
      const rawKind = typeof args.kind === "string" ? args.kind.toLowerCase() : "";
      if (rawKind !== "installment" && rawKind !== "loan") {
        return err("Error: kind must be 'installment' or 'loan'");
      }
      const kind = rawKind as InstallmentKind;
      const totalAmt = typeof args.total_amount === "number" ? args.total_amount : null;
      const borrowedAmt = typeof args.amount_borrowed === "number" ? args.amount_borrowed : null;
      const monthlyAmt = typeof args.monthly_payment === "number" ? args.monthly_payment : null;

      if (kind === "loan" && totalAmt !== null && borrowedAmt === null) {
        return err(
          "For a loan pass amount_borrowed (the principal), not total_amount. If only the total repaid is known, ask the user for the amount borrowed."
        );
      }
      if (kind === "installment" && borrowedAmt !== null && totalAmt === null) {
        return err("For an installment pass total_amount (the price being split), not amount_borrowed.");
      }

      const planName = typeof args.name === "string" ? args.name.trim() : "";
      const months = typeof args.months === "number" && Number.isInteger(args.months) ? args.months : null;
      const firstDate =
        typeof args.first_payment_date === "string" ? args.first_payment_date.trim() : "";
      const cat: CategoryID =
        typeof args.category === "string" && EXPENSE_CATEGORIES.includes(args.category as CategoryID)
          ? (args.category as CategoryID)
          : kind === "loan"
            ? "bills"
            : "shopping";
      const member = resolveWriteMember(
        typeof args.member === "string" ? args.member : null,
        config
      );
      const amountMajor = kind === "loan" ? (borrowedAmt ?? 0) : (totalAmt ?? 0);
      const amountMinor = amountMajor > 0 ? toStorageMinor(amountMajor, currency) : 0;
      const monthlyMinor = monthlyAmt && monthlyAmt > 0 ? toStorageMinor(monthlyAmt, currency) : 0;

      const step = roundingStep(currency);
      const roundedMonthly = roundHalfUp(monthlyMinor, step);
      const tempPlanForDueCount: InstallmentPlanRecord | null =
        months && isValidDayKey(firstDate) && amountMinor > 0
          ? {
              id: "temp",
              name: planName || "Plan",
              kind,
              totalMinor: kind === "loan" ? roundedMonthly * months : amountMinor,
              months,
              firstPaymentDayKey: firstDate,
              category: cat,
              memberID: member.id,
              memberName: member.name,
              note: "",
              currency,
              monthlyPaymentMinor: kind === "loan" ? roundedMonthly : null,
              principalMinor: kind === "loan" ? amountMinor : null,
              createdAt: nowISO,
              updatedAt: nowISO,
              isDeleted: false,
            }
          : null;

      let alreadyPaid =
        typeof args.already_paid_payments === "number" && Number.isInteger(args.already_paid_payments)
          ? args.already_paid_payments
          : 0;
      if (args.all_due_payments_already_recorded === true && tempPlanForDueCount) {
        alreadyPaid = fullSchedule(tempPlanForDueCount).filter((p) => p.dayKey <= todayKey).length;
      }

      const issues = validateNewOrUpdatedPlan({
        kind,
        name: planName,
        amountMinor,
        monthlyPaymentMinor: monthlyMinor,
        months,
        firstPaymentDayKey: firstDate,
        currency,
        alreadyPaidCount: alreadyPaid,
        category: cat,
      });
      if (issues.length > 0) {
        return err(
          `Not saved. ${issues.join(" ")} Ask the user for the missing or correct value; do not guess or invent figures.`
        );
      }

      const plan: InstallmentPlanRecord = {
        id: crypto.randomUUID(),
        name: planName,
        kind,
        totalMinor: kind === "loan" ? roundedMonthly * months! : amountMinor,
        months: months!,
        firstPaymentDayKey: firstDate,
        category: cat,
        memberID: member.id,
        memberName: member.name,
        note: typeof args.note === "string" ? args.note.trim() : "",
        currency,
        monthlyPaymentMinor: kind === "loan" ? roundedMonthly : null,
        principalMinor: kind === "loan" ? amountMinor : null,
        lender:
          kind === "loan" && typeof args.lender === "string" && args.lender.trim()
            ? args.lender.trim()
            : null,
        linkURL: kind === "loan" ? normalizeLink(typeof args.link === "string" ? args.link : null) : null,
        alreadyPaidPaymentCount: alreadyPaid > 0 ? alreadyPaid : null,
        createdAt: nowISO,
        updatedAt: nowISO,
        isDeleted: false,
      };
      if (!hasValidTerms(plan)) {
        return err("Not saved: these terms cannot build a payment schedule.");
      }
      const saved = saveAndReconcilePlan(store, plan, todayKey, nowISO, true);
      return { text: planSaveOutput(saved, "Created", todayKey, store), isError: false };
    }

    case "convert_transaction_to_installment": {
      const txID = typeof args.transaction_id === "string" ? args.transaction_id.trim() : "";
      const months = typeof args.months === "number" && Number.isInteger(args.months) ? args.months : null;
      const firstDate =
        typeof args.first_payment_date === "string" ? args.first_payment_date.trim() : "";
      if (!txID) return err("Error: transaction_id is required");
      if (months === null) return err("Error: months is required");
      if (!isValidDayKey(firstDate)) {
        return err("Error: first_payment_date must be a valid date in YYYY-MM-DD format");
      }
      const tx = store.listTransactions().find((t) => !t.isDeleted && t.id === txID);
      if (!tx) return err(`Transaction not found with id ${txID}.`);
      if (tx.type !== "expense" || isPlanPayment(tx)) {
        return err(
          "Only an ordinary expense can be converted (this one is income or already a plan payment)."
        );
      }

      const issues = validateNewOrUpdatedPlan({
        kind: "installment",
        name: tx.name,
        amountMinor: tx.amountMinor,
        monthlyPaymentMinor: 0,
        months,
        firstPaymentDayKey: firstDate,
        currency,
        alreadyPaidCount: 0,
        category: tx.category,
      });
      if (issues.length > 0) {
        return err(`Not saved. ${issues.join(" ")}`);
      }

      const existingPlans = new Map(store.listPlans().map((p) => [p.id, p]));
      let gen = 1;
      let chosenID = `conv-${tx.id}`;
      let reuseLive: InstallmentPlanRecord | null = null;
      while (true) {
        chosenID = gen === 1 ? `conv-${tx.id}` : `conv-${tx.id}-${gen}`;
        const found = existingPlans.get(chosenID);
        if (!found) break;
        if (!found.isDeleted) {
          reuseLive = found;
          break;
        }
        gen += 1;
      }

      store.upsertTransaction({
        ...tx,
        isDeleted: true,
        needsReview: false,
        planPaymentIndex: null,
        planID: reuseLive ? reuseLive.id : chosenID,
        updatedAt: nowISO,
      });

      if (reuseLive) {
        return {
          text: planSaveOutput(reuseLive, `Converted transaction ${txID} into`, todayKey, store),
          isError: false,
        };
      }

      const plan: InstallmentPlanRecord = {
        id: chosenID,
        name: tx.name,
        kind: "installment",
        totalMinor: tx.amountMinor,
        months,
        firstPaymentDayKey: firstDate,
        category: tx.category,
        memberID: tx.memberID,
        memberName: tx.memberName,
        note: tx.note,
        currency,
        sourceTransactionID: tx.id,
        createdAt: nowISO,
        updatedAt: nowISO,
        isDeleted: false,
      };
      const saved = saveAndReconcilePlan(store, plan, todayKey, nowISO, true);
      return {
        text: planSaveOutput(saved, `Converted transaction ${txID} into`, todayKey, store),
        isError: false,
      };
    }

    case "update_installment_plan": {
      const planID = typeof args.plan_id === "string" ? args.plan_id.trim() : "";
      if (!planID) return err("Error: plan_id is required");
      const existing = store.listPlans().find((p) => !p.isDeleted && p.id === planID);
      if (!existing) {
        return err(`No installment plan or loan found with id ${planID}. Use an id from the plans list.`);
      }
      if (typeof args.kind === "string" && args.kind.toLowerCase() !== existing.kind) {
        return err(
          `The kind of a plan cannot change. To turn it into a ${args.kind}, delete it (ask about its payments) and create a new one.`
        );
      }

      const planName =
        typeof args.name === "string" && args.name.trim() ? args.name.trim() : existing.name;
      const months =
        typeof args.months === "number" && Number.isInteger(args.months)
          ? args.months
          : existing.months;
      const firstDate =
        typeof args.first_payment_date === "string" && isValidDayKey(args.first_payment_date.trim())
          ? args.first_payment_date.trim()
          : existing.firstPaymentDayKey;
      const cat: CategoryID =
        typeof args.category === "string" && EXPENSE_CATEGORIES.includes(args.category as CategoryID)
          ? (args.category as CategoryID)
          : existing.category;
      const member =
        typeof args.member === "string" && args.member.trim()
          ? resolveWriteMember(args.member, config)
          : { id: existing.memberID, name: existing.memberName, avatarSymbol: "person.fill" };

      const ccy = existing.currency;
      const step = roundingStep(ccy);
      const rawAmountMajor =
        existing.kind === "loan"
          ? typeof args.amount_borrowed === "number"
            ? args.amount_borrowed
            : typeof args.total_amount === "number"
              ? args.total_amount
              : null
          : typeof args.total_amount === "number"
            ? args.total_amount
            : typeof args.amount_borrowed === "number"
              ? args.amount_borrowed
              : null;
      const amountMinor =
        rawAmountMajor !== null
          ? toStorageMinor(rawAmountMajor, ccy)
          : existing.kind === "loan"
            ? effectivePrincipalMinor(existing)
            : existing.totalMinor;

      const rawMonthly =
        typeof args.monthly_payment === "number" ? args.monthly_payment : null;
      const monthlyMinor =
        rawMonthly !== null
          ? toStorageMinor(rawMonthly, ccy)
          : existing.monthlyPaymentMinor ?? fullSchedule(existing)[0]?.amountMinor ?? 0;

      const roundedMonthly = roundHalfUp(monthlyMinor, step);
      let alreadyPaid =
        typeof args.already_paid_payments === "number" && Number.isInteger(args.already_paid_payments)
          ? args.already_paid_payments
          : effectiveAlreadyPaidCount(existing);
      if (args.all_due_payments_already_recorded === true) {
        const preview: InstallmentPlanRecord = {
          ...existing,
          name: planName,
          months,
          firstPaymentDayKey: firstDate,
          totalMinor: existing.kind === "loan" ? roundedMonthly * months : amountMinor,
          monthlyPaymentMinor: existing.kind === "loan" ? roundedMonthly : existing.monthlyPaymentMinor,
        };
        alreadyPaid = fullSchedule(preview).filter((p) => p.dayKey <= todayKey).length;
      }

      const issues = validateNewOrUpdatedPlan({
        kind: existing.kind,
        name: planName,
        amountMinor,
        monthlyPaymentMinor: monthlyMinor,
        months,
        firstPaymentDayKey: firstDate,
        currency: ccy,
        alreadyPaidCount: alreadyPaid,
        category: cat,
      });
      if (issues.length > 0) {
        return err(`Not saved. ${issues.join(" ")}`);
      }

      const updated: InstallmentPlanRecord = {
        ...existing,
        name: planName,
        months,
        firstPaymentDayKey: firstDate,
        category: cat,
        memberID: member.id,
        memberName: member.name,
        note: typeof args.note === "string" ? args.note.trim() : existing.note,
        alreadyPaidPaymentCount: alreadyPaid > 0 ? alreadyPaid : null,
        totalMinor: existing.kind === "loan" ? roundedMonthly * months : amountMinor,
        monthlyPaymentMinor: existing.kind === "loan" ? roundedMonthly : null,
        principalMinor: existing.kind === "loan" ? amountMinor : null,
        lender:
          existing.kind === "loan"
            ? typeof args.lender === "string"
              ? args.lender.trim() || null
              : existing.lender
            : null,
        linkURL:
          existing.kind === "loan"
            ? typeof args.link === "string"
              ? normalizeLink(args.link)
              : existing.linkURL
            : null,
        updatedAt: nowISO,
      };
      const saved = saveAndReconcilePlan(store, updated, todayKey, nowISO, true);
      return { text: planSaveOutput(saved, "Updated", todayKey, store), isError: false };
    }

    case "settle_installment_plan": {
      const planID = typeof args.plan_id === "string" ? args.plan_id.trim() : "";
      if (!planID) return err("Error: plan_id is required");
      const existing = store.listPlans().find((p) => !p.isDeleted && p.id === planID);
      if (!existing) return err(`No installment plan or loan found with id ${planID}.`);
      const dayKey =
        typeof args.settled_date === "string" && isValidDayKey(args.settled_date.trim())
          ? args.settled_date.trim()
          : todayKey;
      if (dayKey < existing.firstPaymentDayKey) {
        return err(
          `settled_date ${dayKey} is before the plan's first payment (${existing.firstPaymentDayKey}). Ask the user for the payoff date.`
        );
      }
      const preview = earlySettlementCompute(existing, dayKey, todayKey);
      const saved = saveAndReconcilePlan(
        store,
        { ...existing, settledDayKey: dayKey },
        todayKey,
        nowISO,
        true
      );
      const money = (m: number) => formatMoney(m, saved.currency);
      const pVal = preview.ok
        ? preview.value
        : { payoffPrincipalMinor: 0, interestSavedMinor: 0, cancelledPaymentCount: 0, bookedPaymentsRemovedCount: 0 };
      return {
        text: `Settled [id:${planID}] '${saved.name}' on ${dayKey}: principal paid off ${money(pVal.payoffPrincipalMinor)}, interest saved ${money(pVal.interestSavedMinor)}, ${pVal.cancelledPaymentCount} later payments cancelled (${pVal.bookedPaymentsRemovedCount} already-booked ones removed).`,
        isError: false,
      };
    }

    case "undo_plan_settlement": {
      const planID = typeof args.plan_id === "string" ? args.plan_id.trim() : "";
      if (!planID) return err("Error: plan_id is required");
      const existing = store.listPlans().find((p) => !p.isDeleted && p.id === planID);
      if (!existing) return err(`No installment plan or loan found with id ${planID}.`);
      if (!existing.settledDayKey) {
        return err(`Plan ${planID} is not settled, so there is nothing to undo.`);
      }
      const saved = saveAndReconcilePlan(
        store,
        { ...existing, settledDayKey: null },
        todayKey,
        nowISO,
        true
      );
      return {
        text: planSaveOutput(saved, "Undid the settlement of", todayKey, store),
        isError: false,
      };
    }

    case "delete_installment_plan": {
      const planID = typeof args.plan_id === "string" ? args.plan_id.trim() : "";
      if (!planID) return err("Error: plan_id is required");
      if (typeof args.remove_payments !== "boolean") {
        return err(
          "remove_payments is required. Ask the user whether to keep the payments already recorded as expenses or remove them too, then call again."
        );
      }
      const existing = store.listPlans().find((p) => !p.isDeleted && p.id === planID);
      if (!existing) return err(`No installment plan or loan found with id ${planID}.`);
      const removePayments = args.remove_payments;
      const bookedCount = store
        .listTransactions()
        .filter((tx) => !tx.isDeleted && tx.planID === planID && isPlanPayment(tx)).length;

      saveAndReconcilePlan(
        store,
        {
          ...existing,
          isDeleted: true,
          deletionRemovesPayments: removePayments,
          deletedDayKey: todayKey,
        },
        todayKey,
        nowISO,
        false
      );
      return {
        text: `Deleted [id:${planID}] '${existing.name}'; ${bookedCount} recorded payments ${
          removePayments ? "removed" : "kept as ordinary expenses"
        }.`,
        isError: false,
      };
    }

    default:
      return null;
  }
}
