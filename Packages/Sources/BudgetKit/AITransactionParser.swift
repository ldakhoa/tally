import ClaudeKit
import Foundation
import TallyCore

/// Uses Claude's structured JSON output to parse Vietnamese & English bank notifications,
/// emails, Apple Pay alerts, or natural text into clean transactions.
/// Explicitly rejects promotional/marketing emails, OTPs, newsletters, and ads via `isTransaction`.
public enum AITransactionParser {
    private struct WireResult: Decodable {
        let isTransaction: Bool
        let name: String
        let amount: Double
        let currency: String?
        let type: String
        let category: String
        let date: String
        let note: String
        let confidence: Double
    }

    public static let responseSchema: JSONValue = .schemaObject([
        ("isTransaction", .schemaBool("TRUE only if this text confirms an ACTUAL completed financial transaction (card charge, bank debit/credit, PayNow transfer, ride/food e-receipt, salary, refund). FALSE for marketing/promotional emails, discounts, vouchers, 'up to X off', newsletters, OTPs, login alerts, credit card statements, or ads.")),
        ("name", .schemaString("Short, clean merchant or transaction name (2-50 chars). Empty string if isTransaction is false.")),
        ("amount", .schemaNumber("Positive numeric amount in the transaction's ORIGINAL currency major units (e.g. 50000 for 50,000đ VND, 18.5 for SGD 18.50). 0 if isTransaction is false.")),
        ("currency", .schemaEnum(CurrencyCode.allCases.map(\.rawValue), "Original currency code in the message (e.g. VND for đ/VND, SGD for S$/SGD). Use default currency only if none is stated.")),
        ("type", .schemaEnum(["expense", "income"], "Whether this is an expense or income.")),
        ("category", .schemaEnum(CategoryID.allCases.map(\.rawValue), "Best matching category ID.")),
        ("date", .schemaString("Transaction date in YYYY-MM-DD format; use today's date if not mentioned.")),
        ("note", .schemaString("Optional concise note (card/bank/details), or empty string.")),
        ("confidence", .schemaNumber("Confidence from 0.0 to 1.0 that this is a real completed transaction.")),
    ])

    public static func parse(
        text: String,
        source: TransactionSource,
        defaultCurrency: CurrencyCode,
        language: AppLanguage,
        client: (any AIClient)?,
        now: Date = Date()
    ) async -> ParsedTransactionDraft? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Fast reject obvious promotional emails before spending API tokens.
        if source == .bankEmail && LocalTransactionParser.isLikelyPromotional(trimmed) {
            return nil
        }

        if let client {
            let todayKey = DateKey.dayKey(from: now)
            let system = """
            You extract a single COMPLETED personal budget transaction from bank alerts, bank emails, e-receipts, Apple Pay alerts, or quick notes in English, Vietnamese, or Chinese.
            CRITICAL FILTERING RULES:
            - Set isTransaction = false (and amount = 0) for ANY promotional/marketing email, voucher/discount offer ("up to 50,000đ", "save $20", "win $1,000", "ưu đãi", "khuyến mãi", "giảm giá", "优惠", "折扣", "促销"), newsletter, OTP/verification code, login alert, card statement summary, or advertisement.
            - Set isTransaction = true ONLY for an actual completed payment, transfer, receipt, debit, credit, salary, or refund.
            - Always report the EXACT original currency stated in the text (e.g. "50,000đ" or "VND" -> currency "VND"; "S$" or "SGD" -> currency "SGD"). Only use default currency \(defaultCurrency.rawValue) if no currency is shown.
            - Today's date is \(todayKey). Use it when no transaction date is present.
            - Vietnamese shorthand: 65k = 65000 VND, 1.5tr = 1500000 VND. Chinese shorthand: 1万 = 10000, 3千 = 3000.
            - Expense categories: \(CategoryID.expenseCategories.map(\.rawValue).joined(separator: ", ")).
            - Income categories: \(CategoryID.incomeCategories.map(\.rawValue).joined(separator: ", ")).
            - Make sure category matches type (expense vs income).
            - \(language.aiInstruction)
            """
            let request = ClaudeRequest(
                system: system,
                messages: [.user("Source: \(source.rawValue)\nText:\n\(trimmed)")],
                maxTokens: 1_024,
                effort: .low,
                jsonSchema: responseSchema
            )
            if let wire = try? await client.completeJSON(WireResult.self, request) {
                // If Claude explicitly determined this is NOT a real transaction, DO NOT fall back to regex!
                guard wire.isTransaction, wire.amount > 0 else { return nil }
                if source == .bankEmail && wire.confidence < 0.55 { return nil }

                let type = TransactionType(rawValue: wire.type) ?? .expense
                var category = CategoryID(rawValue: wire.category) ?? (type == .income ? .income : .other)
                if category.transactionType != type {
                    category = type == .income ? .income : .other
                }
                let dayKey = DateKey.date(fromDayKey: wire.date) != nil ? wire.date : todayKey
                let currency = wire.currency.flatMap(CurrencyCode.init(rawValue:)) ?? defaultCurrency
                return ParsedTransactionDraft(
                    name: wire.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transaction" : wire.name,
                    amountMajor: wire.amount,
                    currency: currency,
                    type: type,
                    category: category,
                    dayKey: dayKey,
                    note: wire.note,
                    confidence: min(1, max(0, wire.confidence)),
                    parsedByAI: true
                )
            }
        }

        if source == .bankEmail && LocalTransactionParser.isLikelyPromotional(trimmed) {
            return nil
        }
        return LocalTransactionParser.parse(trimmed, defaultCurrency: defaultCurrency, now: now)
    }

    /// Resolves a parsed draft's amount into the user's budget currency, automatically converting
    /// foreign currencies (e.g., VND -> SGD) and noting the original foreign amount.
    public static func resolvedAmountAndNote(
        for draft: ParsedTransactionDraft,
        targetCurrency: CurrencyCode,
        language: AppLanguage,
        fallbackNote: String = ""
    ) -> (amountMinor: Int64, note: String) {
        let baseNote = draft.note.isEmpty ? fallbackNote : draft.note
        let sourceCurrency = draft.currency ?? targetCurrency
        guard sourceCurrency != targetCurrency else {
            return (targetCurrency.toStorageMinor(draft.amountMajor), baseNote)
        }
        let convertedMajor = CurrencyConverter.convert(draft.amountMajor, from: sourceCurrency, to: targetCurrency)
        let origFormatted = MoneyFormat.format(
            minor: sourceCurrency.toStorageMinor(draft.amountMajor),
            currency: sourceCurrency,
            language: language
        )
        let fxTag = L10n.text(language, en: "Orig: \(origFormatted)", vi: "Gốc: \(origFormatted)", zh: "原币: \(origFormatted)")
        let combinedNote = baseNote.isEmpty ? fxTag : "\(baseNote) · \(fxTag)"
        return (targetCurrency.toStorageMinor(convertedMajor), combinedNote)
    }
}
