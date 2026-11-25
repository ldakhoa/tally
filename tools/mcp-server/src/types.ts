export type CurrencyCode =
  | "SGD"
  | "VND"
  | "USD"
  | "EUR"
  | "GBP"
  | "AUD"
  | "CAD"
  | "MYR"
  | "HKD"
  | "CNY"
  | "JPY"
  | "KRW"
  | "THB"
  | "TWD"
  | "IDR"
  | "PHP"
  | "NZD"
  | "CHF"
  | "INR";

export type TransactionType = "expense" | "income";

export type CategoryID =
  | "housing"
  | "food"
  | "transport"
  | "shopping"
  | "bills"
  | "health"
  | "entertainment"
  | "other"
  | "salary"
  | "freelance"
  | "income";

export const EXPENSE_CATEGORIES: CategoryID[] = [
  "food",
  "housing",
  "transport",
  "shopping",
  "bills",
  "health",
  "entertainment",
  "other",
];

export const INCOME_CATEGORIES: CategoryID[] = ["salary", "freelance", "income"];

export const ALL_CATEGORIES: CategoryID[] = [...EXPENSE_CATEGORIES, ...INCOME_CATEGORIES];

export type TransactionSource =
  | "manual"
  | "applePay"
  | "bankEmail"
  | "bankNotification"
  | "shortcut"
  | "aiQuickAdd"
  | "imported";

export type GoalIcon = "target" | "shield" | "plane" | "laptop" | "house" | "heart";

export const GOAL_ICONS: GoalIcon[] = ["target", "shield", "plane", "laptop", "house", "heart"];

export type InstallmentKind = "installment" | "loan";

export interface PlanPaymentContent {
  name: string;
  amountMinor: number;
  type: TransactionType;
  category: CategoryID;
  dayKey: string;
  createdAt: string;
  note: string;
  source: TransactionSource;
  rawSourceText?: string | null;
  memberID: string;
  memberName: string;
  needsReview: boolean;
  isDeleted: boolean;
}

export interface PlanPaymentUserWrite {
  at: string;
  content: PlanPaymentContent;
}

export interface PlanPaymentScheduleWrite {
  planRevision: string;
  content: PlanPaymentContent;
}

export interface PlanPaymentState {
  user?: PlanPaymentUserWrite | null;
  schedule?: PlanPaymentScheduleWrite | null;
}

export interface TransactionRecord {
  id: string;
  name: string;
  amountMinor: number;
  type: TransactionType;
  category: CategoryID;
  dayKey: string;
  createdAt: string;
  note: string;
  source: TransactionSource;
  rawSourceText?: string | null;
  memberID: string;
  memberName: string;
  needsReview: boolean;
  updatedAt: string;
  isDeleted: boolean;
  planID?: string | null;
  planPaymentIndex?: number | null;
  paymentState?: PlanPaymentState | null;
  originalAmountMinor?: number | null;
  originalCurrencyCode?: string | null;
  exchangeRate?: number | null;
}

export interface BudgetLimitRecord {
  id: string;
  monthKey: string;
  category: CategoryID;
  limitMinor: number;
  updatedAt: string;
  isDeleted: boolean;
}

export interface SavingsGoalRecord {
  id: string;
  name: string;
  icon: GoalIcon;
  targetMinor: number;
  savedMinor: number;
  updatedAt: string;
  isDeleted: boolean;
}

export interface InstallmentPlanRecord {
  id: string;
  name: string;
  kind: InstallmentKind;
  totalMinor: number;
  months: number;
  firstPaymentDayKey: string;
  category: CategoryID;
  memberID: string;
  memberName: string;
  note: string;
  currency: CurrencyCode;
  monthlyPaymentMinor?: number | null;
  principalMinor?: number | null;
  sourceTransactionID?: string | null;
  lender?: string | null;
  linkURL?: string | null;
  settledDayKey?: string | null;
  deletionRemovesPayments?: boolean | null;
  deletedDayKey?: string | null;
  alreadyPaidPaymentCount?: number | null;
  createdAt: string;
  updatedAt: string;
  isDeleted: boolean;
}

export interface HouseholdMember {
  id: string;
  name: string;
  avatarSymbol: string;
}

export interface ExchangeRateTablePayload {
  ratesPerSGD: Record<string, number>;
  rateDate?: string | null;
  fetchedAt?: string | null;
}

export interface VaultConfig {
  currency: CurrencyCode;
  language: string;
  timeZoneOffsetMinutes: number;
  currentMember: HouseholdMember;
  members: HouseholdMember[];
  partnerDisplayName?: string;
  salaryHidden: boolean;
  allowsChanges: boolean;
  mcpEnabled: boolean;
  mcpToken: string;
  exchangeRates?: ExchangeRateTablePayload;
}

export interface VaultSyncRequest {
  currency?: CurrencyCode;
  language?: string;
  timeZoneOffsetMinutes?: number;
  currentMember?: HouseholdMember;
  members?: HouseholdMember[];
  partnerDisplayName?: string;
  salaryHidden?: boolean;
  allowsChanges?: boolean;
  mcpEnabled?: boolean;
  mcpToken?: string;
  exchangeRates?: ExchangeRateTablePayload;
  transactions?: TransactionRecord[];
  budgets?: BudgetLimitRecord[];
  goals?: SavingsGoalRecord[];
  plans?: InstallmentPlanRecord[];
  sinceRevision?: number;
}

export interface VaultStats {
  transactionCount: number;
  budgetCount: number;
  goalCount: number;
  planCount: number;
  lastSyncedAt: string | null;
  lastMCPCallAt: string | null;
  lastMCPTool: string | null;
}

export interface VaultSyncResponse {
  ok: boolean;
  vaultRevision: number;
  remoteChanges: {
    transactions: TransactionRecord[];
    budgets: BudgetLimitRecord[];
    goals: SavingsGoalRecord[];
    plans: InstallmentPlanRecord[];
  };
  stats: VaultStats;
}

export interface VaultConfigPatch {
  mcpEnabled?: boolean;
  allowsChanges?: boolean;
  salaryHidden?: boolean;
  mcpToken?: string;
  currency?: CurrencyCode;
  timeZoneOffsetMinutes?: number;
}

export interface MCPToolDefinition {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  readOnly: boolean;
  destructive?: boolean;
}

export interface MCPToolResult {
  text: string;
  isError: boolean;
}

export interface AdviserContext {
  transactions: TransactionRecord[];
  budgets: BudgetLimitRecord[];
  goals: SavingsGoalRecord[];
  plans: InstallmentPlanRecord[];
  currency: CurrencyCode;
  todayKey: string;
  salaryHidden: boolean;
  currentMemberID: string;
  members: HouseholdMember[];
}
