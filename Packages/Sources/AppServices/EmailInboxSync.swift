import BudgetKit
import Foundation
import Observation
import TallyCore

/// Pulls forwarded bank alert emails from Tally's Cloudflare Email Inbox Worker (`tools/email-inbox`),
/// parses each one via Claude AI (or the offline SG/VN parser), saves into `BudgetStore` (which syncs
/// via iCloud to both phones), and immediately acknowledges/deletes them from the Worker.
@MainActor
@Observable
public final class EmailInboxSync {
    public private(set) var isSyncing = false
    public private(set) var lastSynced: Date?
    public private(set) var lastIngestedCount = 0
    public private(set) var lastError: String?

    @ObservationIgnored private var syncTask: Task<Void, Never>?

    public init() {}

    public func syncIfConfigured(settings: AppSettings, store: BudgetStore) {
        guard settings.isEmailInboxConfigured, !isSyncing else { return }
        syncNow(settings: settings, store: store)
    }

    public func syncNow(settings: AppSettings, store: BudgetStore) {
        guard !isSyncing else { return }
        syncTask?.cancel()
        syncTask = Task {
            await performSync(settings: settings, store: store)
        }
    }

    public func testConnection(url: String, secret: String, language: AppLanguage) async -> Result<Int, Error> {
        do {
            let normalized = try EmailInboxClient.normalizeURL(url)
            let token = secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (KeychainStore.readEmailInboxSecret() ?? "")
                : secret
            let client = EmailInboxClient(baseURL: normalized, secret: token)
            let items = try await client.fetchInbox()
            return .success(items.count)
        } catch let err as EmailInboxError {
            return .failure(NSError(domain: "TallyEmailInbox", code: 1, userInfo: [NSLocalizedDescriptionKey: err.localizedMessage(in: language)]))
        } catch {
            return .failure(error)
        }
    }

    private func performSync(settings: AppSettings, store: BudgetStore) async {
        guard let secret = KeychainStore.readEmailInboxSecret(),
              let baseURL = try? EmailInboxClient.normalizeURL(settings.emailInboxURL)
        else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let inboxClient = EmailInboxClient(baseURL: baseURL, secret: secret)
        do {
            let alerts = try await inboxClient.fetchInbox()
            guard !alerts.isEmpty else {
                lastSynced = Date()
                lastIngestedCount = 0
                return
            }

            let aiClient = settings.autoParseWithAI ? settings.makeAIClient() : nil
            let existingIDs = Set(store.transactions.map(\.id))
            var ackIDs: [String] = []
            var ingested = 0

            for alert in alerts {
                let recordID = "email-\(alert.id)"
                if existingIDs.contains(recordID) {
                    ackIDs.append(alert.id)
                    continue
                }

                let text = alert.combinedText
                if let parsed = await AITransactionParser.parse(
                    text: text,
                    source: .bankEmail,
                    defaultCurrency: settings.currency,
                    language: settings.language,
                    client: aiClient
                ) {
                    let (memberID, memberName) = resolveMember(alert.member, settings: settings)
                    let resolved = AITransactionParser.resolvedAmountAndNote(
                        for: parsed,
                        targetCurrency: settings.currency,
                        language: settings.language,
                        fallbackNote: alert.sender
                    )
                    let record = TransactionRecord(
                        id: recordID,
                        name: parsed.name,
                        amountMinor: max(1, resolved.amountMinor),
                        type: parsed.type,
                        category: parsed.category,
                        dayKey: parsed.dayKey,
                        createdAt: Date(),
                        note: resolved.note,
                        source: .bankEmail,
                        rawSourceText: text,
                        memberID: memberID,
                        memberName: memberName,
                        needsReview: settings.flagAutoCapturedForReview,
                        updatedAt: Date(),
                        isDeleted: false
                    )
                    store.saveTransaction(record, notifyCloud: true)
                    ingested += 1
                }
                ackIDs.append(alert.id)
            }

            if !ackIDs.isEmpty {
                try await inboxClient.ack(ids: ackIDs)
            }
            lastIngestedCount = ingested
            lastSynced = Date()
        } catch let err as EmailInboxError {
            lastError = err.localizedMessage(in: settings.language)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func resolveMember(_ rawMember: String, settings: AppSettings) -> (String, String) {
        let trimmed = rawMember.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (settings.currentMember.id, settings.currentMember.name)
        }
        let me = settings.currentMember
        if trimmed.caseInsensitiveCompare(me.name) == .orderedSame {
            return (me.id, me.name)
        }
        let partner = settings.partnerDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partner.isEmpty && trimmed.caseInsensitiveCompare(partner) == .orderedSame {
            return (HouseholdMember.defaultPartnerID, partner)
        }
        return ("member-\(trimmed.lowercased())", trimmed)
    }
}
