import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

/// Progress, loan metrics, month-by-month schedule and actions for one plan. Reads the plan live
/// from the store so edits made from here show up immediately.
struct InstallmentPlanDetailSheet: View {
    let planID: String

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editingPlan: InstallmentPlanRecord?
    @State private var showingSettle = false
    @State private var confirmingDelete = false
    @State private var confirmingReopen = false

    var body: some View {
        let lang = settings.language
        NavigationStack {
            Group {
                if let plan = store.plan(id: planID), !plan.isDeleted {
                    content(plan: plan, lang: lang)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Plan details", vi: "Chi tiết kế hoạch", zh: "计划详情"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 480, idealWidth: 520, minHeight: 600, idealHeight: 720)
    }

    // MARK: Content

    private func content(plan: InstallmentPlanRecord, lang: AppLanguage) -> some View {
        let todayKey = DateKey.dayKey(from: Date())
        let progress = plan.progress(todayKey: todayKey)
        let rows = InstallmentScheduleRow.rows(for: plan, todayKey: todayKey)
        let showsInterest = plan.kind == .loan || plan.totalInterestMinor > 0

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard(plan: plan, progress: progress, lang: lang)
                if showsInterest {
                    loanMetricsCard(plan: plan, progress: progress, lang: lang)
                }
                scheduleCard(plan: plan, rows: rows, lang: lang)
                actionsCard(plan: plan, progress: progress, lang: lang)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .sheet(item: $editingPlan) { InstallmentPlanEditorSheet(existing: $0) }
        .sheet(isPresented: $showingSettle) { InstallmentSettleSheet(planID: plan.id) }
        .confirmationDialog(
            L10n.text(lang, en: "Delete this plan?", vi: "Xoá kế hoạch này?", zh: "删除此计划？"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            deleteButtons(plan: plan, lang: lang)
        } message: {
            Text(L10n.text(
                lang,
                en: "Payments already recorded as expenses can stay in your history or be removed with the plan.",
                vi: "Các kỳ đã ghi nhận thành khoản chi có thể giữ lại trong lịch sử hoặc xoá cùng kế hoạch.",
                zh: "已记为支出的还款可以保留在账单中，也可以随计划一起删除。"
            ))
        }
        .confirmationDialog(
            L10n.text(lang, en: "Undo early settlement?", vi: "Huỷ tất toán sớm?", zh: "撤销提前结清？"),
            isPresented: $confirmingReopen,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Reopen plan", vi: "Mở lại kế hoạch", zh: "重新开启计划")) {
                store.settlePlan(id: plan.id, on: nil)
            }
        } message: {
            Text(L10n.text(
                lang,
                en: "Remaining payments will be scheduled again and booked as they fall due.",
                vi: "Các kỳ còn lại sẽ được lên lịch lại và tự ghi nhận khi đến hạn.",
                zh: "剩余还款将重新排期，并在到期时自动入账。"
            ))
        }
    }

    // MARK: Header

    private func headerCard(plan: InstallmentPlanRecord, progress: InstallmentProgress, lang: AppLanguage) -> some View {
        Card {
            HStack(spacing: 12) {
                CategoryBadge(category: plan.category, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name).font(.appHeading).lineLimit(2)
                    HStack(spacing: 6) {
                        Tag(text: plan.kind.title(in: lang), color: Color.accent)
                        if let lender = plan.lender, !lender.isEmpty {
                            Text(lender).font(.appCaption).foregroundStyle(Color.textSecondary).lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            TallyProgressBar(value: progress.fraction, fill: progress.isCompleted ? Color.positive : Color.accent)

            HStack {
                Text(L10n.text(
                    lang,
                    en: "\(progress.paidCount) of \(progress.paymentCount) payments",
                    vi: "\(progress.paidCount) / \(progress.paymentCount) kỳ",
                    zh: "已还 \(progress.paidCount) / \(progress.paymentCount) 期"
                ))
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                Spacer()
                statusTag(plan: plan, progress: progress, lang: lang)
            }

            Divider().overlay(Color.hairline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 12) {
                stat(L10n.text(lang, en: "Paid", vi: "Đã trả", zh: "已还"), money(progress.paidMinor))
                stat(L10n.text(lang, en: "Remaining", vi: "Còn lại", zh: "剩余"), money(progress.remainingMinor))
                if let next = progress.nextPayment {
                    stat(
                        L10n.text(lang, en: "Next payment", vi: "Kỳ tiếp theo", zh: "下期还款"),
                        money(next.amountMinor),
                        caption: DateKey.formatAbsoluteDay(next.dayKey, language: lang)
                    )
                }
            }

            if let linkURL = InstallmentLink.url(from: plan.linkURL) {
                // Reachable straight from the header so it is one tap away.
                Button {
                    openURL(linkURL)
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.trendUp, size: 14, color: Color.onInk)
                        Text(L10n.text(lang, en: "Open bank app", vi: "Mở ứng dụng ngân hàng", zh: "打开银行 App"))
                    }
                }
                .pillButton(prominent: true)
            }
        }
    }

    @ViewBuilder
    private func statusTag(plan: InstallmentPlanRecord, progress: InstallmentProgress, lang: AppLanguage) -> some View {
        if progress.isSettled, let day = plan.settledDayKey {
            Tag(
                text: L10n.text(
                    lang,
                    en: "Settled \(DateKey.formatCompactDay(day, language: lang))",
                    vi: "Tất toán \(DateKey.formatCompactDay(day, language: lang))",
                    zh: "已结清 \(DateKey.formatCompactDay(day, language: lang))"
                ),
                color: Color.positive
            )
        } else if progress.isCompleted {
            Tag(text: L10n.text(lang, en: "Paid off", vi: "Đã trả xong", zh: "已还清"), color: Color.positive)
        } else if let day = plan.settledDayKey {
            Tag(
                text: L10n.text(
                    lang,
                    en: "Settles \(DateKey.formatCompactDay(day, language: lang))",
                    vi: "Tất toán \(DateKey.formatCompactDay(day, language: lang))",
                    zh: "将于 \(DateKey.formatCompactDay(day, language: lang)) 结清"
                ),
                color: Color.caution
            )
        }
    }

    private func stat(_ title: String, _ value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.appCaption).foregroundStyle(Color.textSecondary)
            Text(value).font(.appBodyMedium).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if let caption {
                Text(caption).font(.appCaption).foregroundStyle(Color.textSecondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Loan metrics

    private func loanMetricsCard(plan: InstallmentPlanRecord, progress: InstallmentProgress, lang: AppLanguage) -> some View {
        Card(L10n.text(lang, en: "Interest & balance", vi: "Lãi & dư nợ", zh: "利息与余额")) {
            VStack(spacing: 10) {
                metricRow(
                    L10n.text(lang, en: "Outstanding principal", vi: "Dư nợ gốc", zh: "剩余本金"),
                    money(progress.outstandingPrincipalMinor)
                )
                metricRow(
                    L10n.text(lang, en: "Interest paid", vi: "Lãi đã trả", zh: "已付利息"),
                    money(progress.interestPaidMinor)
                )
                metricRow(
                    L10n.text(lang, en: "Interest still to come", vi: "Lãi sắp tới", zh: "未来利息"),
                    money(progress.interestRemainingMinor)
                )
                if progress.isSettled {
                    metricRow(
                        L10n.text(lang, en: "Interest saved by settling", vi: "Lãi tiết kiệm nhờ tất toán", zh: "提前结清节省的利息"),
                        money(progress.interestSavedMinor),
                        valueColor: Color.positive
                    )
                }
                Divider().overlay(Color.hairline)
                metricRow(
                    L10n.text(lang, en: "Effective rate (p.a.)", vi: "Lãi suất thực (năm)", zh: "实际年利率"),
                    InstallmentRateFormat.percent(plan.effectiveAnnualRate, language: lang)
                )
                metricRow(
                    L10n.text(lang, en: "Amount borrowed", vi: "Số tiền vay", zh: "借款金额"),
                    money(plan.effectivePrincipalMinor)
                )
                metricRow(
                    L10n.text(lang, en: "Total interest", vi: "Tổng tiền lãi", zh: "利息总额"),
                    money(plan.totalInterestMinor)
                )
            }
        }
    }

    private func metricRow(_ title: String, _ value: String, valueColor: Color = Color.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.appSecondary).foregroundStyle(Color.textSecondary)
            Spacer(minLength: 8)
            Text(value).font(.appBodyMedium).monospacedDigit().foregroundStyle(valueColor)
        }
    }

    // MARK: Schedule

    private func scheduleCard(plan: InstallmentPlanRecord, rows: [InstallmentScheduleRow], lang: AppLanguage) -> some View {
        Card(L10n.text(lang, en: "Schedule", vi: "Lịch trả", zh: "还款计划")) {
            if rows.isEmpty {
                Text(L10n.text(lang, en: "No payments scheduled.", vi: "Chưa có kỳ trả nào.", zh: "暂无还款安排。"))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        scheduleRow(row, lang: lang)
                    }
                }
            }
        }
    }

    private func scheduleRow(_ row: InstallmentScheduleRow, lang: AppLanguage) -> some View {
        let isPaid = row.state == .paid
        let isPaidOutside = row.state == .paidOutsidePlan
        let isCancelled = row.state == .cancelled

        return HStack(alignment: .top, spacing: 10) {
            Group {
                switch row.state {
                case .paid:
                    CozyUIIcon(.checkmarkCircle, size: 18, color: Color.positive)
                case .paidOutsidePlan:
                    CozyUIIcon(.checkmarkCircle, size: 18, color: Color.info)
                case .upcoming:
                    Circle().strokeBorder(Color.hairlineStrong, lineWidth: 1.5).frame(width: 16, height: 16)
                case .cancelled:
                    CozyUIIcon(.xmarkCircle, size: 18, color: Color.textSecondary.opacity(0.6))
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text("#\(row.index + 1) · \(DateKey.formatAbsoluteDay(row.dayKey, language: lang))")
                        .font(.appBodyMedium)
                        .foregroundStyle(isCancelled ? Color.textSecondary : Color.textPrimary)
                    Spacer(minLength: 8)
                    Text(money(row.paymentMinor))
                        .font(.appAmount)
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Color.textSecondary : Color.textPrimary)
                }
                if isPaidOutside {
                    Text(L10n.text(
                        lang,
                        en: "Paid before Tally · not added as an expense",
                        vi: "Đã trả trước khi dùng Tally · không ghi thành khoản chi",
                        zh: "在使用 Tally 前已支付 · 不计入支出"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.info)
                }
                if let interest = row.interestMinor, let principal = row.principalMinor, !isCancelled {
                    Text(L10n.text(
                        lang,
                        en: "Principal \(money(principal)) · Interest \(money(interest))",
                        vi: "Gốc \(money(principal)) · Lãi \(money(interest))",
                        zh: "本金 \(money(principal)) · 利息 \(money(interest))"
                    ))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    if let balance = row.outstandingPrincipalMinor {
                        Text(L10n.text(
                            lang,
                            en: "Balance after: \(money(balance))",
                            vi: "Dư nợ sau kỳ: \(money(balance))",
                            zh: "还款后余额：\(money(balance))"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    }
                } else if isCancelled {
                    Text(L10n.text(lang, en: "Not due (settled early)", vi: "Không phải trả (tất toán sớm)", zh: "无需偿还（提前结清）"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            isPaid ? Color.positive.opacity(0.08) : (isPaidOutside ? Color.info.opacity(0.08) : Color.clear),
            in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        )
        .overlay {
            if row.state == .upcoming {
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
            }
        }
        .opacity(isCancelled ? 0.7 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isPaid
                ? L10n.text(lang, en: "Paid", vi: "Đã trả", zh: "已还")
                : isPaidOutside
                ? L10n.text(lang, en: "Paid before Tally, not added as an expense", vi: "Đã trả trước khi dùng Tally, không ghi thành khoản chi", zh: "在使用 Tally 前已支付，不计入支出")
                : (isCancelled
                    ? L10n.text(lang, en: "Not due", vi: "Không phải trả", zh: "无需偿还")
                    : L10n.text(lang, en: "Upcoming", vi: "Sắp tới", zh: "待还"))
        )
    }

    // MARK: Actions

    private func actionsCard(plan: InstallmentPlanRecord, progress: InstallmentProgress, lang: AppLanguage) -> some View {
        VStack(spacing: 10) {
            Button {
                editingPlan = plan
            } label: {
                Text(L10n.text(lang, en: "Edit", vi: "Sửa", zh: "编辑"))
            }
            .blockButton(prominent: false)

            if progress.isSettled || plan.settledDayKey != nil {
                Button {
                    confirmingReopen = true
                } label: {
                    Text(L10n.text(lang, en: "Undo early settlement", vi: "Huỷ tất toán sớm", zh: "撤销提前结清"))
                }
                .blockButton(prominent: false)
            } else if !progress.isCompleted {
                Button {
                    showingSettle = true
                } label: {
                    Text(L10n.text(lang, en: "Settle early", vi: "Tất toán sớm", zh: "提前结清"))
                }
                .blockButton(prominent: false)
            }

            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                HStack(spacing: 6) {
                    CozyUIIcon(.trash, size: 16, color: Color.negative)
                    Text(L10n.text(lang, en: "Delete plan", vi: "Xoá kế hoạch", zh: "删除计划"))
                }
            }
            .blockButton(prominent: false, tint: Color.negative)
        }
    }

    @ViewBuilder
    private func deleteButtons(plan: InstallmentPlanRecord, lang: AppLanguage) -> some View {
        let recorded = store.payments(forPlanID: plan.id).count
        if recorded == 0 {
            Button(L10n.text(lang, en: "Delete plan", vi: "Xoá kế hoạch", zh: "删除计划"), role: .destructive) {
                store.deletePlan(id: plan.id, removePayments: false)
                dismiss()
            }
        } else {
            Button(
                L10n.text(
                    lang,
                    en: "Delete plan, keep \(recorded) recorded payments",
                    vi: "Xoá kế hoạch, giữ \(recorded) kỳ đã ghi",
                    zh: "删除计划，保留已记的 \(recorded) 笔还款"
                )
            ) {
                store.deletePlan(id: plan.id, removePayments: false)
                dismiss()
            }
            Button(
                L10n.text(
                    lang,
                    en: "Delete plan and remove \(recorded) recorded payments",
                    vi: "Xoá kế hoạch và \(recorded) kỳ đã ghi",
                    zh: "删除计划并移除已记的 \(recorded) 笔还款"
                ),
                role: .destructive
            ) {
                store.deletePlan(id: plan.id, removePayments: true)
                dismiss()
            }
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.format(minor: minor, currency: settings.currency, language: settings.language)
    }
}

// MARK: - Settle early

/// Confirmation step for early settlement: choose the settlement date and see what it saves.
struct InstallmentSettleSheet: View {
    let planID: String

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var settleDayKey = DateKey.dayKey(from: Date())
    @State private var showingDatePicker = false

    var body: some View {
        let lang = settings.language
        NavigationStack {
            Group {
                if let plan = store.plan(id: planID), !plan.isDeleted {
                    content(plan: plan, lang: lang)
                } else {
                    Color.clear.onAppear { dismiss() }
                }
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Settle early", vi: "Tất toán sớm", zh: "提前结清"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                InstallmentDatePickerSheet(
                    dayKey: $settleDayKey,
                    title: L10n.text(lang, en: "Settlement date", vi: "Ngày tất toán", zh: "结清日期")
                )
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 620)
    }

    private func content(plan: InstallmentPlanRecord, lang: AppLanguage) -> some View {
        let todayKey = DateKey.dayKey(from: Date())
        let preview = InstallmentSettlementPreview(plan: plan, settleDayKey: settleDayKey, todayKey: todayKey)
        let hasInterest = plan.totalInterestMinor > 0

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    CategoryBadge(category: plan.category, size: 42)
                    Text(plan.name).font(.appHeading).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .cardSurface(cornerRadius: 18)

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(L10n.text(lang, en: "Settlement date", vi: "Ngày tất toán", zh: "结清日期"))
                    HStack {
                        InstallmentDatePill(dayKey: settleDayKey, language: lang) { showingDatePicker = true }
                        Spacer(minLength: 0)
                    }
                }

                Card {
                    VStack(spacing: 10) {
                        row(
                            hasInterest
                                ? L10n.text(lang, en: "Principal to pay off", vi: "Dư nợ gốc cần tất toán", zh: "需结清的本金")
                                : L10n.text(lang, en: "Remaining to pay off", vi: "Số còn lại cần tất toán", zh: "需结清的余额"),
                            money(preview.payoffPrincipalMinor)
                        )
                        row(
                            L10n.text(lang, en: "Payments cancelled", vi: "Số kỳ được huỷ", zh: "取消的还款期数"),
                            "\(preview.cancelledPaymentCount) · \(money(preview.cancelledPaymentsMinor))"
                        )
                        if hasInterest {
                            row(
                                L10n.text(lang, en: "Interest saved", vi: "Lãi tiết kiệm được", zh: "节省的利息"),
                                money(preview.interestSavedMinor),
                                valueColor: Color.positive
                            )
                        }
                    }
                }

                if preview.cancelledPaymentCount == 0 {
                    Text(L10n.text(
                        lang,
                        en: "Nothing is left to pay after this date.",
                        vi: "Sau ngày này không còn kỳ nào phải trả.",
                        zh: "此日期之后已无待还款项。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }

                if preview.bookedPaymentsRemovedCount > 0 {
                    Text(L10n.text(
                        lang,
                        en: "\(preview.bookedPaymentsRemovedCount) payment(s) already recorded after this date will be removed from your transactions.",
                        vi: "\(preview.bookedPaymentsRemovedCount) kỳ đã ghi sau ngày này sẽ bị xoá khỏi giao dịch.",
                        zh: "此日期之后已入账的 \(preview.bookedPaymentsRemovedCount) 笔还款将从账单中移除。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.caution)
                }

                Text(L10n.text(
                    lang,
                    en: "The payoff itself is not recorded as an expense. Add it as a transaction if you want it in your spending.",
                    vi: "Khoản tất toán không tự ghi thành chi tiêu. Hãy thêm giao dịch nếu bạn muốn tính vào chi tiêu.",
                    zh: "结清款项不会自动记为支出。如需计入支出，请手动添加一笔账单。"
                ))
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)

                Button(L10n.text(lang, en: "Settle plan", vi: "Tất toán", zh: "确认结清")) {
                    store.settlePlan(id: plan.id, on: settleDayKey)
                    CozyHaptics.success()
                    dismiss()
                }
                .blockButton(prominent: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func row(_ title: String, _ value: String, valueColor: Color = Color.textPrimary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.appSecondary).foregroundStyle(Color.textSecondary)
            Spacer(minLength: 8)
            Text(value).font(.appBodyMedium).monospacedDigit().foregroundStyle(valueColor)
        }
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.format(minor: minor, currency: settings.currency, language: settings.language)
    }
}
