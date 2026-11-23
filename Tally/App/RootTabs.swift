import AppServices
import AssistantUI
import BudgetsUI
import DesignSystem
import GoalsUI
import OverviewUI
import SettingsUI
import SharedUI
import StatisticsUI
import SwiftUI
import TallyCore
import TransactionsUI

enum TallyTab: String, CaseIterable, Identifiable {
    case overview, transactions, statistics, budgets, settings
    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .overview: return L10n.text(language, en: "Overview", vi: "Tổng quan", zh: "概览")
        case .transactions: return L10n.text(language, en: "Transactions", vi: "Giao dịch", zh: "账单")
        case .statistics: return L10n.text(language, en: "Statistics", vi: "Thống kê", zh: "统计")
        case .budgets: return L10n.text(language, en: "Budgets", vi: "Ngân sách", zh: "预算")
        case .settings: return L10n.text(language, en: "Settings", vi: "Cài đặt", zh: "设置")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "house.fill"
        case .transactions: return "arrow.left.arrow.right.circle.fill"
        case .statistics: return "chart.bar.fill"
        case .budgets: return "pawprint.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum PlanSegment: String, CaseIterable, Identifiable {
    case budgets, goals
    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .budgets: return L10n.text(language, en: "Budgets", vi: "Ngân sách", zh: "预算")
        case .goals: return L10n.text(language, en: "Goals", vi: "Mục tiêu", zh: "目标")
        }
    }

    var symbol: String {
        switch self {
        case .budgets: return "chart.pie"
        case .goals: return "target"
        }
    }
}

struct RootTabs: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var selectedTab: TallyTab = .overview
    @State private var planSegment: PlanSegment = .budgets

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        TabView(selection: $selectedTab) {
            OverviewView(
                onSelectTransactions: { selectedTab = .transactions },
                onSelectStatistics: { selectedTab = .statistics },
                onSelectBudgets: {
                    planSegment = .budgets
                    selectedTab = .budgets
                },
                onSelectGoals: {
                    planSegment = .goals
                    selectedTab = .budgets
                },
                onSelectSettings: { selectedTab = .settings }
            )
            .tabItem {
                Label(TallyTab.overview.title(in: lang), systemImage: TallyTab.overview.symbol)
            }
            .badge(store.pendingReviewTransactions.count)
            .tag(TallyTab.overview)

            TransactionsView()
                .tabItem {
                    Label(TallyTab.transactions.title(in: lang), systemImage: TallyTab.transactions.symbol)
                }
                .tag(TallyTab.transactions)

            StatisticsView(onSelectTransactions: { selectedTab = .transactions })
                .tabItem {
                    Label(TallyTab.statistics.title(in: lang), systemImage: TallyTab.statistics.symbol)
                }
                .tag(TallyTab.statistics)

            PlanTabView(segment: $planSegment)
                .tabItem {
                    Label(TallyTab.budgets.title(in: lang), systemImage: TallyTab.budgets.symbol)
                }
                .tag(TallyTab.budgets)

            SettingsView(isModal: false)
                .tabItem {
                    Label(TallyTab.settings.title(in: lang), systemImage: TallyTab.settings.symbol)
                }
                .tag(TallyTab.settings)
        }
        .sheet(isPresented: $settings.isShowingQuickAdd) {
            TransactionEditorSheet()
        }
        .sheet(isPresented: $settings.isShowingSmartCapture) {
            SmartCaptureSheet()
        }
        .sheet(isPresented: $settings.isShowingAskTally) {
            AskTallyView()
        }
        .onChange(of: settings.isShowingSettings) { _, wantsSettings in
            guard wantsSettings else { return }
            settings.isShowingAskTally = false
            settings.isShowingSmartCapture = false
            settings.isShowingQuickAdd = false
            selectedTab = .settings
            settings.isShowingSettings = false
        }
    }
}

/// Hosts Budgets and Savings Goals cleanly under the 4th tab so all 5 primary tabs stay visible
/// without overflowing into iOS's "More" tab.
private struct PlanTabView: View {
    @Binding var segment: PlanSegment

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let lang = settings.language

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(PlanSegment.allCases) { option in
                            let selected = segment == option
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    segment = option
                                }
                            } label: {
                                Label(option.title(in: lang), systemImage: option.symbol)
                                    .font(.appControl)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                    .background(selected ? Color.ink : Color.cardBackground, in: Capsule())
                                    .overlay(
                                        Capsule().strokeBorder(selected ? Color.clear : Color.hairline, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.themedPlain)
                        }
                    }

                    switch segment {
                    case .budgets:
                        BudgetsView(embedded: true)
                    case .goals:
                        GoalsView(embedded: true)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(segment.title(in: lang))
            .toolbar { TopToolbarControls() }
        }
    }
}
