import Foundation

/// Supported currencies, matching Tally Web (`SGD`, `VND`, `USD`, `EUR`, `GBP`, `AUD`, `CAD`, `MYR`).
public enum CurrencyCode: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case sgd = "SGD"
    case vnd = "VND"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case aud = "AUD"
    case cad = "CAD"
    case myr = "MYR"

    public var id: String { rawValue }

    public var isZeroDecimal: Bool { self == .vnd }

    public var fractionDigits: Int { isZeroDecimal ? 0 : 2 }

    public var narrowSymbol: String {
        switch self {
        case .vnd: return "₫"
        case .sgd: return "S$"
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .aud: return "A$"
        case .cad: return "CA$"
        case .myr: return "RM"
        }
    }

    /// Ultra-short symbol for dense calendar day cells (e.g. `-$20`, `+$100`, `-65k`).
    public var calendarSymbol: String {
        switch self {
        case .sgd, .usd, .aud, .cad: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .myr: return "RM"
        case .vnd: return "₫"
        }
    }

    public func name(in language: AppLanguage) -> String {
        switch (self, language.resolved) {
        case (.vnd, .vietnamese): return "Đồng Việt Nam"
        case (.sgd, .vietnamese): return "Đô la Singapore"
        case (.usd, .vietnamese): return "Đô la Mỹ"
        case (.eur, .vietnamese): return "Euro"
        case (.gbp, .vietnamese): return "Bảng Anh"
        case (.aud, .vietnamese): return "Đô la Úc"
        case (.cad, .vietnamese): return "Đô la Canada"
        case (.myr, .vietnamese): return "Ringgit Malaysia"
        case (.vnd, .english): return "Vietnamese Dong"
        case (.sgd, .english): return "Singapore Dollar"
        case (.usd, .english): return "US Dollar"
        case (.eur, .english): return "Euro"
        case (.gbp, .english): return "British Pound"
        case (.aud, .english): return "Australian Dollar"
        case (.cad, .english): return "Canadian Dollar"
        case (.myr, .english): return "Malaysian Ringgit"
        case (.vnd, .chinese): return "越南盾"
        case (.sgd, .chinese): return "新加坡元"
        case (.usd, .chinese): return "美元"
        case (.eur, .chinese): return "欧元"
        case (.gbp, .chinese): return "英镑"
        case (.aud, .chinese): return "澳元"
        case (.cad, .chinese): return "加元"
        case (.myr, .chinese): return "马来西亚林吉特"
        }
    }

    /// Converts a major-unit Double (e.g. `18.50` SGD or `65000` VND) to Tally's integer minor
    /// storage unit (cents, matching Tally Web's `amount = round(major * 100)` so web backups
    /// round-trip losslessly).
    public func toStorageMinor(_ major: Double) -> Int64 {
        if isZeroDecimal {
            return Int64(major.rounded()) * 100
        }
        return Int64((major * 100).rounded())
    }

    /// Converts Tally's integer storage unit back to major units.
    public func toMajor(_ storageMinor: Int64) -> Double {
        Double(storageMinor) / 100.0
    }
}

/// Approximate FX conversion between supported currencies so a foreign-currency receipt
/// (e.g. 50,000 VND Grab ride while budget is in SGD) converts safely instead of logging S$50,000.
public enum CurrencyConverter {
    /// Approximate value of 1 SGD in each currency.
    private static func unitsPerSGD(_ code: CurrencyCode) -> Double {
        switch code {
        case .sgd: return 1.0
        case .vnd: return 19_000.0
        case .usd: return 0.75
        case .eur: return 0.69
        case .gbp: return 0.59
        case .aud: return 1.15
        case .cad: return 1.04
        case .myr: return 3.30
        }
    }

    public static func convert(_ amount: Double, from: CurrencyCode, to: CurrencyCode) -> Double {
        guard from != to else { return amount }
        let inSGD = amount / unitsPerSGD(from)
        let converted = inSGD * unitsPerSGD(to)
        return to.isZeroDecimal ? converted.rounded() : (converted * 100).rounded() / 100
    }
}

/// Formats integer-stored money values cleanly in English, Vietnamese, or Chinese.
public enum MoneyFormat {
    /// Shared mask shown in place of income-revealing amounts when "Hide income" is on.
    public static let hiddenPlaceholder = "•••"

    /// Returns the shared mask when `hidden` is true, otherwise `value`.
    public static func masked(_ value: @autoclosure () -> String, hidden: Bool) -> String {
        hidden ? hiddenPlaceholder : value()
    }

    private static let formatterLock = NSLock()
    private nonisolated(unsafe) static var cachedFormatters: [CurrencyCode: NumberFormatter] = [:]

