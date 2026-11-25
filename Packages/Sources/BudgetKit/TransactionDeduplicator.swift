import Foundation
import TallyCore

/// Cross-source deduplication for transactions captured from multiple channels
/// (Apple Pay Wallet Shortcut, Bank SMS, Bank Email, Paste, Manual).
///
/// Prevents a single purchase from being double- or triple-counted when Apple Pay, SMS,
/// and DBS/OCBC/UOB email alerts all fire for the same payment, while still allowing two
/// legitimately separate same-amount purchases hours apart (e.g., morning & afternoon coffee).
public enum TransactionDeduplicator {
    public struct MatchResult: Equatable, Sendable {
        public let existing: TransactionRecord
        public let reason: Reason

        public enum Reason: Equatable, Sendable {
            case exactID
            case crossSourceNearInTime
            case similarMerchantSameDay
        }
    }

    public struct SweepResult: Equatable, Sendable {
        public let updatedWinners: [TransactionRecord]
        public let duplicateIDsToDelete: [String]

        public var hasChanges: Bool {
            !duplicateIDsToDelete.isEmpty || !updatedWinners.isEmpty
        }
    }

    /// Deterministic priority when choosing which record to keep between two duplicates.
    /// Lower number = higher priority (kept). Every device computes the exact same winner.
    public static func sourcePriority(_ source: TransactionSource) -> Int {
        switch source {
        case .manual: return 0
        case .aiQuickAdd: return 1
        case .applePay: return 2
        case .shortcut: return 3
        case .bankNotification: return 4
        case .bankEmail: return 5
        case .imported: return 6
        }
    }

    private static func isBankAlert(_ source: TransactionSource) -> Bool {
        source == .bankEmail || source == .bankNotification
    }

    /// Finds an existing active transaction that represents the same real-world payment.
    public static func findDuplicate(
        for incoming: TransactionRecord,
        in existing: [TransactionRecord]
    ) -> MatchResult? {
        // 1. Exact ID match (e.g., same Gmail message ID or synced record). Tombstones count too:
        //    an alert the user deleted (or converted into an installment plan) must not come back
        //    when the same email is delivered again. Callers check `existing.isDeleted`.
        if let exact = existing.first(where: { $0.id == incoming.id && !$0.isDeleted })
            ?? existing.first(where: { $0.id == incoming.id }) {
            return MatchResult(existing: exact, reason: .exactID)
        }

        // Candidates: live transactions except scheduled plan payments (those are generated
        // from a plan, never captured), plus tombstoned expenses that were converted into a plan
        // so a re-sent alert for the original purchase is recognized as already captured.
        let active = existing.filter { tx in
            if tx.isDeleted { return tx.isConvertedPlanSource }
            return !tx.isPlanPayment
        }

        let incomingTokens = normalizedMerchantTokens(incoming.name)
        let incomingDay = DateKey.date(fromDayKey: incoming.dayKey)

        for candidate in active {
            let sameConvertedAmount = candidate.amountMinor == incoming.amountMinor
            let sameForeignAmount: Bool = {
                guard let cCode = candidate.originalCurrencyCode,
                      let iCode = incoming.originalCurrencyCode,
                      let cMinor = candidate.originalAmountMinor,
                      let iMinor = incoming.originalAmountMinor,
                      !cCode.isEmpty
                else { return false }
                return cCode.caseInsensitiveCompare(iCode) == .orderedSame && cMinor == iMinor
            }()
            guard candidate.type == incoming.type,
                  sameConvertedAmount || sameForeignAmount
            else { continue }

            let isSameMember = candidate.memberID.isEmpty
                || incoming.memberID.isEmpty
                || candidate.memberID == incoming.memberID
            let isDifferentSource = candidate.source != incoming.source
            let involvesBankAlert = isBankAlert(candidate.source) || isBankAlert(incoming.source)

            // Same-source or non-bank-alert entries from different household members stay separate
            // (e.g., both partners tapping Apple Pay or manually logging the same item).
            // Cross-source pairs involving a bank alert (e.g., Apple Pay on a phone + Bank Email
            // from a shared/supplementary card or mismatched member label like "Me" vs "Khoa")
            // ARE deduplicated across members.
            if !isSameMember && !(isDifferentSource && involvesBankAlert) {
                continue
            }

            let timeDelta = abs(candidate.createdAt.timeIntervalSince(incoming.createdAt))
            let dayDelta = dayDistance(from: candidate.dayKey, to: incoming.dayKey, incomingDate: incomingDay)
            let namesMatch = merchantsLookSimilar(incomingTokens, normalizedMerchantTokens(candidate.name))

            // 2. Different capture channels (e.g. Apple Pay + DBS Email + SMS):
            //    - Same amount within 20 minutes -> duplicate even if merchant strings differ
            //      (e.g. Apple Pay "Starbucks" vs Bank "COFFEE CONCEPT PTE LTD").
            //    - Same amount within ±1 calendar day AND similar merchant name -> duplicate
            //      (handles delayed bank emails arriving hours later or past midnight).
            if isDifferentSource {
                if timeDelta <= 20 * 60 && dayDelta <= 1 {
                    return MatchResult(existing: candidate, reason: .crossSourceNearInTime)
                }
                if dayDelta <= 1 && namesMatch {
                    return MatchResult(existing: candidate, reason: .similarMerchantSameDay)
                }
            }

            // 3. Same capture channel (e.g. duplicate bank email, double-tapped Paste, repeated SMS):
            //    - Same day + similar merchant + within 2 hours (or exact same rawSourceText).
            if isSameMember {
                if let a = candidate.rawSourceText, let b = incoming.rawSourceText, !a.isEmpty, a == b {
                    return MatchResult(existing: candidate, reason: .similarMerchantSameDay)
                }
                if dayDelta == 0 && namesMatch && timeDelta <= 2 * 60 * 60 {
                    return MatchResult(existing: candidate, reason: .similarMerchantSameDay)
                }
            }
        }

        return nil
    }

