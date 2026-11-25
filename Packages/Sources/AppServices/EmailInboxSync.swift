import BudgetKit
import Foundation
import Observation
import TallyCore

/// Pulls forwarded bank alert emails from Tally's Cloudflare Email Inbox Worker (`tools/email-inbox`),
/// parses each one via Claude AI (or the offline SG/VN parser) using the email's real `receivedAt`
/// date, saves into `BudgetStore` (which syncs via iCloud to both phones), and immediately
/// acknowledges/deletes them from the Worker. Loops across batches until the inbox is drained.
@MainActor
@Observable
public final class EmailInboxSync {
    public private(set) var isSyncing = false
    public private(set) var lastSynced: Date?
    public private(set) var lastPulledCount = 0
    public private(set) var lastIngestedCount = 0
    public private(set) var lastSkippedCount = 0
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
        lastPulledCount = 0
        lastIngestedCount = 0
        lastSkippedCount = 0
        defer { isSyncing = false }

        let inboxClient = EmailInboxClient(baseURL: baseURL, secret: secret)
        let aiClient = settings.autoParseWithAI ? settings.makeAIClient() : nil
        let targetCurrency = settings.currency
        let language = settings.language

        do {
            // Drain all pending batches (up to 10 batches = 500 emails max per sync).
            var didRefreshRates = false
            for _ in 0..<10 {
                let alerts = try await inboxClient.fetchInbox()
                guard !alerts.isEmpty else { break }
                if !didRefreshRates {
                    didRefreshRates = true
                    await ExchangeRateService.shared.refreshIfStale()
                }

                lastPulledCount += alerts.count
                // Includes tombstones: an alert the user deleted (or converted into an
                // installment plan) is skipped instead of being re-parsed and resurrected.
                let knownRecordIDs = Set(store.transactions.map(\.id))

                // Process in chunks of 4 concurrently for fast backfill parsing.
                var ackIDs: [String] = []
                for chunkStart in stride(from: 0, to: alerts.count, by: 4) {
                    let chunk = Array(alerts[chunkStart..<min(chunkStart + 4, alerts.count)])

                    let parsedChunk: [(BankEmailAlert, Date, ParsedTransactionDraft?)] = await withTaskGroup(
                        of: (BankEmailAlert, Date, ParsedTransactionDraft?).self
                    ) { group in
                        for alert in chunk {
                            let recordID = "email-\(alert.id)"
                            let emailDate = Self.parseISO8601(alert.receivedAt) ?? Date()
                            if knownRecordIDs.contains(recordID) {
                                group.addTask { (alert, emailDate, nil) }
                                continue
                            }
                            let text = alert.combinedText
                            group.addTask {
                                let draft = await AITransactionParser.parse(
                                    text: text,
                                    source: .bankEmail,
                                    defaultCurrency: targetCurrency,
                                    language: language,
                                    client: aiClient,
                                    now: emailDate
                                )
                                return (alert, emailDate, draft)
                            }
                        }
                        var results: [(BankEmailAlert, Date, ParsedTransactionDraft?)] = []
                        for await item in group { results.append(item) }
                        return results
                    }

                    for (alert, emailDate, parsed) in parsedChunk {
                        let recordID = "email-\(alert.id)"
                        if let parsed {
                            let (memberID, memberName) = resolveMember(alert.member, settings: settings)
                            let resolved = AITransactionParser.resolvedAmountAndNote(
                                for: parsed,
                                targetCurrency: targetCurrency,
                                language: language,
                                fallbackNote: alert.sender
                            )
                            let record = TransactionRecord(
                                id: recordID,
                                name: parsed.name,
                                amountMinor: max(1, resolved.amountMinor),
                                type: parsed.type,
                                category: parsed.category,
                                dayKey: parsed.dayKey,
                                createdAt: emailDate,
                                note: resolved.note,
                                source: .bankEmail,
                                rawSourceText: alert.combinedText,
                                memberID: memberID,
                                memberName: memberName,
                                needsReview: settings.flagAutoCapturedForReview || resolved.usedFallbackUnavailableRate,
                                updatedAt: Date(),
                                isDeleted: false,
                                originalAmountMinor: resolved.originalAmountMinor,
                                originalCurrencyCode: resolved.originalCurrencyCode,
                                exchangeRate: resolved.exchangeRate
                            )
                            let outcome = store.saveAutoCapturedTransaction(record, notifyCloud: true)
                            if !outcome.wasDuplicate {
                                lastIngestedCount += 1
                            } else {
                                lastSkippedCount += 1
                            }
                        } else {
                            lastSkippedCount += 1
                        }
                        ackIDs.append(alert.id)
                    }
                }

                if !ackIDs.isEmpty {
                    try await inboxClient.ack(ids: ackIDs)
                }
                // If fewer than 50 came back, the inbox is now drained.
                if alerts.count < 50 { break }
            }

            lastSynced = Date()
        } catch let err as EmailInboxError {
            lastError = err.localizedMessage(in: settings.language)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
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
        let genericPartnerLabels: Set<String> = [
            "wife", "partner", "husband", "spouse", "vợ", "vo", "chồng", "chong", "người thân"
        ]
        if settings.myDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !settings.cloudZoneRole.isSharedParticipant,
           !genericPartnerLabels.contains(trimmed.lowercased()) {
            settings.myDisplayName = trimmed
            return (me.id, trimmed)
        }
        return ("member-\(trimmed.lowercased())", trimmed)
    }
}
