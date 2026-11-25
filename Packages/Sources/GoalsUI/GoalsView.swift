import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct GoalsView: View {
    public var embedded: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewGoal = false
    @State private var editingGoal: SavingsGoalRecord?
    @State private var contributingGoal: SavingsGoalRecord?

    public init(embedded: Bool = false) {
        self.embedded = embedded
    }

    public var body: some View {
        let lang = settings.language
        let goals = store.activeGoals
        let totalSaved = goals.reduce(Int64(0)) { $0 + $1.savedMinor }
        let totalTarget = goals.reduce(Int64(0)) { $0 + $1.targetMinor }

        if embedded {
            content(goals: goals, totalSaved: totalSaved, totalTarget: totalTarget, lang: lang)
                .sheet(isPresented: $showingNewGoal) {
                    GoalEditorSheet(existing: nil)
                }
                .sheet(item: $editingGoal) { goal in
                    GoalEditorSheet(existing: goal)
                }
                .sheet(item: $contributingGoal) { goal in
                    ContributionSheet(goal: goal)
                }
        } else {
            NavigationStack {
                ScrollView {
                    content(goals: goals, totalSaved: totalSaved, totalTarget: totalTarget, lang: lang)
                        .documentColumn(maxWidth: 1020)
                }
                .pageBackground()
                .navigationTitle(L10n.text(lang, en: "Goals", vi: "Mục tiêu", zh: "存钱目标"))
                .sheet(isPresented: $showingNewGoal) {
                    GoalEditorSheet(existing: nil)
                }
                .sheet(item: $editingGoal) { goal in
                    GoalEditorSheet(existing: goal)
                }
                .sheet(item: $contributingGoal) { goal in
                    ContributionSheet(goal: goal)
                }
            }
        }
    }

    private func content(goals: [SavingsGoalRecord], totalSaved: Int64, totalTarget: Int64, lang: AppLanguage) -> some View {
        let journey = GoalsJourney(goals: goals)

        return VStack(alignment: .leading, spacing: 16) {
            if goals.isEmpty {
                EmptyStateCard(
                    symbol: "target",
                    title: L10n.text(lang, en: "No savings goals yet", vi: "Chưa có mục tiêu tiết kiệm", zh: "暂无存钱目标"),
                    message: L10n.text(lang, en: "Create shared goals like an emergency fund, family trip, or home upgrade.", vi: "Tạo mục tiêu chung như quỹ dự phòng, du lịch gia đình hay mua sắm lớn.", zh: "创建共同存钱目标，例如应急基金、家庭旅行或家居升级。"),
                    actionTitle: embedded ? nil : L10n.text(lang, en: "Create goal", vi: "Tạo mục tiêu", zh: "创建目标")
                ) {
                    showingNewGoal = true
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        CozyStarShape()
                            .fill(Color(hex: 0xF2A92C))
                            .frame(width: 14, height: 14)
                        Text(L10n.text(
                            lang,
                            en: "\(journey.starsEarned)/\(journey.starsTotal) stars collected",
                            vi: "Đã gom \(journey.starsEarned)/\(journey.starsTotal) sao",
                            zh: "已收集 \(journey.starsEarned)/\(journey.starsTotal) 颗星"
                        ))
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .contentTransition(.numericText())
                    }
                    Spacer(minLength: 8)
                    if !embedded {
                        Button {
                            CozyHaptics.medium()
                            showingNewGoal = true
                        } label: {
                            HStack(spacing: 6) {
                                CozyUIIcon(.plus, size: 14, color: Color.onInk)
                                Text(L10n.text(lang, en: "New goal", vi: "Thêm mục tiêu", zh: "新建目标"))
                            }
                        }
                        .pillButton(prominent: true)
                    }
                }

                heroCard(journey: journey, lang: lang)
                    .cozyEntrance(index: 0)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)], spacing: 14) {
                    ForEach(goals) { goal in
                        GoalJourneyCard(
                            goal: goal,
                            currency: settings.currency,
                            language: lang,
                            onContribute: {
                                CozyHaptics.medium()
                                contributingGoal = goal
                            },
                            onEdit: { editingGoal = goal }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Hero: everything saved so far

    private func heroCard(journey: GoalsJourney, lang: AppLanguage) -> some View {
        let percent = Int((journey.fraction * 100).rounded(.down))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        CozyCoinView(size: 16)
                        Text(L10n.text(lang, en: "Total saved", vi: "Tổng đã tiết kiệm", zh: "已累计存款"))
                            .font(.appControl)
                            .foregroundStyle(Color.textSecondary)
                    }

                    CozyCountUpText(value: settings.displayMinor(journey.totalSavedMinor)) {
                        MoneyFormat.format(minor: $0, currency: settings.effectiveDisplayCurrency, language: lang)
                    }
                    .font(.appMetricHero)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                    Text("\(L10n.text(lang, en: "of", vi: "trên", zh: "目标")) \(settings.formatMoney(minor: journey.totalTargetMinor))")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 4)

                CozyProgressRing(
                    value: journey.fraction,
                    size: 88,
                    lineWidth: 11,
                    colors: [Color(hex: 0x9DE0B8), .positive]
                ) {
                    VStack(spacing: 0) {
                        Text("\(percent)%")
                            .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                        Text(L10n.text(lang, en: "there", vi: "chặng đường", zh: "已完成"))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text(lang, en: "\(percent)% of all goals saved", vi: "Đã tiết kiệm \(percent)% tổng mục tiêu", zh: "已存到全部目标的 \(percent)%"))
            }

            HStack(alignment: .top, spacing: 8) {
                CozyStatTile(
                    value: "\(journey.completedCount)",
                    label: L10n.text(lang, en: "goals completed", vi: "mục tiêu đã về đích", zh: "已达成目标"),
                    tint: Color(hex: 0xD6941E)
                ) {
                    CozyTrophyView(size: 18)
                }

                if let closest = journey.closest {
                    CozyStatTile(
                        value: settings.formatMoney(
                            minor: max(0, closest.targetMinor - closest.savedMinor),
                            compact: true
                        ),
                        label: L10n.text(
                            lang,
                            en: "to finish \(closest.name)",
                            vi: "nữa là xong \(closest.name)",
                            zh: "即可完成「\(closest.name)」"
                        ),
                        tint: .positive
                    ) {
                        CozyGoalIcon(goal: closest.icon, size: 16, style: .watercolor)
                    }
                } else {
                    CozyStatTile(
                        value: L10n.text(lang, en: "All done", vi: "Xong hết", zh: "全部达成"),
                        label: L10n.text(lang, en: "time for a new dream", vi: "đặt ước mơ mới thôi", zh: "该定个新梦想了"),
                        tint: .positive
                    ) {
                        CozyUIIcon(.sparkles, size: 15, color: Color.positive)
                    }
                }
            }
        }
        .cozyHeroSurface(.mint)
    }
}