    /// Deterministically sweeps an existing list of transactions to collapse already-stored
    /// auto-captured duplicates (e.g., from cross-device iCloud races or mismatched member labels).
    /// Never removes manual/AI/imported entries.
    public static func findExistingDuplicates(in transactions: [TransactionRecord]) -> SweepResult {
        let sorted = transactions
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                let pL = sourcePriority(lhs.source)
                let pR = sourcePriority(rhs.source)
                if pL != pR { return pL < pR }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id < rhs.id
            }

        var kept: [TransactionRecord] = []
        var updatedByID: [String: TransactionRecord] = [:]
        var duplicateIDs: [String] = []

        for tx in sorted {
            // Plan payments are generated, not captured: never sweep them or match against them.
            if tx.isPlanPayment { continue }
            guard tx.source.isAutomatic else {
                kept.append(tx)
                continue
            }
            if let match = findDuplicate(for: tx, in: kept) {
                duplicateIDs.append(tx.id)
                let merged = mergeMetadata(existing: match.existing, duplicate: tx)
                if merged != match.existing, let idx = kept.firstIndex(where: { $0.id == match.existing.id }) {
                    kept[idx] = merged
                    updatedByID[merged.id] = merged
                }
            } else {
                kept.append(tx)
            }
        }

        return SweepResult(
            updatedWinners: Array(updatedByID.values),
            duplicateIDsToDelete: duplicateIDs
        )
    }

    /// Merges useful metadata from a duplicate alert into the kept transaction without duplicating it.
    public static func mergeMetadata(existing: TransactionRecord, duplicate: TransactionRecord) -> TransactionRecord {
        var updated = existing
        var changed = false
        if (updated.rawSourceText == nil || updated.rawSourceText?.isEmpty == true),
           let dupRaw = duplicate.rawSourceText, !dupRaw.isEmpty {
            updated.rawSourceText = dupRaw
            changed = true
        }
        if updated.note.isEmpty && !duplicate.note.isEmpty {
            updated.note = duplicate.note
            changed = true
        }
        if !updated.isForeignCurrency, duplicate.isForeignCurrency {
            updated.originalAmountMinor = duplicate.originalAmountMinor
            updated.originalCurrencyCode = duplicate.originalCurrencyCode
            if updated.exchangeRate == nil {
                updated.exchangeRate = duplicate.exchangeRate
            }
            changed = true
        }
        if changed {
            updated.updatedAt = Date()
        }
        return updated
    }

    // MARK: - Helpers

    private static let stopWords: Set<String> = [
        "pte", "ltd", "sdn", "bhd", "singapore", "sg", "vn", "vietnam", "inc", "llc",
        "corp", "co", "the", "and", "at", "to", "from", "payment", "paynow", "paylah",
        "dbs", "posb", "ocbc", "uob", "trust", "card", "apple", "pay", "ntuc", "mart", "store"
    ]

    public static func normalizedMerchantTokens(_ name: String) -> Set<String> {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        let words = String(cleaned)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
        return Set(words)
    }

    private static func merchantsLookSimilar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if !a.isDisjoint(with: b) { return true }
        // Prefix/substring match for tokens like "fairprice" vs "fairpricefinest" or "grab" vs "grabfood"
        for lhs in a {
            for rhs in b {
                if lhs.count >= 4 && rhs.count >= 4 && (lhs.contains(rhs) || rhs.contains(lhs)) {
                    return true
                }
            }
        }
        return false
    }

    private static func dayDistance(from dayKeyA: String, to dayKeyB: String, incomingDate: Date?) -> Int {
        if dayKeyA == dayKeyB { return 0 }
        guard let dA = DateKey.date(fromDayKey: dayKeyA),
              let dB = incomingDate ?? DateKey.date(fromDayKey: dayKeyB)
        else { return 99 }
        return abs(Int((dA.timeIntervalSince(dB) / 86_400.0).rounded()))
    }
}
