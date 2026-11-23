import AppServices
import AssistantUI
import BudgetsUI
import DesignSystem
import GoalsUI
import OverviewUI
import SettingsUI
import SharedUI
import SwiftUI
import TallyCore
import TransactionsUI

enum TallyTab: String, CaseIterable, Identifiable {
    case overview, transactions, budgets, goals
    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .overview: return L10n.text(language, en: "Overview", vi: "Tổng quan")
        case .transactions: return L10n.text(language, en: "Activity", vi: "Giao dịch")
        case .budgets: return L10n.text(language, en: "Budgets", vi: "Ngân sách")
        case .goals: return L10n.text(language, en: "Goals", vi: "Mục tiêu")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .transactions: return "arrow.left.arrow.right"
        case .budgets: return "chart.pie"
        case .goals: return "target"
        }
    }
}

struct RootTabs: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var selectedTab: TallyTab = .overview

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        TabView(selection: $selectedTab) {
            OverviewView(
                onSelectTransactions: { selectedTab = .transactions },
                onSelectGoals: { selectedTab = .goals }
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

            BudgetsView()
                .tabItem {
                    Label(TallyTab.budgets.title(in: lang), systemImage: TallyTab.budgets.symbol)
                }
                .tag(TallyTab.budgets)

            GoalsView()
                .tabItem {
                    Label(TallyTab.goals.title(in: lang), systemImage: TallyTab.goals.symbol)
                }
                .tag(TallyTab.goals)
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
        .sheet(isPresented: $settings.isShowingSettings) {
            SettingsView()
        }
    }
}
