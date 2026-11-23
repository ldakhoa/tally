import Foundation
import TallyCore

/// Builds the system prompt and live household budget summary for Ask Tally AI conversations.
public enum BudgetAssistantPrompt {
    public static func systemPrompt(
        snapshot: MonthlySnapshot,
        goals: [SavingsGoalRecord],
        currency: CurrencyCode,
        language: AppLanguage
    ) -> String {
        let monthTitle = DateKey.formatMonth(snapshot.monthKey, language: language)
        let income = MoneyFormat.format(minor: snapshot.incomeMinor, currency: currency, language: language)
        let spending = MoneyFormat.format(minor: snapshot.spendingMinor, currency: currency, language: language)
        let savings = MoneyFormat.format(minor: snapshot.netSavingsMinor, currency: currency, language: language)
        let today = MoneyFormat.format(minor: snapshot.todaySpendingMinor, currency: currency, language: language)

        let categoryLines = snapshot.categoryBreakdown.map { item in
            let amt = MoneyFormat.format(minor: item.spentMinor, currency: currency, language: language)
            let pct = Int((item.share * 100).rounded())
            return "- \(item.category.title(in: language)): \(amt) (\(pct)%)"
        }.joined(separator: "\n")

        let budgetLines = snapshot.budgets.map { b in
            let spent = snapshot.expensesByCategory[b.category] ?? 0
            let spentStr = MoneyFormat.format(minor: spent, currency: currency, language: language)
            let limitStr = MoneyFormat.format(minor: b.limitMinor, currency: currency, language: language)
            return "- \(b.category.title(in: language)): \(spentStr) / \(limitStr)"
        }.joined(separator: "\n")

        let memberLines = snapshot.memberBreakdown.map { m in
            let name = m.memberName.isEmpty ? m.memberID : m.memberName
            let spentStr = MoneyFormat.format(minor: m.spendingMinor, currency: currency, language: language)
            return "- \(name): \(spentStr) (\(m.count) tx)"
        }.joined(separator: "\n")

        let recentLines = snapshot.transactions.prefix(20).map { tx in
            let sign = tx.type == .income ? "+" : "-"
            let amt = MoneyFormat.format(minor: tx.amountMinor, currency: currency, language: language)
            let who = tx.memberName.isEmpty ? "" : " [\(tx.memberName)]"
            return "- \(tx.dayKey): \(tx.name) \(sign)\(amt) (\(tx.category.title(in: language)))\(who)"
        }.joined(separator: "\n")

        let goalLines = goals.filter { !$0.isDeleted }.map { g in
            let saved = MoneyFormat.format(minor: g.savedMinor, currency: currency, language: language)
            let target = MoneyFormat.format(minor: g.targetMinor, currency: currency, language: language)
            return "- \(g.name): \(saved) / \(target) (\(g.percent)%)"
        }.joined(separator: "\n")

        return """
        You are Tally, a calm, practical personal & household finance assistant helping a couple track daily spending, budgets, and savings goals.
        \(language.aiInstruction)
        Keep replies crisp, scannable, and grounded strictly in the user's real numbers below. Use short bullet points where helpful.

        Current month: \(monthTitle) (\(snapshot.monthKey))
        Currency: \(currency.rawValue)
        Monthly income: \(income)
        Monthly spending: \(spending)
        Net savings: \(savings)
        Today's spending: \(today)

        Spending by category:
        \(categoryLines.isEmpty ? "None yet" : categoryLines)

        Monthly budgets:
        \(budgetLines.isEmpty ? "No budgets set" : budgetLines)

        Household members:
        \(memberLines.isEmpty ? "No entries" : memberLines)

        Savings goals:
        \(goalLines.isEmpty ? "No goals" : goalLines)

        Recent transactions (latest 20):
        \(recentLines.isEmpty ? "None" : recentLines)
        """
    }

    public static func suggestedPrompts(in language: AppLanguage) -> [String] {
        switch language.resolved {
        case .vietnamese:
            return [
                "Tháng này hai vợ chồng chi tiêu nhiều nhất ở đâu?",
                "Mình còn bao nhiêu ngân sách cho phần còn lại của tháng?",
                "Có khoản chi nào bất thường trong tháng này không?",
                "Gợi ý cách tiết kiệm thêm 15% tháng tới",
            ]
        case .english:
            return [
                "Where did most of our spending go this month?",
                "How are we tracking against our category budgets?",
                "Spot any unusual expenses this month",
                "How can we boost our savings rate next month?",
            ]
        }
    }
}
