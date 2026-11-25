import Foundation

/// Supported household currencies, matching Tally Web plus common regional & travel currencies.
public enum CurrencyCode: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case sgd = "SGD"
    case vnd = "VND"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case aud = "AUD"
    case cad = "CAD"
    case myr = "MYR"
    case hkd = "HKD"
    case cny = "CNY"
    case jpy = "JPY"
    case krw = "KRW"
    case thb = "THB"
    case twd = "TWD"
    case idr = "IDR"
    case php = "PHP"
    case nzd = "NZD"
    case chf = "CHF"
    case inr = "INR"

    public var id: String { rawValue }

    public var isZeroDecimal: Bool {
        switch self {
        case .vnd, .jpy, .krw, .idr:
            return true
        default:
            return false
        }
    }

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
        case .hkd: return "HK$"
        case .cny: return "¥"
        case .jpy: return "¥"
        case .krw: return "₩"
        case .thb: return "฿"
        case .twd: return "NT$"
        case .idr: return "Rp"
        case .php: return "₱"
        case .nzd: return "NZ$"
        case .chf: return "CHF "
        case .inr: return "₹"
        }
    }

    /// Ultra-short symbol for dense calendar day cells (e.g. `-$20`, `+$100`, `-65k`).
    public var calendarSymbol: String {
        switch self {
        case .sgd, .usd, .aud, .cad, .nzd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .myr: return "RM"
        case .vnd: return "₫"
        case .hkd: return "HK$"
        case .cny, .jpy: return "¥"
        case .krw: return "₩"
        case .thb: return "฿"
        case .twd: return "NT$"
        case .idr: return "Rp"
        case .php: return "₱"
        case .chf: return "CHF"
        case .inr: return "₹"
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
        case (.hkd, .vietnamese): return "Đô la Hồng Kông"
        case (.cny, .vietnamese): return "Nhân dân tệ"
        case (.jpy, .vietnamese): return "Yên Nhật"
        case (.krw, .vietnamese): return "Won Hàn Quốc"
        case (.thb, .vietnamese): return "Baht Thái"
        case (.twd, .vietnamese): return "Tân Đài tệ"
        case (.idr, .vietnamese): return "Rupiah Indonesia"
        case (.php, .vietnamese): return "Peso Philippines"
        case (.nzd, .vietnamese): return "Đô la New Zealand"
        case (.chf, .vietnamese): return "Franc Thụy Sĩ"
        case (.inr, .vietnamese): return "Rupee Ấn Độ"

        case (.vnd, .english): return "Vietnamese Dong"
        case (.sgd, .english): return "Singapore Dollar"
        case (.usd, .english): return "US Dollar"
        case (.eur, .english): return "Euro"
        case (.gbp, .english): return "British Pound"
        case (.aud, .english): return "Australian Dollar"
        case (.cad, .english): return "Canadian Dollar"
        case (.myr, .english): return "Malaysian Ringgit"
        case (.hkd, .english): return "Hong Kong Dollar"
        case (.cny, .english): return "Chinese Yuan"
        case (.jpy, .english): return "Japanese Yen"
        case (.krw, .english): return "South Korean Won"
        case (.thb, .english): return "Thai Baht"
        case (.twd, .english): return "New Taiwan Dollar"
        case (.idr, .english): return "Indonesian Rupiah"
        case (.php, .english): return "Philippine Peso"
        case (.nzd, .english): return "New Zealand Dollar"
        case (.chf, .english): return "Swiss Franc"
        case (.inr, .english): return "Indian Rupee"

        case (.vnd, .chinese): return "越南盾"
        case (.sgd, .chinese): return "新加坡元"
        case (.usd, .chinese): return "美元"
        case (.eur, .chinese): return "欧元"
        case (.gbp, .chinese): return "英镑"
        case (.aud, .chinese): return "澳元"
        case (.cad, .chinese): return "加元"
        case (.myr, .chinese): return "马来西亚林吉特"
        case (.hkd, .chinese): return "港元"
        case (.cny, .chinese): return "人民币"
        case (.jpy, .chinese): return "日元"
        case (.krw, .chinese): return "韩元"
        case (.thb, .chinese): return "泰铢"
        case (.twd, .chinese): return "新台币"
        case (.idr, .chinese): return "印尼盾"
        case (.php, .chinese): return "菲律宾比索"
        case (.nzd, .chinese): return "新西兰元"
        case (.chf, .chinese): return "瑞士法郎"
        case (.inr, .chinese): return "印度卢比"
        }
    }

    /// Converts a major-unit Double (e.g. `18.50` SGD or `65000` VND) to Tally's integer minor
    /// storage unit (cents, matching Tally Web's `amount = round(major * 100)` so web backups
    /// round-trip losslessly).
    public func toStorageMinor(_ major: Double) -> Int64 {
        Self.toStorageMinor(major, isZeroDecimal: isZeroDecimal)
    }

    /// Converts Tally's integer storage unit back to major units.
    public func toMajor(_ storageMinor: Int64) -> Double {
        Self.toMajor(storageMinor)
    }

    // MARK: - Arbitrary ISO 4217 Currency Helpers

    private static let validISOCodes: Set<String> = Set(
        Locale.commonISOCurrencyCodes.map { $0.uppercased() }
    ).union(CurrencyCode.allCases.map(\.rawValue))

    private static let extraZeroDecimalCodes: Set<String> = [
        "BIF", "CLP", "DJF", "GNF", "ISK", "KMF", "PYG", "RWF", "UGX", "VUV", "XAF", "XOF", "XPF"
    ]

    private static let codeAliases: [String: String] = [
        "RMB": "CNY",
        "CNH": "CNY",
        "NTD": "TWD",
        "S$": "SGD",
        "HK$": "HKD",
        "US$": "USD",
        "NT$": "TWD",
        "A$": "AUD",
        "AU$": "AUD",
        "CA$": "CAD",
        "NZ$": "NZD",
        "RM": "MYR",
        "RP": "IDR",
        "VNĐ": "VND",
        "Đ": "VND",
    ]

    public static func normalizeCode(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        let mapped = codeAliases[upper] ?? upper
        guard mapped.count == 3, validISOCodes.contains(mapped) else { return nil }
        return mapped
    }

    public static func isZeroDecimal(code: String) -> Bool {
        let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let known = CurrencyCode(rawValue: upper) {
            return known.isZeroDecimal
        }
        return extraZeroDecimalCodes.contains(upper)
    }

    public static func fractionDigits(forCode code: String) -> Int {
        isZeroDecimal(code: code) ? 0 : 2
    }

    public static func toStorageMinor(_ major: Double, currencyCode: String) -> Int64 {
        toStorageMinor(major, isZeroDecimal: isZeroDecimal(code: currencyCode))
    }

    private static func toStorageMinor(_ major: Double, isZeroDecimal: Bool) -> Int64 {
        if isZeroDecimal {
            return Int64(major.rounded()) * 100
        }
        return Int64((major * 100).rounded())
    }

    public static func toMajor(_ storageMinor: Int64) -> Double {
        Double(storageMinor) / 100.0
    }

    public static func displayName(forCode code: String, language: AppLanguage) -> String {
        let upper = normalizeCode(code) ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let known = CurrencyCode(rawValue: upper) {
            return known.name(in: language)
        }
        if let localized = language.locale.localizedString(forCurrencyCode: upper), !localized.isEmpty {
            return localized
        }
        return upper
    }

    public static func displaySymbol(forCode code: String) -> String {
        let upper = normalizeCode(code) ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let known = CurrencyCode(rawValue: upper) {
            return known.narrowSymbol
        }
        return upper
    }
}

