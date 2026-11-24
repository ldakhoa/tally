import BudgetKit
import ClaudeKit
import Foundation
import TallyCore

/// Installment plan & loan tools for the assistant. Validation goes through
/// `InstallmentPlanDraft` (the manual editor's rules); failures go back to the model as tool
/// errors naming what is missing so it asks the user instead of guessing.
/// What plan tools need from the app settings (kept separate so tests need no `AppSettings`).
struct PlanToolEnvironment {
    var language: AppLanguage
    var currency: CurrencyCode
    var todayKey: String
    var resolveMember: (String?) -> HouseholdMember
}

extension AssistantService {
    static func executePlan(
        _ command: AssistantCommand,
        todayKey: String,
        settings: AppSettings,
        store: BudgetStore
    ) -> ToolExecutionOutcome {
        let environment = PlanToolEnvironment(
            language: settings.language,
            currency: settings.currency,
            todayKey: todayKey,
            resolveMember: { resolveMember(hint: $0, settings: settings, store: store) }
        )
        return executePlan(command, environment: environment, store: store)
    }

    static func executePlan(
        _ command: AssistantCommand,
        environment: PlanToolEnvironment,
        store: BudgetStore
    ) -> ToolExecutionOutcome {
        let lang = environment.language
        let todayKey = environment.todayKey
        func failure(_ text: String) -> ToolExecutionOutcome {
            ToolExecutionOutcome(toolOutput: text, isError: true, receipts: [])
        }
        func livePlan(_ id: String) -> InstallmentPlanRecord? {
            store.plan(id: id).flatMap { $0.isDeleted ? nil : $0 }
        }
        func notFound(_ id: String) -> ToolExecutionOutcome {
            failure("No installment plan or loan found with id \(id). Use an id from the plans list.")
        }

        switch command {
        case .createPlan(let fields):
            let member = environment.resolveMember(fields.memberHint)
            var draft = AssistantPlanDrafts.newDraft(fields, currency: environment.currency, member: member)
            if fields.allDuePaymentsAlreadyPaid == true { draft.alreadyPaidCount = draft.duePaymentCount(todayKey: todayKey) }
            guard let record = draft.makeRecord() else {
                return failure(AssistantPlanDrafts.issuesDescription(draft))
            }
            guard store.savePlan(record, todayKey: todayKey) else {
                return failure("Not saved: these terms cannot build a payment schedule. Ask the user to check the amount and months.")
            }
            let saved = store.plan(id: record.id) ?? record
            return saveOutcome(saved, kind: .planCreated, verb: "Created", todayKey: todayKey, language: lang, store: store)

        case .convertTransactionToPlan(let transactionID, let months, let firstPaymentDayKey):
            guard let tx = store.activeTransactions.first(where: { $0.id == transactionID }) else {
                return failure("Transaction not found with id \(transactionID).")
            }
            guard tx.type == .expense, !tx.isPlanPayment else {
                return failure("Only an ordinary expense can be converted (this one is income or already a plan payment).")
            }
            var check = InstallmentPlanDraft(
                name: tx.name, amountMinor: tx.amountMinor, months: months,
                firstPaymentDayKey: firstPaymentDayKey, currency: environment.currency
            )
            check.category = tx.category
            guard check.isValid else { return failure(AssistantPlanDrafts.issuesDescription(check)) }
            guard let plan = store.convertTransactionToPlan(
                transactionID: transactionID,
                months: months,
                firstPaymentDayKey: firstPaymentDayKey,
                currency: environment.currency,
                todayKey: todayKey
            ) else {
                return failure("Not converted: these terms cannot build a payment schedule. Ask the user to check the months and date.")
            }
            let saved = store.plan(id: plan.id) ?? plan
            return saveOutcome(saved, kind: .planConverted, verb: "Converted transaction \(transactionID) into", todayKey: todayKey, language: lang, store: store)

        case .updatePlan(let planID, let fields):
            guard let plan = livePlan(planID) else { return notFound(planID) }
            if let kind = fields.kind, kind != plan.kind {
                return failure("The kind of a plan cannot change. To turn it into a \(kind.rawValue), delete it (ask about its payments) and create a new one.")
            }
            let member = fields.memberHint.map { environment.resolveMember($0) }
            var draft = AssistantPlanDrafts.updatedDraft(fields, plan: plan, member: member)
            if fields.allDuePaymentsAlreadyPaid == true { draft.alreadyPaidCount = draft.duePaymentCount(todayKey: todayKey) }
            guard let record = draft.makeRecord(existing: plan) else {
                return failure(AssistantPlanDrafts.issuesDescription(draft))
            }
            guard store.savePlan(record, todayKey: todayKey) else {
                return failure("Not saved: these terms cannot build a payment schedule.")
            }
            let saved = store.plan(id: record.id) ?? record
            return saveOutcome(saved, kind: .planUpdated, verb: "Updated", todayKey: todayKey, language: lang, store: store)

        case .settlePlan(let planID, let dayKey):
            guard let plan = livePlan(planID) else { return notFound(planID) }
            guard dayKey >= plan.firstPaymentDayKey else {
                return failure("settled_date \(dayKey) is before the plan's first payment (\(plan.firstPaymentDayKey)). Ask the user for the payoff date.")
            }
            let preview = InstallmentSettlementPreview(plan: plan, settleDayKey: dayKey, todayKey: todayKey)
            store.settlePlan(id: planID, on: dayKey, todayKey: todayKey)
            let saved = store.plan(id: planID) ?? plan
            let money = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: saved.currency, language: lang) }
            let english = { (minor: Int64) in MoneyFormat.format(minor: minor, currency: saved.currency, language: .english) }
            var details = [L10n.text(
                lang,
                en: "Paid off \(DateKey.formatAbsoluteDay(dayKey, language: lang)) · \(preview.cancelledPaymentCount) later payments cancelled",
                vi: "Tất toán ngày \(DateKey.formatAbsoluteDay(dayKey, language: lang)) · huỷ \(preview.cancelledPaymentCount) kỳ sau đó",
                zh: "于 \(DateKey.formatAbsoluteDay(dayKey, language: lang)) 结清 · 取消之后的 \(preview.cancelledPaymentCount) 期"
            )]
            if preview.interestSavedMinor > 0 {
                details.append(L10n.text(
                    lang,
                    en: "Principal paid off \(money(preview.payoffPrincipalMinor)) · interest saved \(money(preview.interestSavedMinor))",
                    vi: "Gốc tất toán \(money(preview.payoffPrincipalMinor)) · tiết kiệm lãi \(money(preview.interestSavedMinor))",
                    zh: "结清本金 \(money(preview.payoffPrincipalMinor)) · 节省利息 \(money(preview.interestSavedMinor))"
                ))
            }
            let receipt = AssistantActionReceipt(
                kind: .planSettled,
                emoji: "",
                title: saved.name,
                subtitle: L10n.text(lang, en: "Settled early", vi: "Đã tất toán sớm", zh: "已提前结清"),
                amountText: money(preview.payoffPrincipalMinor),
                isPositive: true,
                details: details
            )
            return ToolExecutionOutcome(
                toolOutput: "Settled [id:\(planID)] '\(saved.name)' on \(dayKey): principal paid off \(english(preview.payoffPrincipalMinor)), interest saved \(english(preview.interestSavedMinor)), \(preview.cancelledPaymentCount) later payments cancelled (\(preview.bookedPaymentsRemovedCount) already-booked ones removed).",
                isError: false,
                receipts: [receipt]
            )