// MARK: - Goal card: ring, milestone stars, celebration

private struct GoalJourneyCard: View {
    @Environment(AppSettings.self) private var settings

    let goal: SavingsGoalRecord
    let currency: CurrencyCode
    let language: AppLanguage
    let onContribute: () -> Void
    let onEdit: () -> Void

    @State private var burstTrigger = 0
    @State private var milestoneToast: Int?
    @State private var toastToken = 0

    var body: some View {
        let lang = language
        let milestones = GoalMilestones(goal: goal)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let gold = Color(hex: 0xD6941E)

        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                CozyProgressRing(
                    value: goal.progress,
                    size: 58,
                    lineWidth: 5,
                    colors: milestones.isComplete ? [Color(hex: 0xFFD966), gold] : [goal.icon.color.opacity(0.55), goal.icon.color],
                    animatesOnAppear: false
                ) {
                    GoalBadge(icon: goal.icon, size: 38)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(.appHeading)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(money(goal.savedMinor)) / \(money(goal.targetMinor))")
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                if milestones.isComplete {
                    CozyTrophyView(size: 34)
                } else {
                    Text("\(goal.percent)%")
                        .font(.system(size: 21, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(goal.icon.color)
                        .contentTransition(.numericText())
                }
            }

            CozyMilestoneBar(
                value: goal.progress,
                fill: milestones.isComplete ? gold : goal.icon.color,
                milestones: GoalMilestones.steps.map { Double($0) / 100 },
                height: 12,
                animatesOnAppear: false
            )

            Text(statusLine(milestones: milestones, lang: lang))
                .font(.appCaption.weight(.medium))
                .foregroundStyle(milestones.isComplete ? gold : Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if !milestones.isComplete {
                    Button(action: onContribute) {
                        HStack(spacing: 6) {
                            CozyCoinView(size: 15)
                            Text(L10n.text(lang, en: "Contribute", vi: "Góp thêm", zh: "存入一笔"))
                        }
                    }
                    .pillButton(prominent: true)
                }

                Button(L10n.text(lang, en: "Edit", vi: "Sửa", zh: "编辑"), action: onEdit)
                    .pillButton()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .overlay {
            if milestones.isComplete {
                shape.strokeBorder(Color(hex: 0xF5B959, alpha: 0.75), lineWidth: 1.5)
            }
        }
        .overlay(alignment: .top) {
            if let milestoneToast {
                milestoneBanner(percent: milestoneToast, lang: lang)
                    .offset(y: -14)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .overlay {
            CozyCoinBurstOverlay(trigger: burstTrigger, coinCount: 14)
        }
        .onChange(of: goal.savedMinor) { oldValue, newValue in
            guard newValue > oldValue else { return }
            let before = GoalMilestones.reachedCount(savedMinor: oldValue, targetMinor: goal.targetMinor)
            let after = GoalMilestones.reachedCount(savedMinor: newValue, targetMinor: goal.targetMinor)
            // The contribution sheet is still sliding away: celebrate once the card is in view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                burstTrigger += 1
                if after > before {
                    showMilestone(GoalMilestones.steps[after - 1])
                }
            }
        }
    }

    private func showMilestone(_ percent: Int) {
        toastToken += 1
        let token = toastToken
        withAnimation(.spring(response: 0.42, dampingFraction: 0.55).delay(0.25)) {
            milestoneToast = percent
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard token == toastToken else { return }
            withAnimation(.easeOut(duration: 0.3)) { milestoneToast = nil }
        }
    }

    private func milestoneBanner(percent: Int, lang: AppLanguage) -> some View {
        HStack(spacing: 6) {
            CozyStarShape()
                .fill(Color(hex: 0xFFD966))
                .frame(width: 15, height: 15)
            Text(percent >= 100
                 ? L10n.text(lang, en: "Goal complete!", vi: "Về đích rồi!", zh: "目标达成！")
                 : L10n.text(lang, en: "\(percent)% milestone reached!", vi: "Chạm mốc \(percent)%!", zh: "达到 \(percent)% 里程碑！"))
                .font(.appControl)
                .foregroundStyle(Color.onInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.ink, in: Capsule())
        .floatingShadow()
        .accessibilityAddTraits(.isStaticText)
    }

    private func statusLine(milestones: GoalMilestones, lang: AppLanguage) -> String {
        guard let next = milestones.nextStepPercent else {
            return L10n.text(lang, en: "Goal complete. You earned this one!", vi: "Đã về đích. Thành quả của bạn đó!", zh: "目标达成，这是你挣来的！")
        }
        let amount = money(milestones.toNextMinor)
        if next >= 100 {
            return L10n.text(lang, en: "\(amount) more and it's yours", vi: "Còn \(amount) nữa là về đích", zh: "再存 \(amount) 就达成")
        }
        return L10n.text(lang, en: "\(amount) to the \(next)% star", vi: "Còn \(amount) nữa là chạm sao \(next)%", zh: "再存 \(amount) 点亮 \(next)% 星")
    }

    private func money(_ minor: Int64) -> String {
        settings.formatMoney(minor: minor)
    }
}

public struct GoalEditorSheet: View {
    let existing: SavingsGoalRecord?

    public init(existing: SavingsGoalRecord? = nil) {
        self.existing = existing
    }

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum AmountField { case target, saved }

    @State private var name = ""
    @State private var icon: GoalIcon = .target
    @State private var targetKeypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var savedKeypad = AmountKeypadEngine(maxFractionDigits: 2)
    @State private var activeAmountField: AmountField = .target
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    @FocusState private var isNameFocused: Bool

    public var body: some View {
        let lang = settings.language
        let targetMajor = max(0, targetKeypad.evaluatedValue ?? 0)
        let canSave = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && targetMajor > 0

        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(L10n.text(lang, en: "Goal name", vi: "Tên mục tiêu", zh: "目标名称"))
                            TextField(L10n.text(lang, en: "e.g. Emergency fund, Japan trip", vi: "VD: Quỹ dự phòng, Du lịch Nhật", zh: "例如：应急基金、日本旅行"), text: $name)
                                .focused($isNameFocused)
                                .submitLabel(.done)
                                .onSubmit { isNameFocused = false }
                                .tallyField()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(L10n.text(lang, en: "Icon", vi: "Biểu tượng", zh: "图标"))
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(GoalIcon.allCases) { item in
                                        let selected = icon == item
                                        Button {
                                            CozyHaptics.selection()
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                                icon = item
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                CozyGoalIcon(
                                                    goal: item,
                                                    size: 18,
                                                    style: selected ? .tinted(Color.onInk) : .watercolor
                                                )
                                                Text(item.title(in: lang))
                                                    .font(.appControl)
                                                    .lineLimit(1)
                                            }
                                            .padding(.horizontal, 12)
                                            .frame(minHeight: 36)
                                            .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                            .background(selected ? Color.ink : Color.cardBackground, in: Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(selected ? Color.clear : Color.hairlineStrong, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.themedPlain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Custom-keypad amount fields (no iOS numeric keypad)
                        HStack(spacing: 10) {
                            amountFieldTile(
                                title: L10n.text(lang, en: "Target (\(settings.currency.rawValue))", vi: "Mục tiêu (\(settings.currency.rawValue))", zh: "目标金额（\(settings.currency.rawValue)）"),
                                engine: targetKeypad,
                                isActive: !isNameFocused && activeAmountField == .target
                            ) {
                                isNameFocused = false
                                withAnimation(.snappy(duration: 0.16)) {
                                    activeAmountField = .target
                                }
                            }

                            amountFieldTile(
                                title: L10n.text(lang, en: "Already saved", vi: "Đã tiết kiệm", zh: "已存入"),
                                engine: savedKeypad,
                                isActive: !isNameFocused && activeAmountField == .saved
                            ) {
                                isNameFocused = false
                                withAnimation(.snappy(duration: 0.16)) {
                                    activeAmountField = .saved
                                }
                            }
                        }

                        if settings.isConvertingDisplay {
                            let savedMajor = max(0, savedKeypad.evaluatedValue ?? 0)
                            if targetMajor > 0 || savedMajor > 0 {
                                HStack(spacing: 12) {
                                    if targetMajor > 0 {
                                        Text("≈ \(settings.formatMoney(minor: settings.currency.toStorageMinor(targetMajor)))")
                                    }
                                    Spacer(minLength: 4)
                                    if savedMajor > 0 {
                                        Text("≈ \(settings.formatMoney(minor: settings.currency.toStorageMinor(savedMajor)))")
                                    }
                                }
                                .font(.appCaption)
                                .monospacedDigit()
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 4)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                }
                .scrollDismissesKeyboard(.interactively)

                if !isNameFocused {
                    AmountKeypadView(
                        engine: activeKeypadBinding,
                        currency: settings.currency,
                        language: lang,
                        saveTitle: L10n.text(lang, en: "Save goal", vi: "Lưu mục tiêu", zh: "保存目标"),
                        isSaveEnabled: canSave,
                        onSave: save
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    HStack(spacing: 10) {
                        Button {
                            isNameFocused = false
                        } label: {
                            CozyUIIcon(.keypad, size: 19, color: Color.textPrimary)
                                .frame(width: 44, height: 44)
                                .background(Color.softFill, in: Circle())
                        }
                        .buttonStyle(.themedPlain)
                        .accessibilityLabel(L10n.text(lang, en: "Show number keypad", vi: "Mở bàn phím số", zh: "显示数字键盘"))

                        Button(L10n.text(lang, en: "Save goal", vi: "Lưu mục tiêu", zh: "保存目标"), action: save)
                            .blockButton(prominent: true)
                            .disabled(!canSave)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Color.appBackground
                            .overlay(alignment: .top) { Divider().overlay(Color.hairline) }
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .animation(.snappy(duration: 0.22), value: isNameFocused)
            .pageBackground()
            .keypadKeyboardInput(engine: activeKeypadBinding, isEnabled: !isNameFocused, isSaveEnabled: canSave, onSave: save)
            .cozySheetToolbar(title: existing == nil
                ? L10n.text(lang, en: "New goal", vi: "Mục tiêu mới", zh: "新建目标")
                : L10n.text(lang, en: "Edit goal", vi: "Sửa mục tiêu", zh: "编辑目标")) {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            } trailing: {
                if isNameFocused {
                    Button(L10n.text(lang, en: "Keypad", vi: "Bàn phím số", zh: "数字键盘")) {
                        isNameFocused = false
                    }
                    .font(.appControl)
                } else if existing != nil {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        CozyUIIcon(.trash, size: 18, color: Color.negative)
                    }
                    .accessibilityLabel(L10n.text(lang, en: "Delete goal", vi: "Xoá mục tiêu", zh: "删除目标"))
                }
            }
            .confirmationDialog(
                L10n.text(lang, en: "Delete this savings goal?", vi: "Xoá mục tiêu tiết kiệm này?", zh: "删除此存钱目标？"),
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button(L10n.text(lang, en: "Delete goal", vi: "Xoá mục tiêu", zh: "删除目标"), role: .destructive) {
                    if let existing { store.deleteGoal(id: existing.id) }
                    dismiss()
                }
            }
            .onAppear {
                let maxDigits = settings.currency.fractionDigits
                if let existing {
                    name = existing.name
                    icon = existing.icon
                    targetKeypad = AmountKeypadEngine(initialAmountMajor: settings.currency.toMajor(existing.targetMinor), maxFractionDigits: maxDigits)
                    let savedMajor = settings.currency.toMajor(existing.savedMinor)
                    savedKeypad = AmountKeypadEngine(initialAmountMajor: savedMajor > 0 ? savedMajor : nil, maxFractionDigits: maxDigits)
                } else {
                    targetKeypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: maxDigits)
                    savedKeypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: maxDigits)
                }
            }
        }
        .cozySheetFrame(minWidth: 440, idealWidth: 480, minHeight: 560, idealHeight: 640)
    }

    private var activeKeypadBinding: Binding<AmountKeypadEngine> {
        Binding(
            get: { activeAmountField == .target ? targetKeypad : savedKeypad },
            set: { newValue in
                if activeAmountField == .target {
                    targetKeypad = newValue
                } else {
                    savedKeypad = newValue
                }
            }
        )
    }

    private func amountFieldTile(
        title: String,
        engine: AmountKeypadEngine,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let currency = settings.currency
        let display = engine.formattedDisplayNumber(currency: currency)
        let isEmpty = engine.isEmpty

        return Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.appCaption.weight(.semibold))
                        .foregroundStyle(isActive ? Color.accent : Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if isActive {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 6, height: 6)
                    }
                }

                if engine.hasOperator {
                    Text(engine.formattedExpression)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if currency != .vnd {
                        Text(currency.narrowSymbol)
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text(display)
                        .font(.appMetric)
                        .monospacedDigit()
                        .foregroundStyle(isEmpty ? Color.textSecondary.opacity(0.45) : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .contentTransition(.numericText())
                    if currency == .vnd {
                        Text("₫")
                            .font(.appCaption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? Color.ink : Color.hairline, lineWidth: isActive ? 1.8 : 1)
            )
        }
        .buttonStyle(.themedPlain)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.text(settings.language, en: "Enter a goal name.", vi: "Nhập tên mục tiêu.", zh: "请输入目标名称。")
            return
        }
        let target = max(0, targetKeypad.evaluatedValue ?? 0)
        let saved = max(0, savedKeypad.evaluatedValue ?? 0)
        guard target > 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter a valid target amount.", vi: "Nhập số tiền mục tiêu hợp lệ.", zh: "请输入有效的目标金额。")
            return
        }
        let record = SavingsGoalRecord(
            id: existing?.id ?? UUID().uuidString,
            name: trimmed,
            icon: icon,
            targetMinor: settings.currency.toStorageMinor(target),
            savedMinor: settings.currency.toStorageMinor(saved)
        )
        store.saveGoal(record)
        dismiss()
    }
}

private struct ContributionSheet: View {
    let goal: SavingsGoalRecord

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var keypad = AmountKeypadEngine(maxFractionDigits: 2)

    var body: some View {
        let lang = settings.language
        let currency = settings.currency
        let amountMajor = max(0, keypad.evaluatedValue ?? 0)
        let canSave = amountMajor > 0

        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        GoalBadge(icon: goal.icon, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.appHeading)
                            Text("\(MoneyFormat.format(minor: goal.savedMinor, currency: currency, language: lang)) / \(MoneyFormat.format(minor: goal.targetMinor, currency: currency, language: lang))")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Text("\(projectedPercent(amountMajor: amountMajor))%")
                            .font(.system(size: 19, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(goal.icon.color)
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: amountMajor)
                    }
                    .padding(14)
                    .cardSurface(cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 8) {
                        CozyMilestoneBar(
                            value: projectedProgress(amountMajor: amountMajor),
                            fill: goal.icon.color,
                            milestones: GoalMilestones.steps.map { Double($0) / 100 },
                            height: 12
                        )
                        Text(previewLine(amountMajor: amountMajor, lang: lang))
                            .font(.appCaption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 4)

                    Spacer(minLength: 8)

                    VStack(spacing: 4) {
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
                            Text(L10n.text(lang, en: "Contribution amount", vi: "Số tiền góp thêm", zh: "本次存入金额"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            if currency != .vnd {
                                Text("+\(currency.narrowSymbol)")
                                    .font(.custom("AvenirNext-Medium", size: 26))
                                    .foregroundStyle(keypad.isEmpty ? Color.textSecondary.opacity(0.45) : Color.positive.opacity(0.8))
                            } else if !keypad.isEmpty {
                                Text("+")
                                    .font(.custom("AvenirNext-Medium", size: 28))
                                    .foregroundStyle(Color.positive.opacity(0.8))
                            }
                            Text(keypad.formattedDisplayNumber(currency: currency))
                                .font(.custom("AvenirNext-DemiBold", size: 44).monospacedDigit())
                                .foregroundStyle(keypad.isEmpty ? Color.textSecondary.opacity(0.38) : Color.positive)
                                .lineLimit(1)
                                .minimumScaleFactor(0.48)
                                .contentTransition(.numericText())
                            if currency == .vnd {
                                Text("₫")
                                    .font(.custom("AvenirNext-Medium", size: 26))
                                    .foregroundStyle(keypad.isEmpty ? Color.textSecondary.opacity(0.45) : Color.positive.opacity(0.8))
                            }
                        }

                        if settings.isConvertingDisplay, amountMajor > 0 {
                            Text("≈ \(settings.formatMoney(minor: currency.toStorageMinor(amountMajor)))")
                                .font(.appCaption)
                                .monospacedDigit()
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                AmountKeypadView(
                    engine: $keypad,
                    currency: currency,
                    language: lang,
                    saveTitle: canSave
                        ? L10n.text(
                            lang,
                            en: "Add · \(MoneyFormat.format(minor: currency.toStorageMinor(amountMajor), currency: currency, language: lang))",
                            vi: "Góp · \(MoneyFormat.format(minor: currency.toStorageMinor(amountMajor), currency: currency, language: lang))",
                            zh: "存入 · \(MoneyFormat.format(minor: currency.toStorageMinor(amountMajor), currency: currency, language: lang))"
                        )
                        : L10n.text(lang, en: "Add contribution", vi: "Thêm khoản góp", zh: "确认存入"),
                    isSaveEnabled: canSave
                ) {
                    if amountMajor > 0 {
                        store.addContribution(goalID: goal.id, amountMinor: currency.toStorageMinor(amountMajor))
                        dismiss()
                    }
                }
            }
            .pageBackground()
            .keypadKeyboardInput(engine: $keypad, isEnabled: true, isSaveEnabled: canSave) {
                if amountMajor > 0 {
                    store.addContribution(goalID: goal.id, amountMinor: currency.toStorageMinor(amountMajor))
                    dismiss()
                }
            }
            .cozySheetToolbar(title: L10n.text(lang, en: "Contribute", vi: "Góp tiết kiệm", zh: "存钱入账")) {
                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
            }
            .onAppear {
                keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: settings.currency.fractionDigits)
            }
        }
        .presentationDetents([.large])
        .cozySheetFrame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 600)
    }

    // MARK: Live preview of where this contribution lands

    private func projectedSavedMinor(amountMajor: Double) -> Int64 {
        goal.savedMinor + settings.currency.toStorageMinor(amountMajor)
    }

    private func projectedProgress(amountMajor: Double) -> Double {
        guard goal.targetMinor > 0 else { return 0 }
        return min(1, max(0, Double(projectedSavedMinor(amountMajor: amountMajor)) / Double(goal.targetMinor)))
    }

    private func projectedPercent(amountMajor: Double) -> Int {
        guard goal.targetMinor > 0 else { return 0 }
        return Int((Double(projectedSavedMinor(amountMajor: amountMajor)) * 100 / Double(goal.targetMinor)).rounded(.down))
    }

    private func previewLine(amountMajor: Double, lang: AppLanguage) -> String {
        let projected = GoalMilestones(savedMinor: projectedSavedMinor(amountMajor: amountMajor), targetMinor: goal.targetMinor)
        let current = GoalMilestones(goal: goal)
        if amountMajor > 0, projected.reachedCount > current.reachedCount, let reached = projected.lastReachedPercent {
            return reached >= 100
                ? L10n.text(lang, en: "This one finishes the goal!", vi: "Khoản này đưa bạn về đích luôn!", zh: "这一笔就能达成目标！")
                : L10n.text(lang, en: "This one lights up the \(reached)% star", vi: "Khoản này thắp sáng sao \(reached)%", zh: "这一笔会点亮 \(reached)% 星")
        }
        guard let next = projected.nextStepPercent else {
            return L10n.text(lang, en: "Goal complete", vi: "Đã về đích", zh: "目标已达成")
        }
        let amount = MoneyFormat.format(minor: projected.toNextMinor, currency: settings.currency, language: lang)
        return L10n.text(lang, en: "\(amount) to the \(next)% star", vi: "Còn \(amount) nữa là chạm sao \(next)%", zh: "再存 \(amount) 点亮 \(next)% 星")
    }
}
