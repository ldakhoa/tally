import AppIntents
import AppServices
import BudgetKit
import Foundation
import TallyCore

// MARK: - App Enum Wrappers for Apple Shortcuts

enum CaptureSourceAppEnum: String, AppEnum {
    case applePay
    case bankEmail
    case bankNotification
    case shortcut

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Source"
    static var caseDisplayRepresentations: [CaptureSourceAppEnum: DisplayRepresentation] = [
        .applePay: "Apple Pay",
        .bankEmail: "Bank Email",
        .bankNotification: "Bank Notification / SMS",
        .shortcut: "Shortcut",
    ]

    var domainSource: TransactionSource {
        switch self {
        case .applePay: return .applePay
        case .bankEmail: return .bankEmail
        case .bankNotification: return .bankNotification
        case .shortcut: return .shortcut
        }
    }
}

enum CategoryAppEnum: String, AppEnum {
    case food, housing, transport, shopping, bills, health, entertainment, other, salary, freelance, income

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var caseDisplayRepresentations: [CategoryAppEnum: DisplayRepresentation] = [
        .food: "Food & drink",
        .housing: "Housing",
        .transport: "Transport",
        .shopping: "Shopping",
        .bills: "Bills & utilities",
        .health: "Health",
        .entertainment: "Entertainment",
        .other: "Other",
        .salary: "Salary",
        .freelance: "Freelance",
        .income: "Other income",
    ]

    var domainCategory: CategoryID {
        CategoryID(rawValue: rawValue) ?? .other
    }
}

// MARK: - 0A. Natural-Language Siri & Cross-App Assistant Intent

/// Speak or type naturally to Siri in Vietnamese, English, or Chinese:
/// e.g. "Hôm nay tôi mới PayNow cho bạn $5 tiền ăn trưa", "Đặt ngân sách ăn uống 800",
/// or "Tạo mục tiêu tiết kiệm đi Nhật 5000".
/// Powered by Apple Foundation Models (on-device) or Claude according to Settings, with offline fallback.
struct TellTallyIntent: AppIntent {
    static var title: LocalizedStringResource = "Tell Tally"
    static var description = IntentDescription(
        "Speak or type naturally in Vietnamese, English, or Chinese to log expenses, set budgets, create savings goals, or ask about spending."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Message",
        description: "What you spent, earned, or want to update in Tally.",
        requestValueDialog: IntentDialog("What would you like to tell Tally?")
    )
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Tell Tally \(\.$message)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let store = BudgetStore.current ?? BudgetStore()
        store.reload()
        let outcome = await AssistantService.runOneShot(
            message: message,
            settings: settings,
            store: store
        )
        return .result(dialog: IntentDialog(stringLiteral: outcome.reply))
    }
}

// MARK: - 0B. Unified 1-Action Auto-Log Intent (Zero Multi-Field Wiring!)

