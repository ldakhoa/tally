import assert from "node:assert/strict";
import test from "node:test";
import { externalInstructions, runReadTool } from "../src/adviser.ts";
import { handleMCPBody, type MCPHost } from "../src/mcp.ts";
import { formatMoney, todayKeyForOffsetMinutes, toStorageMinor } from "../src/money.ts";
import {
  authorizationServerMetadata,
  handleOAuthAuthorizeGet,
  handleOAuthAuthorizePost,
  handleOAuthRegister,
  handleOAuthToken,
  protectedResourceMetadata,
  sha256Base64Url,
  type OAuthStore,
} from "../src/oauth.ts";
import { earlySettlementCompute } from "../src/plans.ts";
import { mergeBudget, mergeGoal, mergePlan, mergeTransaction } from "../src/sync.ts";
import type {
  BudgetLimitRecord,
  InstallmentPlanRecord,
  SavingsGoalRecord,
  TransactionRecord,
  VaultConfig,
} from "../src/types.ts";
import type { VaultWriteStore } from "../src/writes.ts";

function makeConfig(overrides: Partial<VaultConfig> = {}): VaultConfig {
  return {
    currency: "SGD",
    language: "en",
    timeZoneOffsetMinutes: 480,
    currentMember: { id: "me", name: "Alex", avatarSymbol: "person.fill" },
    members: [
      { id: "me", name: "Alex", avatarSymbol: "person.fill" },
      { id: "p", name: "Sam", avatarSymbol: "person.fill" },
    ],
    partnerDisplayName: "Sam",
    salaryHidden: false,
    allowsChanges: false,
    mcpEnabled: true,
    mcpToken: "mcp-secret-token",
    ...overrides,
  };
}

function makeHarness(configOverrides: Partial<VaultConfig> = {}) {
  const config = makeConfig(configOverrides);
  const txs = new Map<string, TransactionRecord>();
  const budgets = new Map<string, BudgetLimitRecord>();
  const goals = new Map<string, SavingsGoalRecord>();
  const plans = new Map<string, InstallmentPlanRecord>();
  const calledTools: string[] = [];

  const writeStore: VaultWriteStore = {
    getConfig: () => config,
    listTransactions: () => [...txs.values()],
    listBudgets: () => [...budgets.values()],
    listGoals: () => [...goals.values()],
    listPlans: () => [...plans.values()],
    upsertTransaction: (r) => txs.set(r.id, r),
    upsertBudget: (r) => budgets.set(r.id, r),
    upsertGoal: (r) => goals.set(r.id, r),
    upsertPlan: (r) => plans.set(r.id, r),
  };

  const host: MCPHost = {
    getConfig: () => config,
    getAdviserContext: (todayKey) => ({
      transactions: [...txs.values()],
      budgets: [...budgets.values()],
      goals: [...goals.values()],
      plans: [...plans.values()],
      currency: config.currency,
      todayKey,
      salaryHidden: config.salaryHidden,
      currentMemberID: config.currentMember.id,
      members: config.members,
    }),
    getWriteStore: () => writeStore,
    recordToolCall: (name) => calledTools.push(name),
  };

  return { config, txs, budgets, goals, plans, calledTools, host };
}

