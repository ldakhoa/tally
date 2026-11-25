export interface OAuthStore {
  getClient(clientId: string): { clientId: string; redirectUris: string[]; clientName: string } | null;
  saveClient(clientId: string, redirectUris: string[], clientName: string, createdAt: string): void;
  getPairingState(): { code: string | null; expiresAt: number; attempts: number };
  incrementPairingAttempts(): void;
  clearPairingCode(): void;
  getMCPToken(): string;
  saveAuthCode(record: {
    code: string;
    clientId: string;
    redirectUri: string;
    codeChallenge: string;
    expiresAt: number;
  }): void;
  consumeAuthCode(
    code: string,
    nowMs: number
  ): {
    clientId: string;
    redirectUri: string;
    codeChallenge: string;
  } | null;
  saveAccessToken(token: string, clientId: string, createdAt: string): void;
}

export function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export async function constantTimeEqual(a: string, b: string): Promise<boolean> {
  if (!a && !b) return true;
  const enc = new TextEncoder();
  const ha = await crypto.subtle.digest("SHA-256", enc.encode(a));
  const hb = await crypto.subtle.digest("SHA-256", enc.encode(b));
  const va = new Uint8Array(ha);
  const vb = new Uint8Array(hb);
  let diff = a.length === b.length ? 0 : 1;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

export function isValidRedirectURI(raw: string): boolean {
  try {
    const u = new URL(raw);
    if (u.protocol === "https:") return Boolean(u.hostname);
    if (u.protocol === "http:") {
      return u.hostname === "localhost" || u.hostname === "127.0.0.1";
    }
    return false;
  } catch {
    return false;
  }
}

export async function sha256Base64Url(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  let binary = "";
  for (const b of digest) binary += String.fromCharCode(b);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export function protectedResourceMetadata(origin: string) {
  return {
    resource: `${origin}/mcp`,
    authorization_servers: [origin],
    bearer_methods_supported: ["header"],
  };
}

export function authorizationServerMetadata(origin: string) {
  return {
    issuer: origin,
    authorization_endpoint: `${origin}/oauth/authorize`,
    token_endpoint: `${origin}/oauth/token`,
    registration_endpoint: `${origin}/oauth/register`,
    response_types_supported: ["code"],
    grant_types_supported: ["authorization_code"],
    code_challenge_methods_supported: ["S256"],
    token_endpoint_auth_methods_supported: ["none", "client_secret_post"],
  };
}

export async function handleOAuthRegister(
  request: Request,
  store: OAuthStore,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const body = (await request.json().catch(() => null)) as {
    redirect_uris?: unknown;
    client_name?: unknown;
  } | null;
  if (!body || !Array.isArray(body.redirect_uris) || body.redirect_uris.length === 0) {
    return jsonResponse({ error: "invalid_client_metadata", error_description: "redirect_uris required" }, 400, corsHeaders);
  }
  const uris = body.redirect_uris.filter(
    (u): u is string => typeof u === "string" && isValidRedirectURI(u)
  );
  if (uris.length !== body.redirect_uris.length) {
    return jsonResponse({ error: "invalid_redirect_uri", error_description: "Each redirect_uri must be https:// or localhost" }, 400, corsHeaders);
  }
  const clientName =
    typeof body.client_name === "string" && body.client_name.trim()
      ? body.client_name.trim().slice(0, 120)
      : "AI Assistant";
  const clientId = `tally_${crypto.randomUUID().replaceAll("-", "")}`;
  store.saveClient(clientId, uris, clientName, new Date().toISOString());

  return jsonResponse(
    {
      client_id: clientId,
      client_name: clientName,
      redirect_uris: uris,
      token_endpoint_auth_method: "none",
      grant_types: ["authorization_code"],
      response_types: ["code"],
    },
    201,
    corsHeaders
  );
}

export function handleOAuthAuthorizeGet(url: URL, store: OAuthStore): Response {
  const clientId = url.searchParams.get("client_id") ?? "";
  const redirectUri = url.searchParams.get("redirect_uri") ?? "";
  const state = url.searchParams.get("state") ?? "";
  const codeChallenge = url.searchParams.get("code_challenge") ?? "";
  const codeChallengeMethod = url.searchParams.get("code_challenge_method") ?? "";
  const responseType = url.searchParams.get("response_type") ?? "";

  if (!clientId || !redirectUri || responseType !== "code") {
    return htmlResponse(renderErrorPage("Invalid OAuth request parameters."), 400);
  }
  if (!codeChallenge || codeChallengeMethod !== "S256") {
    return htmlResponse(renderErrorPage("PKCE S256 is required."), 400);
  }
  const client = store.getClient(clientId);
  if (!client || !client.redirectUris.includes(redirectUri)) {
    return htmlResponse(renderErrorPage("Unknown client or unregistered redirect_uri."), 400);
  }

  return htmlResponse(
    renderAuthorizePage({
      clientName: client.clientName,
      clientId,
      redirectUri,
      state,
      codeChallenge,
      codeChallengeMethod,
      errorMessage: null,
    }),
    200
  );
}

export async function handleOAuthAuthorizePost(
  request: Request,
  store: OAuthStore,
  nowMs = Date.now()
): Promise<Response> {
  const text = await request.text();
  const form = new URLSearchParams(text);
  const clientId = form.get("client_id") ?? "";
  const redirectUri = form.get("redirect_uri") ?? "";
  const state = form.get("state") ?? "";
  const codeChallenge = form.get("code_challenge") ?? "";
  const codeChallengeMethod = form.get("code_challenge_method") ?? "";
  const secretInput = (form.get("pairing_code") ?? "").trim();

  const client = store.getClient(clientId);
  if (!client || !client.redirectUris.includes(redirectUri) || codeChallengeMethod !== "S256" || !codeChallenge) {
    return htmlResponse(renderErrorPage("Invalid OAuth authorization request."), 400);
  }

  const pairing = store.getPairingState();
  const mcpToken = store.getMCPToken();

  let authorized = false;
  if (mcpToken && (await constantTimeEqual(secretInput, mcpToken))) {
    authorized = true;
  } else if (
    pairing.code &&
    pairing.expiresAt > nowMs &&
    pairing.attempts < 5 &&
    (await constantTimeEqual(secretInput, pairing.code))
  ) {
    authorized = true;
    store.clearPairingCode();
  } else if (pairing.code) {
    store.incrementPairingAttempts();
  }

  if (!authorized) {
    const expiredOrLocked = pairing.attempts >= 5 || (pairing.code !== null && pairing.expiresAt <= nowMs);
    return htmlResponse(
      renderAuthorizePage({
        clientName: client.clientName,
        clientId,
        redirectUri,
        state,
        codeChallenge,
        codeChallengeMethod,
        errorMessage: expiredOrLocked
          ? "Pairing code expired or locked. Generate a fresh 6-digit code in Tally Settings."
          : "That code did not match. Check Tally Settings → MCP & AI Assistants.",
      }),
      401
    );
  }

  const authCode = randomHex(24);
  store.saveAuthCode({
    code: authCode,
    clientId,
    redirectUri,
    codeChallenge,
    expiresAt: nowMs + 5 * 60_000,
  });

  const redirect = new URL(redirectUri);
  redirect.searchParams.set("code", authCode);
  if (state) redirect.searchParams.set("state", state);
  return new Response(null, {
    status: 302,
    headers: { Location: redirect.toString() },
  });
}

export async function handleOAuthToken(
  request: Request,
  store: OAuthStore,
  corsHeaders: Record<string, string>,
  nowMs = Date.now()
): Promise<Response> {
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  let params: URLSearchParams;
  if (contentType.includes("application/json")) {
    const json = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    params = new URLSearchParams();
    for (const [k, v] of Object.entries(json)) {
      if (typeof v === "string") params.set(k, v);
    }
  } else {
    params = new URLSearchParams(await request.text());
  }

  const grantType = params.get("grant_type") ?? "";
  const code = params.get("code") ?? "";
  const redirectUri = params.get("redirect_uri") ?? "";
  const codeVerifier = params.get("code_verifier") ?? "";
  const clientId = params.get("client_id") ?? "";

  if (grantType !== "authorization_code") {
    return jsonResponse({ error: "unsupported_grant_type" }, 400, corsHeaders);
  }
  if (!code || !codeVerifier) {
    return jsonResponse({ error: "invalid_request" }, 400, corsHeaders);
  }

  const consumed = store.consumeAuthCode(code, nowMs);
  if (!consumed) {
    return jsonResponse({ error: "invalid_grant", error_description: "Code invalid or expired" }, 400, corsHeaders);
  }
  if (clientId && consumed.clientId !== clientId) {
    return jsonResponse({ error: "invalid_grant", error_description: "Client mismatch" }, 400, corsHeaders);
  }
  if (redirectUri && consumed.redirectUri !== redirectUri) {
    return jsonResponse({ error: "invalid_grant", error_description: "Redirect URI mismatch" }, 400, corsHeaders);
  }

  const computedChallenge = await sha256Base64Url(codeVerifier);
  if (!(await constantTimeEqual(computedChallenge, consumed.codeChallenge))) {
    return jsonResponse({ error: "invalid_grant", error_description: "Invalid PKCE verifier" }, 400, corsHeaders);
  }

  const accessToken = `tly_${randomHex(32)}`;
  store.saveAccessToken(accessToken, consumed.clientId, new Date(nowMs).toISOString());

  return jsonResponse(
    {
      access_token: accessToken,
      token_type: "Bearer",
      expires_in: 31_536_000,
    },
    200,
    corsHeaders
  );
}

function randomHex(byteCount: number): string {
  const bytes = new Uint8Array(byteCount);
  crypto.getRandomValues(bytes);
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function jsonResponse(data: unknown, status: number, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

function htmlResponse(html: string, status: number): Response {
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Frame-Options": "DENY",
    },
  });
}

function renderAuthorizePage(opts: {
  clientName: string;
  clientId: string;
  redirectUri: string;
  state: string;
  codeChallenge: string;
  codeChallengeMethod: string;
  errorMessage: string | null;
}): string {
  const safeClient = escapeHTML(opts.clientName);
  const errBanner = opts.errorMessage
    ? `<div class="err">${escapeHTML(opts.errorMessage)}</div>`
    : "";
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Connect ${safeClient} to Tally</title>
  <style>
    :root { color-scheme: light dark; }
    body {
      margin: 0; padding: 24px;
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Rounded", system-ui, sans-serif;
      background: #FAF5EE; color: #3D2C26;
      display: flex; min-height: 100vh; align-items: center; justify-content: center;
      box-sizing: border-box;
    }
    @media (prefers-color-scheme: dark) {
      body { background: #1E1916; color: #F5ECE4; }
      .card { background: #2A231F !important; border-color: #3E332D !important; }
      input { background: #1E1916 !important; color: #F5ECE4 !important; border-color: #4E4039 !important; }
      .sub { color: #C2B3A7 !important; }
    }
    .card {
      width: 100%; max-width: 400px; padding: 28px; border-radius: 26px;
      background: #FFFDF9; border: 1px solid #EDE3D8;
      box-shadow: 0 12px 32px rgba(107, 68, 35, 0.12);
      box-sizing: border-box;
    }
    .badge {
      display: inline-block; padding: 5px 12px; border-radius: 999px;
      background: #E87D5522; color: #D4653F; font-size: 13px; font-weight: 600;
      margin-bottom: 12px;
    }
    h1 { margin: 0 0 8px; font-size: 22px; line-height: 1.25; }
    .sub { margin: 0 0 20px; font-size: 14px; color: #6E5A50; line-height: 1.45; }
    label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 6px; }
    input[type="text"], input[type="password"] {
      width: 100%; box-sizing: border-box; padding: 13px 14px;
      border-radius: 14px; border: 1px solid #DFD3C6; background: #FAF5EE;
      font-size: 18px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      letter-spacing: 0.12em; text-align: center;
    }
    .err {
      margin-bottom: 14px; padding: 10px 12px; border-radius: 12px;
      background: #C94A4A1F; color: #C94A4A; font-size: 13px; font-weight: 500;
    }
    button {
      margin-top: 18px; width: 100%; padding: 14px; border: none;
      border-radius: 999px; background: #4E382F; color: #FAF0E6;
      font-size: 16px; font-weight: 600; cursor: pointer;
    }
    button:hover { opacity: 0.92; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Tally Household Budget</div>
    <h1>Connect ${safeClient}</h1>
    <p class="sub">Enter the 6-digit pairing code (or access token) shown in <strong>Tally → Settings → MCP &amp; AI Assistants</strong>.</p>
    ${errBanner}
    <form method="POST" action="/oauth/authorize">
      <input type="hidden" name="client_id" value="${escapeHTML(opts.clientId)}" />
      <input type="hidden" name="redirect_uri" value="${escapeHTML(opts.redirectUri)}" />
      <input type="hidden" name="state" value="${escapeHTML(opts.state)}" />
      <input type="hidden" name="code_challenge" value="${escapeHTML(opts.codeChallenge)}" />
      <input type="hidden" name="code_challenge_method" value="${escapeHTML(opts.codeChallengeMethod)}" />
      <label for="pairing_code">Pairing Code</label>
      <input id="pairing_code" name="pairing_code" type="text" autocomplete="one-time-code" placeholder="123456" required autofocus />
      <button type="submit">Approve Connection</button>
    </form>
  </div>
</body>
</html>`;
}

function renderErrorPage(message: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" /><title>Tally Authorization Error</title></head>
<body style="font-family: -apple-system, sans-serif; padding: 32px; background: #FAF5EE; color: #3D2C26;">
  <h2>Could not authorize connection</h2>
  <p>${escapeHTML(message)}</p>
</body>
</html>`;
}
