import Foundation
import TallyCore

/// Builds the system prompt and live household budget summary for Ask Tally AI conversations.
public enum BudgetAssistantPrompt {
    public static func systemPrompt(
        snapshot: MonthlySnapshot,
        goals: [SavingsGoalRecord],
        currency: CurrencyCode,
        language: AppLanguage,
        myName: String = "",
        partnerName: String = "",
        now: Date = Date()
    ) -> String {
        let todayKey = DateKey.dayKey(from: now)
        let monthTitle = DateKey.formatMonth(snapshot.monthKey, language: language)
        let income = MoneyFormat.format(minor: snapshot.incomeMinor, currency: currency, language: language)
        let spending = MoneyFormat.format(minor: snapshot.spendingMinor, currency: currency, language: language)
        let savings = MoneyFormat.format(minor: snapshot.netSavingsMinor, currency: currency, language: language)
        let today = MoneyFormat.format(minor: snapshot.todaySpendingMinor, currency: currency, language: language)

        let categoryLines = snapshot.categoryBreakdown.map { item in
            let amt = MoneyFormat.format(minor: item.spentMinor, currency: currency, language: language)
            let pct = Int((item.share * 100).rounded())
            return "- \(item.category.title(in: language)) (\(item.category.rawValue)): \(amt) (\(pct)%)"
        }.joined(separator: "\n")

        let budgetLines = snapshot.budgets.map { b in
            let spent = snapshot.expensesByCategory[b.category] ?? 0
            let spentStr = MoneyFormat.format(minor: spent, currency: currency, language: language)
            let limitStr = MoneyFormat.format(minor: b.limitMinor, currency: currency, language: language)
            return "- \(b.category.title(in: language)) (\(b.category.rawValue)): \(spentStr) / \(limitStr)"
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
            return "- [id:\(tx.id)] \(tx.dayKey): \(tx.name) \(sign)\(amt) (\(tx.category.rawValue))\(who)"
        }.joined(separator: "\n")

        let goalLines = goals.filter { !$0.isDeleted }.map { g in
            let saved = MoneyFormat.format(minor: g.savedMinor, currency: currency, language: language)
            let target = MoneyFormat.format(minor: g.targetMinor, currency: currency, language: language)
            return "- [id:\(g.id)] \(g.name): \(saved) / \(target) (\(g.percent)%)"
        }.joined(separator: "\n")

        let profileLine: String = {
            var parts: [String] = []
            if !myName.isEmpty { parts.append("Current user: \(myName)") }
            if !partnerName.isEmpty { parts.append("Partner: \(partnerName)") }
            return parts.isEmpty ? "" : "\n" + parts.joined(separator: " · ")
        }()

        return """
        You are Tally, a calm, proactive personal & household finance assistant helping a couple manage daily transactions, monthly budgets, and savings goals across the entire Tally app.
        \(language.aiInstruction) If the user writes in English, Vietnamese, or Chinese, understand them naturally and reply clearly.

        CAPABILITIES & ACTION RULES:
        - You have real tools that directly read & write the user's app data (Transactions, Monthly Budgets, and Savings Goals).
        - Whenever the user tells you they spent money, paid rent, paid a credit card bill, received salary/income, etc. — IMMEDIATELY call `add_transactions` to save all mentioned items (you can add multiple items in one call).
        - Whenever the user mentions saving for a goal (e.g. buying a car, Japan trip, emergency fund) or contributing to a goal — IMMEDIATELY call `create_savings_goal` or `update_savings_goal`.
        - Whenever the user tells you what their monthly budget should be (e.g. food 800, housing 3000) — IMMEDIATELY call `set_budgets`.
        - Whenever the user asks to edit or delete a recent transaction, budget, or goal — call the matching update/delete tool using the IDs listed below.
        - Never claim you added/updated data without actually calling the corresponding tool first.
        - After tools succeed, give a crisp, friendly confirmation summarizing what was saved and any helpful context (like remaining budget or goal progress).
        - For analytical questions, answer strictly from the live numbers below using short bullet points.

        Today's date: \(todayKey)
        Active viewed month: \(monthTitle) (\(snapshot.monthKey))
        Currency: \(currency.rawValue)\(profileLine)
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
                "Nay mình đóng tiền nhà 3000 và trả thẻ tín dụng 800",
                "Đặt ngân sách tháng này: ăn uống 1000, mua sắm 500",
                "Tạo mục tiêu tiết kiệm đi du lịch Nhật 5000",
                "Tháng này hai vợ chồng chi tiêu nhiều nhất ở đâu?",
            ]
        case .chinese:
            return [
                "今天交了房租 3000，还信用卡 800",
                "设置本月预算：餐饮 1000，购物 500",
                "创建存钱目标：日本旅行 5000",
                "这个月我们花钱最多的分类是什么？",
            ]
        case .english:
            return [
                "Today I paid rent 3000 and credit card bill 800",
                "Set this month's budget: Food 1000, Shopping 500",
                "Create a savings goal for Japan trip of 5000",
                "Where did most of our spending go this month?",
            ]
        }
    }
}
