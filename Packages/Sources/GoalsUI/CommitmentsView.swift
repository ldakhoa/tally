import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

/// Installment plans and loans: a summary card, plan cards, a collapsed "Completed" group, an
/// empty state and the add / detail sheets.
///
/// Mirrors `GoalsView`: `embedded` renders the content only (for the iPhone plan tab, which
/// supplies the navigation stack, title and toolbar); otherwise it is a full page with its own
/// `NavigationStack`, scroll view, background, title and toolbar (the iPad / Mac sidebar layout).
public struct CommitmentsView: View {
    public var embedded: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewPlan = false
    @State private var viewingPlan: InstallmentPlanRecord?
    @State private var showCompleted = false

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        if embedded {
            content
                .sheet(isPresented: $showingNewPlan) {
                    InstallmentPlanEditorSheet(existing: nil)
                }
                .sheet(item: $viewingPlan) { plan in
                    InstallmentPlanDetailSheet(planID: plan.id)
                }
        } else {
            NavigationStack {
                ScrollView {
                    content
                        .documentColumn(maxWidth: 1020)
                }
                .pageBackground()
                .navigationTitle(L10n.text(settings.language, en: "Commitments", vi: "Khoản cam kết", zh: "分期与贷款"))
                .toolbar { TopToolbarControls() }
                .sheet(isPresented: $showingNewPlan) {
                    InstallmentPlanEditorSheet(existing: nil)
                }
                .sheet(item: $viewingPlan) { plan in
                    InstallmentPlanDetailSheet(planID: plan.id)
                }
            }
        }
    }

    private var content: some View {
        let lang = settings.language
        let todayKey = DateKey.dayKey(from: Date())
        let overview = CommitmentsOverview(plans: store.activePlans, todayKey: todayKey)

        return VStack(alignment: .leading, spacing: 14) {
            if overview.isEmpty {
                emptyState(lang: lang)
            } else {
                addButtonRow(lang: lang)
                if !overview.active.isEmpty {
                    summaryCard(overview: overview, lang: lang)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(overview.active) { entry in
                            planCard(entry: entry, lang: lang, todayKey: todayKey)
                        }
                    }
                }
                if !overview.completed.isEmpty {
                    completedGroup(entries: overview.completed, lang: lang)
                }
            }
        }
    }

    // MARK: Add / summary

    /// The page title already says "Commitments", so the row only carries the add button.
    private func addButtonRow(lang: AppLanguage) -> some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                CozyHaptics.medium()
                showingNewPlan = true
            } label: {
                HStack(spacing: 6) {
                    CozyUIIcon(.plus, size: 14, color: Color.onInk)
                    Text(L10n.text(lang, en: "Add", vi: "Thêm", zh: "添加"))
                }
            }
            .pillButton(prominent: true)
            .accessibilityLabel(L10n.text(lang, en: "Add installment or loan", vi: "Thêm trả góp hoặc khoản vay", zh: "添加分期或贷款"))
        }
    }

    private func summaryCard(overview: CommitmentsOverview, lang: AppLanguage) -> some View {
        Card {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(lang, en: "Committed this month", vi: "Phải trả tháng này", zh: "本月应还"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(money(overview.committedThisMonthMinor))
                        .font(.appMetric)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(lang, en: "Total remaining debt", vi: "Tổng dư nợ còn lại", zh: "剩余债务合计"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    Text(money(overview.remainingDebtMinor))
                        .font(.appMetric)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Plan rows

    private func planCard(entry: CommitmentsOverview.Entry, lang: AppLanguage, todayKey: String) -> some View {
        let plan = entry.plan
        let progress = entry.progress
        let monthly = plan.fullSchedule.first?.amountMinor ?? 0

        return Button {
            CozyHaptics.light()
            viewingPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CategoryBadge(category: plan.category, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.name)
                            .font(.appHeading)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Tag(text: plan.kind.title(in: lang), color: Color.accent)
                            if let lender = plan.lender, !lender.isEmpty {
                                Text(lender)
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(money(monthly))
                            .font(.appAmount)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(L10n.text(lang, en: "per month", vi: "mỗi tháng", zh: "每月"))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                TallyProgressBar(value: progress.fraction, fill: Color.accent)

                HStack {
                    Text(L10n.text(
                        lang,
                        en: "\(progress.paidCount) / \(progress.paymentCount) paid",
                        vi: "Đã trả \(progress.paidCount) / \(progress.paymentCount) kỳ",
                        zh: "已还 \(progress.paidCount) / \(progress.paymentCount) 期"
                    ))
                    Spacer(minLength: 8)
                    if let next = progress.nextPaymentDayKey {
                        Text(L10n.text(
                            lang,
                            en: "Next: \(DateKey.formatCompactDay(next, language: lang))",
                            vi: "Kỳ tới: \(DateKey.formatCompactDay(next, language: lang))",
                            zh: "下期：\(DateKey.formatCompactDay(next, language: lang))"
                        ))
                    }
                }
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
        .accessibilityHint(L10n.text(lang, en: "Opens plan details", vi: "Mở chi tiết kế hoạch", zh: "打开计划详情"))
    }

    // MARK: Completed group

    private func completedGroup(entries: [CommitmentsOverview.Entry], lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                CozyHaptics.selection()
                withAnimation(.snappy(duration: 0.2)) { showCompleted.toggle() }
            } label: {
                HStack(spacing: 8) {
                    CozyUIIcon(showCompleted ? .chevronDown : .chevronRight, size: 13, color: Color.textSecondary)
                        .frame(width: 16)
                    Text(L10n.text(lang, en: "Completed", vi: "Đã hoàn tất", zh: "已完成"))
                        .font(.appHeading)
                        .foregroundStyle(Color.textPrimary)
                    Tag(text: "\(entries.count)")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.themedPlain)
            .accessibilityValue(showCompleted
                ? L10n.text(lang, en: "Expanded", vi: "Đang mở", zh: "已展开")
                : L10n.text(lang, en: "Collapsed", vi: "Đang thu gọn", zh: "已折叠"))

            if showCompleted {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(entries) { entry in
                        completedCard(entry: entry, lang: lang)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func completedCard(entry: CommitmentsOverview.Entry, lang: AppLanguage) -> some View {
        let plan = entry.plan
        return Button {
            CozyHaptics.light()
            viewingPlan = plan
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(category: plan.category, size: 38)
                    .opacity(0.8)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name)
                        .font(.appBodyMedium)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(completedCaption(plan: plan, progress: entry.progress, lang: lang))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Tag(
                    text: entry.progress.isSettled
                        ? L10n.text(lang, en: "Settled", vi: "Đã tất toán", zh: "已结清")
                        : L10n.text(lang, en: "Paid off", vi: "Đã trả xong", zh: "已还清"),
                    color: Color.positive
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.themedPlain)
    }

    private func completedCaption(plan: InstallmentPlanRecord, progress: InstallmentProgress, lang: AppLanguage) -> String {
        let kind = plan.kind.title(in: lang)
        let total = money(progress.paidMinor)
        return "\(kind) · \(total)"
    }

    // MARK: Empty state

    private func emptyState(lang: AppLanguage) -> some View {
        VStack(spacing: 12) {
            CozyUIIcon(.creditCard, size: 34, color: Color.accent)
                .frame(width: 64, height: 64)
                .background(Color.accent.opacity(0.12), in: Circle())
            Text(L10n.text(lang, en: "No installments or loans", vi: "Chưa có khoản trả góp hay vay", zh: "暂无分期或贷款"))
                .font(.appHeading)
                .multilineTextAlignment(.center)
            Text(L10n.text(
                lang,
                en: "Track card installments and loans here. Each monthly payment is booked as an expense automatically when it falls due.",
                vi: "Theo dõi trả góp thẻ và khoản vay tại đây. Mỗi kỳ trả hàng tháng sẽ tự ghi thành khoản chi khi đến hạn.",
                zh: "在这里记录信用卡分期和贷款。每月还款到期时会自动记为一笔支出。"
            ))
            .font(.appSecondary)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            Button(L10n.text(lang, en: "Add installment or loan", vi: "Thêm trả góp hoặc khoản vay", zh: "添加分期或贷款")) {
                CozyHaptics.medium()
                showingNewPlan = true
            }
            .pillButton(prominent: true)
            .padding(.top, 4)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.format(minor: minor, currency: settings.currency, language: settings.language)
    }
}
