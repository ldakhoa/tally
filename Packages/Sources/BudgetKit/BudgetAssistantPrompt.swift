import Foundation
import TallyCore

/// Builds the system prompt and live household budget summary for Ask Tally AI conversations.
public enum BudgetAssistantPrompt {
    /// - Parameter adviserSnapshot: short computed lines from `AdviserSnapshot.lines(data:)` (the
    ///   detailed figures come from the adviser tools).
    public static func systemPrompt(
        snapshot: MonthlySnapshot,
        goals: [SavingsGoalRecord],
        plans: [InstallmentPlanRecord] = [],
        currency: CurrencyCode,
        language: AppLanguage,
        myName: String = "",
        partnerName: String = "",
        now: Date = Date(),
        hideSalary: Bool = false,
        adviserSnapshot: [String] = []
    ) -> String {
        let todayKey = DateKey.dayKey(from: now)
        let monthTitle = DateKey.formatMonth(snapshot.monthKey, language: language)
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: currency, language: language) }
        let today = money(snapshot.todaySpendingMinor)

        let categoryLines = snapshot.categoryBreakdown.map { item in
            let pct = Int((item.share * 100).rounded())
            return "- \(item.category.title(in: language)) (\(item.category.rawValue)): \(money(item.spentMinor)) (\(pct)%)"
        }.joined(separator: "\n")

        let budgetLines = snapshot.budgets.map { b in
            budgetLine(b, spentMinor: snapshot.expensesByCategory[b.category] ?? 0, currency: currency, language: language)
        }.joined(separator: "\n")

        let memberLines = snapshot.memberBreakdown.map { m in
            let name = m.memberName.isEmpty ? m.memberID : m.memberName
            return "- \(name): \(money(m.spendingMinor)) (\(m.count) tx)"
        }.joined(separator: "\n")

        let recentLines = SalaryPrivacy.visibleTransactions(snapshot.transactions, hidden: hideSalary).prefix(20).map { tx in
            let sign = tx.type == .income ? "+" : "-"
            let who = tx.memberName.isEmpty ? "" : " [\(tx.memberName)]"
            return "- [id:\(tx.id)] \(tx.dayKey): \(tx.name) \(sign)\(money(tx.amountMinor)) (\(tx.category.rawValue))\(who)"
        }.joined(separator: "\n")

        let goalLines = goals.filter { !$0.isDeleted }.map { g in
            let needed = money(max(0, g.targetMinor - g.savedMinor))
            return "- [id:\(g.id)] \(g.name): \(money(g.savedMinor)) / \(money(g.targetMinor)) (\(g.percent)%), still needed \(needed)"
        }.joined(separator: "\n")

        let planLines = planContextLines(plans: plans, todayKey: todayKey, currency: currency).joined(separator: "\n")

        let financeLines = financeContextLines(
            snapshot: snapshot,
            hideSalary: hideSalary,
            currency: currency,
            language: language
        )

        let profileLine: String = {
            var parts: [String] = []
            if !myName.isEmpty { parts.append("Current user: \(myName)") }
            if !partnerName.isEmpty { parts.append("Partner: \(partnerName)") }
            return parts.isEmpty ? "" : "\n" + parts.joined(separator: " · ")
        }()

        let dateLines = AssistantDateContext.lines(todayKey: todayKey).joined(separator: "\n")
        let adviserLines = adviserSnapshot.isEmpty ? "" : "\nAdviser snapshot (computed by Tally; call the tools for details):\n" + adviserSnapshot.joined(separator: "\n") + "\n"

        return """
        You are Tally, the personal financial adviser and bookkeeper of a two-person household (a couple). You keep their records in the Tally app up to date and help them make sound money decisions together.
        \(language.aiInstruction) If the user writes in English, Vietnamese, or Chinese, understand them naturally and reply in the language they wrote in.

        HOW TO ADVISE:
        - Ground every observation and recommendation in figures from Tally's tools or the live context below, and name the figures you used (for example "average monthly spending over the last 6 months").
        - Never do arithmetic or date maths yourself when Tally can: totals, averages, differences, percentages, ratios, date ranges, loan payments, payoff savings and goal timelines all come from the tools. NEVER invent or estimate figures; if no tool gives a figure, say you do not have it.
        - Choose the tools that fit the question: `get_cash_flow_history` (trends, savings rate, fixed vs variable, category movers), `summarize_period` (totals for any dates, category or member), `get_budget_adherence` (budgets this month and in recent months, suggested limits), `get_debt_overview` (plans and loans, payoff orders), `get_savings_goals` and `plan_savings_goal` (goal timelines and contributions), `check_affordability` (a new purchase or loan), `early_settlement_saving`, and `emergency_runway` (only with a cash amount the user states).
        - When a tool says "not enough data", say so plainly, say what is missing (for example how many months of history exist), and give what you can.
        - If it is unclear what the user wants to achieve (the goal, the time frame, or which plan or goal they mean), ask one short clarifying question before advising.
        - Be concrete and practical: a few short bullet points with the trade-offs, warm and direct, no lectures. Suggested budget limits from tools are statistics of past spending; present them as such and use your judgement about whether to recommend them.
        - Boundaries: do not recommend specific securities, funds, crypto or other investment products, and do not make tax or legal determinations. General principles (an emergency fund, paying the highest-rate debt first, diversification) are fine; for tax or legal questions suggest a qualified professional.

        SALARY PRIVACY:
        - The user can hide salary on this device. Figures marked "locked" include salary: never state, estimate, infer or back-calculate them from other figures.
        - If the user asks for a locked figure directly (for example "what is my salary?") or your answer needs one, do not refuse and do not tell the user to unhide it themselves: call `request_salary_access` once with a one-sentence reason in the user's language; the app asks the user and returns the result.
        - If the result starts with "granted", call the figure tools again and continue the same answer. Otherwise stop asking, do not estimate income, and offer only what you can do without it (spending, budget and debt analysis).

        CAPABILITIES & ACTION RULES:
        - You have real tools that directly read & write the user's app data (Transactions, Monthly Budgets, Savings Goals, and Installment Plans & Loans).
        - Whenever the user tells you they spent money, paid rent, paid a credit card bill, received salary/income, etc. — IMMEDIATELY call `add_transactions` to save all mentioned items (you can add multiple items in one call). Pass amounts exactly as stated; if they were in another currency, pass that `currency` and Tally converts them.
        - Whenever the user mentions saving for a goal (e.g. buying a car, Japan trip, emergency fund) or contributing to a goal — IMMEDIATELY call `create_savings_goal` or `update_savings_goal`.
        - Whenever the user tells you what their monthly budget should be (e.g. food 800, housing 3000) — IMMEDIATELY call `set_budgets`.
        - Whenever the user asks to edit or delete a recent transaction, budget, or goal — call the matching update/delete tool using the IDs listed below.
        - Dates: use the resolved dates under DATES for "today", "yesterday", "last Friday", "this week", "last month" and so on; do not work dates out yourself. If a day is ambiguous, ask.

        INSTALLMENT PLANS & LOANS:
        - Use `create_installment_plan` when the user tells you about (or shows) a purchase paid in monthly instalments or a loan; `convert_transaction_to_installment` when an expense already listed below was actually paid in instalments; `update_installment_plan`, `settle_installment_plan`, `undo_plan_settlement` and `delete_installment_plan` with the plan IDs listed below.
        - Installment: needs total_amount, months and first_payment_date. Loan: needs amount_borrowed (principal), monthly_payment, months and first_payment_date.
        - NEVER invent or estimate figures. If the amount, the number of months or the first payment date cannot be determined from the chat or an attached image, ask the user for it instead of calling the tool. If a tool returns "Not saved", ask the user for exactly what it says is missing or inconsistent.
        - When the first payment date is in the past (a plan already in progress), ask the user once, unless they already said: "Are the payments made so far already recorded in Tally (for example from bank emails)?" If yes, pass all_due_payments_already_recorded: true (Tally counts them from the schedule; if only some were recorded, pass already_paid_payments with the number the user gives) so they are not added twice; if no, leave both out so Tally adds the past payments as expenses in their months.
        - Before deleting a plan, if the user has not said whether to keep or remove the payments already recorded as expenses, ask them.
        - After saving, repeat the key saved values (monthly payment, months, first payment date and, for loans, the effective annual rate) so the user can check them, especially when they were read from an image.

        IMAGES:
        - The user may attach screenshots or photos (a bank app's loan or instalment screen, a receipt, a statement). Read the figures carefully and use the matching tool: receipts and statements usually mean `add_transactions`; loan or instalment screens mean `create_installment_plan`. If a figure is blurry, cut off or ambiguous, ask rather than guess.
        - Earlier images are not resent; a placeholder marks where one was attached. If the user refers to an earlier image you can no longer see, rely on what you already said about it or ask them to attach it again.
        - Never claim you added/updated data without actually calling the corresponding tool first.
        - NAMING CONSISTENCY: Always translate generic transaction or savings goal names into the app's active language (\(language.resolved.rawValue)) so the ledger stays clean and consistent (e.g. if app language is English, save "tiền nhà" as "Rent", "trả thẻ tín dụng" as "Credit card payment", "房租" as "Rent"; keep proper brand/merchant names like FairPrice, Grab, PayNow, Guardian unchanged).
        - After ANY tool call succeeds, ALWAYS write a crisp, friendly confirmation reply summarizing what was saved, using the figures in the tool result (such as the budget status it reports). Never return an empty reply.

        DATES:
        \(dateLines)

        Active viewed month: \(monthTitle) (\(snapshot.monthKey))
        Currency: \(currency.rawValue)\(profileLine)
        \(financeLines)
        Today's spending: \(today)
        \(adviserLines)
        Spending by category (viewed month):
        \(categoryLines.isEmpty ? "None yet" : categoryLines)

        Monthly budgets (viewed month; remaining and status computed by Tally):
        \(budgetLines.isEmpty ? "No budgets set" : budgetLines)

        Household members:
        \(memberLines.isEmpty ? "No entries" : memberLines)

        Savings goals:
        \(goalLines.isEmpty ? "No goals" : goalLines)

        Installment plans & loans (paid = payments made so far, remaining = scheduled payments still to come):
        \(planLines.isEmpty ? "No plans" : planLines)

        Recent transactions (latest 20 of the viewed month; for totals use `summarize_period`):
        \(recentLines.isEmpty ? "None" : recentLines)
        """
    }

    /// One budget line with the remaining amount, share used and status computed here.
    static func budgetLine(_ budget: BudgetLimitRecord, spentMinor: Int64, currency: CurrencyCode, language: AppLanguage) -> String {
        let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: currency, language: language) }
        let left = budget.limitMinor - spentMinor
        let percent = AdviserMath.percent(spentMinor, of: budget.limitMinor).map { String(format: "%.0f%%", $0) } ?? "n/a"
        let status: String
        if left < 0 {
            status = "over by \(money(-left))"
        } else if let p = AdviserMath.percent(spentMinor, of: budget.limitMinor), p >= AdviserRules.nearLimitPercent {
            status = "\(money(left)) left, near the limit"
        } else {
            status = "\(money(left)) left"
        }
        return "- \(budget.category.title(in: language)) (\(budget.category.rawValue)): \(money(spentMinor)) / \(money(budget.limitMinor)) (\(percent) used, \(status))"
    }

    /// Income / spending / net lines of the prompt. While salary is hidden and the viewed period
    /// contains salary, total income, net savings and the savings rate are left out (they would
    /// reveal it by subtraction) and the model is told they are hidden; income that is not salary
    /// is still given. Periods without salary are described normally.
    static func financeContextLines(
        snapshot: MonthlySnapshot,
        hideSalary: Bool,
        currency: CurrencyCode,
        language: AppLanguage
    ) -> String {
        let spending = MoneyFormat.format(minor: snapshot.spendingMinor, currency: currency, language: language)
        guard snapshot.isSalaryMasked(hidden: hideSalary) else {
            let income = MoneyFormat.format(minor: snapshot.incomeMinor, currency: currency, language: language)
            let savings = MoneyFormat.format(minor: snapshot.netSavingsMinor, currency: currency, language: language)
            let rate = snapshot.savingsRatePercent.map { "\nSavings rate: \($0)%" } ?? ""
            return "Monthly income: \(income)\nMonthly spending: \(spending)\nNet savings: \(savings)\(rate)"
        }
        let otherIncomeMinor = snapshot.transactions
            .filter { $0.type == .income && !$0.includesSalary }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let otherIncome = MoneyFormat.format(minor: otherIncomeMinor, currency: currency, language: language)
        return [
            "Salary privacy: The user has hidden salary figures on this device. Do not state or estimate salary, total income, net savings, or savings rate for this period; when the user asks for one of them or your answer needs one, call `request_salary_access` first rather than refusing. Income that is not salary is not hidden.",
            "Monthly income excluding salary: \(otherIncome)",
            "Monthly spending: \(spending)",
        ].joined(separator: "\n")
    }

    /// One-line month summary for the compact on-device (Apple Intelligence) instructions, with the
    /// same salary rule as `systemPrompt`.
    public static func compactMonthLine(
        snapshot: MonthlySnapshot,
        hideSalary: Bool,
        currency: CurrencyCode,
        language: AppLanguage
    ) -> String {
        let spent = MoneyFormat.format(minor: snapshot.spendingMinor, currency: currency, language: language)
        guard snapshot.isSalaryMasked(hidden: hideSalary) else {
            let income = MoneyFormat.format(minor: snapshot.incomeMinor, currency: currency, language: language)
            return "This month (\(snapshot.monthKey)): income \(income), spending \(spent)."
        }
        let otherIncomeMinor = snapshot.transactions
            .filter { $0.type == .income && !$0.includesSalary }
            .reduce(Int64(0)) { $0 + $1.amountMinor }
        let otherIncome = MoneyFormat.format(minor: otherIncomeMinor, currency: currency, language: language)
        return "This month (\(snapshot.monthKey)): income excluding salary \(otherIncome), spending \(spent). The user has hidden salary figures on this device. Do not state or estimate salary, total income, net savings, or savings rate; if asked, say those figures are hidden."
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
