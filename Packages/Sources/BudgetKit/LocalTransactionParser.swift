import Foundation
import TallyCore

/// A parsed transaction candidate before it is saved.
public struct ParsedTransactionDraft: Codable, Hashable, Sendable {
    public var name: String
    public var amountMajor: Double
    public var currency: CurrencyCode?
    public var type: TransactionType
    public var category: CategoryID
    public var dayKey: String
    public var note: String
    public var confidence: Double
    public var parsedByAI: Bool

    public init(
        name: String,
        amountMajor: Double,
        currency: CurrencyCode? = nil,
        type: TransactionType = .expense,
        category: CategoryID = .other,
        dayKey: String = DateKey.dayKey(from: Date()),
        note: String = "",
        confidence: Double = 0.75,
        parsedByAI: Bool = false
    ) {
        self.name = name
        self.amountMajor = amountMajor
        self.currency = currency
        self.type = type
        self.category = category
        self.dayKey = dayKey
        self.note = note
        self.confidence = confidence
        self.parsedByAI = parsedByAI
    }
}

/// Deterministic offline parser for Vietnamese & English bank alerts, emails, Apple Pay notes,
/// and natural shorthand (e.g. "ăn phở 65k", "TK 1903xxx -125,000 VND tai HIGHLANDS COFFEE",
/// "You spent SGD 18.50 at FairPrice").
public enum LocalTransactionParser {
    /// Rejects obvious marketing/promotional emails, newsletters, OTPs, and ads.
    public static func isLikelyPromotional(_ rawText: String) -> Bool {
        let folded = rawText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let strongTransactionSignals = [
            "transaction alert", "card transaction", "made a payment", "has been debited",
            "has been credited", "was made on your", "you have transferred", "you have received",
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
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let detectedType = detectType(lowered: lowered, raw: trimmed)
        guard let (amount, detectedCurrency) = extractAmountAndCurrency(from: trimmed, defaultCurrency: defaultCurrency) else {
            return nil
        }

        let merchant = extractMerchant(from: trimmed, fallbackType: detectedType)
        let category = inferCategory(text: "\(merchant) \(trimmed)", type: detectedType)
        let dayKey = extractDate(from: trimmed) ?? DateKey.dayKey(from: now)

        return ParsedTransactionDraft(
            name: merchant,
            amountMajor: amount,
            currency: detectedCurrency,
            type: detectedType,
            category: category,
            dayKey: dayKey,
            note: trimmed.count > 80 ? String(trimmed.prefix(140)) : "",
            confidence: 0.72,
            parsedByAI: false
        )
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
            "shopee", "lazada", "tiki", "tiktok shop", "amazon", "uniqlo", "zara", "h&m", "decathlon",
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
        if raw.range(of: #"\+\s*(?:[A-Z]{3}\s*)?[S$₫€£]?\s*\d"#, options: .regularExpression) != nil {
            return .income
        }
        if raw.range(of: #"[-−]\s*(?:[A-Z]{3}\s*)?[S$₫€£]?\s*\d"#, options: .regularExpression) != nil {
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

    private static func extractAmountAndCurrency(from text: String, defaultCurrency: CurrencyCode) -> (Double, CurrencyCode?)? {
        // 1. Vietnamese shorthand: e.g. "65k", "1.5tr", "2,5 triệu", "350 nghìn"
        if let match = firstMatch(#"(?i)(?<![\d.,])(\d+(?:[.,]\d+)?)\s*(tr(?:i[eệ]u)?|m|k|ngh[iì]n|ng[aà]n)\b"#, in: text) {
            let numStr = match[1].replacingOccurrences(of: ",", with: ".")
            let unit = match[2].lowercased()
            if let base = Double(numStr) {
                let multiplier: Double = (unit.hasPrefix("tr") || unit == "m") ? 1_000_000 : 1_000
                let value = base * multiplier
                if value > 0 { return (value, .vnd) }
            }
        }

        // 2. Explicit currency prefix/suffix: "SGD 18.50", "S$18.50", "USD 12.40", "$12.40", "125,000 VND", "65.000đ"
        let prefixPatterns: [(String, CurrencyCode)] = [
            (#"(?i)\b(?:SGD|S\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .sgd),
            (#"(?i)\b(?:VND|VNĐ)\s*([0-9][0-9.,]*)"#, .vnd),
            (#"(?i)\b(?:USD|US\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .usd),
            (#"(?i)\b(?:MYR|RM)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .myr),
            (#"(?i)\b(?:AUD|A\$)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .aud),
            (#"(?i)\b(?:EUR|€)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .eur),
            (#"(?i)\b(?:GBP|£)\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, .gbp),
            (#"\$\s*([0-9][0-9,]*(?:\.\d{1,2})?)"#, defaultCurrency == .vnd ? .sgd : defaultCurrency),
        ]
        for (pattern, code) in prefixPatterns {
            if let match = firstMatch(pattern, in: text),
               let value = parseNumber(match[1], isZeroDecimal: code.isZeroDecimal), value > 0 {
                return (value, code)
            }
        }

        let suffixPatterns: [(String, CurrencyCode)] = [
            (#"(?i)([0-9][0-9.,]*)\s*(?:VND|VNĐ|đ|d\b)"#, .vnd),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*SGD\b"#, .sgd),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*USD\b"#, .usd),
            (#"(?i)([0-9][0-9,]*(?:\.\d{1,2})?)\s*MYR\b"#, .myr),
        ]
        for (pattern, code) in suffixPatterns {
            if let match = firstMatch(pattern, in: text),
               let value = parseNumber(match[1], isZeroDecimal: code.isZeroDecimal), value > 0 {
                return (value, code)
            }
        }

        // 3. Fallback: signed or standalone number (skipping account numbers / dates like 1903... or 2026-11-23)
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

    private static func parseNumber(_ raw: String, isZeroDecimal: Bool) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isZeroDecimal {
            // In VND, both "125,000" and "125.000" are thousand separators.
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
            #"(?i)(?:tại|tai|at|to|merchant[:\s]+)\s+([A-Za-zÀ-ỹ0-9 &'\-./]{2,45}?)(?:\s+(?:on|vào|vao|luc|lúc|ngày|ngay|with|bằng|bang|so du|số dư|sd|ref|ma gd|mã gd)\b|[.,;\n]|$)"#,
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
        stripped = stripped.replacingOccurrences(of: #"(?i)[+-−]?\s*(?:SGD|S\$|VND|VNĐ|USD|US\$|MYR|RM|\$|€|£)?\s*\d[\d.,]*\s*(?:tr(?:i[eệ]u)?|k|ngh[iì]n|ng[aà]n|VND|VNĐ|SGD|USD|đ|d\b)?"#, with: " ", options: .regularExpression)
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
        return nil
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