        case .undoPlanSettlement(let planID):
            guard let plan = livePlan(planID) else { return notFound(planID) }
            guard plan.settledDayKey != nil else {
                return failure("Plan \(planID) is not settled, so there is nothing to undo.")
            }
            store.settlePlan(id: planID, on: nil, todayKey: todayKey)
            let saved = store.plan(id: planID) ?? plan
            return saveOutcome(saved, kind: .planUnsettled, verb: "Undid the settlement of", todayKey: todayKey, language: lang, store: store)

        case .deletePlan(let planID, let removePayments):
            guard let plan = livePlan(planID) else { return notFound(planID) }
            let bookedCount = store.payments(forPlanID: planID).count
            store.deletePlan(id: planID, removePayments: removePayments, todayKey: todayKey)
            let detail = removePayments
                ? L10n.text(lang, en: "\(bookedCount) recorded payments removed", vi: "Đã xoá \(bookedCount) khoản đã ghi", zh: "已删除 \(bookedCount) 笔已记录的还款")
                : L10n.text(lang, en: "\(bookedCount) recorded payments kept as expenses", vi: "Giữ \(bookedCount) khoản đã ghi làm khoản chi", zh: "保留 \(bookedCount) 笔已记录的还款为支出")
            let receipt = AssistantActionReceipt(
                kind: .planDeleted,
                emoji: "",
                title: plan.name,
                subtitle: L10n.text(lang, en: "Deleted plan", vi: "Đã xoá kế hoạch", zh: "已删除计划"),
                details: [detail]
            )
            return ToolExecutionOutcome(
                toolOutput: "Deleted [id:\(planID)] '\(plan.name)'; \(bookedCount) recorded payments \(removePayments ? "removed" : "kept as ordinary expenses").",
                isError: false,
                receipts: [receipt]
            )