function seedTransactions(txs: Map<string, TransactionRecord>) {
  const rows: TransactionRecord[] = [
    {
      id: "tx-sal-10",
      name: "salary",
      amountMinor: 500_000,
      type: "income",
      category: "salary",
      dayKey: "2026-10-01",
      createdAt: "2026-10-01T01:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-10-01T01:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-food-10",
      name: "Phở Hà Nội",
      amountMinor: 4_000,
      type: "expense",
      category: "food",
      dayKey: "2026-10-05",
      createdAt: "2026-10-05T05:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-10-05T05:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-shop-10",
      name: "IKEA",
      amountMinor: 30_000,
      type: "expense",
      category: "shopping",
      dayKey: "2026-10-06",
      createdAt: "2026-10-06T05:00:00Z",
      note: "sofa deposit",
      source: "manual",
      memberID: "p",
      memberName: "Sam",
      needsReview: false,
      updatedAt: "2026-10-06T05:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-sal-11",
      name: "salary",
      amountMinor: 500_000,
      type: "income",
      category: "salary",
      dayKey: "2026-11-01",
      createdAt: "2026-11-01T01:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-11-01T01:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-free-11",
      name: "Design gig",
      amountMinor: 20_000,
      type: "income",
      category: "freelance",
      dayKey: "2026-11-03",
      createdAt: "2026-11-03T01:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-11-03T01:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-food-11",
      name: "Lunch",
      amountMinor: 2_500,
      type: "expense",
      category: "food",
      dayKey: "2026-11-10",
      createdAt: "2026-11-10T04:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-11-10T04:00:00Z",
      isDeleted: false,
    },
    {
      id: "tx-tr-11",
      name: "Grab",
      amountMinor: 6_000,
      type: "expense",
      category: "transport",
      dayKey: "2026-11-12",
      createdAt: "2026-11-12T04:00:00Z",
      note: "",
      source: "manual",
      memberID: "me",
      memberName: "Alex",
      needsReview: false,
      updatedAt: "2026-11-12T04:00:00Z",
      isDeleted: false,
    },
  ];
  for (const r of rows) txs.set(r.id, r);
}

test("money formatting, VND zero-decimal, and timezone todayKey match Swift", () => {
  assert.equal(formatMoney(-6000, "SGD"), "−S$60.00");
  assert.equal(formatMoney(20000, "SGD", { signed: true }), "+S$200.00");
  assert.equal(formatMoney(toStorageMinor(65000, "VND"), "VND"), "65.000 ₫");
  assert.equal(formatMoney(-12500000, "VND"), "−125.000 ₫");

  // 2026-11-24T17:00:00Z at UTC+8 (480 min) is 2026-11-25
  const utcDate = new Date("2026-11-24T17:00:00.000Z");
  assert.equal(todayKeyForOffsetMinutes(480, utcDate), "2026-11-25");
  assert.equal(todayKeyForOffsetMinutes(0, utcDate), "2026-11-24");
});

test("read tools: get_overview, list_transactions diacritic/FX search, summarize_period, and salary hiding", async () => {
  const h = makeHarness();
  seedTransactions(h.txs);
  h.goals.set("g1", {
    id: "g1",
    name: "Japan trip",
    icon: "plane",
    targetMinor: 400_000,
    savedMinor: 100_000,
    updatedAt: "2026-11-01T00:00:00Z",
    isDeleted: false,
  });

  const now = new Date("2026-11-24T04:00:00.000Z");
  const overviewRes = runReadTool("get_overview", {}, h.host.getAdviserContext("2026-11-24"));
  assert.ok(overviewRes && !overviewRes.isError);
  assert.match(overviewRes.text, /Currency: SGD/);
  assert.match(overviewRes.text, /Today: 2026-11-24 \(Tuesday\)/);
  assert.match(overviewRes.text, /Japan trip: S\$1,000\.00 \/ S\$4,000\.00 \(25%\)/);
  assert.match(overviewRes.text, /Salary: visible\./);

  const searchRes = runReadTool(
    "list_transactions",
    { search: "pho ha noi" },
    h.host.getAdviserContext("2026-11-24")
  );
  assert.ok(searchRes && !searchRes.isError);
  const parsedSearch = JSON.parse(searchRes.text);
  assert.equal(parsedSearch.total_matching, 1);
  assert.equal(parsedSearch.transactions[0].name, "Phở Hà Nội");

  const badDate = runReadTool(
    "list_transactions",
    { end_date: "2026-02-30" },
    h.host.getAdviserContext("2026-11-24")
  );
  assert.ok(badDate?.isError);

  // Salary hidden mode
  h.config.salaryHidden = true;
  const hiddenList = runReadTool(
    "list_transactions",
    {},
    h.host.getAdviserContext("2026-11-24")
  );
  assert.ok(hiddenList);
  const hiddenJson = JSON.parse(hiddenList.text);
  assert.equal(hiddenJson.total_matching, 5);
  assert.ok(hiddenJson.salary_hidden);
  assert.equal(hiddenList.text.includes("5,000"), false);

  const hiddenSummary = runReadTool(
    "summarize_period",
    { month: "2026-11" },
    h.host.getAdviserContext("2026-11-24")
  );
  assert.ok(hiddenSummary);
  assert.match(hiddenSummary.text, /locked \(salary hidden\)/);
  assert.equal(hiddenSummary.text.includes("5,000"), false);
  void now;
});

