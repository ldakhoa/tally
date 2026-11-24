import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct BudgetsView: View {
    public var embedded: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewBudget = false
    @State private var editingBudget: BudgetLimitRecord?

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        let lang = settings.language
        let snapshot = store.monthlySnapshot

        if embedded {
            content(snapshot: snapshot, lang: lang)
                .sheet(isPresented: $showingNewBudget) {
                    BudgetEditorSheet(existing: nil)
                }
                .sheet(item: $editingBudget) { budget in
                    BudgetEditorSheet(existing: budget)
                }
        } else {
            NavigationStack {
                ScrollView {
                    content(snapshot: snapshot, lang: lang)
                        .documentColumn(maxWidth: 1020)
                }
                .pageBackground()
                .navigationTitle(L10n.text(lang, en: "Budgets", vi: "Ngân sách", zh: "预算"))
                .toolbar { TopToolbarControls() }
                .sheet(isPresented: $showingNewBudget) {
                    BudgetEditorSheet(existing: nil)
                }
                .sheet(item: $editingBudget) { budget in
                    BudgetEditorSheet(existing: budget)
                }
            }
        }
    }

    private func content(snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let momentum = BudgetMomentum(
            snapshot: snapshot,
            todayKey: DateKey.dayKey(from: Date()),
            underBudgetMonthStreak: store.underBudgetMonthStreak
        )

        return VStack(alignment: .leading, spacing: 16) {
            PeriodHeaderBar {
                if !embedded {
                    Button {
                        CozyHaptics.medium()
                        showingNewBudget = true
                    } label: {
                        HStack(spacing: 6) {
                            CozyUIIcon(.plus, size: 14, color: Color.onInk)
                            Text(L10n.text(lang, en: "Set limit", vi: "Đặt hạn mức", zh: "设置预算"))
                        }
                    }
                    .pillButton(prominent: true)
                }
            }

            if momentum.pace != .noBudget {
                heroCard(momentum: momentum, lang: lang)
                    .cozyEntrance(index: 0)
            }

            if !snapshot.transactions.isEmpty || !snapshot.budgets.isEmpty {
                keptCard(snapshot: snapshot, lang: lang)
                    .cozyEntrance(index: 1)
            }

            if snapshot.budgets.isEmpty {
                EmptyStateCard(
                    symbol: "chart.pie",
                    title: L10n.text(lang, en: "No budgets for this month", vi: "Chưa đặt ngân sách tháng này", zh: "本月尚未设置预算"),
                    message: L10n.text(lang, en: "Set monthly limits per category like Food, Housing, or Shopping.", vi: "Đặt hạn mức tháng cho từng mục như Ăn uống, Nhà ở, Mua sắm.", zh: "为餐饮、住房、购物等分类设置每月预算限额。"),
                    actionTitle: embedded ? nil : L10n.text(lang, en: "Set a budget", vi: "Đặt ngân sách", zh: "设置预算")
                ) {
                    showingNewBudget = true
                }

                Button {
                    CozyHaptics.light()
                    _ = store.copyBudgetsFromPreviousMonth()
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.copy, size: 15, color: Color.textPrimary)
                        Text(L10n.text(lang, en: "Copy from previous month", vi: "Sao chép từ tháng trước", zh: "沿用上月预算"))
                    }
                }
                .blockButton(prominent: false)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(snapshot.budgets) { budget in
                        BudgetCategoryCard(
                            budget: budget,
                            spentMinor: snapshot.expensesByCategory[budget.category] ?? 0,
                            timing: momentum.timing,
                            daysLeft: momentum.daysLeft,
                            currency: settings.currency,
                            language: lang
                        ) {
                            CozyHaptics.light()
                            editingBudget = budget
                        }
                    }
                }
            }
        }
    }

    // MARK: - Hero: what is left, pace, streak

    private func heroCard(momentum: BudgetMomentum, lang: AppLanguage) -> some View {
        let style = BudgetPaceStyle(pace: momentum.pace)
        let currency = settings.currency
        let isOver = momentum.pace == .over
        let percentLeft = Int((momentum.leftFraction * 100).rounded(.down))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        CozyCoinView(size: 16)
                        Text(heroTitle(momentum: momentum, lang: lang))
                            .font(.appControl)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    CozyCountUpText(value: abs(momentum.leftMinor)) {
                        MoneyFormat.format(minor: $0, currency: currency, language: lang)
                    }
                    .font(.appMetricHero)
                    .foregroundStyle(isOver ? Color.negative : Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    HStack(spacing: 5) {
                        CozyUIIcon(style.glyph, size: 13, color: style.color)
                        Text(paceText(momentum: momentum, lang: lang))
                            .font(.appCaption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .foregroundStyle(style.color)
                    .background(style.color.opacity(0.14), in: Capsule())
                }

                Spacer(minLength: 4)

                CozyProgressRing(value: momentum.leftFraction, size: 88, lineWidth: 11, colors: style.ringColors) {
                    VStack(spacing: 0) {
                        Text("\(percentLeft)%")
                            .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                        Text(L10n.text(lang, en: "left", vi: "còn lại", zh: "剩余"))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text(lang, en: "\(percentLeft)% of budget left", vi: "Còn \(percentLeft)% ngân sách", zh: "预算剩余 \(percentLeft)%"))
            }

            HStack(spacing: 10) {
                CozyPetDuoView(mood: style.petMood, petSize: 34)
                Text(cheerText(pace: momentum.pace, lang: lang))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                if momentum.timing == .current, !isOver {
                    CozyStatTile(
                        value: MoneyFormat.format(minor: momentum.safeToSpendPerDayMinor, currency: currency, language: lang, compact: true),
                        label: L10n.text(lang, en: "per day · \(momentum.daysLeft)d left", vi: "mỗi ngày · còn \(momentum.daysLeft) ngày", zh: "每天可花 · 剩 \(momentum.daysLeft) 天"),
                        tint: .accent
                    ) {
                        CozyUIIcon(.calendar, size: 15, color: Color.accent)
                    }
                } else {
                    CozyStatTile(
                        value: MoneyFormat.format(minor: momentum.totalMinor, currency: currency, language: lang, compact: true),
                        label: L10n.text(lang, en: "total limit", vi: "tổng hạn mức", zh: "总限额"),
                        tint: .accent
                    ) {
                        CozyUIIcon(.calendar, size: 15, color: Color.accent)
                    }
                }

                CozyStatTile(
                    value: L10n.text(lang, en: "\(momentum.underBudgetMonthStreak) mo", vi: "\(momentum.underBudgetMonthStreak) tháng", zh: "\(momentum.underBudgetMonthStreak) 个月"),
                    label: momentum.underBudgetMonthStreak > 0
                        ? L10n.text(lang, en: "under-budget streak", vi: "chuỗi dưới ngân sách", zh: "连续未超支")
                        : L10n.text(lang, en: "finish under to start a streak", vi: "giữ tháng này để mở chuỗi", zh: "本月不超支即可开启连胜"),
                    tint: Color(hex: 0xEE7B2D)
                ) {
                    CozyStreakFlame(size: 16, isActive: momentum.underBudgetMonthStreak > 0)
                }

                CozyStatTile(
                    value: "\(momentum.categoriesOnTrack)/\(momentum.categoriesTotal)",
                    label: L10n.text(lang, en: "categories within limit", vi: "mục trong hạn mức", zh: "分类未超支"),
                    tint: .positive
                ) {
                    CozyUIIcon(.checkmarkCircle, size: 15, color: Color.positive)
                }
            }
        }
        .cozyHeroSurface(style.tone)
    }

    private func heroTitle(momentum: BudgetMomentum, lang: AppLanguage) -> String {
        if momentum.pace == .over {
            return L10n.text(lang, en: "Over budget by", vi: "Đã vượt ngân sách", zh: "已超出预算")
        }
        switch momentum.timing {
        case .past:
            return L10n.text(lang, en: "Kept under budget", vi: "Giữ lại được dưới ngân sách", zh: "预算内省下")
        case .current:
            return L10n.text(lang, en: "Left to spend this month", vi: "Còn tiêu được tháng này", zh: "本月还能花")
        case .future:
            return L10n.text(lang, en: "Budget ready to spend", vi: "Ngân sách sẵn sàng", zh: "预算已就绪")
        }
    }

    private func paceText(momentum: BudgetMomentum, lang: AppLanguage) -> String {
        let cushion = MoneyFormat.format(minor: abs(momentum.paceCushionMinor), currency: settings.currency, language: lang, compact: true)
        switch momentum.pace {
        case .ahead:
            return L10n.text(lang, en: "\(cushion) ahead of plan", vi: "Đi trước kế hoạch \(cushion)", zh: "领先计划 \(cushion)")
        case .onTrack:
            return L10n.text(lang, en: "Right on pace", vi: "Đúng nhịp kế hoạch", zh: "节奏刚刚好")
        case .behind:
            return L10n.text(lang, en: "\(cushion) faster than plan", vi: "Tiêu nhanh hơn kế hoạch \(cushion)", zh: "比计划多花 \(cushion)")
        case .over:
            return L10n.text(lang, en: "Time to slow down", vi: "Hãm phanh thôi nào", zh: "该踩刹车啦")
        case .finishedUnder:
            return L10n.text(lang, en: "Closed under budget", vi: "Chốt tháng dưới ngân sách", zh: "本月未超支")
        case .upcoming, .noBudget:
            return L10n.text(lang, en: "All set for the month", vi: "Sẵn sàng cho tháng mới", zh: "新的一月已就绪")
        }
    }

    private func cheerText(pace: BudgetMomentum.Pace, lang: AppLanguage) -> String {
        switch pace {
        case .ahead:
            return L10n.text(lang, en: "So good! That cushion can go straight into a goal", vi: "Giỏi quá! Phần dư này bỏ ống heo được đó", zh: "太棒了！多出来的可以存进目标")
        case .onTrack:
            return L10n.text(lang, en: "Steady hands. Keep this rhythm", vi: "Đều tay lắm, giữ nhịp này nha", zh: "很稳，保持这个节奏")
        case .behind:
            return L10n.text(lang, en: "A few light days and you're back on pace", vi: "Nhẹ tay vài hôm là về lại nhịp ngay", zh: "轻松几天就能回到节奏")
        case .over:
            return L10n.text(lang, en: "A little over. We'll win it back next month", vi: "Lố xíu rồi, tháng sau mình gỡ lại nha", zh: "稍微超了，下个月赢回来")
        case .finishedUnder:
            return L10n.text(lang, en: "What a clean finish!", vi: "Tháng này chốt đẹp quá!", zh: "这个月收得漂亮！")
        case .upcoming, .noBudget:
            return L10n.text(lang, en: "The plan is ready when you are", vi: "Kế hoạch sẵn sàng rồi nè", zh: "计划已备好，随时出发")
        }
    }

    // MARK: - Kept this month: the earn-more / keep-more ladder

    private func keptCard(snapshot: MonthlySnapshot, lang: AppLanguage) -> some View {
        let currency = settings.currency
        let hidden = snapshot.isSalaryMasked(hidden: settings.hideSalary)
        let level = SavingsLevel(incomeMinor: snapshot.incomeMinor, netSavingsMinor: snapshot.netSavingsMinor)
        let shownLevel = hidden ? nil : level
        let tierStyle = SavingsTierStyle(tier: shownLevel?.tier)

        return Card {
            HStack(spacing: 12) {
                tierStyle.sticker
                    .frame(width: 44, height: 44)
                    .background(tierStyle.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .strokeBorder(tierStyle.color.opacity(0.3), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(lang, en: "Kept this month", vi: "Giữ lại tháng này", zh: "本月留下"))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    if hidden {
                        Text(MoneyFormat.hiddenPlaceholder)
                            .font(.appMetric)
                            .salaryMaskAccessibility(true, language: lang)
                    } else {
                        CozyCountUpText(value: snapshot.netSavingsMinor) {
                            MoneyFormat.format(minor: $0, currency: currency, language: lang)
                        }
                        .font(.appMetric)
                        .foregroundStyle(snapshot.netSavingsMinor < 0 ? Color.negative : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    }
                }

                Spacer(minLength: 6)

                if let shownLevel {
                    VStack(alignment: .trailing, spacing: 4) {
                        Tag(
                            text: L10n.text(
                                lang,
                                en: "Lv \(shownLevel.tier.rawValue + 1) · \(tierStyle.title(in: lang))",
                                vi: "Cấp \(shownLevel.tier.rawValue + 1) · \(tierStyle.title(in: lang))",
                                zh: "\(shownLevel.tier.rawValue + 1) 级 · \(tierStyle.title(in: lang))"
                            ),
                            color: tierStyle.color
                        )
                        Text(L10n.text(lang, en: "\(shownLevel.ratePercent)% of income", vi: "\(shownLevel.ratePercent)% thu nhập", zh: "收入的 \(shownLevel.ratePercent)%"))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            if let shownLevel {
                CozyMilestoneBar(value: shownLevel.progressToNext, fill: tierStyle.color, milestones: [1], height: 10)
            }

            Text(keptHint(level: shownLevel, hidden: hidden, lang: lang))
                .font(.appCaption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keptHint(level: SavingsLevel?, hidden: Bool, lang: AppLanguage) -> String {
        if hidden {
            return L10n.text(lang, en: "Salary is hidden. Show it to see your level.", vi: "Đang ẩn lương. Hiện lương để xem cấp độ của bạn.", zh: "工资已隐藏，显示后可查看等级。")
        }
        guard let level else {
            return L10n.text(lang, en: "Log this month's first income to unlock your level.", vi: "Ghi khoản thu đầu tiên của tháng để mở cấp độ.", zh: "记下本月第一笔收入即可解锁等级。")
        }
        guard let next = level.nextTier else {
            return L10n.text(lang, en: "Top level. You keep more than half of what you earn!", vi: "Cấp cao nhất rồi! Bạn giữ được hơn nửa số tiền kiếm ra.", zh: "已是最高等级！你留下了一半以上的收入。")
        }
        let earn = MoneyFormat.format(minor: level.earnMoreMinor, currency: settings.currency, language: lang, compact: true)
        let cut = MoneyFormat.format(minor: level.spendLessMinor, currency: settings.currency, language: lang, compact: true)
        let nextTitle = SavingsTierStyle(tier: next).title(in: lang)
        return L10n.text(
            lang,
            en: "Earn \(earn) more, or spend \(cut) less, to reach \(nextTitle).",
            vi: "Kiếm thêm \(earn), hoặc bớt tiêu \(cut), là lên cấp \(nextTitle).",
            zh: "多赚 \(earn)，或少花 \(cut)，即可升到「\(nextTitle)」。"
        )
    }
}

// MARK: - Styles derived from the deterministic figures

private struct BudgetPaceStyle {
    let color: Color
    let ringColors: [Color]
    let glyph: CozyUIIconKind
    let petMood: PetMood
    let tone: CozyHeroTone

    init(pace: BudgetMomentum.Pace) {
        switch pace {
        case .ahead, .finishedUnder:
            color = .positive
            ringColors = [Color(hex: 0x9DE0B8), .positive]
            glyph = .trendUp
            petMood = .happy
            tone = .mint
        case .onTrack:
            color = .positive
            ringColors = [Color(hex: 0x9DE0B8), .positive]
            glyph = .checkmark
            petMood = .cozy
            tone = .mint
        case .behind:
            color = .caution
            ringColors = [Color(hex: 0xFFD966), .caution]
            glyph = .bolt
            petMood = .cozy
            tone = .honey
        case .over:
            color = .negative
            ringColors = [.negative, .negative]
            glyph = .warning
            petMood = .alert
            tone = .peach
        case .upcoming, .noBudget:
            color = .accent
            ringColors = [Color(hex: 0xFFD2D8), .accent]
            glyph = .sparkles
            petMood = .cozy
            tone = .peach
        }
    }
}

private struct SavingsTierStyle {
    let tier: SavingsLevel.Tier?

    var color: Color {
        switch tier {
        case nil: return .textSecondary
        case .starting: return .caution
        case .seed, .sprout: return .positive
        case .bloom: return .accent
        case .golden, .master: return Color(hex: 0xD6941E)
        }
    }

    @ViewBuilder var sticker: some View {
        switch tier {
        case nil: CozyUIIcon(.eyeClosed, size: 22, color: color)
        case .starting: CozyUIIcon(.bolt, size: 22, color: color)
        case .seed, .sprout: CozyUIIcon(.leaf, size: 24, color: color)
        case .bloom: CozyUIIcon(.sparkles, size: 24, color: color)
        case .golden: CozyCoinView(size: 28)
        case .master: CozyTrophyView(size: 30)
        }
    }

    func title(in lang: AppLanguage) -> String {
        switch tier {
        case nil: return ""
        case .starting: return L10n.text(lang, en: "Warming up", vi: "Khởi động", zh: "热身")
        case .seed: return L10n.text(lang, en: "Seed", vi: "Hạt mầm", zh: "种子")
        case .sprout: return L10n.text(lang, en: "Sprout", vi: "Chồi non", zh: "嫩芽")
        case .bloom: return L10n.text(lang, en: "Bloom", vi: "Ra hoa", zh: "开花")
        case .golden: return L10n.text(lang, en: "Golden piggy", vi: "Heo vàng", zh: "金猪")
        case .master: return L10n.text(lang, en: "Money master", vi: "Cao thủ giữ tiền", zh: "存钱高手")
        }
    }
}

// MARK: - Category card

private struct BudgetCategoryCard: View {
    let budget: BudgetLimitRecord
    let spentMinor: Int64
    let timing: BudgetMomentum.Timing
    let daysLeft: Int
    let currency: CurrencyCode
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        let lang = language
        let remaining = budget.limitMinor - spentMinor
        let ratio = Double(spentMinor) / Double(max(1, budget.limitMinor))
        let isOver = remaining < 0
        let isTight = !isOver && ratio > 0.85
        let stateColor: Color = isOver ? .negative : (isTight ? .caution : .positive)

        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    CategoryBadge(category: budget.category, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(budget.category.title(in: lang))
                            .font(.appHeading)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(money(spentMinor)) / \(money(budget.limitMinor))")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(money(abs(remaining)))
                            .font(.appAmount)
                            .foregroundStyle(stateColor)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        Text(isOver
                             ? L10n.text(lang, en: "over", vi: "vượt", zh: "超出")
                             : L10n.text(lang, en: "left", vi: "còn lại", zh: "剩余"))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                CozyMilestoneBar(
                    value: ratio,
                    fill: isOver ? .negative : (isTight ? .caution : budget.category.color),
                    height: 12,
                    animatesOnAppear: false
                )

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        CozyUIIcon(isOver ? .warning : (isTight ? .bolt : .checkmark), size: 12, color: stateColor)
                        Text(statusText(isOver: isOver, isTight: isTight, lang: lang))
                            .font(.appCaption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .foregroundStyle(stateColor)
                    .background(stateColor.opacity(0.13), in: Capsule())

                    Spacer(minLength: 4)

                    if timing == .current, remaining > 0, daysLeft > 0 {
                        Text(L10n.text(
                            lang,
                            en: "≈ \(money(remaining / Int64(daysLeft), compact: true)) / day",
                            vi: "≈ \(money(remaining / Int64(daysLeft), compact: true)) / ngày",
                            zh: "≈ 每天 \(money(remaining / Int64(daysLeft), compact: true))"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    } else {
                        Text("\(Int((ratio * 100).rounded(.down)))%")
                            .font(.appCaption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.cozyCard)
        .accessibilityHint(L10n.text(lang, en: "Edits this limit", vi: "Sửa hạn mức này", zh: "编辑此预算"))
    }

    private func statusText(isOver: Bool, isTight: Bool, lang: AppLanguage) -> String {
        if isOver { return L10n.text(lang, en: "Over the limit", vi: "Vượt hạn mức", zh: "已超支") }
        if spentMinor == budget.limitMinor { return L10n.text(lang, en: "Right at the limit", vi: "Vừa chạm trần", zh: "刚好用完") }
        if isTight { return L10n.text(lang, en: "Almost at the limit", vi: "Sắp chạm trần", zh: "快到上限") }
        if timing == .past { return L10n.text(lang, en: "Finished under", vi: "Chốt dưới hạn mức", zh: "未超支收官") }
        if spentMinor == 0 { return L10n.text(lang, en: "Untouched", vi: "Chưa đụng tới", zh: "还没动用") }
        return L10n.text(lang, en: "Under control", vi: "Trong tầm kiểm soát", zh: "尽在掌握")
    }

    private func money(_ minor: Int64, compact: Bool = false) -> String {
        MoneyFormat.format(minor: minor, currency: currency, language: language, compact: compact)
    }
}

public struct BudgetEditorSheet: View {
    let existing: BudgetLimitRecord?

    public init(existing: BudgetLimitRecord? = nil) {
        self.existing = existing
    }

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var category: CategoryID = .food
    @State private var keypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    public var body: some View {
        let lang = settings.language
        let liveAmount = resolvedLimitMajor
        let canSave = liveAmount > 0

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Hero amount stage
                        amountHeroStage(lang: lang)

                        HStack {
                            Text(DateKey.formatMonth(store.selectedMonth, language: lang))
                                .font(.appCaption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.softFill, in: Capsule())
                            Spacer()
                        }

                        if existing == nil {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(L10n.text(lang, en: "Category", vi: "Danh mục", zh: "分类"))
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                                    ForEach(availableCategories) { item in
                                        let selected = category == item
                                        Button {
                                            withAnimation(.snappy(duration: 0.16)) {
                                                category = item
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                CozyCategoryIcon(
                                                    category: item,
                                                    size: 18,
                                                    style: selected ? .tinted(Color.onInk) : .watercolor
                                                )
                                                Text(item.title(in: lang))
                                                    .font(.appCaption.weight(.medium))
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 10)
                                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                                            .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                            .background(selected ? Color.ink : Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                                        }
                                        .buttonStyle(.themedPlain)
                                    }
                                }
                            }
                        } else if let existing {
                            Card {
                                HStack(spacing: 12) {
                                    CategoryBadge(category: existing.category, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(existing.category.title(in: lang))
                                            .font(.appHeading)
                                        Text(L10n.text(lang, en: "Monthly spending limit", vi: "Hạn mức chi tiêu tháng", zh: "每月支出限额"))
                                            .font(.appCaption)
                                            .foregroundStyle(Color.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 14)
                }

                AmountKeypadView(
                    engine: $keypad,
                    currency: settings.currency,
                    language: lang,
                    saveTitle: saveButtonTitle(amountMajor: liveAmount, lang: lang),
                    isSaveEnabled: canSave,
                    onSave: save
                )
            }
            .pageBackground()
            .keypadKeyboardInput(engine: $keypad, isEnabled: true, isSaveEnabled: canSave, onSave: save)
            .cozySheetToolbar(title: existing == nil
                ? L10n.text(lang, en: "Set budget", vi: "Đặt ngân sách", zh: "设置预算")
                : L10n.text(lang, en: "Edit budget", vi: "Sửa ngân sách", zh: "编辑预算")) {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            } trailing: {
                if existing != nil {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        CozyUIIcon(.trash, size: 18, color: Color.negative)
                    }
                    .accessibilityLabel(L10n.text(lang, en: "Remove budget", vi: "Xoá hạn mức", zh: "删除预算"))
                }
            }
            .confirmationDialog(
                L10n.text(lang, en: "Remove this budget?", vi: "Xoá hạn mức này?", zh: "删除此预算？"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.text(lang, en: "Remove budget", vi: "Xoá hạn mức", zh: "删除预算"), role: .destructive) {
                    if let existing { store.deleteBudget(id: existing.id) }
                    dismiss()
                }
            }
            .onAppear {
                let maxDigits = settings.currency.fractionDigits
                if let existing {
                    category = existing.category
                    let major = settings.currency.toMajor(existing.limitMinor)
                    keypad = AmountKeypadEngine(initialAmountMajor: major, maxFractionDigits: maxDigits)
                } else {
                    keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: maxDigits)
                    if let first = availableCategories.first {
                        category = first
                    }
                }
            }
        }
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 640)
    }

    private func amountHeroStage(lang: AppLanguage) -> some View {
        let currency = settings.currency
        let displayNumber = keypad.formattedDisplayNumber(currency: currency)
        let isEmpty = keypad.isEmpty
        let amountColor: Color = isEmpty ? Color.textSecondary.opacity(0.38) : Color.textPrimary

        return VStack(spacing: 4) {
            if keypad.hasOperator {
                HStack(spacing: 6) {
                    Text(keypad.formattedExpression)
                        .font(.appCaption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                    Text("=")
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.softFill, in: Capsule())
            } else {
                Text(L10n.text(lang, en: "Monthly limit (\(currency.rawValue))", vi: "Hạn mức tháng (\(currency.rawValue))", zh: "每月限额（\(currency.rawValue)）"))
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if currency != .vnd {
                    Text(currency.narrowSymbol)
                        .font(.custom("AvenirNext-Medium", size: 26))
                        .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                }
                Text(displayNumber)
                    .font(.custom("AvenirNext-DemiBold", size: 42).monospacedDigit())
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
                    .contentTransition(.numericText())
                if currency == .vnd {
                    Text("₫")
                        .font(.custom("AvenirNext-Medium", size: 26))
                        .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : amountColor.opacity(0.75))
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var resolvedLimitMajor: Double {
        max(0, keypad.evaluatedValue ?? 0)
    }

    private func saveButtonTitle(amountMajor: Double, lang: AppLanguage) -> String {
        guard amountMajor > 0 else {
            return L10n.text(lang, en: "Save budget", vi: "Lưu hạn mức", zh: "保存预算")
        }
        let formatted = MoneyFormat.format(
            minor: settings.currency.toStorageMinor(amountMajor),
            currency: settings.currency,
            language: lang
        )
        return L10n.text(lang, en: "Save · \(formatted)", vi: "Lưu · \(formatted)", zh: "保存 · \(formatted)")
    }

    private var availableCategories: [CategoryID] {
        let taken = Set(store.monthlySnapshot.budgets.map(\.category))
        let free = CategoryID.expenseCategories.filter { !taken.contains($0) }
        return free.isEmpty ? CategoryID.expenseCategories : free
    }

    private func save() {
        let major = resolvedLimitMajor
        guard major > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter a valid limit.", vi: "Nhập hạn mức hợp lệ.", zh: "请输入有效的预算金额。")
            return
        }
        let record = BudgetLimitRecord(
            monthKey: store.selectedMonth,
            category: existing?.category ?? category,
            limitMinor: settings.currency.toStorageMinor(major)
        )
        store.saveBudget(record)
        dismiss()
    }
}
