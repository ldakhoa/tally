import ClaudeKit
import Foundation
import TallyCore

/// Uses Claude's structured JSON output to parse Vietnamese & English bank notifications,
/// emails, Apple Pay alerts, or natural text into clean transactions.
/// Explicitly rejects promotional/marketing emails, OTPs, newsletters, and ads via `isTransaction`.
public enum AITransactionParser {
    public struct ResolvedTransactionAmount: Equatable, Sendable {
        public let amountMinor: Int64
        public let note: String
        public let originalAmountMinor: Int64?
        public let originalCurrencyCode: String?
        public let exchangeRate: Double?
        public let isLiveRate: Bool
        public let rateDate: String?
        public let usedFallbackUnavailableRate: Bool

        public init(
            amountMinor: Int64,
            note: String,
            originalAmountMinor: Int64? = nil,
            originalCurrencyCode: String? = nil,
            exchangeRate: Double? = nil,
            isLiveRate: Bool = false,
            rateDate: String? = nil,
            usedFallbackUnavailableRate: Bool = false
        ) {
            self.amountMinor = amountMinor
            self.note = note
            self.originalAmountMinor = originalAmountMinor
            self.originalCurrencyCode = originalCurrencyCode
            self.exchangeRate = exchangeRate
            self.isLiveRate = isLiveRate
            self.rateDate = rateDate
            self.usedFallbackUnavailableRate = usedFallbackUnavailableRate
        }
    }

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
        ("amount", .schemaNumber("Positive numeric amount in the transaction's ORIGINAL currency major units (e.g. 83.75 for HKD 83.75, 50000 for 50,000đ VND, 18.5 for SGD 18.50). Ignore secondary estimated cashback/reward amounts. 0 if isTransaction is false.")),
        ("currency", .schemaString("3-letter uppercase ISO 4217 currency code of the transaction's ORIGINAL amount (e.g. SGD, HKD, JPY, CNY, VND, USD, MYR, THB, EUR, GBP, AED). Use default currency only if no currency is shown.")),
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
            - Loan, cash-advance, balance-transfer, credit-limit and card-upgrade OFFERS (e.g. "CashOne", "get cash at 1.9% p.a.", "pre-approved", "apply by ...") are promotional: isTransaction = false, even when they quote amounts or rates.
            - Never invent a placeholder amount. If no money actually moved, isTransaction = false and amount = 0.
            - Set isTransaction = true ONLY for an actual completed payment, transfer, receipt, debit, credit, salary, or refund.
            - Always report the EXACT original amount and 3-letter ISO 4217 currency code stated in the text without converting (e.g. "HKD 83.75" -> amount 83.75, currency "HKD"; "50,000đ" -> currency "VND"; "S$" -> currency "SGD"). Only use default currency \(defaultCurrency.rawValue) if no currency is shown.
            - When a card purchase alert also mentions a small secondary estimated cashback, reward, or points figure (e.g. "You'll receive estimated S$0.07 cashback*"), extract ONLY the main purchase amount and currency, not the cashback.
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
                // A model can contradict itself: `isTransaction = true` on a result it names
                // "… Promo (not a transaction)". Its own wording wins over the flag.
                if LocalTransactionParser.describesNonTransaction(
                    name: wire.name,
                    note: wire.note,
                    strict: source == .bankEmail
                ) {
                    return nil
                }

                let type = TransactionType(rawValue: wire.type) ?? .expense
                var category = CategoryID(rawValue: wire.category) ?? (type == .income ? .income : .other)
                if category.transactionType != type {
                    category = type == .income ? .income : .other
                }
                let dayKey = DateKey.date(fromDayKey: wire.date) != nil ? wire.date : todayKey
                let currencyCode = wire.currency.flatMap(CurrencyCode.normalizeCode) ?? defaultCurrency.rawValue
                return ParsedTransactionDraft(
                    name: wire.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transaction" : wire.name,
                    amountMajor: wire.amount,
                    currencyCode: currencyCode,
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
    /// foreign currencies (e.g., HKD -> SGD, VND -> SGD) and recording original amount & FX rate.
    public static func resolvedAmountAndNote(
        for draft: ParsedTransactionDraft,
        targetCurrency: CurrencyCode,
        language: AppLanguage,
        fallbackNote: String = "",
        rates: ExchangeRateTable = .current
    ) -> ResolvedTransactionAmount {
        let baseNote = draft.note.isEmpty ? fallbackNote : draft.note
        let sourceCode = draft.currencyCode.flatMap(CurrencyCode.normalizeCode) ?? targetCurrency.rawValue
        guard sourceCode != targetCurrency.rawValue else {
            return ResolvedTransactionAmount(
                amountMinor: targetCurrency.toStorageMinor(draft.amountMajor),
                note: baseNote
            )
        }

        let originalMinor = CurrencyCode.toStorageMinor(draft.amountMajor, currencyCode: sourceCode)
        let origFormatted = MoneyFormat.format(
            minor: originalMinor,
            currencyCode: sourceCode,
            language: language
        )

        if let conversion = rates.convert(draft.amountMajor, from: sourceCode, to: targetCurrency) {
            let fxTag = L10n.text(language, en: "Orig: \(origFormatted)", vi: "Gốc: \(origFormatted)", zh: "原币: \(origFormatted)")
            let combinedNote: String
            if baseNote.isEmpty {
                combinedNote = fxTag
            } else if baseNote.contains(origFormatted) {
                combinedNote = baseNote
            } else {
                combinedNote = "\(baseNote) · \(fxTag)"
            }
            return ResolvedTransactionAmount(
                amountMinor: conversion.convertedMinor,
                note: combinedNote,
                originalAmountMinor: originalMinor,
                originalCurrencyCode: sourceCode,
                exchangeRate: conversion.rate,
                isLiveRate: conversion.isLiveRate,
                rateDate: conversion.rateDate,
                usedFallbackUnavailableRate: false
            )
        }

        let missingTag = L10n.text(
            language,
            en: "Orig: \(origFormatted) (check FX rate)",
            vi: "Gốc: \(origFormatted) (kiểm tra tỷ giá)",
            zh: "原币: \(origFormatted)（请核对汇率）"
        )
        let combinedNote = baseNote.isEmpty ? missingTag : "\(baseNote) · \(missingTag)"
        return ResolvedTransactionAmount(
            amountMinor: targetCurrency.toStorageMinor(draft.amountMajor),
            note: combinedNote,
            originalAmountMinor: originalMinor,
            originalCurrencyCode: sourceCode,
            exchangeRate: nil,
            isLiveRate: false,
            rateDate: nil,
            usedFallbackUnavailableRate: true
        )
    }
}
