# Tally Cloud Email Inbox (Cloudflare Worker)

Hands-free bank email capture for Singapore & Vietnam banks (DBS, OCBC, UOB, Trust, PayNow, Grab, Vietcombank, Techcombank…) with **zero Apple Shortcuts required** for emails.

## 1. Deploy the Worker (Free Tier)

```bash
cd tools/email-inbox
npm install
npx wrangler login
npx wrangler deploy
```

Generate a strong secret and save it in Cloudflare:

```bash
openssl rand -hex 24
npx wrangler secret put INBOX_SECRET
```

## 2. Connect Your Bank Emails (Pick Either Method)

### Option A — Gmail (Zero custom domain, works for both you & your wife)
1. Open [script.google.com](https://script.google.com) → **New project**.
2. Paste `gmail-forwarder.gs` and fill in `WORKER_URL`, `INBOX_SECRET`, and `MEMBER_NAME` (`"Khoa"` on your Gmail, `"Wife"` on hers).
3. Add a **Time-driven trigger** every **5 minutes** for `syncBankAlertsToTally`.

### Option B — Cloudflare Email Routing (Custom domain)
1. In Cloudflare Dashboard → **Email → Email Routing → Routing Rules**, route `tally@yourdomain.com` (and optionally `tally+wife@yourdomain.com`) to Worker **`tally-email-inbox`**.
2. Forward DBS/OCBC/UOB bank alert emails from Gmail/iCloud Mail to that address.

## 3. Connect Tally iOS

Open **Tally → Settings → Auto-Capture & Shortcuts → Cloud Bank Email Inbox**:
- Enter your Worker URL (`https://tally-email-inbox.<subdomain>.workers.dev`) and `INBOX_SECRET`.
- Tap **Save & Test** — Tally automatically pulls new bank emails whenever you open the app, parses them with Claude AI (or offline parser), tags the right household member, syncs via iCloud, and deletes them from the Worker immediately after acknowledging.