test("loan amortization & early settlement math matches Swift", () => {
  const plan: InstallmentPlanRecord = {
    id: "loan-1",
    name: "Car loan",
    kind: "loan",
    totalMinor: 1_200_000,
    months: 12,
    firstPaymentDayKey: "2026-06-01",
    category: "bills",
    memberID: "me",
    memberName: "Alex",
    note: "",
    currency: "SGD",
    monthlyPaymentMinor: 100_000,
    principalMinor: 1_100_000,
    createdAt: "2026-06-01T00:00:00Z",
    updatedAt: "2026-06-01T00:00:00Z",
    isDeleted: false,
  };
  const settlement = earlySettlementCompute(plan, "2026-09-01", "2026-09-01");
  assert.equal(settlement.ok, true);
  if (settlement.ok) {
    assert.equal(settlement.value.cancelledPaymentCount, 8);
    assert.ok(settlement.value.payoffPrincipalMinor > 0);
    assert.ok(settlement.value.interestSavedMinor > 0);
  }
});

test("MCP protocol + write tool gating + FX conversion + plan materialization", async () => {
  const h = makeHarness({ allowsChanges: false });
  const now = new Date("2026-11-24T04:00:00.000Z");

  // Initialize
  const initRaw = await handleMCPBody(
    JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: { protocolVersion: "2025-06-18" },
    }),
    h.host,
    now
  );
  assert.ok(initRaw);
  const init = JSON.parse(initRaw);
  assert.equal(init.result.protocolVersion, "2025-06-18");
  assert.match(externalInstructions("SGD", false), /read-only/);

  // Write rejected when allowsChanges = false
  const blockedRaw = await handleMCPBody(
    JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "tools/call",
      params: {
        name: "add_transactions",
        arguments: { items: [{ name: "Coffee", amount: 4.5, type: "expense", category: "food" }] },
      },
    }),
    h.host,
    now
  );
  const blocked = JSON.parse(blockedRaw!);
  assert.equal(blocked.result.isError, true);

  // Enable writes
  h.config.allowsChanges = true;
  const listRaw = await handleMCPBody(
    JSON.stringify({ jsonrpc: "2.0", id: 3, method: "tools/list" }),
    h.host,
    now
  );
  const tools = JSON.parse(listRaw!).result.tools as Array<{ name: string }>;
  assert.equal(tools.length, 25);

  const addRaw = await handleMCPBody(
    JSON.stringify({
      jsonrpc: "2.0",
      id: 4,
      method: "tools/call",
      params: {
        name: "add_transactions",
        arguments: {
          items: [{ name: "PinDuoDuo", amount: 83.75, currency: "HKD", type: "expense", category: "shopping" }],
        },
      },
    }),
    h.host,
    now
  );
  const addReply = JSON.parse(addRaw!);
  assert.equal(addReply.result.isError, false);
  assert.equal(h.txs.size, 1);
  const savedTx = [...h.txs.values()][0];
  assert.equal(savedTx.originalCurrencyCode, "HKD");
  assert.equal(savedTx.originalAmountMinor, 8375);

  // Create installment plan with 2 due payments -> materializes 2 expenses
  const planRaw = await handleMCPBody(
    JSON.stringify({
      jsonrpc: "2.0",
      id: 5,
      method: "tools/call",
      params: {
        name: "create_installment_plan",
        arguments: {
          kind: "installment",
          name: "iPhone",
          total_amount: 1200,
          months: 12,
          first_payment_date: "2026-10-15",
        },
      },
    }),
    h.host,
    now
  );
  const planReply = JSON.parse(planRaw!);
  assert.equal(planReply.result.isError, false);
  assert.match(planReply.result.content[0].text, /2 payments due so far/);
});

