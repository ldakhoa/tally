/**
 * Tally Gmail Auto-Forwarder (Zero Custom Domain, Free on Google Apps Script)
 *
 * Strictly matches real bank transaction alerts & e-receipts while excluding
 * Gmail Promotions/Social and marketing blasts.
 */

const WORKER_URL = "https://tally-email-inbox.<your-subdomain>.workers.dev/v1/ingest";
const INBOX_SECRET = "PASTE_YOUR_INBOX_SECRET_HERE";
const MEMBER_NAME = "Khoa"; // Change to your wife's name on her Gmail!
const PROCESSED_LABEL = "TallySynced";

// Only real Singapore + Vietnam bank alerts & e-receipts (excludes Promotions, Social, newsletters & promos)
const GMAIL_QUERY = [
  "-label:" + PROCESSED_LABEL,
  "-category:promotions",
  "-category:social",
  "newer_than:7d",
  '-subject:(promo OR promotion OR voucher OR cashback OR "up to" OR offer OR newsletter OR statement OR "ưu đãi" OR "khuyến mãi" OR "giảm giá" OR "cơ hội" OR "mời bạn" OR OTP)',
  "(",
  'subject:("Transaction Alert" OR "Card Transaction" OR "PayNow" OR "PayLah" OR "Funds Transfer" OR "Your Grab E-Receipt" OR "Payment Confirmation" OR "Biến động số dư" OR "Thông báo giao dịch")',
  'OR (from:(dbs.com OR dbs.com.sg OR posb.com.sg OR ocbc.com OR uobgroup.com OR uob.com.sg OR trustbank.sg OR citi.com OR sc.com OR hsbc OR maribank OR gxsbank OR youtrip OR vietcombank OR techcombank OR mbbank OR tpbank) ("SGD" OR "VND" OR "USD" OR "S$" OR "transferred" OR "debited" OR "credited" OR "payment"))',
  ")"
].join(" ");

function syncBankAlertsToTally() {
  const label = GmailApp.getUserLabelByName(PROCESSED_LABEL) || GmailApp.createLabel(PROCESSED_LABEL);
  const threads = GmailApp.search(GMAIL_QUERY, 0, 25);

  for (const thread of threads) {
    let allOk = true;
    for (const message of thread.getMessages()) {
      const payload = {
        id: "gmail-" + message.getId(),
        subject: message.getSubject() || "",
        sender: message.getFrom() || "",
        body: (message.getPlainBody() || "").slice(0, 4000),
        member: MEMBER_NAME,
        receivedAt: message.getDate().toISOString(),
      };

      const res = UrlFetchApp.fetch(WORKER_URL, {
        method: "post",
        contentType: "application/json",
        headers: { Authorization: "Bearer " + INBOX_SECRET },
        payload: JSON.stringify(payload),
        muteHttpExceptions: true,
      });

      if (res.getResponseCode() < 200 || res.getResponseCode() >= 300) {
        allOk = false;
        console.error("Failed to ingest", payload.id, res.getResponseCode(), res.getContentText());
      }
    }
    if (allOk) {
      thread.addLabel(label);
    }
  }
}
