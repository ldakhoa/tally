import Foundation
import TallyCore

/// A parsed transaction candidate before it is saved.
public struct ParsedTransactionDraft: Codable, Hashable, Sendable {
    public var name: String
    public var amountMajor: Double
    public var currencyCode: String?
    public var type: TransactionType
    public var category: CategoryID
    public var dayKey: String
    public var note: String
    public var confidence: Double
    public var parsedByAI: Bool

    public var currency: CurrencyCode? {
        get { currencyCode.flatMap(CurrencyCode.init(rawValue:)) }
        set { currencyCode = newValue?.rawValue }
    }

    public init(
        name: String,
        amountMajor: Double,
        currencyCode: String? = nil,
        type: TransactionType = .expense,
        category: CategoryID = .other,
        dayKey: String = DateKey.dayKey(from: Date()),
        note: String = "",
        confidence: Double = 0.75,
        parsedByAI: Bool = false
    ) {
        self.name = name
        self.amountMajor = amountMajor
        self.currencyCode = currencyCode.flatMap(CurrencyCode.normalizeCode) ?? currencyCode?.uppercased()
        self.type = type
        self.category = category
        self.dayKey = dayKey
        self.note = note
        self.confidence = confidence
        self.parsedByAI = parsedByAI
    }

    public init(
        name: String,
        amountMajor: Double,
        currency: CurrencyCode?,
        type: TransactionType = .expense,
        category: CategoryID = .other,
        dayKey: String = DateKey.dayKey(from: Date()),
        note: String = "",
        confidence: Double = 0.75,
        parsedByAI: Bool = false
    ) {
        self.init(
            name: name,
            amountMajor: amountMajor,
            currencyCode: currency?.rawValue,
            type: type,
            category: category,
            dayKey: dayKey,
            note: note,
            confidence: confidence,
            parsedByAI: parsedByAI
        )
    }
}

public struct RecognizedBankAlert: Equatable, Sendable {
    public let amount: Double
    public let currencyCode: String
    public let type: TransactionType

    public var currency: CurrencyCode? { CurrencyCode(rawValue: currencyCode) }

    public init(amount: Double, currencyCode: String, type: TransactionType) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.type = type
    }
}

/// Deterministic offline parser for Vietnamese, Singapore, & international bank alerts, emails,
/// Apple Pay notes, and natural shorthand (e.g. "ăn phở 65k",
/// "TK 1903xxx -125,000 VND tai HIGHLANDS COFFEE", "You spent SGD 18.50 at FairPrice",
/// "0% FX fees! You've spent HKD 83.75 using Freedom credit card at PinDuoDuo...").
public enum LocalTransactionParser {
    /// Rejects obvious marketing/promotional emails, newsletters, OTPs, and ads.
    public static func isLikelyPromotional(_ rawText: String) -> Bool {
        let normalized = normalizeApostrophes(rawText)
        let folded = normalized.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let strongTransactionSignals = [
            "transaction alert", "card transaction", "made a payment", "has been debited",
            "has been credited", "was made on your", "you have transferred", "you have received",
            "you've spent", "you have spent", "you spent", "alert us via",
            "e-receipt", "your grab e-receipt", "bien dong so du", "so du kha dung",
            "sd tk ", "tai khoan thanh toan", "paynow transfer", "payment confirmation"
        ]
        if containsAny(folded, strongTransactionSignals) {
            return false
        }
        let promoSignals = [
            "unsubscribe", "view in browser", "promotional", "promotion", "voucher", "promo code",
            "discount", "up to ", "limited time", "exclusive offer", "special offer", "lucky draw",
            "win up to", "stand a chance", "redeem now", "apply now", "refer a friend",
            "khuyen mai", "uu dai", "giam gia", "giam ngay", "ma giam", "tang ngay",
            "co hoi trung", "dua ca nha di choi", "moi ban be", "one-time password", "otp is",
            "verification code", "do not share this code", "statement is ready",
            // Loan, cash-advance and card-upsell offers (e.g. "CashOne", balance transfer mailers).
            "pre-approved", "preapproved", "pre-qualified", "personal loan offer",
            "interest rate", "% p.a", "offer ends", "offer valid", "valid till", "valid until",
            "t&cs apply", "terms and conditions apply", "sign up now", "cash rebate when"
        ]
        return containsAny(folded, promoSignals)
    }