test("LWW sync merge preserves tombstones and joins plan payment states", () => {
  const older: TransactionRecord = {
    id: "t1",
    name: "Lunch",
    amountMinor: 1000,
    type: "expense",
    category: "food",
    dayKey: "2026-11-20",
    createdAt: "2026-11-20T04:00:00Z",
    note: "",
    source: "manual",
    memberID: "me",
    memberName: "Alex",
    needsReview: false,
    updatedAt: "2026-11-20T04:00:00Z",
    isDeleted: false,
  };
  const deletedNewer: TransactionRecord = {
    ...older,
    isDeleted: true,
    updatedAt: "2026-11-21T04:00:00Z",
  };
  assert.equal(mergeTransaction(older, deletedNewer).isDeleted, true);
  assert.equal(mergeTransaction(deletedNewer, older).isDeleted, true);

  // Equal timestamp tie-break prefers tombstone
  const sameTimeDeleted: TransactionRecord = { ...older, isDeleted: true };
  assert.equal(mergeTransaction(older, sameTimeDeleted).isDeleted, true);

  // Budget / Goal / Plan merges
  const b1: BudgetLimitRecord = {
    id: "2026-11/food",
    monthKey: "2026-11",
    category: "food",
    limitMinor: 50000,
    updatedAt: "2026-11-01T00:00:00Z",
    isDeleted: false,
  };
  const b2: BudgetLimitRecord = { ...b1, limitMinor: 60000, updatedAt: "2026-11-02T00:00:00Z" };
  assert.equal(mergeBudget(b1, b2).limitMinor, 60000);

  const g1: SavingsGoalRecord = {
    id: "g1",
    name: "Trip",
    icon: "plane",
    targetMinor: 100000,
    savedMinor: 10000,
    updatedAt: "2026-11-01T00:00:00Z",
    isDeleted: false,
  };
  const g2: SavingsGoalRecord = { ...g1, savedMinor: 20000, updatedAt: "2026-11-02T00:00:00Z" };
  assert.equal(mergeGoal(g1, g2).savedMinor, 20000);

  const p1: InstallmentPlanRecord = {
    id: "p1",
    name: "Mac",
    kind: "installment",
    totalMinor: 200000,
    months: 12,
    firstPaymentDayKey: "2026-11-01",
    category: "shopping",
    memberID: "me",
    memberName: "Alex",
    note: "",
    currency: "SGD",
    createdAt: "2026-11-01T00:00:00Z",
    updatedAt: "2026-11-01T00:00:00Z",
    isDeleted: false,
  };
  const p2: InstallmentPlanRecord = { ...p1, settledDayKey: "2026-11-15", updatedAt: "2026-11-15T00:00:00Z" };
  assert.equal(mergePlan(p1, p2).settledDayKey, "2026-11-15");
});

