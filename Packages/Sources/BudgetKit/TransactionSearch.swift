import Foundation

/// Deterministic text matching for the transaction search field.
public enum TransactionSearch {
    /// Lowercases and strips diacritics so "pho" finds "Phở" and "duong" finds "Đường".
    public static func fold(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }

    /// The query split into folded words; empty when the query is blank.
    public static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// `true` when every word of the query appears in at least one of `fields`
    /// (merchant, category, note, member, amount…). A blank query matches everything.
    public static func matches(query: String, fields: [String]) -> Bool {
        let words = tokens(query)
        guard !words.isEmpty else { return true }
        let haystack = fields.map(fold)
        return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
    }
}
