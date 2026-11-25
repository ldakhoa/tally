import { DurableObject } from "cloudflare:workers";
import { handleMCPBody, type MCPHost } from "./mcp.ts";
import { todayKeyForOffsetMinutes } from "./money.ts";
import {
  authorizationServerMetadata,
  constantTimeEqual,
  handleOAuthAuthorizeGet,
  handleOAuthAuthorizePost,
  handleOAuthRegister,
  handleOAuthToken,
  protectedResourceMetadata,
  type OAuthStore,
} from "./oauth.ts";
import { mergeBudget, mergeGoal, mergePlan, mergeTransaction } from "./sync.ts";
import type {
  AdviserContext,
  BudgetLimitRecord,
  InstallmentPlanRecord,
  SavingsGoalRecord,
  TransactionRecord,
  VaultConfig,
  VaultConfigPatch,
  VaultStats,
  VaultSyncRequest,
  VaultSyncResponse,
} from "./types.ts";
import type { VaultWriteStore } from "./writes.ts";

export interface Env {
  VAULT: DurableObjectNamespace<TallyVault>;
  TALLY_SYNC_SECRET: string;
}

const DEFAULT_CONFIG: VaultConfig = {
  currency: "SGD",
  language: "en",
  timeZoneOffsetMinutes: 480,
  currentMember: { id: "member-primary", name: "Me", avatarSymbol: "person.fill" },
  members: [{ id: "member-primary", name: "Me", avatarSymbol: "person.fill" }],
  salaryHidden: false,
  allowsChanges: false,
  mcpEnabled: true,
  mcpToken: "",
};

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, Mcp-Protocol-Version",
  "Access-Control-Max-Age": "86400",
};