test("OAuth 2.1 + PKCE S256 + DCR + HTML escaping + pairing attempt lockout", async () => {
  const clients = new Map<string, { clientId: string; redirectUris: string[]; clientName: string }>();
  const codes = new Map<
    string,
    { clientId: string; redirectUri: string; codeChallenge: string; expiresAt: number; consumed: boolean }
  >();
  const tokens = new Map<string, string>();
  let pairingCode: string | null = "654321";
  let pairingExpiresAt = 1_000_000;
  let pairingAttempts = 0;

  const store: OAuthStore = {
    getClient: (id) => clients.get(id) ?? null,
    saveClient: (clientId, redirectUris, clientName) => {
      clients.set(clientId, { clientId, redirectUris, clientName });
    },
    getPairingState: () => ({ code: pairingCode, expiresAt: pairingExpiresAt, attempts: pairingAttempts }),
    incrementPairingAttempts: () => {
      pairingAttempts += 1;
      if (pairingAttempts >= 5) pairingCode = null;
    },
    clearPairingCode: () => {
      pairingCode = null;
    },
    getMCPToken: () => "master-mcp-token",
    saveAuthCode: ({ code, clientId, redirectUri, codeChallenge, expiresAt }) => {
      codes.set(code, { clientId, redirectUri, codeChallenge, expiresAt, consumed: false });
    },
    consumeAuthCode: (code, nowMs) => {
      const rec = codes.get(code);
      if (!rec || rec.consumed || rec.expiresAt < nowMs) return null;
      rec.consumed = true;
      return { clientId: rec.clientId, redirectUri: rec.redirectUri, codeChallenge: rec.codeChallenge };
    },
    saveAccessToken: (token, clientId) => {
      tokens.set(token, clientId);
    },
  };

  assert.equal(protectedResourceMetadata("https://tally.example.workers.dev").resource, "https://tally.example.workers.dev/mcp");
  assert.equal(authorizationServerMetadata("https://tally.example.workers.dev").token_endpoint, "https://tally.example.workers.dev/oauth/token");

  // DCR with XSS-like client_name verifies escaping
  const regRes = await handleOAuthRegister(
    new Request("https://tally.example.workers.dev/oauth/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        client_name: '<script>alert("x")</script>',
        redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
      }),
    }),
    store,
    {}
  );
  assert.equal(regRes.status, 201);
  const reg = (await regRes.json()) as { client_id: string };

  const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
  const challenge = await sha256Base64Url(verifier);
  const authUrl = new URL("https://tally.example.workers.dev/oauth/authorize");
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("client_id", reg.client_id);
  authUrl.searchParams.set("redirect_uri", "https://claude.ai/api/mcp/auth_callback");
  authUrl.searchParams.set("state", "xyz");
  authUrl.searchParams.set("code_challenge", challenge);
  authUrl.searchParams.set("code_challenge_method", "S256");

  const getPage = handleOAuthAuthorizeGet(authUrl, store);
  assert.equal(getPage.status, 200);
  const html = await getPage.text();
  assert.equal(html.includes("<script>alert"), false);
  assert.match(html, /&lt;script&gt;alert/);

  // Wrong code fails 401
  const badForm = new URLSearchParams({
    client_id: reg.client_id,
    redirect_uri: "https://claude.ai/api/mcp/auth_callback",
    state: "xyz",
    code_challenge: challenge,
    code_challenge_method: "S256",
    pairing_code: "000000",
  });
  const badAuth = await handleOAuthAuthorizePost(
    new Request("https://tally.example.workers.dev/oauth/authorize", {
      method: "POST",
      body: badForm.toString(),
    }),
    store,
    1000
  );
  assert.equal(badAuth.status, 401);

  // Good code redirects with auth code
  badForm.set("pairing_code", "654321");
  const okAuth = await handleOAuthAuthorizePost(
    new Request("https://tally.example.workers.dev/oauth/authorize", {
      method: "POST",
      body: badForm.toString(),
    }),
    store,
    1000
  );
  assert.equal(okAuth.status, 302);
  const loc = new URL(okAuth.headers.get("Location")!);
  const authCode = loc.searchParams.get("code")!;
  assert.equal(loc.searchParams.get("state"), "xyz");

  // Token exchange
  const tokenRes = await handleOAuthToken(
    new Request("https://tally.example.workers.dev/oauth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code: authCode,
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        client_id: reg.client_id,
        code_verifier: verifier,
      }).toString(),
    }),
    store,
    {},
    2000
  );
  assert.equal(tokenRes.status, 200);
  const tokenBody = (await tokenRes.json()) as { access_token: string; token_type: string };
  assert.equal(tokenBody.token_type, "Bearer");
  assert.ok(tokens.has(tokenBody.access_token));
});
