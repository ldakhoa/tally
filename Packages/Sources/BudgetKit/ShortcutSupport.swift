import Foundation
import TallyCore

/// Pre-built or shareable Apple Shortcut templates exposed in Settings → Auto-Capture & Shortcuts.
public enum ShortcutTemplateID: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case shareSheet
    case quickSpend
    case applePayHelper

    public var id: String { rawValue }

    /// Name of the signed `.shortcut` resource bundled in the app target, if any.
    public var bundledResourceName: String? {
        switch self {
        case .shareSheet: return "LogToTally"
        case .quickSpend: return "QuickSpendTally"
        case .applePayHelper: return nil
        }
    }

    public var isBuiltInTemplate: Bool {
        bundledResourceName != nil
    }
}

/// Guided background automation setups shown in the Shortcut Setup Onboarding sheet.
public enum ShortcutGuideKind: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case applePay
    case bankEmail
    case bankSMS

    public var id: String { rawValue }

    public var transactionSource: TransactionSource {
        switch self {
        case .applePay: return .applePay
        case .bankEmail: return .bankEmail
        case .bankSMS: return .bankNotification
        }
    }

    public var tallyActionName: String {
        switch self {
        case .applePay: return "Log Apple Pay Transaction"
        case .bankEmail, .bankSMS: return "Auto-Log to Tally"
        }
    }
}

/// Validates and canonicalizes Apple iCloud Shortcut share URLs (`https://www.icloud.com/shortcuts/<id>`).
/// Opening an `icloud.com/shortcuts/...` URL routes straight into Apple Shortcuts' "Add Shortcut" sheet.
public enum ShortcutICloudLink {
    public static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        let lower = trimmed.lowercased()
        if !lower.contains("://") && (lower.hasPrefix("icloud.com/") || lower.hasPrefix("www.icloud.com/")) {
            withScheme = "https://\(trimmed)"
        } else {
            withScheme = trimmed
        }

        guard let components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              host == "icloud.com" || host == "www.icloud.com"
        else { return nil }

        let segments = components.path.split(separator: "/").map(String.init)
        guard segments.count == 2,
              segments[0].lowercased() == "shortcuts"
        else { return nil }

        let shortcutID = segments[1]
        guard shortcutID.count >= 8,
              shortcutID.count <= 128,
              shortcutID.unicodeScalars.allSatisfy({
                  ($0.value >= 48 && $0.value <= 57)     // 0-9
                  || ($0.value >= 65 && $0.value <= 90)  // A-Z
                  || ($0.value >= 97 && $0.value <= 122) // a-z
                  || $0 == "-" || $0 == "_"
              })
        else { return nil }

        return URL(string: "https://www.icloud.com/shortcuts/\(shortcutID)")
    }
}

/// Normalized result of parsing Apple Wallet's `Transaction` automation parameters.
public struct ParsedApplePayInput: Equatable, Sendable {
    public let amountMajor: Double
    public let currencyCode: String
    public let merchantName: String
    public let cardName: String?
    public let note: String
    public let rawSummary: String

    public init(
        amountMajor: Double,
        currencyCode: String,
        merchantName: String,
        cardName: String?,
        note: String,
        rawSummary: String
    ) {
        self.amountMajor = amountMajor
        self.currencyCode = currencyCode
        self.merchantName = merchantName
        self.cardName = cardName
        self.note = note
        self.rawSummary = rawSummary
    }
}