/// FX conversion between currencies using live/cached rates with deterministic offline fallback.
public enum CurrencyConverter {
    public static func convert(
        _ amount: Double,
        from: CurrencyCode,
        to: CurrencyCode,
        rates: ExchangeRateTable = .current
    ) -> Double {
        guard from != to else { return amount }
        return rates.convert(amount, from: from.rawValue, to: to)?.convertedMajor ?? amount
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
    private nonisolated(unsafe) static var cachedFormatters: [String: NumberFormatter] = [:]

    private static func formatDecimal(_ absMajor: Double, currencyCode: String) -> String {
        let upper = currencyCode.uppercased()
        let isVND = upper == CurrencyCode.vnd.rawValue
        let fractionDigits = CurrencyCode.fractionDigits(forCode: upper)
        let key = "\(isVND ? "vnd" : "std")-\(fractionDigits)"
        formatterLock.lock()
        defer { formatterLock.unlock() }
        let formatter: NumberFormatter
        if let existing = cachedFormatters[key] {
            formatter = existing
        } else {
            let created = NumberFormatter()
            created.numberStyle = .decimal
            created.groupingSeparator = isVND ? "." : ","
            created.decimalSeparator = isVND ? "," : "."
            created.minimumFractionDigits = fractionDigits
            created.maximumFractionDigits = fractionDigits
            cachedFormatters[key] = created
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
        let signPrefix = Self.signPrefix(minor: minor, signed: signed)

        if compact {
            return signPrefix + formatCompact(absMajor, symbol: currency.narrowSymbol, isVND: currency == .vnd, isZeroDecimal: currency.isZeroDecimal, language: language)
        }

        let number = formatDecimal(absMajor, currencyCode: currency.rawValue)
        if currency == .vnd {
            return "\(signPrefix)\(number) ₫"
        }
        return "\(signPrefix)\(currency.narrowSymbol)\(number)"
    }

    /// Formats any ISO 4217 currency code (using `CurrencyCode` formatting for known currencies
    /// and `<CODE> <amount>` for other world currencies).
    public static func format(
        minor: Int64,
        currencyCode: String,
        language: AppLanguage = .english,
        compact: Bool = false,
        signed: Bool = false
    ) -> String {
        let upper = CurrencyCode.normalizeCode(currencyCode)
            ?? currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let known = CurrencyCode(rawValue: upper) {
            return format(minor: minor, currency: known, language: language, compact: compact, signed: signed)
        }

        let absMajor = abs(CurrencyCode.toMajor(minor))
        let signPrefix = Self.signPrefix(minor: minor, signed: signed)
        let isZeroDecimal = CurrencyCode.isZeroDecimal(code: upper)

        if compact {
            return signPrefix + formatCompact(absMajor, symbol: "\(upper) ", isVND: false, isZeroDecimal: isZeroDecimal, language: language)
        }

        let number = formatDecimal(absMajor, currencyCode: upper)
        return "\(signPrefix)\(upper) \(number)"
    }

    private static func signPrefix(minor: Int64, signed: Bool) -> String {
        if minor < 0 { return "−" }
        if signed && minor > 0 { return "+" }
        return ""
    }

    private static func formatCompact(
        _ absMajor: Double,
        symbol: String,
        isVND: Bool,
        isZeroDecimal: Bool,
        language: AppLanguage
    ) -> String {
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
            rounded = isZeroDecimal ? "\(Int64(scaled.rounded()))" : String(format: "%.0f", scaled)
        } else if scaled >= 10 || abs(scaled - scaled.rounded()) < 0.05 {
            rounded = String(format: "%.0f", scaled)
        } else {
            rounded = String(format: "%.1f", scaled)
        }
        if isVND {
            return "\(rounded)\(suffix)₫"
        }
        return "\(symbol)\(rounded)\(suffix)"
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