export class TallyVault extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS meta (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS transactions (
          id TEXT PRIMARY KEY,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL,
          payload TEXT NOT NULL,
          mcp_revision INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS budgets (
          id TEXT PRIMARY KEY,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL,
          payload TEXT NOT NULL,
          mcp_revision INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS goals (
          id TEXT PRIMARY KEY,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL,
          payload TEXT NOT NULL,
          mcp_revision INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS plans (
          id TEXT PRIMARY KEY,
          updated_at TEXT NOT NULL,
          is_deleted INTEGER NOT NULL,
          payload TEXT NOT NULL,
          mcp_revision INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS oauth_clients (
          client_id TEXT PRIMARY KEY,
          redirect_uris TEXT NOT NULL,
          client_name TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS oauth_codes (
          code TEXT PRIMARY KEY,
          client_id TEXT NOT NULL,
          redirect_uri TEXT NOT NULL,
          code_challenge TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          consumed INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS oauth_tokens (
          token TEXT PRIMARY KEY,
          client_id TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      `);
    });
  }

  // MARK: Meta helpers

  private getMeta(key: string): string | null {
    const rows = this.ctx.storage.sql
      .exec("SELECT value FROM meta WHERE key = ? LIMIT 1", key)
      .toArray();
    return rows.length > 0 ? String(rows[0].value) : null;
  }

  private setMeta(key: string, value: string): void {
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)",
      key,
      value
    );
  }

  private deleteMeta(key: string): void {
    this.ctx.storage.sql.exec("DELETE FROM meta WHERE key = ?", key);
  }

  private getConfig(): VaultConfig {
    const raw = this.getMeta("config");
    if (!raw) return { ...DEFAULT_CONFIG };
    try {
      return { ...DEFAULT_CONFIG, ...JSON.parse(raw) };
    } catch {
      return { ...DEFAULT_CONFIG };
    }
  }

  private saveConfig(next: VaultConfig): void {
    const previous = this.getConfig();
    if (previous.mcpToken && next.mcpToken && previous.mcpToken !== next.mcpToken) {
      this.ctx.storage.sql.exec("DELETE FROM oauth_tokens");
      this.ctx.storage.sql.exec("DELETE FROM oauth_codes");
    }
    this.setMeta("config", JSON.stringify(next));
  }

  private getVaultRevision(): number {
    const raw = this.getMeta("vault_revision");
    const parsed = raw ? Number(raw) : 0;
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private nextVaultRevision(): number {
    const next = this.getVaultRevision() + 1;
    this.setMeta("vault_revision", String(next));
    return next;
  }

  // MARK: Table reads & writes

  private readAll<T>(table: "transactions" | "budgets" | "goals" | "plans"): T[] {
    const rows = this.ctx.storage.sql
      .exec(`SELECT payload FROM ${table}`)
      .toArray();
    const out: T[] = [];
    for (const row of rows) {
      try {
        out.push(JSON.parse(String(row.payload)) as T);
      } catch {
        // Ignore malformed row
      }
    }
    return out;
  }

  private readById<T>(table: "transactions" | "budgets" | "goals" | "plans", id: string): T | null {
    const rows = this.ctx.storage.sql
      .exec(`SELECT payload FROM ${table} WHERE id = ? LIMIT 1`, id)
      .toArray();
    if (rows.length === 0) return null;
    try {
      return JSON.parse(String(rows[0].payload)) as T;
    } catch {
      return null;
    }
  }

  private readSinceRevision<T>(
    table: "transactions" | "budgets" | "goals" | "plans",
    sinceRevision: number
  ): T[] {
    const rows = this.ctx.storage.sql
      .exec(`SELECT payload FROM ${table} WHERE mcp_revision > ?`, sinceRevision)
      .toArray();
    const out: T[] = [];
    for (const row of rows) {
      try {
        out.push(JSON.parse(String(row.payload)) as T);
      } catch {
        // Ignore
      }
    }
    return out;
  }

  private writeRecord<T extends { id: string; updatedAt: string; isDeleted: boolean }>(
    table: "transactions" | "budgets" | "goals" | "plans",
    record: T,
    mcpRevision: number
  ): void {
    this.ctx.storage.sql.exec(
      `INSERT OR REPLACE INTO ${table} (id, updated_at, is_deleted, payload, mcp_revision) VALUES (?, ?, ?, ?, ?)`,
      record.id,
      record.updatedAt,
      record.isDeleted ? 1 : 0,
      JSON.stringify(record),
      mcpRevision
    );
  }

  private getStats(): VaultStats {
    const count = (table: string) => {
      const r = this.ctx.storage.sql
        .exec(`SELECT COUNT(*) AS c FROM ${table} WHERE is_deleted = 0`)
        .toArray();
      return Number(r[0]?.c ?? 0);
    };
    return {
      transactionCount: count("transactions"),
      budgetCount: count("budgets"),
      goalCount: count("goals"),
      planCount: count("plans"),
      lastSyncedAt: this.getMeta("last_synced_at"),
      lastMCPCallAt: this.getMeta("last_mcp_call_at"),
      lastMCPTool: this.getMeta("last_mcp_tool"),
    };
  }

  // MARK: RPC / Sync / Pairing handlers

  async sync(req: VaultSyncRequest): Promise<VaultSyncResponse> {
    const cfg = this.getConfig();
    const nextCfg: VaultConfig = {
      currency: req.currency ?? cfg.currency,
      language: req.language ?? cfg.language,
      timeZoneOffsetMinutes: req.timeZoneOffsetMinutes ?? cfg.timeZoneOffsetMinutes,
      currentMember: req.currentMember ?? cfg.currentMember,
      members: req.members ?? cfg.members,
      partnerDisplayName: req.partnerDisplayName ?? cfg.partnerDisplayName,
      salaryHidden: req.salaryHidden ?? cfg.salaryHidden,
      allowsChanges: req.allowsChanges ?? cfg.allowsChanges,
      mcpEnabled: req.mcpEnabled ?? cfg.mcpEnabled,
      mcpToken: req.mcpToken ?? cfg.mcpToken,
      exchangeRates: req.exchangeRates ?? cfg.exchangeRates,
    };
    this.saveConfig(nextCfg);

    // Sync writes arrive with mcp_revision = 0 so they aren't echoed right back as MCP changes.
    for (const tx of req.transactions ?? []) {
      const existing = this.readById<TransactionRecord>("transactions", tx.id);
      const merged = mergeTransaction(existing, tx);
      if (!existing || JSON.stringify(merged) !== JSON.stringify(existing)) {
        this.writeRecord("transactions", merged, 0);
      }
    }
    for (const b of req.budgets ?? []) {
      const existing = this.readById<BudgetLimitRecord>("budgets", b.id);
      const merged = mergeBudget(existing, b);
      if (!existing || JSON.stringify(merged) !== JSON.stringify(existing)) {
        this.writeRecord("budgets", merged, 0);
      }
    }
    for (const g of req.goals ?? []) {
      const existing = this.readById<SavingsGoalRecord>("goals", g.id);
      const merged = mergeGoal(existing, g);
      if (!existing || JSON.stringify(merged) !== JSON.stringify(existing)) {
        this.writeRecord("goals", merged, 0);
      }
    }
    for (const p of req.plans ?? []) {
      const existing = this.readById<InstallmentPlanRecord>("plans", p.id);
      const merged = mergePlan(existing, p);
      if (!existing || JSON.stringify(merged) !== JSON.stringify(existing)) {
        this.writeRecord("plans", merged, 0);
      }
    }

    const since = typeof req.sinceRevision === "number" ? req.sinceRevision : 0;
    const nowISO = new Date().toISOString();
    this.setMeta("last_synced_at", nowISO);

    return {
      ok: true,
      vaultRevision: this.getVaultRevision(),
      remoteChanges: {
        transactions: this.readSinceRevision<TransactionRecord>("transactions", since),
        budgets: this.readSinceRevision<BudgetLimitRecord>("budgets", since),
        goals: this.readSinceRevision<SavingsGoalRecord>("goals", since),
        plans: this.readSinceRevision<InstallmentPlanRecord>("plans", since),
      },
      stats: this.getStats(),
    };
  }

  async patchConfig(patch: VaultConfigPatch): Promise<{ ok: true; configSummary: Record<string, unknown> }> {
    const cfg = this.getConfig();
    const next: VaultConfig = {
      ...cfg,
      ...(patch.mcpEnabled !== undefined ? { mcpEnabled: patch.mcpEnabled } : {}),
      ...(patch.allowsChanges !== undefined ? { allowsChanges: patch.allowsChanges } : {}),
      ...(patch.salaryHidden !== undefined ? { salaryHidden: patch.salaryHidden } : {}),
      ...(patch.mcpToken !== undefined ? { mcpToken: patch.mcpToken } : {}),
      ...(patch.currency !== undefined ? { currency: patch.currency } : {}),
      ...(patch.timeZoneOffsetMinutes !== undefined
        ? { timeZoneOffsetMinutes: patch.timeZoneOffsetMinutes }
        : {}),
    };
    this.saveConfig(next);
    return {
      ok: true,
      configSummary: {
        mcpEnabled: next.mcpEnabled,
        allowsChanges: next.allowsChanges,
        salaryHidden: next.salaryHidden,
        currency: next.currency,
      },
    };
  }

  async createPairingCode(): Promise<{ code: string; expiresAt: string }> {
    const buf = new Uint32Array(1);
    crypto.getRandomValues(buf);
    const code = String(buf[0] % 1_000_000).padStart(6, "0");
    const expiresAtMs = Date.now() + 10 * 60_000;
    this.setMeta("pairing_code", code);
    this.setMeta("pairing_expires_at", String(expiresAtMs));
    this.setMeta("pairing_attempts", "0");
    return { code, expiresAt: new Date(expiresAtMs).toISOString() };
  }

  // MARK: OAuthStore & MCPHost bridges

  private makeOAuthStore(): OAuthStore {
    return {
      getClient: (clientId) => {
        const rows = this.ctx.storage.sql
          .exec(
            "SELECT client_id, redirect_uris, client_name FROM oauth_clients WHERE client_id = ? LIMIT 1",
            clientId
          )
          .toArray();
        if (rows.length === 0) return null;
        return {
          clientId: String(rows[0].client_id),
          redirectUris: JSON.parse(String(rows[0].redirect_uris)) as string[],
          clientName: String(rows[0].client_name),
        };
      },
      saveClient: (clientId, redirectUris, clientName, createdAt) => {
        this.ctx.storage.sql.exec(
          "INSERT OR REPLACE INTO oauth_clients (client_id, redirect_uris, client_name, created_at) VALUES (?, ?, ?, ?)",
          clientId,
          JSON.stringify(redirectUris),
          clientName,
          createdAt
        );
      },
      getPairingState: () => ({
        code: this.getMeta("pairing_code"),
        expiresAt: Number(this.getMeta("pairing_expires_at") ?? "0"),
        attempts: Number(this.getMeta("pairing_attempts") ?? "0"),
      }),
      incrementPairingAttempts: () => {
        const attempts = Number(this.getMeta("pairing_attempts") ?? "0") + 1;
        this.setMeta("pairing_attempts", String(attempts));
        if (attempts >= 5) {
          this.deleteMeta("pairing_code");
        }
      },
      clearPairingCode: () => {
        this.deleteMeta("pairing_code");
        this.deleteMeta("pairing_expires_at");
        this.deleteMeta("pairing_attempts");
      },
      getMCPToken: () => this.getConfig().mcpToken,
      saveAuthCode: ({ code, clientId, redirectUri, codeChallenge, expiresAt }) => {
        this.ctx.storage.sql.exec(
          "INSERT OR REPLACE INTO oauth_codes (code, client_id, redirect_uri, code_challenge, expires_at, consumed) VALUES (?, ?, ?, ?, ?, 0)",
          code,
          clientId,
          redirectUri,
          codeChallenge,
          expiresAt
        );
      },
      consumeAuthCode: (code, nowMs) => {
        const rows = this.ctx.storage.sql
          .exec(
            "SELECT client_id, redirect_uri, code_challenge, expires_at, consumed FROM oauth_codes WHERE code = ? LIMIT 1",
            code
          )
          .toArray();
        if (rows.length === 0) return null;
        const row = rows[0];
        if (Number(row.consumed) !== 0 || Number(row.expires_at) < nowMs) {
          return null;
        }
        this.ctx.storage.sql.exec("UPDATE oauth_codes SET consumed = 1 WHERE code = ?", code);
        return {
          clientId: String(row.client_id),
          redirectUri: String(row.redirect_uri),
          codeChallenge: String(row.code_challenge),
        };
      },
      saveAccessToken: (token, clientId, createdAt) => {
        this.ctx.storage.sql.exec(
          "INSERT OR REPLACE INTO oauth_tokens (token, client_id, created_at) VALUES (?, ?, ?)",
          token,
          clientId,
          createdAt
        );
      },
    };
  }

  private async isAuthorizedMCPToken(token: string): Promise<boolean> {
    if (!token) return false;
    const expected = this.getConfig().mcpToken;
    if (expected && (await constantTimeEqual(token, expected))) {
      return true;
    }
    const rows = this.ctx.storage.sql.exec("SELECT token FROM oauth_tokens").toArray();
    for (const row of rows) {
      if (await constantTimeEqual(token, String(row.token))) return true;
    }
    return false;
  }

  private makeMCPHost(): MCPHost {
    return {
      getConfig: () => this.getConfig(),
      getAdviserContext: (todayKey) => {
        const cfg = this.getConfig();
        return {
          transactions: this.readAll<TransactionRecord>("transactions"),
          budgets: this.readAll<BudgetLimitRecord>("budgets"),
          goals: this.readAll<SavingsGoalRecord>("goals"),
          plans: this.readAll<InstallmentPlanRecord>("plans"),
          currency: cfg.currency,
          todayKey,
          salaryHidden: cfg.salaryHidden,
          currentMemberID: cfg.currentMember.id,
          members: cfg.members,
        };
      },
      getWriteStore: (): VaultWriteStore => {
        let rev: number | null = null;
        const ensureRev = () => {
          if (rev === null) rev = this.nextVaultRevision();
          return rev;
        };
        return {
          getConfig: () => this.getConfig(),
          listTransactions: () => this.readAll<TransactionRecord>("transactions"),
          listBudgets: () => this.readAll<BudgetLimitRecord>("budgets"),
          listGoals: () => this.readAll<SavingsGoalRecord>("goals"),
          listPlans: () => this.readAll<InstallmentPlanRecord>("plans"),
          upsertTransaction: (r) => this.writeRecord("transactions", r, ensureRev()),
          upsertBudget: (r) => this.writeRecord("budgets", r, ensureRev()),
          upsertGoal: (r) => this.writeRecord("goals", r, ensureRev()),
          upsertPlan: (r) => this.writeRecord("plans", r, ensureRev()),
        };
      },
      recordToolCall: (name) => {
        this.setMeta("last_mcp_call_at", new Date().toISOString());
        this.setMeta("last_mcp_tool", name);
      },
    };
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const origin = url.origin;

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // OAuth discovery & endpoints
    if (
      request.method === "GET" &&
      (url.pathname === "/.well-known/oauth-protected-resource" ||
        url.pathname === "/.well-known/oauth-protected-resource/mcp")
    ) {
      return json(protectedResourceMetadata(origin), 200, CORS_HEADERS);
    }
    if (request.method === "GET" && url.pathname === "/.well-known/oauth-authorization-server") {
      return json(authorizationServerMetadata(origin), 200, CORS_HEADERS);
    }
    if (request.method === "POST" && url.pathname === "/oauth/register") {
      return handleOAuthRegister(request, this.makeOAuthStore(), CORS_HEADERS);
    }
    if (url.pathname === "/oauth/authorize") {
      if (request.method === "GET") return handleOAuthAuthorizeGet(url, this.makeOAuthStore());
      if (request.method === "POST") return handleOAuthAuthorizePost(request, this.makeOAuthStore());
      return new Response("Method Not Allowed", { status: 405 });
    }
    if (request.method === "POST" && url.pathname === "/oauth/token") {
      return handleOAuthToken(request, this.makeOAuthStore(), CORS_HEADERS);
    }

    // Sync/Admin endpoints (authenticated via TALLY_SYNC_SECRET at Worker entrypoint)
    if (url.pathname === "/v1/health" && request.method === "GET") {
      const cfg = this.getConfig();
      return json({
        ok: true,
        service: "tally-mcp-server",
        mcpEnabled: cfg.mcpEnabled,
        allowsChanges: cfg.allowsChanges,
        stats: this.getStats(),
      });
    }
    if (url.pathname === "/v1/sync" && request.method === "POST") {
      const payload = (await request.json().catch(() => null)) as VaultSyncRequest | null;
      if (!payload) return json({ error: "invalid_json" }, 400);
      return json(await this.sync(payload));
    }
    if (url.pathname === "/v1/config" && request.method === "POST") {
      const payload = (await request.json().catch(() => null)) as VaultConfigPatch | null;
      if (!payload) return json({ error: "invalid_json" }, 400);
      return json(await this.patchConfig(payload));
    }
    if (url.pathname === "/v1/pairing-code" && request.method === "POST") {
      return json(await this.createPairingCode());
    }

    // MCP endpoints
    const tokenMatch = /^\/u\/([^/]+)\/mcp$/.exec(url.pathname);
    const isStandardMCP = url.pathname === "/mcp";

    if (isStandardMCP || tokenMatch) {
      let authorized = false;
      if (tokenMatch) {
        const pathToken = decodeURIComponent(tokenMatch[1]);
        const expected = this.getConfig().mcpToken;
        authorized = Boolean(expected) && (await constantTimeEqual(pathToken, expected));
      } else {
        const auth = request.headers.get("authorization") ?? "";
        if (auth.toLowerCase().startsWith("bearer ")) {
          const bearer = auth.slice(7).trim();
          authorized = await this.isAuthorizedMCPToken(bearer);
        }
      }

      if (!authorized) {
        return new Response("Missing or wrong bearer token\n", {
          status: 401,
          headers: {
            "Content-Type": "text/plain; charset=utf-8",
            "WWW-Authenticate": `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource"`,
            ...CORS_HEADERS,
          },
        });
      }

      const cfg = this.getConfig();
      if (!cfg.mcpEnabled) {
        return new Response("Tally Cloud MCP is paused in Tally settings.\n", {
          status: 503,
          headers: { "Content-Type": "text/plain; charset=utf-8", ...CORS_HEADERS },
        });
      }

      if (request.method !== "POST") {
        return new Response("Use POST\n", {
          status: 405,
          headers: {
            "Content-Type": "text/plain; charset=utf-8",
            Allow: "POST",
            ...CORS_HEADERS,
          },
        });
      }

      const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
      if (!contentType.includes("application/json")) {
        return new Response("Content-Type must be application/json\n", {
          status: 415,
          headers: { "Content-Type": "text/plain; charset=utf-8", ...CORS_HEADERS },
        });
      }

      const body = await request.text();
      const reply = await handleMCPBody(body, this.makeMCPHost());
      if (reply === null) {
        return new Response(null, { status: 202, headers: CORS_HEADERS });
      }
      return new Response(reply, {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          ...CORS_HEADERS,
        },
      });
    }

    return json({ error: "not_found" }, 404, CORS_HEADERS);
  }
}

async function isSyncAuthorized(request: Request, env: Env): Promise<boolean> {
  const expected = env.TALLY_SYNC_SECRET?.trim() ?? "";
  if (!expected) return false;
  const auth = request.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return false;
  const token = auth.slice(7).trim();
  return token.length > 0 && constantTimeEqual(token, expected);
}

function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...extraHeaders },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/v1/")) {
      if (!(await isSyncAuthorized(request, env))) {
        return json({ error: "unauthorized" }, 401);
      }
    }
    const id = env.VAULT.idFromName("household-default");
    const stub = env.VAULT.get(id);
    return stub.fetch(request);
  },
};