/// Deterministic parser for Apple Pay / Wallet Transaction automation inputs.
/// Apple Shortcuts passes Wallet's `Amount` as a localized currency string (such as `"S$18.50"`,
/// `"$10.00"`, `"10.00 $"`, `"HK$83.75"`, `"€12,50"`, or `"125.000 ₫"`), not as a raw `Double`.
public enum ApplePayInputParser {
    public static func parseFormattedAmount(
        _ rawAmount: String,
        explicitCurrency: String? = nil,
        defaultCurrency: CurrencyCode
    ) -> (amountMajor: Double, currencyCode: String)? {
        let normalized = rawAmount
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{2009}", with: " ")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        // Reject multiple leading/embedded signs like "--18.50".
        let signCount = normalized.filter { $0 == "-" || $0 == "+" }.count
        guard signCount <= 1 else { return nil }

        // Split into optional prefix currency/sign, numeric core, and optional suffix currency.
        guard let split = splitAmountComponents(normalized) else { return nil }

        let cleanedPrefix = stripOuterSignsAndWhitespace(split.prefix)
        let cleanedSuffix = stripOuterSignsAndWhitespace(split.suffix)

        var detectedCode: String?
        if !cleanedPrefix.isEmpty {
            guard let code = resolveCurrencyToken(cleanedPrefix, defaultCurrency: defaultCurrency) else {
                return nil
            }
            detectedCode = code
        }
        if !cleanedSuffix.isEmpty {
            guard let code = resolveCurrencyToken(cleanedSuffix, defaultCurrency: defaultCurrency) else {
                return nil
            }
            if detectedCode == nil {
                detectedCode = code
            }
        }

        let finalCode = explicitCurrency.flatMap(CurrencyCode.normalizeCode)
            ?? detectedCode
            ?? defaultCurrency.rawValue

        guard let value = parseNumericValue(
            split.number,
            isZeroDecimal: CurrencyCode.isZeroDecimal(code: finalCode)
        ), value.isFinite, value > 0 else {
            return nil
        }

        return (value, finalCode)
    }

    public static func parse(
        amountText: String,
        merchant: String?,
        cardName: String?,
        explicitCurrency: String? = nil,
        defaultCurrency: CurrencyCode
    ) -> ParsedApplePayInput? {
        guard let parsed = parseFormattedAmount(
            amountText,
            explicitCurrency: explicitCurrency,
            defaultCurrency: defaultCurrency
        ) else { return nil }

        let cleanedMerchant = nonEmptyTrimmed(merchant)
        let cleanedCard = nonEmptyTrimmed(cardName)
        let merchantName = cleanedMerchant ?? cleanedCard ?? "Apple Pay"

        let note: String
        if let cleanedCard, cleanedMerchant != nil {
            note = "Apple Pay · \(cleanedCard)"
        } else {
            note = "Apple Pay"
        }

        let cardSuffix = cleanedCard.map { " (\($0))" } ?? ""
        let rawSummary = "Apple Pay \(parsed.amountMajor) \(parsed.currencyCode) at \(merchantName)\(cardSuffix)"

        return ParsedApplePayInput(
            amountMajor: parsed.amountMajor,
            currencyCode: parsed.currencyCode,
            merchantName: merchantName,
            cardName: cleanedCard,
            note: note,
            rawSummary: rawSummary
        )
    }