    private static func formatDecimal(_ absMajor: Double, currency: CurrencyCode) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let formatter: NumberFormatter
        if let existing = cachedFormatters[currency] {
            formatter = existing
        } else {
            let created = NumberFormatter()
            created.numberStyle = .decimal
            created.groupingSeparator = currency == .vnd ? "." : ","
            created.decimalSeparator = currency == .vnd ? "," : "."
            created.minimumFractionDigits = currency.fractionDigits
            created.maximumFractionDigits = currency.fractionDigits
            cachedFormatters[currency] = created
            formatter = created
        }
        return formatter.string(from: NSNumber(value: absMajor)) ?? "\(Int64(absMajor))"
    }

    public static func format(
        minor: Int64,
        currency: CurrencyCode,
        language: AppLanguage = .english,
        compact: Bool = false,
        signed: Bool = false
    ) -> String {
        let major = currency.toMajor(minor)
        let absMajor = abs(major)
        let signPrefix: String
        if minor < 0 {
            signPrefix = "−"
        } else if signed && minor > 0 {
            signPrefix = "+"
        } else {
            signPrefix = ""
        }

        if compact {
            return signPrefix + formatCompact(absMajor, currency: currency, language: language)
        }

        let number = formatDecimal(absMajor, currency: currency)
        if currency == .vnd {
            return "\(signPrefix)\(number) ₫"
        }
        return "\(signPrefix)\(currency.narrowSymbol)\(number)"
    }

    private static func formatCompact(_ absMajor: Double, currency: CurrencyCode, language: AppLanguage) -> String {
        let isVI = language.resolved == .vietnamese
        let suffix: String
        let scaled: Double
        if absMajor >= 1_000_000_000 {
            scaled = absMajor / 1_000_000_000
            suffix = isVI ? " tỷ" : "B"
        } else if absMajor >= 1_000_000 {
            scaled = absMajor / 1_000_000
            suffix = isVI ? " tr" : "M"
        } else if absMajor >= 1_000 {
            scaled = absMajor / 1_000
            suffix = isVI ? "k" : "K"
        } else {
            scaled = absMajor
            suffix = ""
        }
        let rounded: String
        if suffix.isEmpty {
            rounded = currency.isZeroDecimal ? "\(Int64(scaled.rounded()))" : String(format: "%.0f", scaled)
        } else if scaled >= 10 || abs(scaled - scaled.rounded()) < 0.05 {
            rounded = String(format: "%.0f", scaled)
        } else {
            rounded = String(format: "%.1f", scaled)
        }
        if currency == .vnd {
            return "\(rounded)\(suffix)₫"
        }
        return "\(currency.narrowSymbol)\(rounded)\(suffix)"
    }

    /// Ultra-compact amount string designed to fit inside narrow 7-column calendar cells
    /// (e.g. `-$20`, `+$100`, `-$4.5`, `+$2.4K`, `-65k`, `+25tr`).
    public static func formatCalendarAmount(
        minor: Int64,
        currency: CurrencyCode,
        language: AppLanguage = .english,
        isIncome: Bool
    ) -> String {
        let absMajor = abs(currency.toMajor(minor))
        let sign = isIncome ? "+" : "-"
        let isVI = language.resolved == .vietnamese

        let scaled: Double
        let suffix: String
        if absMajor >= 1_000_000_000 {
            scaled = absMajor / 1_000_000_000
            suffix = isVI ? "tỷ" : "B"
        } else if absMajor >= 1_000_000 {
            scaled = absMajor / 1_000_000
            suffix = isVI ? "tr" : "M"
        } else if absMajor >= 1_000 {
            scaled = absMajor / 1_000
            suffix = isVI ? "k" : "K"
        } else {
            scaled = absMajor
            suffix = ""
        }

        let numberText: String
        if suffix.isEmpty {
            if currency.isZeroDecimal || scaled >= 10 || abs(scaled - scaled.rounded()) < 0.05 {
                numberText = "\(Int64(scaled.rounded()))"
            } else {
                numberText = String(format: "%.1f", scaled)
            }
        } else if scaled >= 10 || abs(scaled - scaled.rounded()) < 0.05 {
            numberText = "\(Int64(scaled.rounded()))"
        } else {
            numberText = String(format: "%.1f", scaled)
        }

        if currency == .vnd {
            return suffix.isEmpty ? "\(sign)\(numberText)₫" : "\(sign)\(numberText)\(suffix)"
        }
        return "\(sign)\(currency.calendarSymbol)\(numberText)\(suffix)"
    }
}