/// The simplest possible Shortcuts action: takes a single text input (auto-connected to
/// Shortcut Input or the previous action's result) — works for Apple Pay, DBS/OCBC/UOB/Trust
/// bank emails, PayNow alerts, bank SMS, or OCR'd payment screenshots.
struct AutoLogTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Auto-Log to Tally"
    static var description = IntentDescription(
        "One-step action for bank emails, SMS, PayNow alerts, or OCR'd screenshots — Tally extracts and logs the transaction."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Transaction Text",
        description: "Automatically receives Shortcut Input (Email, SMS, Apple Pay text, or extracted screenshot text).",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Auto-Log \(\.$input) to Tally")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let lower = input.lowercased()
        let detectedSource: TransactionSource
        if lower.contains("apple pay") || lower.contains("wallet") {
            detectedSource = .applePay
        } else if lower.contains("subject:") || lower.contains("@") || input.count > 180 {
            detectedSource = .bankEmail
        } else {
            detectedSource = .bankNotification
        }

        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil
        guard let parsed = await AITransactionParser.parse(
            text: input,
            source: detectedSource,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        ) else {
            let err = L10n.text(
                settings.language,
                en: "Could not find a transaction amount in that text.",
                vi: "Không tìm thấy số tiền giao dịch trong nội dung gửi vào.",
                zh: "未在文本中找到交易金额。"
            )
            return .result(dialog: IntentDialog(stringLiteral: err))
        }

        if let parsedCode = parsed.currencyCode, parsedCode != settings.currency.rawValue {
            await ExchangeRateService.shared.refreshIfStale()
        }
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: parsed,
            targetCurrency: settings.currency,
            language: settings.language
        )
        let saved = BudgetStore.ingestFromShortcut(
            name: parsed.name,
            amountMajor: settings.currency.toMajor(max(1, resolved.amountMinor)),
            type: parsed.type,
            category: parsed.category,
            dayKey: parsed.dayKey,
            note: resolved.note,
            source: detectedSource,
            rawSourceText: input,
            originalAmountMinor: resolved.originalAmountMinor,
            originalCurrencyCode: resolved.originalCurrencyCode,
            exchangeRate: resolved.exchangeRate,
            needsReviewOverride: resolved.usedFallbackUnavailableRate ? true : nil
        )
        let formatted = MoneyFormat.masked(
            MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language),
            hidden: saved.isSalaryMasked(hidden: settings.hideSalary)
        )
        let origSuffix: String = {
            guard !saved.isSalaryMasked(hidden: settings.hideSalary),
                  let orig = saved.formattedOriginalAmount(language: settings.language)
            else { return "" }
            return " (\(orig))"
        }()
        let msg = L10n.text(
            settings.language,
            en: "Logged \(saved.name): \(formatted)\(origSuffix) (\(saved.category.title(in: settings.language))).",
            vi: "Đã lưu \(saved.name): \(formatted)\(origSuffix) (\(saved.category.title(in: settings.language))).",
            zh: "已记录 \(saved.name)：\(formatted)\(origSuffix)（\(saved.category.title(in: settings.language))）。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - 1. Apple Pay Wallet Automation Intent

/// Wire directly into Apple Shortcuts → Automation → Transaction (Apple Wallet):
/// Accepts Wallet's formatted `Amount` string (e.g. `S$18.50`, `$10.00`, `HK$83.75`),
/// `Merchant`, and `Card or Pass Name` automatically on every Apple Pay tap!
struct LogApplePayTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Apple Pay Transaction"
    static var description = IntentDescription(
        "Automatically logs an Apple Pay purchase into Tally. Accepts formatted Wallet Amount text directly and detects currency & category."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        description: "Connect Shortcut Input → Amount. Accepts formatted Wallet text like S$18.50, $10.00, HK$83.75, 125.000 ₫, or a plain number."
    )
    var amount: String

    @Parameter(
        title: "Merchant",
        description: "Connect Shortcut Input → Merchant."
    )
    var merchant: String?

    @Parameter(
        title: "Card or Pass Name",
        description: "Optional — connect Shortcut Input → Card or Pass."
    )
    var cardName: String?

    @Parameter(
        title: "Currency",
        description: "Optional — leave blank to auto-detect from Amount."
    )
    var currency: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log Apple Pay \(\.$amount) at \(\.$merchant)") {
            \.$cardName
            \.$currency
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        guard let parsed = ApplePayInputParser.parse(
            amountText: amount,
            merchant: merchant,
            cardName: cardName,
            explicitCurrency: currency,
            defaultCurrency: settings.currency
        ) else {
            let err = L10n.text(
                settings.language,
                en: "Could not read a valid amount from Apple Pay input.",
                vi: "Không đọc được số tiền hợp lệ từ giao dịch Apple Pay.",
                zh: "无法从 Apple Pay 输入中读取有效金额。"
            )
            return .result(dialog: IntentDialog(stringLiteral: err))
        }

        var category = LocalTransactionParser.inferCategory(
            text: "\(parsed.merchantName) \(parsed.cardName ?? "")",
            type: .expense
        )
        var finalName = parsed.merchantName

        if settings.autoParseWithAI, let client = settings.makeAIClient(),
           let aiDraft = await AITransactionParser.parse(
            text: parsed.rawSummary,
            source: .applePay,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
           ) {
            category = aiDraft.category
            finalName = aiDraft.name
        }

        if parsed.currencyCode != settings.currency.rawValue {
            await ExchangeRateService.shared.refreshIfStale()
        }
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: ParsedTransactionDraft(
                name: finalName,
                amountMajor: parsed.amountMajor,
                currencyCode: parsed.currencyCode,
                type: .expense,
                category: category,
                note: parsed.note
            ),
            targetCurrency: settings.currency,
            language: settings.language
        )

        let saved = BudgetStore.ingestFromShortcut(
            name: finalName,
            amountMajor: settings.currency.toMajor(max(1, resolved.amountMinor)),
            type: .expense,
            category: category,
            note: resolved.note,
            source: .applePay,
            rawSourceText: parsed.rawSummary,
            originalAmountMinor: resolved.originalAmountMinor,
            originalCurrencyCode: resolved.originalCurrencyCode,
            exchangeRate: resolved.exchangeRate,
            needsReviewOverride: resolved.usedFallbackUnavailableRate ? true : nil
        )

        let formatted = MoneyFormat.masked(
            MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language),
            hidden: saved.isSalaryMasked(hidden: settings.hideSalary)
        )
        let origSuffix: String = {
            guard !saved.isSalaryMasked(hidden: settings.hideSalary),
                  let orig = saved.formattedOriginalAmount(language: settings.language)
            else { return "" }
            return " (\(orig))"
        }()
        let msg = L10n.text(
            settings.language,
            en: "Logged \(formatted)\(origSuffix) at \(saved.name) (\(saved.category.title(in: settings.language))).",
            vi: "Đã ghi \(formatted)\(origSuffix) tại \(saved.name) (\(saved.category.title(in: settings.language))).",
            zh: "已在 \(saved.name) 记录 \(formatted)\(origSuffix)（\(saved.category.title(in: settings.language))）。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - 2. Bank Email / SMS / Notification Parser Intent

/// Wire into Apple Shortcuts → Automation → Email or Message:
/// Pass the bank email content or SMS body, and Tally extracts amount, merchant, type, and category
/// using Claude AI (when configured) or the built-in Vietnamese/English bank alert parser.
struct LogTransactionFromTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Expense from Text"
    static var description = IntentDescription(
        "Parses a bank email, SMS, or notification in Vietnamese or English and logs it to Tally."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Bank Alert or Text")
    var text: String

    @Parameter(title: "Source", default: .bankNotification)
    var source: CaptureSourceAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let client = settings.autoParseWithAI ? settings.makeAIClient() : nil

        guard let parsed = await AITransactionParser.parse(
            text: text,
            source: source.domainSource,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
        ) else {
            let err = L10n.text(
                settings.language,
                en: "Could not find a transaction amount in the provided text.",
                vi: "Không tìm thấy số tiền giao dịch trong nội dung gửi vào.",
                zh: "未在提供的文本中找到交易金额。"
            )
            return .result(dialog: IntentDialog(stringLiteral: err))
        }

        if let parsedCode = parsed.currencyCode, parsedCode != settings.currency.rawValue {
            await ExchangeRateService.shared.refreshIfStale()
        }
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: parsed,
            targetCurrency: settings.currency,
            language: settings.language
        )
        let saved = BudgetStore.ingestFromShortcut(
            name: parsed.name,
            amountMajor: settings.currency.toMajor(max(1, resolved.amountMinor)),
            type: parsed.type,
            category: parsed.category,
            dayKey: parsed.dayKey,
            note: resolved.note,
            source: source.domainSource,
            rawSourceText: text,
            originalAmountMinor: resolved.originalAmountMinor,
            originalCurrencyCode: resolved.originalCurrencyCode,
            exchangeRate: resolved.exchangeRate,
            needsReviewOverride: resolved.usedFallbackUnavailableRate ? true : nil
        )

        let formatted = MoneyFormat.masked(
            MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language),
            hidden: saved.isSalaryMasked(hidden: settings.hideSalary)
        )
        let origSuffix: String = {
            guard !saved.isSalaryMasked(hidden: settings.hideSalary),
                  let orig = saved.formattedOriginalAmount(language: settings.language)
            else { return "" }
            return " (\(orig))"
        }()
        let msg = L10n.text(
            settings.language,
            en: "Saved \(saved.name): \(formatted)\(origSuffix) in \(saved.category.title(in: settings.language)).",
            vi: "Đã lưu \(saved.name): \(formatted)\(origSuffix) (\(saved.category.title(in: settings.language))).",
            zh: "已保存 \(saved.name)：\(formatted)\(origSuffix)（\(saved.category.title(in: settings.language))）。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - 3. Quick Structured Log Intent (Siri / Action Button)

struct QuickLogExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Log Expense"
    static var description = IntentDescription("Quickly logs a manual expense or income into Tally.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Name")
    var name: String

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category", default: .food)
    var category: CategoryAppEnum

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Currency")
    var currency: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let domainCat = category.domainCategory
        let statedCode = currency.flatMap(CurrencyCode.normalizeCode) ?? settings.currency.rawValue
        if statedCode != settings.currency.rawValue {
            await ExchangeRateService.shared.refreshIfStale()
        }
        let resolved = AITransactionParser.resolvedAmountAndNote(
            for: ParsedTransactionDraft(
                name: name,
                amountMajor: abs(amount),
                currencyCode: statedCode,
                type: domainCat.transactionType,
                category: domainCat,
                note: note ?? ""
            ),
            targetCurrency: settings.currency,
            language: settings.language
        )
        let saved = BudgetStore.ingestFromShortcut(
            name: name,
            amountMajor: settings.currency.toMajor(max(1, resolved.amountMinor)),
            type: domainCat.transactionType,
            category: domainCat,
            note: resolved.note,
            source: .shortcut,
            originalAmountMinor: resolved.originalAmountMinor,
            originalCurrencyCode: resolved.originalCurrencyCode,
            exchangeRate: resolved.exchangeRate,
            needsReviewOverride: resolved.usedFallbackUnavailableRate ? true : nil
        )
        let formatted = MoneyFormat.masked(
            MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language),
            hidden: saved.isSalaryMasked(hidden: settings.hideSalary)
        )
        let origSuffix: String = {
            guard !saved.isSalaryMasked(hidden: settings.hideSalary),
                  let orig = saved.formattedOriginalAmount(language: settings.language)
            else { return "" }
            return " (\(orig))"
        }()
        let msg = L10n.text(
            settings.language,
            en: "Logged \(formatted)\(origSuffix) for \(saved.name).",
            vi: "Đã ghi \(formatted)\(origSuffix) cho \(saved.name).",
            zh: "已为 \(saved.name) 记录 \(formatted)\(origSuffix)。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - 4. Spending Summary Intent (Siri / Daily Check-in)

struct GetSpendingSummaryIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Spending Summary"
    static var description = IntentDescription("Returns today's and this month's household spending from Tally.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let store = BudgetStore.current ?? BudgetStore()
        store.reload()
        let snapshot = store.snapshot
        let todayStr = settings.formatMoney(minor: snapshot.todaySpendingMinor)
        let monthStr = settings.formatMoney(minor: snapshot.spendingMinor)
        let msg = L10n.text(
            settings.language,
            en: "Today's spending is \(todayStr). This month's total spending is \(monthStr).",
            vi: "Hôm nay đã chi \(todayStr). Tổng chi tiêu tháng này là \(monthStr).",
            zh: "今日支出 \(todayStr)，本月累计支出 \(monthStr)。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - App Shortcuts Provider

struct TallyShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TellTallyIntent(),
            phrases: [
                "Tell \(.applicationName)",
                "Ask \(.applicationName)",
                "Log with \(.applicationName)",
                "Record in \(.applicationName)",
            ],
            shortTitle: "Tell Tally",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: AutoLogTransactionIntent(),
            phrases: [
                "Auto-log to \(.applicationName)",
                "Log bank alert in \(.applicationName)",
            ],
            shortTitle: "Auto-Log to Tally",
            systemImageName: "bolt.horizontal.fill"
        )
        AppShortcut(
            intent: QuickLogExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add spending to \(.applicationName)",
            ],
            shortTitle: "Quick Log Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: GetSpendingSummaryIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "Check my budget in \(.applicationName)",
            ],
            shortTitle: "Spending Summary",
            systemImageName: "chart.pie.fill"
        )
    }
}
