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
        let freedom = DebtFreedom(overview: overview, todayKey: todayKey)

        return VStack(alignment: .leading, spacing: 16) {
            if overview.isEmpty {
                emptyState(lang: lang)
            } else {
                if !embedded || freedom.completedCount > 0 {
                    addButtonRow(freedom: freedom, lang: lang)
                }
                if overview.active.isEmpty {
                    debtFreeCard(lang: lang)
                        .cozyEntrance(index: 0)
                } else {
                    summaryCard(overview: overview, freedom: freedom, lang: lang)
                        .cozyEntrance(index: 0)
                }
                if freedom.releasedMonthlyMinor > 0 || freedom.nextPayoffMilestone != nil {
                    monthlyReliefCard(freedom: freedom, lang: lang)
                }
                if !overview.active.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                        ForEach(overview.active) { entry in
                            planCard(entry: entry, lang: lang)
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

    /// The page title already says "Commitments", so the row carries the trophy count and the add button.
    private func addButtonRow(freedom: DebtFreedom, lang: AppLanguage) -> some View {
        HStack(spacing: 8) {
            if freedom.completedCount > 0 {
                HStack(spacing: 5) {
                    CozyTrophyView(size: 16)
                    Text(L10n.text(
                        lang,
                        en: "\(freedom.completedCount) paid off",
                        vi: "Đã trả xong \(freedom.completedCount) khoản",
                        zh: "已还清 \(freedom.completedCount) 笔"
                    ))
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if !embedded {
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
    }

    /// Hero: how far along the road to debt-free, when it ends and what it gives back.
    private func summaryCard(overview: CommitmentsOverview, freedom: DebtFreedom, lang: AppLanguage) -> some View {
        let percent = Int((freedom.fraction * 100).rounded(.down))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        CozyUIIcon(.checkmarkCircle, size: 16, color: Color.positive)
                        Text(L10n.text(lang, en: "Paid off so far", vi: "Đã trả được", zh: "已还金额"))
                            .font(.appControl)
                            .foregroundStyle(Color.textSecondary)
                    }

                    CozyCountUpText(value: freedom.paidMinor) { money($0) }
                        .font(.appMetricHero)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if let debtFreeDay = freedom.debtFreeDayKey {
                        HStack(spacing: 5) {
                            CozyUIIcon(.calendar, size: 13, color: Color.caution)
                            Text(debtFreeText(dayKey: debtFreeDay, months: freedom.monthsUntilDebtFree, lang: lang))
                                .font(.appCaption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.caution)
                        .background(Color.caution.opacity(0.15), in: Capsule())
                    }
                }

                Spacer(minLength: 4)

                CozyProgressRing(
                    value: freedom.fraction,
                    size: 88,
                    lineWidth: 11,
                    colors: [Color(hex: 0xFFD966), Color(hex: 0xE89A2B)]
                ) {
                    VStack(spacing: 0) {
                        Text("\(percent)%")
                            .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                        Text(L10n.text(lang, en: "debt-free", vi: "hết nợ", zh: "无债"))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text(lang, en: "\(percent)% of the way to debt-free", vi: "Đã đi \(percent)% chặng đường hết nợ", zh: "距离无债已完成 \(percent)%"))
            }

            HStack(alignment: .top, spacing: 8) {
                CozyStatTile(
                    value: money(overview.committedThisMonthMinor, compact: true),
                    label: L10n.text(lang, en: "due this month", vi: "phải trả tháng này", zh: "本月应还"),
                    tint: .accent
                ) {
                    CozyUIIcon(.creditCard, size: 15, color: Color.accent)
                }

                CozyStatTile(
                    value: money(freedom.remainingMinor, compact: true),
                    label: L10n.text(lang, en: "left to pay", vi: "dư nợ còn lại", zh: "剩余债务"),
                    tint: .caution
                ) {
                    CozyUIIcon(.trendDown, size: 15, color: Color.caution)
                }

                if freedom.freedMonthlyMinor > 0 {
                    CozyStatTile(
                        value: "+\(money(freedom.freedMonthlyMinor, compact: true))",
                        label: L10n.text(lang, en: "more per month after all payoffs", vi: "dư thêm mỗi tháng khi hết nợ", zh: "全部还清后每月多出"),
                        tint: .positive
                    ) {
                        CozyCoinView(size: 15)
                    }
                }
            }
        }
        .cozyHeroSurface(.honey)
    }

    private func monthlyReliefCard(freedom: DebtFreedom, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(L10n.text(lang, en: "More room to save", vi: "Dư thêm để tiết kiệm", zh: "每月多一点储蓄空间"))
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                CozyCoinView(size: 22)
            }
            .accessibilityAddTraits(.isHeader)

            if freedom.releasedMonthlyMinor > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthlyAmount(freedom.releasedMonthlyMinor, lang: lang))
                        .font(.appAmount)
                        .monospacedDigit()
                        .foregroundStyle(Color.positive)
                    Text(L10n.text(lang, en: "Already freed up by paid-off plans", vi: "Đã dư ra nhờ các khoản trả xong", zh: "已还清的分期和贷款腾出的金额"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let milestone = freedom.nextPayoffMilestone {
                let month = DateKey.formatMonth(milestone.monthKey, language: lang)
                VStack(alignment: .leading, spacing: 5) {
                    Label {
                        Text(L10n.text(lang, en: "Expected payoff in \(month)", vi: "Dự kiến trả xong vào \(month)", zh: "预计于\(month)还清"))
                    } icon: {
                        CozyUIIcon(.calendar, size: 14, color: Color.positive)
                    }
                    .font(.appCaption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                    Text(monthlyAmount(milestone.monthlyReliefMinor, lang: lang))
                        .font(.appAmount)
                        .monospacedDigit()
                        .foregroundStyle(Color.positive)
                    Text(milestone.planNames.formatted(.list(type: .and).locale(lang.locale)))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            }
        }
        .cozyHeroSurface(.mint)
    }

    private func monthlyAmount(_ minor: Int64, lang: AppLanguage) -> String {
        let amount = money(minor)
        return L10n.text(lang, en: "+\(amount) per month", vi: "+\(amount) mỗi tháng", zh: "每月多出 \(amount)")
    }

    /// Shown when every plan is finished.
    private func debtFreeCard(lang: AppLanguage) -> some View {
        HStack(spacing: 14) {
            CozyTrophyView(size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text(lang, en: "Debt-free!", vi: "Hết nợ rồi!", zh: "无债一身轻！"))
                    .font(.appSection)
                    .foregroundStyle(Color.textPrimary)
                Text(L10n.text(
                    lang,
                    en: "Every plan is paid off. Everything you earn now is yours to keep.",
                    vi: "Mọi khoản đã trả xong. Từ giờ kiếm được bao nhiêu là của mình bấy nhiêu.",
                    zh: "所有计划都已还清，现在赚的每一分都属于你。"
                ))
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .cozyHeroSurface(.mint)
    }

    private func debtFreeText(dayKey: String, months: Int, lang: AppLanguage) -> String {
        let month = DateKey.formatMonth(DateKey.monthKey(fromDayKey: dayKey), language: lang)
        if months <= 0 {
            return L10n.text(lang, en: "Debt-free this month", vi: "Hết nợ ngay tháng này", zh: "本月即可无债")
        }
        return L10n.text(
            lang,
            en: "Debt-free \(month) · \(months) mo to go",
            vi: "Hết nợ \(month) · còn \(months) tháng",
            zh: "\(month) 无债 · 还有 \(months) 个月"
        )
    }

    // MARK: Plan rows

    private func planCard(entry: CommitmentsOverview.Entry, lang: AppLanguage) -> some View {
        let plan = entry.plan
        let progress = entry.progress
        let monthly = plan.fullSchedule.first?.amountMinor ?? 0
        let paymentsLeft = DebtFreedom.paymentsLeft(progress)

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

                CozyPaymentDots(
                    total: progress.paymentCount,
                    paid: progress.paidCount,
                    fill: paymentsLeft <= 2 ? Color.positive : Color.accent,
                    animatesOnAppear: false
                )

                HStack(spacing: 6) {
                    if paymentsLeft <= 2 {
                        HStack(spacing: 4) {
                            CozyUIIcon(.sparkles, size: 12, color: Color.positive)
                            Text(paymentsLeft <= 1
                                 ? L10n.text(lang, en: "Last payment!", vi: "Kỳ cuối rồi!", zh: "最后一期！")
                                 : L10n.text(lang, en: "Almost done", vi: "Sắp xong rồi", zh: "快还清了"))
                        }
                        .font(.appCaption.weight(.semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .foregroundStyle(Color.positive)
                        .background(Color.positive.opacity(0.13), in: Capsule())
                    } else {
                        Text(L10n.text(
                            lang,
                            en: "\(progress.paidCount)/\(progress.paymentCount) paid · \(paymentsLeft) to go",
                            vi: "Đã trả \(progress.paidCount)/\(progress.paymentCount) · còn \(paymentsLeft) kỳ",
                            zh: "已还 \(progress.paidCount)/\(progress.paymentCount) · 剩 \(paymentsLeft) 期"
                        ))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
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
        .buttonStyle(.cozyCard)
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
                    .overlay(alignment: .bottomTrailing) {
                        CozyTrophyView(size: 18)
                            .offset(x: 6, y: 5)
                    }
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
            if !embedded {
                Button(L10n.text(lang, en: "Add installment or loan", vi: "Thêm trả góp hoặc khoản vay", zh: "添加分期或贷款")) {
                    CozyHaptics.medium()
                    showingNewPlan = true
                }
                .pillButton(prominent: true)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func money(_ minor: Int64, compact: Bool = false) -> String {
        MoneyFormat.format(minor: minor, currency: settings.currency, language: settings.language, compact: compact)
    }
}
