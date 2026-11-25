import Foundation

/// Outcome of converting a foreign-currency amount into the household's currency.
public struct CurrencyConversion: Equatable, Sendable {
    public let convertedMajor: Double
    public let convertedMinor: Int64
    /// Target currency units per 1 source currency unit (e.g. ~0.171 SGD per 1 HKD).
    public let rate: Double
    public let isLiveRate: Bool
    public let rateDate: String?

    public init(
        convertedMajor: Double,
        convertedMinor: Int64,
        rate: Double,
        isLiveRate: Bool,
        rateDate: String?
    ) {
        self.convertedMajor = convertedMajor
        self.convertedMinor = convertedMinor
        self.rate = rate
        self.isLiveRate = isLiveRate
        self.rateDate = rateDate
    }
}

/// Snapshot of exchange rates relative to 1 SGD (`ratesPerSGD["SGD"] == 1.0`).
public struct ExchangeRateTable: Codable, Equatable, Sendable {
    public var ratesPerSGD: [String: Double]
    public var rateDate: String?
    public var fetchedAt: Date?

    public var isLive: Bool { fetchedAt != nil }

    public init(
        ratesPerSGD: [String: Double],
        rateDate: String? = nil,
        fetchedAt: Date? = nil
    ) {
        var sanitized: [String: Double] = ["SGD": 1.0]
        for (rawKey, value) in ratesPerSGD {
            guard value > 0, value.isFinite else { continue }
            if let code = CurrencyCode.normalizeCode(rawKey) {
                sanitized[code] = value
            }
        }
        sanitized["SGD"] = 1.0
        self.ratesPerSGD = sanitized
        self.rateDate = rateDate
        self.fetchedAt = fetchedAt
    }

    private static let currentLock = NSLock()
    private nonisolated(unsafe) static var _current: ExchangeRateTable = .fallback

    /// Active rates table used by pure domain converters; updated by `ExchangeRateService`.
    public static var current: ExchangeRateTable {
        get {
            currentLock.lock()
            defer { currentLock.unlock() }
            return _current
        }
        set {
            currentLock.lock()
            _current = newValue
            currentLock.unlock()
        }
    }

    /// Built-in offline fallback rates (units per 1 SGD).
    /// Preserves the original 8 currency baselines verbatim for deterministic offline behavior.
    public static let fallback = ExchangeRateTable(
        ratesPerSGD: [
            "SGD": 1.0,
            "VND": 19_000.0,
            "USD": 0.75,
            "EUR": 0.69,
            "GBP": 0.59,
            "AUD": 1.15,
            "CAD": 1.04,
            "MYR": 3.30,
            // Expanded household & travel currencies
            "HKD": 5.85,
            "CNY": 5.42,
            "JPY": 114.0,
            "KRW": 1_040.0,
            "THB": 25.8,
            "TWD": 24.2,
            "IDR": 11_900.0,
            "PHP": 43.5,
            "NZD": 1.26,
            "CHF": 0.66,
            "INR": 63.5,
            // Additional common travel currencies
            "AED": 2.75,
            "BND": 1.0,
            "MOP": 6.03,
            "SEK": 8.0,
            "NOK": 8.2,
            "DKK": 5.15,
            "PLN": 3.0,
            "TRY": 26.0,
            "MXN": 15.0,
            "BRL": 4.3,
            "ZAR": 13.5,
            "SAR": 2.81,
            "QAR": 2.73,
            "KHR": 3_050.0,
            "LAK": 16_400.0,
            "MMK": 1_575.0,
            "LKR": 220.0,
            "CZK": 17.5,
            "HUF": 280.0,
            "ILS": 2.75,
            "KWD": 0.23,
            "BHD": 0.28,
            "OMR": 0.29,
        ],
        rateDate: nil,
        fetchedAt: nil
    )

    /// Returns `(rate, isLive, rateDate)` where `1 source = rate * target`.
    /// Never mixes a live numerator with a fallback denominator.
    public func conversionRate(
        from sourceCode: String,
        to targetCode: String
    ) -> (rate: Double, isLive: Bool, rateDate: String?)? {
        guard let src = CurrencyCode.normalizeCode(sourceCode),
              let dst = CurrencyCode.normalizeCode(targetCode)
        else { return nil }

        if src == dst {
            return (1.0, isLive, rateDate)
        }

        if let s = ratesPerSGD[src], s > 0, s.isFinite,
           let t = ratesPerSGD[dst], t > 0, t.isFinite {
            let ratio = t / s
            if ratio > 0, ratio.isFinite {
                return (ratio, isLive, rateDate)
            }
        }

        if self != Self.fallback,
           let fs = Self.fallback.ratesPerSGD[src], fs > 0, fs.isFinite,
           let ft = Self.fallback.ratesPerSGD[dst], ft > 0, ft.isFinite {
            let ratio = ft / fs
            if ratio > 0, ratio.isFinite {
                return (ratio, false, nil)
            }
        }

        return nil
    }

    public func convert(
        _ amount: Double,
        from sourceCode: String,
        to target: CurrencyCode
    ) -> CurrencyConversion? {
        guard amount.isFinite,
              let info = conversionRate(from: sourceCode, to: target.rawValue)
        else { return nil }

        let raw = amount * info.rate
        guard raw.isFinite, abs(raw) < 9e14 else { return nil }

        let convertedMajor = target.isZeroDecimal
            ? raw.rounded()
            : (raw * 100).rounded() / 100
        let convertedMinor = target.toStorageMinor(convertedMajor)

        return CurrencyConversion(
            convertedMajor: convertedMajor,
            convertedMinor: convertedMinor,
            rate: info.rate,
            isLiveRate: info.isLive,
            rateDate: info.rateDate
        )
    }

    /// Converts an integer storage minor amount (`Int64`, scaled by 100) between currencies.
    public func convertMinor(_ minor: Int64, from source: CurrencyCode, to target: CurrencyCode) -> Int64 {
        guard minor != 0, source != target else { return minor }
        let sign: Int64 = minor < 0 ? -1 : 1
        let absMinor = minor == Int64.min ? Int64.max : abs(minor)
        guard let converted = convert(source.toMajor(absMinor), from: source.rawValue, to: target) else {
            return minor
        }
        return sign * converted.convertedMinor
    }

    public var availableCurrencyCodes: [String] {
        var combined = Set(CurrencyCode.allCases.map(\.rawValue))
        combined.formUnion(ratesPerSGD.keys)
        combined.formUnion(Self.fallback.ratesPerSGD.keys)
        return combined
            .compactMap(CurrencyCode.normalizeCode)
            .sorted()
    }

    public static func formatRate(_ rate: Double, from sourceCode: String, to target: CurrencyCode) -> String {
        guard rate > 0, rate.isFinite else { return "" }
        let src = CurrencyCode.normalizeCode(sourceCode) ?? sourceCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if rate < 0.001 {
            let inv = 1.0 / rate
            return "1 \(target.rawValue) = \(formatRateNumber(inv)) \(src)"
        }
        return "1 \(src) = \(formatRateNumber(rate)) \(target.rawValue)"
    }

    private static func formatRateNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        if value >= 100 {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        } else if value >= 10 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        } else {
            formatter.minimumFractionDigits = 4
            formatter.maximumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.4f", value)
    }
}