    private static func nonEmptyTrimmed(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    private static func splitAmountComponents(_ text: String) -> (prefix: String, number: String, suffix: String)? {
        guard let firstDigit = text.firstIndex(where: { $0.isASCII && $0.isNumber }) else {
            return nil
        }
        var end = firstDigit
        while end < text.endIndex {
            let ch = text[end]
            if (ch.isASCII && ch.isNumber) || ch == "." || ch == "," {
                end = text.index(after: end)
            } else {
                break
            }
        }
        let prefix = String(text[..<firstDigit])
        let number = String(text[firstDigit..<end])
        let suffix = String(text[end...])

        // Reject trailing punctuation or malformed adjacent separators inside the number slice.
        guard let last = number.last, last.isASCII, last.isNumber,
              !number.contains(".."), !number.contains(",,"),
              !number.contains(".,"), !number.contains(",.")
        else { return nil }

        // Reject disconnected extra digits in the suffix (e.g. "12 abc 34").
        if suffix.contains(where: { $0.isASCII && $0.isNumber }) {
            return nil
        }

        return (prefix, number, suffix)
    }

    private static func stripOuterSignsAndWhitespace(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var scalars = Substring(trimmed)
        while let first = scalars.first, first == "+" || first == "-" || first.isWhitespace {
            scalars = scalars.dropFirst()
        }
        while let last = scalars.last, last == "+" || last == "-" || last.isWhitespace {
            scalars = scalars.dropLast()
        }
        return String(scalars)
    }

    private static func resolveCurrencyToken(_ token: String, defaultCurrency: CurrencyCode) -> String? {
        switch token {
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥": return (defaultCurrency == .cny || defaultCurrency == .jpy) ? defaultCurrency.rawValue : "JPY"
        case "₩": return "KRW"
        case "฿": return "THB"
        case "₱": return "PHP"
        case "₹": return "INR"
        case "₫", "đ", "Đ": return "VND"
        case "$": return defaultCurrency == .vnd ? "SGD" : defaultCurrency.rawValue
        case "C$", "c$": return "CAD"
        case "SG$", "sg$": return "SGD"
        default:
            return CurrencyCode.normalizeCode(token)
        }
    }

    private static func parseNumericValue(_ raw: String, isZeroDecimal: Bool) -> Double? {
        if isZeroDecimal {
            let dotCount = raw.filter { $0 == "." }.count
            let commaCount = raw.filter { $0 == "," }.count

            if dotCount > 0 && commaCount > 0,
               let lastDot = raw.lastIndex(of: "."),
               let lastComma = raw.lastIndex(of: ",") {
                if lastDot > lastComma {
                    let frac = raw[raw.index(after: lastDot)...]
                    if dotCount == 1, (1...2).contains(frac.count) {
                        return Double(raw.replacingOccurrences(of: ",", with: ""))
                    }
                } else {
                    let frac = raw[raw.index(after: lastComma)...]
                    if commaCount == 1, (1...2).contains(frac.count) {
                        let normalized = raw
                            .replacingOccurrences(of: ".", with: "")
                            .replacingOccurrences(of: ",", with: ".")
                        return Double(normalized)
                    }
                }
            } else if dotCount == 1 && commaCount == 0,
                      let dotIdx = raw.firstIndex(of: ".") {
                let fracCount = raw.distance(from: raw.index(after: dotIdx), to: raw.endIndex)
                if (1...2).contains(fracCount) {
                    return Double(raw)
                }
            } else if commaCount == 1 && dotCount == 0,
                      let commaIdx = raw.firstIndex(of: ",") {
                let fracCount = raw.distance(from: raw.index(after: commaIdx), to: raw.endIndex)
                if (1...2).contains(fracCount) {
                    return Double(raw.replacingOccurrences(of: ",", with: "."))
                }
            }

            let stripped = raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
            return Double(stripped)
        }

        // Standard decimal currencies:
        let hasComma = raw.contains(",")
        let hasDot = raw.contains(".")

        if hasComma && hasDot {
            guard let lastComma = raw.lastIndex(of: ","),
                  let lastDot = raw.lastIndex(of: ".")
            else { return nil }
            if lastDot > lastComma {
                return Double(raw.replacingOccurrences(of: ",", with: ""))
            } else {
                let withoutDots = raw.replacingOccurrences(of: ".", with: "")
                guard withoutDots.filter({ $0 == "," }).count == 1 else { return nil }
                return Double(withoutDots.replacingOccurrences(of: ",", with: "."))
            }
        }

        if hasComma {
            let commaCount = raw.filter { $0 == "," }.count
            if commaCount == 1, let commaIdx = raw.firstIndex(of: ",") {
                let fracCount = raw.distance(from: raw.index(after: commaIdx), to: raw.endIndex)
                if (1...2).contains(fracCount) {
                    return Double(raw.replacingOccurrences(of: ",", with: "."))
                }
            }
            return Double(raw.replacingOccurrences(of: ",", with: ""))
        }

        if hasDot {
            let dotCount = raw.filter { $0 == "." }.count
            if dotCount > 1 {
                return Double(raw.replacingOccurrences(of: ".", with: ""))
            }
        }

        return Double(raw)
    }
}
