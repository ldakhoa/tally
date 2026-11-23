import AppServices
import BudgetKit
import DesignSystem
import SharedUI
import SwiftUI
import TallyCore

public struct GoalsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var showingNewGoal = false
    @State private var editingGoal: SavingsGoalRecord?
    @State private var contributingGoal: SavingsGoalRecord?

    public init() {}

    public var body: some View {
        let lang = settings.language
        let goals = store.activeGoals
        let totalSaved = goals.reduce(Int64(0)) { $0 + $1.savedMinor }
        let totalTarget = goals.reduce(Int64(0)) { $0 + $1.targetMinor }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !goals.isEmpty {
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L10n.text(lang, en: "Total saved", vi: "Tổng đã tiết kiệm"))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                    Text(MoneyFormat.format(minor: totalSaved, currency: settings.currency, language: lang))
                                        .font(.appMetric)
                                }
                                Spacer()
                                Button {
                                    showingNewGoal = true
                                } label: {
                                    Label(L10n.text(lang, en: "New goal", vi: "Thêm mục tiêu"), systemImage: "plus")
                                }
                                .pillButton(prominent: true)
                            }
                            if totalTarget > 0 {
                                TallyProgressBar(value: Double(totalSaved) / Double(totalTarget), fill: .positive)
                                Text("\(L10n.text(lang, en: "Target:", vi: "Mục tiêu:")) \(MoneyFormat.format(minor: totalTarget, currency: settings.currency, language: lang))")
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }

                    if goals.isEmpty {
                        EmptyStateCard(
                            symbol: "target",
                            title: L10n.text(lang, en: "No savings goals yet", vi: "Chưa có mục tiêu tiết kiệm"),
                            message: L10n.text(lang, en: "Create shared goals like an emergency fund, family trip, or home upgrade.", vi: "Tạo mục tiêu chung như quỹ dự phòng, du lịch gia đình hay mua sắm lớn."),
                            actionTitle: L10n.text(lang, en: "Create goal", vi: "Tạo mục tiêu")
                        ) {
                            showingNewGoal = true
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(goals) { goal in
                                Card {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(goal.icon.tintBackground)
                                            .frame(width: 40, height: 40)
                                            .overlay {
                                                Image(systemName: goal.icon.symbol)
                                                    .foregroundStyle(goal.icon.color)
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
                                            Label(L10n.text(lang, en: "Contribute", vi: "Góp thêm"), systemImage: "plus")
                                        }
                                        .pillButton(prominent: true)

                                        Button(L10n.text(lang, en: "Edit", vi: "Sửa")) {
                                            editingGoal = goal
                                        }
                                        .pillButton()
                                    }
                                }
                            }
                        }
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Goals", vi: "Mục tiêu"))
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

private struct GoalEditorSheet: View {
    let existing: SavingsGoalRecord?

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon: GoalIcon = .target
    @State private var targetText = ""
    @State private var savedText = "0"
    @State private var errorMessage: String?

    var body: some View {
        let lang = settings.language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Goal name", vi: "Tên mục tiêu"))
                        TextField(L10n.text(lang, en: "e.g. Emergency fund, Japan trip", vi: "VD: Quỹ dự phòng, Du lịch Nhật"), text: $name)
                            .tallyField()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(L10n.text(lang, en: "Icon", vi: "Biểu tượng"))
                        ChipPicker(
                            L10n.text(lang, en: "Icon", vi: "Biểu tượng"),
                            selection: $icon,
                            options: GoalIcon.allCases,
                            sideMargin: 0
                        ) { $0.title(in: lang) } symbol: { $0.symbol }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Target amount (\(settings.currency.rawValue))", vi: "Số tiền mục tiêu (\(settings.currency.rawValue))"))
                        TextField("100000000", text: $targetText)
                            .font(.appMetric)
                            #if os(iOS)
                            .keyboardType(settings.currency.isZeroDecimal ? .numberPad : .decimalPad)
                            #endif
                            .tallyField()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(L10n.text(lang, en: "Already saved", vi: "Đã tiết kiệm"))
                        TextField("0", text: $savedText)
                            .font(.appHeading)
                            #if os(iOS)
                            .keyboardType(settings.currency.isZeroDecimal ? .numberPad : .decimalPad)
                            #endif
                            .tallyField()
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.appSecondary).foregroundStyle(Color.negative)
                    }

                    Button(L10n.text(lang, en: "Save goal", vi: "Lưu mục tiêu"), action: save)
                        .blockButton(prominent: true)

                    if let existing {
                        Button(L10n.text(lang, en: "Delete goal", vi: "Xoá mục tiêu"), role: .destructive) {
                            store.deleteGoal(id: existing.id)
                            dismiss()
                        }
                        .blockButton(prominent: false, tint: .negative)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(existing == nil
                ? L10n.text(lang, en: "New goal", vi: "Mục tiêu mới")
                : L10n.text(lang, en: "Edit goal", vi: "Sửa mục tiêu"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) { dismiss() }
                }
            }
            .onAppear {
                guard let existing else { return }
                name = existing.name
                icon = existing.icon
                let t = settings.currency.toMajor(existing.targetMinor)
                let s = settings.currency.toMajor(existing.savedMinor)
                targetText = settings.currency.isZeroDecimal ? "\(Int64(t.rounded()))" : String(format: "%.2f", t)
                savedText = settings.currency.isZeroDecimal ? "\(Int64(s.rounded()))" : String(format: "%.2f", s)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L10n.text(settings.language, en: "Enter a goal name.", vi: "Nhập tên mục tiêu.")
            return
        }
        let targetNorm = targetText.replacingOccurrences(of: ",", with: settings.currency.isZeroDecimal ? "" : ".")
        let savedNorm = savedText.replacingOccurrences(of: ",", with: settings.currency.isZeroDecimal ? "" : ".")
        guard let target = Double(targetNorm), target > 0, let saved = Double(savedNorm), saved >= 0 else {
            errorMessage = L10n.text(settings.language, en: "Enter valid target and saved amounts.", vi: "Nhập số tiền hợp lệ.")
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

    @State private var amountText = ""

    var body: some View {
        let lang = settings.language
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(goal.name).font(.appHeading)
                Text("\(MoneyFormat.format(minor: goal.savedMinor, currency: settings.currency, language: lang)) / \(MoneyFormat.format(minor: goal.targetMinor, currency: settings.currency, language: lang))")
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)

                TextField(settings.currency.isZeroDecimal ? "2000000" : "250", text: $amountText)
                    .font(.appMetricHero)
                    #if os(iOS)
                    .keyboardType(settings.currency.isZeroDecimal ? .numberPad : .decimalPad)
                    #endif
                    .tallyField()

                Button(L10n.text(lang, en: "Add contribution", vi: "Thêm khoản góp")) {
                    let norm = amountText.replacingOccurrences(of: ",", with: settings.currency.isZeroDecimal ? "" : ".")
                    if let major = Double(norm), major > 0 {
                        store.addContribution(goalID: goal.id, amountMinor: settings.currency.toStorageMinor(major))
                        dismiss()
                    }
                }
                .blockButton(prominent: true)

                Spacer()
            }
            .documentColumn()
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Contribute", vi: "Góp tiết kiệm"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
