# Tally Cloud MCP Server (Cloudflare Worker)

Always-on remote [Model Context Protocol](https://modelcontextprotocol.io) server for Tally, backed by a private SQLite Durable Object (`TallyVault`). Works 24/7 from Claude iOS/Web, ChatGPT, Muse, Claude Code, Codex, Claude Desktop, Antigravity, and Cursor—even when your Mac is asleep.

## 1-Tap Setup (Recommended)

Open **Tally on Mac → Settings → MCP & AI Assistants → 1-Tap Set Up Cloud MCP**.

Or run from the terminal:

```bash
tools/deploy-mcp
```

This installs dependencies, deploys the Worker, sets `TALLY_SYNC_SECRET` & `TALLY_MCP_TOKEN`, and opens Tally on Mac to save and sync your credentials across iPhone, iPad, and Mac via iCloud Keychain.

## Manual Deploy

```bash
cd tools/mcp-server
npm install
npx wrangler login
npx wrangler deploy
openssl rand -hex 32 | npx wrangler secret put TALLY_SYNC_SECRET
```

## Endpoints

- `POST /mcp` — Streamable HTTP MCP endpoint (`Authorization: Bearer <token>` or OAuth 2.1 access token)
- `POST /u/<token>/mcp` — 1-URL quick connector for mobile/web/desktop apps that take a URL without custom headers
- `GET /.well-known/oauth-protected-resource`, `GET /.well-known/oauth-authorization-server`, `POST /oauth/register`, `GET|POST /oauth/authorize`, `POST /oauth/token` — OAuth 2.1 + PKCE S256 + Dynamic Client Registration
- `GET /v1/health`, `POST /v1/sync`, `POST /v1/config`, `POST /v1/pairing-code` — Authenticated by `TALLY_SYNC_SECRET`
