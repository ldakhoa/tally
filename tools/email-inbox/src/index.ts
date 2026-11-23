import { DurableObject } from "cloudflare:workers";

export interface Env {
  INBOX: DurableObjectNamespace<EmailInbox>;
  /** Shared bearer secret set via `wrangler secret put INBOX_SECRET`. */
  INBOX_SECRET: string;
  /** Optional default member label when forwarded via Cloudflare Email Routing. */
  DEFAULT_MEMBER?: string;
}

export interface BankAlertItem {
  id: string;
  subject: string;
  sender: string;
  body: string;
  member: string;
  receivedAt: string;
}

/**
 * SQLite-backed Durable Object holding pending bank alert emails until Tally iOS pulls
 * and acknowledges them (privacy-first: ack deletes items immediately).
 */
export class EmailInbox extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS alerts (
          id TEXT PRIMARY KEY,
          subject TEXT NOT NULL,
          sender TEXT NOT NULL,
          body TEXT NOT NULL,
          member TEXT NOT NULL,
          received_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS seen_ids (
          id TEXT PRIMARY KEY,
          seen_at TEXT NOT NULL
        );
      `);
    });
  }

  async enqueue(item: BankAlertItem, force = false): Promise<{ accepted: boolean; duplicate: boolean }> {
    if (!force) {
      const existing = this.ctx.storage.sql
        .exec("SELECT 1 FROM seen_ids WHERE id = ? LIMIT 1", item.id)
        .toArray();
      if (existing.length > 0) {
        return { accepted: false, duplicate: true };
      }
    }

    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO alerts (id, subject, sender, body, member, received_at) VALUES (?, ?, ?, ?, ?, ?)",
      item.id,
      item.subject.slice(0, 300),
      item.sender.slice(0, 200),
      item.body.slice(0, 8000),
      item.member.slice(0, 80),
      item.receivedAt
    );
    this.ctx.storage.sql.exec(
      "INSERT OR REPLACE INTO seen_ids (id, seen_at) VALUES (?, ?)",
      item.id,
      item.receivedAt
    );

    // Keep seen_ids bounded (latest 2000 message IDs)
    this.ctx.storage.sql.exec(`
      DELETE FROM seen_ids WHERE id NOT IN (
        SELECT id FROM seen_ids ORDER BY seen_at DESC LIMIT 2000
      )
    `);
    return { accepted: true, duplicate: false };
  }

  async list(limit = 50): Promise<BankAlertItem[]> {
    const rows = this.ctx.storage.sql
      .exec(
        "SELECT id, subject, sender, body, member, received_at FROM alerts ORDER BY received_at ASC LIMIT ?",
        Math.min(Math.max(limit, 1), 100)
      )
      .toArray();
    return rows.map((row) => ({
      id: String(row.id),
      subject: String(row.subject),
      sender: String(row.sender),
      body: String(row.body),
      member: String(row.member),
      receivedAt: String(row.received_at),
    }));
  }

  async ack(ids: string[]): Promise<number> {
    let removed = 0;
    for (const id of ids) {
      if (typeof id !== "string" || !id) continue;
      const cursor = this.ctx.storage.sql.exec("DELETE FROM alerts WHERE id = ?", id);
      removed += cursor.rowsWritten;
    }
    return removed;
  }
}

async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const ha = await crypto.subtle.digest("SHA-256", enc.encode(a));
  const hb = await crypto.subtle.digest("SHA-256", enc.encode(b));
  const va = new Uint8Array(ha);
  const vb = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

async function isAuthorized(request: Request, env: Env): Promise<boolean> {
  const expected = env.INBOX_SECRET?.trim() ?? "";
  if (!expected) return false;
  const auth = request.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return false;
  const token = auth.slice(7).trim();
  return token.length > 0 && constantTimeEqual(token, expected);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function extractPlainTextFromRawEmail(raw: string): string {
  const splitIdx = raw.indexOf("\r\n\r\n");
  const body = splitIdx >= 0 ? raw.slice(splitIdx + 4) : raw;
  // Strip HTML tags and collapse whitespace so bank HTML emails become clean plain text.
  return body
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/=\r?\n/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function getInboxStub(env: Env): DurableObjectStub<EmailInbox> {
  const id = env.INBOX.idFromName("household-default");
  return env.INBOX.get(id);
}

export default {
  /**
   * Cloudflare Email Routing handler: forward bank alert emails directly to
   * e.g. `tally@yourdomain.com` (or `tally+wife@yourdomain.com` to tag member!).
   */
  async email(message: ForwardableEmailMessage, env: Env): Promise<void> {
    const raw = await new Response(message.raw).text();
    const subject = message.headers.get("subject") ?? "Bank Alert";
    const messageId = message.headers.get("message-id") ?? crypto.randomUUID();
    const toAddr = message.to.toLowerCase();
    const plusMatch = toAddr.match(/\+([^@]+)@/);
    const member = plusMatch ? plusMatch[1] : (env.DEFAULT_MEMBER ?? "");
    const cleanBody = extractPlainTextFromRawEmail(raw);

    const stub = getInboxStub(env);
    await stub.enqueue({
      id: messageId,
      subject,
      sender: message.from,
      body: cleanBody,
      member,
      receivedAt: new Date().toISOString(),
    });
  },

  /**
   * HTTPS API for Google Apps Script (`POST /v1/ingest`) and Tally iOS (`GET /v1/inbox`, `POST /v1/ack`).
   */
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/v1/health") {
      return json({ ok: true, service: "tally-email-inbox" });
    }

    if (!(await isAuthorized(request, env))) {
      return json({ error: "unauthorized" }, 401);
    }

    const stub = getInboxStub(env);

    if (request.method === "POST" && url.pathname === "/v1/ingest") {
      const payload = (await request.json().catch(() => null)) as (Partial<BankAlertItem> & { force?: boolean }) | null;
      if (!payload || (!payload.body && !payload.subject)) {
        return json({ error: "missing subject or body" }, 400);
      }
      const item: BankAlertItem = {
        id: payload.id?.trim() || crypto.randomUUID(),
        subject: payload.subject?.trim() || "Bank Alert",
        sender: payload.sender?.trim() || "",
        body: payload.body?.trim() || payload.subject?.trim() || "",
        member: payload.member?.trim() || "",
        receivedAt: payload.receivedAt || new Date().toISOString(),
      };
      const result = await stub.enqueue(item, payload.force === true);
      return json({ ok: true, id: item.id, ...result });
    }

    if (request.method === "GET" && url.pathname === "/v1/inbox") {
      const items = await stub.list(50);
      return json({ items });
    }

    if (request.method === "POST" && url.pathname === "/v1/ack") {
      const payload = (await request.json().catch(() => null)) as { ids?: string[] } | null;
      const ids = Array.isArray(payload?.ids) ? payload.ids : [];
      const removed = await stub.ack(ids);
      return json({ ok: true, removed });
    }

    return json({ error: "not_found" }, 404);
  },
};