    /// `true` when a parsed result describes itself as something other than a real transaction,
    /// e.g. a model that answered "SC CashOne Promo (not a transaction)" while still marking it as
    /// one. `strict` adds promotional wording and is meant for auto-captured bank emails only, so a
    /// typed note like "promo lunch 12" still parses.
    public static func describesNonTransaction(name: String, note: String, strict: Bool) -> Bool {
        let folded = "\(name) \(note)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let denials = [
            "not a transaction", "not an actual transaction", "not a real transaction", "non-transaction",
            "no actual transaction", "no transaction", "no real transaction", "no completed transaction",
            "khong phai giao dich", "khong co giao dich", "不是交易", "非交易", "没有实际交易", "無實際交易"
        ]
        if containsAny(folded, denials) { return true }
        guard strict else { return false }
        // Words a model uses to describe the email itself, not a discount on a real receipt
        // ("promo code applied" on an e-receipt must still parse).
        let promotional = [
            "promotional", "promo email", "promo mail", "marketing", "advertis", "newsletter",
            "offer email", "loan offer", "email khuyen mai", "thu khuyen mai", "quang cao", "tiep thi",
            "促销邮件", "推广邮件", "广告", "營銷", "营销"
        ]
        return containsAny(folded, promotional)
    }

    public static func parse(
        _ rawText: String,
        defaultCurrency: CurrencyCode,
        now: Date = Date()
    ) -> ParsedTransactionDraft? {
        let trimmed = normalizeApostrophes(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let detectedType = detectType(lowered: lowered, raw: trimmed)
        guard let (amount, detectedCurrencyCode) = extractAmountAndCurrency(from: trimmed, defaultCurrency: defaultCurrency) else {
            return nil
        }

        let merchant = extractMerchant(from: trimmed, fallbackType: detectedType)
        let category = inferCategory(text: "\(merchant) \(trimmed)", type: detectedType)
        let dayKey = extractDate(from: trimmed) ?? DateKey.dayKey(from: now)

        return ParsedTransactionDraft(
            name: merchant,
            amountMajor: amount,
            currencyCode: detectedCurrencyCode,
            type: detectedType,
            category: category,
            dayKey: dayKey,
            note: trimmed.count > 80 ? String(trimmed.prefix(140)) : "",
            confidence: 0.72,
            parsedByAI: false
        )
    }

    public static func recognizedBankAlertAmount(_ text: String) -> RecognizedBankAlert? {
        let trimmed = normalizeApostrophes(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isLikelyPromotional(trimmed),
              firstMatch(#"(?i)\b(?:declined|failed|unsuccessful|pending|reversed|cancelled|canceled)\b"#, in: trimmed) == nil else { return nil }

        if let match = firstMatch(#"(?i)^SD\s+TK\s+[\dx*]+\s+([-+−])\s*(\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:VND|VNĐ|đ)(?=\s|[.,;]|$)"#, in: trimmed),
           let value = parseNumber(match[2], isZeroDecimal: true), value > 0, value.isFinite {
            return RecognizedBankAlert(amount: value, currencyCode: "VND", type: match[1] == "+" ? .income : .expense)
        }

        let currToken = #"(?:(?i:S\$|HK\$|US\$|NT\$|AU\$|A\$|CA\$|NZ\$|RM|Rp|VNĐ|SGD|VND|USD|EUR|GBP|AUD|CAD|MYR|HKD|CNY|RMB|JPY|KRW|THB|TWD|NTD|IDR|PHP|NZD|CHF|INR)|€|£|¥|₩|฿|₱|₹|(?-i:[A-Z]{3}))"#
        let numToken = #"(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?"#
        let amountPattern = "(?:\(currToken)\\s*\(numToken)|\(numToken)\\s*\(currToken))"
        let prefix = #"(?i)^(?:(?:0%\s*FX\s*fees!\s*)|(?:[A-Za-z\d]+\s*(?:Alert)?:\s*))*"#
        let templates: [(String, TransactionType)] = [
            (#"You have made a payment of ("# + amountPattern + #")\s+to\b"#, .expense),
            (#"A transaction of ("# + amountPattern + #")\s+was made on your\b"#, .expense),
            (#"You have received ("# + amountPattern + #")\s+via PayNow from\b"#, .income),
            (#"You(?:'ve|\s+have)?\s+spent\s+("# + amountPattern + #")\s+(?:using|on|at|with)\b"#, .expense),
            (#"You(?:'ve|\s+have)?\s+(?:paid|been\s+charged)\s+("# + amountPattern + #")\s+(?:at|to|on|with|using)\b"#, .expense),
            (#"(?:A\s+)?(?:card\s+transaction|purchase|payment)\s+of\s+("# + amountPattern + #")\s+(?:was\s+made|at|to|on|with)\b"#, .expense),
            (#"You(?:'ve|\s+have)?\s+transferred\s+("# + amountPattern + #")\s+(?:via\s+PayNow\s+)?to\b"#, .expense),
        ]
        for (template, type) in templates {
            if let match = firstMatch(prefix + template, in: trimmed),
               let (amount, currencyCode) = parseBankAlertAmountSlice(match[1]),
               amount > 0, amount.isFinite {
                return RecognizedBankAlert(amount: amount, currencyCode: currencyCode, type: type)
            }
        }
        return nil
    }

    private static func parseBankAlertAmountSlice(_ raw: String) -> (Double, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let m = firstMatch(#"^([^\d\s]+)\s*([0-9][0-9,]*(?:\.\d{1,2})?)$"#, in: trimmed),
           let code = resolveCurrencyToken(m[1], defaultCurrency: .sgd),
           let value = parseNumber(m[2], isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)) {
            return (value, code)
        }
        if let m = firstMatch(#"^([0-9][0-9,]*(?:\.\d{1,2})?)\s*([^\d\s]+)$"#, in: trimmed),
           let code = resolveCurrencyToken(m[2], defaultCurrency: .sgd),
           let value = parseNumber(m[1], isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)) {
            return (value, code)
        }
        return nil
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
        case "₫": return "VND"
        case "$": return defaultCurrency == .vnd ? "SGD" : defaultCurrency.rawValue
        default:
            return CurrencyCode.normalizeCode(token)
        }
    }

    /// Categorizes an Apple Pay merchant name quickly offline.
    public static func inferCategory(text: String, type: TransactionType) -> CategoryID {
        let lower = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if type == .income {
            if containsAny(lower, ["luong", "salary", "payroll", "bonus", "thuong"]) { return .salary }
            if containsAny(lower, ["freelance", "project", "du an", "client", "invoice", "consulting"]) { return .freelance }
            return .income
        }
        if containsAny(lower, [
            "pho", "bun", "com", "banh", "tra sua", "cafe", "coffee", "highlands", "starbucks", "phuc long",
            "katinat", "the coffee house", "trung nguyen", "lotteria", "kfc", "mcdonald", "pizza", "sushi",
            "grabfood", "shopeefood", "baemin", "gofood", "foodpanda", "deliveroo", "fairprice", "ntuc",
            "cold storage", "giant", "sheng siong", "redmart", "don don donki", "donki", "meidi-ya",
            "winmart", "vinmart", "bach hoa xanh", "coopmart", "lotte mart", "aeon", "7-eleven", "cheers",
            "an sang", "an trua", "an toi", "an uong", "nha hang", "restaurant", "grocer", "hawker",
            "supermarket", "bakery", "kopitiam", "koufu", "food republic", "toast box", "ya kun",
            "luckin", "chicha", "koi ", "liho", "gong cha", "din tai fung", "saizeriya", "genki",
            "dinner", "lunch", "breakfast", "sua", "trai cay"
        ]) { return .food }

        if containsAny(lower, [
            "grab", "gojek", "tada", "cdg zig", "comfortdelgro", "be ", "xanh sm", "taxi", "uber",
            "mrt", "ez-link", "simplygo", "transitlink", "bus", "metro", "xang", "petrol", "shell",
            "esso", "spc ", "caltex", "petrolimex", "parking", "gui xe", "ve may bay",
            "vietnam airlines", "vietjet", "scoot", "singapore airlines", "changi", "toll", "erp", "train"
        ]) { return .transport }

        if containsAny(lower, [
            "rent", "thue nha", "tien nha", "mortgage", "condo", "hdb", "town council", "mcst",
            "apartment", "management fee", "phi quan ly", "chung cu", "ikea", "courts", "noi that"
        ]) { return .housing }

        if containsAny(lower, [
            "dien", "nuoc", "internet", "wifi", "fpt", "viettel", "vnpt", "mobifone", "vinaphone",
            "singtel", "starhub", "m1 ", "simba", "circles.life", "giga", "eight ", "sp group",
            "sp services", "geneco", "keppel electric", "tuas power", "electric", "water", "utility",
            "bill", "hoa don", "icloud", "apple.com/bill", "google one", "insurance", "prudential",
            "aia ", "great eastern", "income insurance", "bao hiem"
        ]) { return .bills }

        if containsAny(lower, [
            "shopee", "lazada", "tiki", "tiktok shop", "amazon", "pinduoduo", "taobao", "tmall",
            "aliexpress", "temu", "shein", "jd.com", "1688", "qoo10", "zalora", "ebay", "asos", "etsy",
            "uniqlo", "zara", "h&m", "decathlon",
            "muji", "daiso", "apple store", "challenger", "harvey norman", "best denki", "cellphones",
            "the gioi di dong", "dien may", "mua sam", "quan ao", "giay", "shoes", "shopping", "mall",
            "takashimaya", "ion orchard", "vivocity", "jewel", "sephora", "love bonito"
        ]) { return .shopping }

        if containsAny(lower, [
            "benh vien", "hospital", "clinic", "polyclinic", "raffles medical", "fullerton health",
            "phong kham", "nha thuoc", "pharmacity", "long chau", "guardian", "watsons", "unity ",
            "pharmacy", "doctor", "bac si", "thuoc", "dental", "nha khoa",
            "gym", "fitness", "active sg", "activesg", "anytime fitness", "yoga", "health", "kham benh"
        ]) { return .health }

        if containsAny(lower, [
            "cgv", "lotte cinema", "galaxy", "golden village", "shaw", "cathay", "netflix", "spotify",
            "youtube", "disney", "cinema", "movie", "xem phim", "game", "steam", "playstation",
            "nintendo", "concert", "karaoke", "du lich", "hotel", "airbnb", "agoda", "booking.com", "klook"
        ]) { return .entertainment }

        return .other
    }

    private static func detectType(lowered: String, raw: String) -> TransactionType {
        let folded = lowered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        // Explicit plus sign before digits like "+15,000,000 VND" or "+$500"
        if raw.range(of: #"\+\s*(?:[A-Z]{3}\s*)?[S$₫€£¥₩฿₱₹]?\s*\d"#, options: .regularExpression) != nil {
            return .income
        }
        if raw.range(of: #"[-−]\s*(?:[A-Z]{3}\s*)?[S$₫€£¥₩฿₱₹]?\s*\d"#, options: .regularExpression) != nil {
            return .expense
        }
        if containsAny(folded, [
            "luong", "salary", "payroll", "nhan duoc", "credited", "credit ", "deposit",
            "chuyen den", "hoan tien", "refund", "cashback", "thuong", "bonus", "dividend",
            "income", "received from", "have received", "incoming transfer", "paynow received",
            "fast credit"
        ]) && !containsAny(folded, ["credit card", "the tin dung", "thanh toan", "debited", "spent", "made a payment", "transferred"]) {
            return .income
        }
        return .expense
    }

    private static func extractAmountAndCurrency(from text: String, defaultCurrency: CurrencyCode) -> (Double, String?)? {
        // 1. Recognized structured bank alert always wins over secondary amounts (like cashback or balance).
        if let bankAlert = recognizedBankAlertAmount(text) {
            return (bankAlert.amount, bankAlert.currencyCode)
        }

        // 2. Vietnamese shorthand: e.g. "65k", "1.5tr", "2,5 triệu", "350 nghìn"
        if let match = firstMatch(#"(?i)(?<![\d.,])(\d+(?:[.,]\d+)?)\s*(tr(?:i[eệ]u)?|m|k|ngh[iì]n|ng[aà]n)\b"#, in: text) {
            let numStr = match[1].replacingOccurrences(of: ",", with: ".")
            let unit = match[2].lowercased()
            if let base = Double(numStr) {
                let multiplier: Double = (unit.hasPrefix("tr") || unit == "m") ? 1_000_000 : 1_000
                let value = base * multiplier
                if value > 0 { return (value, "VND") }
            }
        }

        // 3. Collect all explicit currency+amount matches (prefix & suffix), picking earliest non-secondary match.
        struct CurrencyMatch {
            let location: Int
            let amount: Double
            let currencyCode: String
            let isSecondary: Bool
        }

        let bareDollarDefault = defaultCurrency == .vnd ? "SGD" : defaultCurrency.rawValue
        let yenDefault = (defaultCurrency == .cny || defaultCurrency == .jpy) ? defaultCurrency.rawValue : "JPY"

        let prefixSpecs: [(pattern: String, code: String?)] = [
            (#"(?i)\b(?:SGD|S\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "SGD"),
            (#"(?i)\b(?:HKD|HK\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "HKD"),
            (#"(?i)\b(?:USD|US\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "USD"),
            (#"(?i)\b(?:TWD|NTD|NT\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "TWD"),
            (#"(?i)\b(?:NZD|NZ\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "NZD"),
            (#"(?i)\b(?:CAD|CA\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "CAD"),
            (#"(?i)\b(?:AUD|AU\$|A\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "AUD"),
            (#"(?i)\b(?:MYR|RM)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "MYR"),
            (#"(?i)\b(?:IDR|Rp)\s*([0-9][0-9.,]*)"#, "IDR"),
            (#"(?i)\b(?:VND|VNĐ)\s*([0-9][0-9.,]*)"#, "VND"),
            (#"(?i)(?:\bEUR\b|€)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "EUR"),
            (#"(?i)(?:\bGBP\b|£)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "GBP"),
            (#"(?i)\bJPY\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "JPY"),
            (#"(?i)\b(?:CNY|RMB)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "CNY"),
            (#"(?i)(?:\bKRW\b|₩)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "KRW"),
            (#"(?i)(?:\bTHB\b|฿)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "THB"),
            (#"(?i)(?:\bPHP\b|₱)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "PHP"),
            (#"(?i)(?:\bINR\b|₹)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "INR"),
            (#"(?i)\bCHF\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, "CHF"),
            (#"¥\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, yenDefault),
            (#"(?<![A-Za-z])\$\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, bareDollarDefault),
        ]

        var matches: [CurrencyMatch] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for (pattern, explicitCode) in prefixSpecs {
            guard let code = explicitCode, let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for hit in regex.matches(in: text, range: fullRange) {
                guard hit.numberOfRanges >= 2,
                      let r = Range(hit.range(at: 1), in: text),
                      let value = parseNumber(String(text[r]), isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)),
                      value > 0
                else { continue }
                matches.append(CurrencyMatch(
                    location: hit.range.location,
                    amount: value,
                    currencyCode: code,
                    isSecondary: isSecondaryAmountContext(in: text, range: hit.range)
                ))
            }
        }

        // Case-sensitive uppercase ISO 4217 prefix for any other currency (e.g. AED 120.50, SEK 350).
        if let isoPrefix = try? NSRegularExpression(pattern: #"(?-i)(?<![A-Za-z])([A-Z]{3})\s+([0-9][0-9,]*(?:\.\d{1,2})?)"#) {
            for hit in isoPrefix.matches(in: text, range: fullRange) {
                guard hit.numberOfRanges >= 3,
                      let cRange = Range(hit.range(at: 1), in: text),
                      let nRange = Range(hit.range(at: 2), in: text),
                      let code = CurrencyCode.normalizeCode(String(text[cRange])),
                      let value = parseNumber(String(text[nRange]), isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)),
                      value > 0
                else { continue }
                matches.append(CurrencyMatch(
                    location: hit.range.location,
                    amount: value,
                    currencyCode: code,
                    isSecondary: isSecondaryAmountContext(in: text, range: hit.range)
                ))
            }
        }

        let suffixSpecs: [(pattern: String, code: String)] = [
            (#"(?i)([0-9][0-9.,]*)\s*(?:VND|VNĐ|₫|đ|d\b)"#, "VND"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*SGD\b"#, "SGD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*HKD\b"#, "HKD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*USD\b"#, "USD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*MYR\b"#, "MYR"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*AUD\b"#, "AUD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*CAD\b"#, "CAD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*EUR\b"#, "EUR"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*GBP\b"#, "GBP"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*(?:CNY|RMB)\b"#, "CNY"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*JPY\b"#, "JPY"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*KRW\b"#, "KRW"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*THB\b"#, "THB"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*(?:TWD|NTD)\b"#, "TWD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*IDR\b"#, "IDR"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*PHP\b"#, "PHP"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*NZD\b"#, "NZD"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*CHF\b"#, "CHF"),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*INR\b"#, "INR"),
        ]
        for (pattern, code) in suffixSpecs {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for hit in regex.matches(in: text, range: fullRange) {
                guard hit.numberOfRanges >= 2,
                      let r = Range(hit.range(at: 1), in: text),
                      let value = parseNumber(String(text[r]), isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)),
                      value > 0
                else { continue }
                matches.append(CurrencyMatch(
                    location: hit.range.location,
                    amount: value,
                    currencyCode: code,
                    isSecondary: isSecondaryAmountContext(in: text, range: hit.range)
                ))
            }
        }

        if let isoSuffix = try? NSRegularExpression(pattern: #"(?-i)([0-9][0-9,]*(?:\.\d{1,2})?)\s+([A-Z]{3})\b"#) {
            for hit in isoSuffix.matches(in: text, range: fullRange) {
                guard hit.numberOfRanges >= 3,
                      let nRange = Range(hit.range(at: 1), in: text),
                      let cRange = Range(hit.range(at: 2), in: text),
                      let code = CurrencyCode.normalizeCode(String(text[cRange])),
                      let value = parseNumber(String(text[nRange]), isZeroDecimal: CurrencyCode.isZeroDecimal(code: code)),
                      value > 0
                else { continue }
                matches.append(CurrencyMatch(
                    location: hit.range.location,
                    amount: value,
                    currencyCode: code,
                    isSecondary: isSecondaryAmountContext(in: text, range: hit.range)
                ))
            }
        }

        if !matches.isEmpty {
            let ordered = matches.sorted { lhs, rhs in
                if lhs.isSecondary != rhs.isSecondary { return !lhs.isSecondary }
                return lhs.location < rhs.location
            }
            if let best = ordered.first {
                return (best.amount, best.currencyCode)
            }
        }

        // 4. Fallback: signed or standalone number (skipping account numbers / dates like 1903... or 2026-11-23)
        if let match = firstMatch(#"[+-−]\s*([0-9][0-9.,]{1,12})"#, in: text),
           let value = parseNumber(match[1], isZeroDecimal: defaultCurrency.isZeroDecimal), value > 0 {
            return (value, nil)
        }

        // Plain freeform text like "pho 65000" or "coffee 6.50"
        let tokens = text.split(whereSeparator: { $0.isWhitespace })
        for token in tokens.reversed() {
            let clean = String(token).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]"))
            if clean.contains("/") || clean.contains("-") || clean.contains(":") { continue }
            if let value = parseNumber(clean, isZeroDecimal: defaultCurrency.isZeroDecimal), value > 0, value < 1_000_000_000 {
                return (value, nil)
            }
        }

        return nil
    }

    private static func isSecondaryAmountContext(in text: String, range: NSRange) -> Bool {
        let ns = text as NSString
        let beforeStart = max(0, range.location - 24)
        let beforeLen = range.location - beforeStart
        let afterStart = range.location + range.length
        let afterLen = min(ns.length - afterStart, 20)
        let before = ns.substring(with: NSRange(location: beforeStart, length: beforeLen))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let after = ns.substring(with: NSRange(location: afterStart, length: afterLen))
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let secondarySignals = ["cashback", "rebate", "reward", "balance", "available", "so du", "avail bal"]
        if secondarySignals.contains(where: { before.contains($0) || after.contains($0) }) {
            return true
        }
        return before.hasSuffix("sd ")
    }

    private static func parseNumber(_ raw: String, isZeroDecimal: Bool) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isZeroDecimal {
            // Preserve ".0" / ".00" fractional endings (e.g. "JPY 2,400.00") while still treating
            // Vietnamese thousand-grouped integers ("125.000", "1.250.000") as whole numbers.
            let dotCount = trimmed.filter { $0 == "." }.count
            if dotCount == 1, let dotIdx = trimmed.firstIndex(of: ".") {
                let fracCount = trimmed.distance(from: trimmed.index(after: dotIdx), to: trimmed.endIndex)
                if fracCount >= 1 && fracCount <= 2 {
                    return Double(trimmed.replacingOccurrences(of: ",", with: ""))
                }
            }
            let stripped = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
            return Double(stripped)
        }
        // Standard decimal currencies: remove commas as thousand separators.
        if trimmed.contains(",") && trimmed.contains(".") {
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        }
        if trimmed.contains(",") {
            let parts = trimmed.split(separator: ",")
            if parts.count == 2 && parts[1].count <= 2 {
                return Double(trimmed.replacingOccurrences(of: ",", with: "."))
            }
            return Double(trimmed.replacingOccurrences(of: ",", with: ""))
        }
        return Double(trimmed)
    }

    private static func extractMerchant(from text: String, fallbackType: TransactionType) -> String {
        // Common bank SMS/email phrases: "at MERCHANT", "to MERCHANT", "tai MERCHANT", "tại MERCHANT", "ND: ..."
        let merchantPatterns = [
            #"(?i)(?<![A-Za-zÀ-ỹ])(?:tại|tai|at|to|merchant[:\s]+)\s+([A-Za-zÀ-ỹ0-9 &'\-./]{2,45}?)(?:\s+(?:on|vào|vao|luc|lúc|ngày|ngay|with|bằng|bang|so du|số dư|sd|ref|ma gd|mã gd)\b|[.,;\n]|$)"#,
            #"(?i)(?:nội dung|noi dung|nd|content|desc(?:ription)?)[:\s]+([^\n.;]{2,50})"#,
        ]
        for pattern in merchantPatterns {
            if let match = firstMatch(pattern, in: text) {
                let cleaned = cleanMerchantName(match[1])
                if cleaned.count >= 2 { return cleaned }
            }
        }

        // For short natural text ("ăn phở 65k", "coffee 6.50"), strip the numeric/currency part.
        var stripped = text
        stripped = stripped.replacingOccurrences(
            of: #"(?i)[+-−]?\s*(?:SGD|S\$|HKD|HK\$|VND|VNĐ|USD|US\$|MYR|RM|AUD|AU\$|A\$|CAD|CA\$|NZD|NZ\$|EUR|GBP|JPY|CNY|RMB|KRW|THB|TWD|NTD|IDR|Rp|PHP|CHF|INR|[\$€£¥₩฿₱₹])?\s*\d[\d.,]*\s*(?:tr(?:i[eệ]u)?|k|ngh[iì]n|ng[aà]n|VND|VNĐ|SGD|HKD|USD|MYR|AUD|CAD|EUR|GBP|JPY|CNY|RMB|KRW|THB|TWD|NTD|IDR|PHP|NZD|CHF|INR|đ|d\b)?"#,
            with: " ",
            options: .regularExpression
        )
        stripped = stripped.replacingOccurrences(of: #"(?-i)\b[A-Z]{3}\b(?=\s*$|\s+\d)"#, with: " ", options: .regularExpression)
        stripped = cleanMerchantName(stripped)
        if !stripped.isEmpty {
            return String(stripped.prefix(60))
        }
        return fallbackType == .income ? "Income" : "Expense"
    }

    private static func cleanMerchantName(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-:.,;")))
        guard !collapsed.isEmpty else { return "" }
        // Title-case ALL CAPS bank merchant strings like "HIGHLANDS COFFEE" -> "Highlands Coffee"
        if collapsed == collapsed.uppercased() && collapsed.count > 3 {
            return collapsed.localizedCapitalized
        }
        return collapsed.prefix(1).uppercased() + collapsed.dropFirst()
    }

    private static let monthLookup: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static func extractDate(from text: String) -> String? {
        // ISO YYYY-MM-DD
        if let m = firstMatch(#"\b(20\d{2})-(\d{2})-(\d{2})\b"#, in: text) {
            let key = "\(m[1])-\(m[2])-\(m[3])"
            if DateKey.date(fromDayKey: key) != nil { return key }
        }
        // DD/MM/YYYY or DD-MM-YYYY
        if let m = firstMatch(#"\b(\d{1,2})[/-](\d{1,2})[/-](20\d{2})\b"#, in: text),
           let d = Int(m[1]), let mo = Int(m[2]), let y = Int(m[3]) {
            let key = String(format: "%04d-%02d-%02d", y, mo, d)
            if DateKey.date(fromDayKey: key) != nil { return key }
        }
        // DD MMM YYYY (e.g. "25 Nov 2026")
        if let m = firstMatch(#"\b(\d{1,2})\s+([A-Za-z]{3,9})\s+(20\d{2})\b"#, in: text),
           let d = Int(m[1]), let mo = monthLookup[m[2].lowercased()], let y = Int(m[3]) {
            let key = String(format: "%04d-%02d-%02d", y, mo, d)
            if DateKey.date(fromDayKey: key) != nil { return key }
        }
        // MMM DD, YYYY (e.g. "Nov 25, 2026")
        if let m = firstMatch(#"\b([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(20\d{2})\b"#, in: text),
           let mo = monthLookup[m[1].lowercased()], let d = Int(m[2]), let y = Int(m[3]) {
            let key = String(format: "%04d-%02d-%02d", y, mo, d)
            if DateKey.date(fromDayKey: key) != nil { return key }
        }
        return nil
    }

    private static func normalizeApostrophes(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { idx in
            let r = match.range(at: idx)
            guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }
}