        default:
            return failure("Unsupported plan command.")
        }
    }

    /// Receipt + tool output for a saved plan, stating the values that were recorded.
    private static func saveOutcome(
        _ plan: InstallmentPlanRecord,
        kind: AssistantActionReceipt.Kind,
        verb: String,
        todayKey: String,
        language lang: AppLanguage,
        store: BudgetStore
    ) -> ToolExecutionOutcome {
        let regular = plan.fullSchedule.first?.amountMinor ?? 0
        let subtitle: String = {
            let kindTitle = plan.kind.title(in: lang)
            switch kind {
            case .planUpdated: return L10n.text(lang, en: "\(kindTitle) updated", vi: "Đã cập nhật \(kindTitle.lowercased())", zh: "\(kindTitle)已更新")
            case .planUnsettled: return L10n.text(lang, en: "Settlement undone", vi: "Đã huỷ tất toán", zh: "已撤销结清")
            case .planConverted: return L10n.text(lang, en: "Converted to \(kindTitle.lowercased())", vi: "Đã chuyển thành \(kindTitle.lowercased())", zh: "已转为\(kindTitle)")
            default: return L10n.text(lang, en: "New \(kindTitle.lowercased())", vi: "\(kindTitle) mới", zh: "新\(kindTitle)")
            }
        }()
        let receipt = AssistantActionReceipt(
            kind: kind,
            emoji: "",
            title: plan.name,
            subtitle: subtitle,
            amountText: L10n.text(
                lang,
                en: "\(MoneyFormat.format(minor: regular, currency: plan.currency, language: lang))/mo",
                vi: "\(MoneyFormat.format(minor: regular, currency: plan.currency, language: lang))/tháng",
                zh: "\(MoneyFormat.format(minor: regular, currency: plan.currency, language: lang))/月"
            ),
            details: AssistantPlanSummary.detailLines(for: plan, todayKey: todayKey, language: lang)
        )
        var output = "\(verb) \(AssistantPlanSummary.modelSummary(for: plan, todayKey: todayKey))."
        let booked = store.payments(forPlanID: plan.id).filter { $0.dayKey <= todayKey }.count
        if booked > 0 {
            output += " \(booked) payments due so far are recorded as expenses by this plan."
        }
        if plan.firstPaymentDayKey < todayKey, plan.effectiveAlreadyPaidCount == 0, booked > 0 {
            output += " The first payment is in the past: if those payments were already recorded in Tally, call update_installment_plan with all_due_payments_already_recorded (or already_paid_payments if only some were) so they are not counted twice."
        }
        return ToolExecutionOutcome(toolOutput: output, isError: false, receipts: [receipt])
    }
}
