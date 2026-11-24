import Foundation

/// One person, one member ID. Every device first generates its own random member ID, so the same
/// person on an iPhone and a Mac starts out as two household members with the same name. Each
/// device resolves that the same way from the synced records, so they all settle on one ID.
public enum MemberIdentity {
    /// The ID this person should use everywhere: the smallest device-generated ID among
    /// `currentID` and the IDs of `records` carrying the same display name (case-insensitive).
    /// Synthetic `member-…` IDs (Email Inbox labels, the default partner) are never chosen.
    /// Deterministic for a given set of records, so devices that see the same data agree.
    public static func canonicalID(
        currentID: String,
        name: String,
        records: [(memberID: String, memberName: String)]
    ) -> String {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return currentID }
        var best = currentID
        for record in records where !record.memberID.isEmpty && !record.memberID.hasPrefix("member-") {
            let recordName = record.memberName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard recordName.caseInsensitiveCompare(wanted) == .orderedSame else { continue }
            if best.hasPrefix("member-") || record.memberID < best { best = record.memberID }
        }
        return best
    }
}
