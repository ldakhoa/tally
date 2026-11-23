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

// MARK: - 0. Unified 1-Action Auto-Log Intent (Zero Multi-Field Wiring!)

/// The simplest possible Shortcuts action: takes a single text input (auto-connected to
/// Shortcut Input or the previous action's result) — works for Apple Pay, DBS/OCBC/UOB/Trust
/// bank emails, PayNow alerts, bank SMS, or OCR'd payment screenshots.
struct AutoLogTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Auto-Log to Tally"
    static var description = IntentDescription(
        "One-step action: pass any Apple Pay alert, bank email, SMS, or note and Tally extracts and logs the transaction."
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
            rawSourceText: input
        )
        let formatted = MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language)
        let msg = L10n.text(
            settings.language,
            en: "Logged \(saved.name): \(formatted) (\(saved.category.title(in: settings.language))).",
            vi: "Đã lưu \(saved.name): \(formatted) (\(saved.category.title(in: settings.language))).",
            zh: "已记录 \(saved.name)：\(formatted)（\(saved.category.title(in: settings.language))）。"
        )
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: - 1. Apple Pay Wallet Automation Intent

/// Wire directly into Apple Shortcuts → Automation → Transaction (Apple Wallet):
/// Passes Amount, Merchant, and Card/Pass Name automatically on every Apple Pay tap!
struct LogApplePayTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Apple Pay Transaction"
    static var description = IntentDescription(
        "Automatically logs an Apple Pay purchase into Tally with smart category detection."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Merchant")
    var merchant: String

    @Parameter(title: "Card or Pass Name")
    var cardName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let cleanedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawLine = "Apple Pay \(amount) \(settings.currency.rawValue) at \(cleanedMerchant) \(cardName ?? "")"

        var category = LocalTransactionParser.inferCategory(text: cleanedMerchant, type: .expense)
        var finalName = cleanedMerchant.isEmpty ? "Apple Pay" : cleanedMerchant

        if settings.autoParseWithAI, let client = settings.makeAIClient(),
           let aiDraft = await AITransactionParser.parse(
            text: rawLine,
            source: .applePay,
            defaultCurrency: settings.currency,
            language: settings.language,
            client: client
           ) {
            category = aiDraft.category
            finalName = aiDraft.name
        }

        let saved = BudgetStore.ingestFromShortcut(
            name: finalName,
            amountMajor: abs(amount),
            type: .expense,
            category: category,
            note: cardName?.isEmpty == false ? "Apple Pay · \(cardName!)" : "Apple Pay",
            source: .applePay,
            rawSourceText: rawLine
        )

        let formatted = MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language)
        let msg = L10n.text(
            settings.language,
            en: "Logged \(formatted) at \(saved.name) (\(saved.category.title(in: settings.language))).",
            vi: "Đã ghi \(formatted) tại \(saved.name) (\(saved.category.title(in: settings.language))).",
            zh: "已在 \(saved.name) 记录 \(formatted)（\(saved.category.title(in: settings.language))）。"
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
            rawSourceText: text
        )

        let formatted = MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language)
        let msg = L10n.text(
            settings.language,
            en: "Saved \(saved.name): \(formatted) in \(saved.category.title(in: settings.language)).",
            vi: "Đã lưu \(saved.name): \(formatted) (\(saved.category.title(in: settings.language))).",
            zh: "已保存 \(saved.name)：\(formatted)（\(saved.category.title(in: settings.language))）。"
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

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let settings = AppSettings()
        let domainCat = category.domainCategory
        let saved = BudgetStore.ingestFromShortcut(
            name: name,
            amountMajor: abs(amount),
            type: domainCat.transactionType,
            category: domainCat,
            note: note ?? "",
            source: .shortcut
        )
        let formatted = MoneyFormat.format(minor: saved.amountMinor, currency: settings.currency, language: settings.language)
        let msg = L10n.text(
            settings.language,
            en: "Logged \(formatted) for \(saved.name).",
            vi: "Đã ghi \(formatted) cho \(saved.name).",
            zh: "已为 \(saved.name) 记录 \(formatted)。"
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
        let todayStr = MoneyFormat.format(minor: snapshot.todaySpendingMinor, currency: settings.currency, language: settings.language)
        let monthStr = MoneyFormat.format(minor: snapshot.spendingMinor, currency: settings.currency, language: settings.language)
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
