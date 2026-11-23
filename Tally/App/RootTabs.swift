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
#if os(iOS)
import UIKit
#endif

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

    var cozyIcon: CozyTabIconKind {
        switch self {
        case .overview: return .overview
        case .transactions: return .transactions
        case .statistics: return .statistics
        case .budgets: return .budgets
        case .settings: return .settings
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
}

@MainActor
@Observable
final class TabRouter {
    var selectedTab: TallyTab = .overview
    var planSegment: PlanSegment = .budgets

    func goToTransactions() {
        CozyHaptics.selection()
        selectedTab = .transactions
    }

    func goToStatistics() {
        CozyHaptics.selection()
        selectedTab = .statistics
    }

    func goToBudgets() {
        CozyHaptics.selection()
        planSegment = .budgets
        selectedTab = .budgets
    }

    func goToGoals() {
        CozyHaptics.selection()
        planSegment = .goals
        selectedTab = .budgets
    }

    func goToSettings() {
        CozyHaptics.selection()
        selectedTab = .settings
    }
}

private struct TabPagesHost: View {
    let router: TabRouter
    let loadedTabs: Set<TallyTab>

    var body: some View {
        ZStack {
            if loadedTabs.contains(.overview) || router.selectedTab == .overview {
                OverviewView(
                    onSelectTransactions: router.goToTransactions,
                    onSelectStatistics: router.goToStatistics,
                    onSelectBudgets: router.goToBudgets,
                    onSelectGoals: router.goToGoals,
                    onSelectSettings: router.goToSettings
                )
                .opacity(router.selectedTab == .overview ? 1 : 0)
                .allowsHitTesting(router.selectedTab == .overview)
                .accessibilityHidden(router.selectedTab != .overview)
                .zIndex(router.selectedTab == .overview ? 1 : 0)
            }

            if loadedTabs.contains(.transactions) || router.selectedTab == .transactions {
                TransactionsView()
                    .opacity(router.selectedTab == .transactions ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == .transactions)
                    .accessibilityHidden(router.selectedTab != .transactions)
                    .zIndex(router.selectedTab == .transactions ? 1 : 0)
            }

            if loadedTabs.contains(.statistics) || router.selectedTab == .statistics {
                StatisticsView(onSelectTransactions: router.goToTransactions)
                    .opacity(router.selectedTab == .statistics ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == .statistics)
                    .accessibilityHidden(router.selectedTab != .statistics)
                    .zIndex(router.selectedTab == .statistics ? 1 : 0)
            }

            if loadedTabs.contains(.budgets) || router.selectedTab == .budgets {
                PlanTabView(router: router)
                    .opacity(router.selectedTab == .budgets ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == .budgets)
                    .accessibilityHidden(router.selectedTab != .budgets)
                    .zIndex(router.selectedTab == .budgets ? 1 : 0)
            }

            if loadedTabs.contains(.settings) || router.selectedTab == .settings {
                SettingsView(isModal: false)
                    .opacity(router.selectedTab == .settings ? 1 : 0)
                    .allowsHitTesting(router.selectedTab == .settings)
                    .accessibilityHidden(router.selectedTab != .settings)
                    .zIndex(router.selectedTab == .settings ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.tabBarBottomInset, 100)
        .animation(.easeOut(duration: 0.14), value: router.selectedTab)
    }
}

struct RootTabs: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store

    @State private var router = TabRouter()
    @State private var loadedTabs: Set<TallyTab> = [.overview]
    @State private var celebrationTrigger = 0
    @State private var lastTransactionCount = -1

    var body: some View {
        @Bindable var settings = settings
        @Bindable var router = router
        let lang = settings.language

        let tabItems = TallyTab.allCases.map { tab in
            CozyTabBarItem(
                id: tab,
                icon: tab.cozyIcon,
                accessibilityLabel: tab.title(in: lang),
                badgeCount: tab == .overview ? store.pendingReviewTransactions.count : 0
            )
        }

        ZStack {
            TabPagesHost(router: router, loadedTabs: loadedTabs)
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.appBackground.opacity(0), Color.appBackground.opacity(0.92), Color.appBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 92)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

                CozyFloatingTabBar(items: tabItems, selection: $router.selectedTab)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            CozyCelebrationOverlay(trigger: celebrationTrigger)
                .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            Group {
                if router.selectedTab != .settings {
                    FloatingTallyActionDock(
                        language: lang,
                        onAskTally: { settings.isShowingAskTally = true },
                        onQuickAdd: { settings.isShowingQuickAdd = true },
                        onSmartPaste: { settings.isShowingSmartCapture = true }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 84)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: router.selectedTab == .settings)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .onAppear {
            lastTransactionCount = store.activeTransactions.count
        }
        .task {
            CozySounds.warmUp()
            // Stagger pre-warming of remaining tabs after launch settles so first tap or scrub is locked at 120fps.
            try? await Task.sleep(for: .milliseconds(250))
            let tabsToWarm: [TallyTab] = [.transactions, .budgets, .statistics, .settings]
            for tab in tabsToWarm {
                guard !Task.isCancelled else { break }
                if !loadedTabs.contains(tab) {
                    loadedTabs.insert(tab)
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        .onChange(of: router.selectedTab) { _, newTab in
            if !loadedTabs.contains(newTab) {
                loadedTabs.insert(newTab)
            }
        }
        .onChange(of: store.activeTransactions.count) { _, newCount in
            if lastTransactionCount >= 0 && newCount > lastTransactionCount {
                celebrationTrigger += 1
            }
            lastTransactionCount = newCount
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
            CozyHaptics.selection()
            router.selectedTab = .settings
            settings.isShowingSettings = false
        }
    }
}

/// Hosts Budgets and Savings Goals cleanly under the 4th tab so all 5 primary tabs stay visible
/// without overflowing into iOS's "More" tab.
private struct PlanTabView: View {
    @Bindable var router: TabRouter

    @Environment(AppSettings.self) private var settings
    @Namespace private var segmentNamespace

    var body: some View {
        let lang = settings.language

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        ForEach(PlanSegment.allCases) { option in
                            let selected = router.planSegment == option
                            Button {
                                guard router.planSegment != option else { return }
                                CozyHaptics.selection()
                                CozySounds.play(.tick)
                                router.planSegment = option
                            } label: {
                                HStack(spacing: 7) {
                                    switch option {
                                    case .budgets:
                                        CozyPiggyIcon(
                                            size: 18,
                                            style: selected ? .tinted(Color.onInk) : .watercolor
                                        )
                                    case .goals:
                                        CozyGoalIcon(
                                            goal: .target,
                                            size: 18,
                                            style: selected ? .tinted(Color.onInk) : .watercolor
                                        )
                                    }
                                    Text(option.title(in: lang))
                                        .font(.appControl)
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                .background {
                                    if selected {
                                        Capsule()
                                            .fill(Color.ink)
                                            .matchedGeometryEffect(id: "planSegmentPill", in: segmentNamespace)
                                    }
                                }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Color.cardBackground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                    .animation(.spring(response: 0.24, dampingFraction: 0.8), value: router.planSegment)

                    switch router.planSegment {
                    case .budgets:
                        BudgetsView(embedded: true)
                    case .goals:
                        GoalsView(embedded: true)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(router.planSegment.title(in: lang))
            .toolbar { TopToolbarControls() }
        }
    }
}

/// Floating bottom-right action dock featuring the animated Pet AI Companion (Ask Tally)
/// and a tactile `+` Add Expense button.
private struct FloatingTallyActionDock: View {
    let language: AppLanguage
    let onAskTally: () -> Void
    let onQuickAdd: () -> Void
    let onSmartPaste: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var petBounce = false

    var body: some View {
        let isDark = colorScheme == .dark
        VStack(spacing: 12) {
            // Cute Pet AI Companion button (Ask Tally)
            Button {
                CozyHaptics.light()
                CozySounds.play(.pop)
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    petBounce = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    petBounce = false
                }
                onAskTally()
            } label: {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [Color(hex: 0x3D2E29), Color(hex: 0x2F2220)]
                                        : [Color(hex: 0xFFE9D8), Color(hex: 0xFFF7EC)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)

                        ShibaPuppyView(mood: .happy, size: 42, isBouncing: petBounce)
                            .offset(y: 2)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(
                                isDark ? Color.accent.opacity(0.35) : Color(hex: 0x4E382F, alpha: 0.16),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(hex: 0x5A3F37, alpha: isDark ? 0.32 : 0.18), radius: 7, y: 3)

                    // Gleaming AI sparkle badge
                    ZStack {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 19, height: 19)
                            .overlay(Circle().strokeBorder(Color.cardBackground, lineWidth: 1.5))
                        CozyUIIcon(.sparkles, size: 11, color: Color.onAccent)
                    }
                    .offset(x: 3, y: -3)
                }
            }
            .buttonStyle(.cozyCard)
            .accessibilityLabel(L10n.text(language, en: "Ask Tally AI", vi: "Hỏi Trợ lý Tally AI", zh: "问问 Tally AI"))

            // Primary Add Expense FAB (long-press for Smart Paste)
            Button {
                CozyHaptics.medium()
                CozySounds.play(.pop)
                onQuickAdd()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.cardBackground.opacity(0.35), lineWidth: 1.5)
                        )
                        .shadow(color: Color.ink.opacity(0.28), radius: 10, y: 5)

                    CozyUIIcon(.plus, size: 24, color: Color.onInk, lineWidthScale: 1.12)
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    #endif
                    onSmartPaste()
                }
            )
            .accessibilityLabel(L10n.text(language, en: "Add transaction", vi: "Thêm giao dịch", zh: "记一笔"))
        }
    }
}
