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
                        .documentColumn()
                }
                .pageBackground()
                .navigationTitle(L10n.text(lang, en: "Goals", vi: "Mục tiêu", zh: "存钱目标"))
                .toolbar { TopToolbarControls() }
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
        VStack(alignment: .leading, spacing: 18) {
            if !goals.isEmpty {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(lang, en: "Total saved", vi: "Tổng đã tiết kiệm", zh: "已累计存款"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                            Text(MoneyFormat.format(minor: totalSaved, currency: settings.currency, language: lang))
                                .font(.appMetric)
                        }
                        Spacer()
                        Button {
                            showingNewGoal = true
                        } label: {
                            Label(L10n.text(lang, en: "New goal", vi: "Thêm mục tiêu", zh: "新建目标"), systemImage: "plus")
                        }
                        .pillButton(prominent: true)
                    }
                    if totalTarget > 0 {
                        TallyProgressBar(value: Double(totalSaved) / Double(totalTarget), fill: .positive)
                        Text("\(L10n.text(lang, en: "Target:", vi: "Mục tiêu:", zh: "总目标：")) \(MoneyFormat.format(minor: totalTarget, currency: settings.currency, language: lang))")
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }

            if goals.isEmpty {
                EmptyStateCard(
                    symbol: "target",
                    title: L10n.text(lang, en: "No savings goals yet", vi: "Chưa có mục tiêu tiết kiệm", zh: "暂无存钱目标"),
                    message: L10n.text(lang, en: "Create shared goals like an emergency fund, family trip, or home upgrade.", vi: "Tạo mục tiêu chung như quỹ dự phòng, du lịch gia đình hay mua sắm lớn.", zh: "创建共同存钱目标，例如应急基金、家庭旅行或家居升级。"),
                    actionTitle: L10n.text(lang, en: "Create goal", vi: "Tạo mục tiêu", zh: "创建目标")
                ) {
                    showingNewGoal = true
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(goals) { goal in
                        Card {
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(goal.icon.tintBackground)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(goal.icon.color.opacity(0.22), lineWidth: 1)
                                    }
                                    .overlay {
                                        Text(goal.icon.cuteEmoji)
                                            .font(.system(size: 22))
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goal.name).font(.appHeading)
                                    Text("\(MoneyFormat.format(minor: goal.savedMinor, currency: settings.currency, language: lang)) / \(MoneyFormat.format(minor: goal.targetMinor, currency: settings.currency, language: lang))")
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                Spacer()
                                Tag(text: "\(goal.percent)%", color: goal.icon.color)
                            }

                            TallyProgressBar(value: goal.progress, fill: goal.icon.color)

                            HStack(spacing: 10) {
                                Button {
                                    contributingGoal = goal
                                } label: {
                                    Label(L10n.text(lang, en: "Contribute", vi: "Góp thêm", zh: "存入一笔"), systemImage: "plus")
                                }
                                .pillButton(prominent: true)

                                Button(L10n.text(lang, en: "Edit", vi: "Sửa", zh: "编辑")) {
                                    editingGoal = goal
                                }
                                .pillButton()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct GoalEditorSheet: View {
    let existing: SavingsGoalRecord?

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

    var body: some View {
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
                            ChipPicker(
                                L10n.text(lang, en: "Icon", vi: "Biểu tượng", zh: "图标"),
                                selection: $icon,
                                options: GoalIcon.allCases,
                                sideMargin: 0
                            ) { "\($0.cuteEmoji) \($0.title(in: lang))" }
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
                            Image(systemName: "number.square")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(Color.textPrimary)
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
            .navigationTitle(existing == nil
                ? L10n.text(lang, en: "New goal", vi: "Mục tiêu mới", zh: "新建目标")
                : L10n.text(lang, en: "Edit goal", vi: "Sửa mục tiêu", zh: "编辑目标"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isNameFocused {
                        Button(L10n.text(lang, en: "Keypad", vi: "Bàn phím số", zh: "数字键盘")) {
                            isNameFocused = false
                        }
                        .font(.appControl)
                    } else if existing != nil {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.negative)
                        }
                        .accessibilityLabel(L10n.text(lang, en: "Delete goal", vi: "Xoá mục tiêu", zh: "删除目标"))
                    }
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
                        Text(goal.icon.cuteEmoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(goal.icon.tintBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.name).font(.appHeading)
                            Text("\(MoneyFormat.format(minor: goal.savedMinor, currency: currency, language: lang)) / \(MoneyFormat.format(minor: goal.targetMinor, currency: currency, language: lang))")
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Tag(text: "\(goal.percent)%", color: goal.icon.color)
                    }
                    .padding(14)
                    .cardSurface(cornerRadius: 18)

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
            .navigationTitle(L10n.text(lang, en: "Contribute", vi: "Góp tiết kiệm", zh: "存钱入账"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
            }
            .onAppear {
                keypad = AmountKeypadEngine(initialAmountMajor: nil, maxFractionDigits: settings.currency.fractionDigits)
            }
        }
        .presentationDetents([.large])
    }
}
