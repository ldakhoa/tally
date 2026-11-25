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
#elseif os(macOS)
import AppKit
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
    case budgets, goals, commitments
    var id: String { rawValue }

    /// Page title (navigation bar).
    func title(in language: AppLanguage) -> String {
        switch self {
        case .budgets: return L10n.text(language, en: "Budgets", vi: "Ngân sách", zh: "预算")
        case .goals: return L10n.text(language, en: "Goals", vi: "Mục tiêu", zh: "目标")
        case .commitments: return L10n.text(language, en: "Commitments", vi: "Khoản cam kết", zh: "分期与贷款")
        }
    }

    func addTitle(in language: AppLanguage) -> String {
        switch self {
        case .budgets: return L10n.text(language, en: "Set budget limit", vi: "Đặt hạn mức ngân sách", zh: "设置预算")
        case .goals: return L10n.text(language, en: "New goal", vi: "Thêm mục tiêu", zh: "新建目标")
        case .commitments: return L10n.text(language, en: "Add installment or loan", vi: "Thêm trả góp hoặc khoản vay", zh: "添加分期或贷款")
        }
    }

    /// Short label for the segmented control: three segments with icons must fit on the narrowest
    /// iPhone, and "Commitments" / "Khoản cam kết" / "分期与贷款" are too long for one third.
    func segmentTitle(in language: AppLanguage) -> String {
        switch self {
        case .commitments: return L10n.text(language, en: "Loans", vi: "Trả góp", zh: "分期")
        default: return title(in: language)
        }
    }
}

enum SidebarDestination: String, CaseIterable, Identifiable, Hashable {
    case overview, transactions, statistics, budgets, goals, commitments, settings
    var id: String { rawValue }

    static var primaryCases: [SidebarDestination] {
        [.overview, .transactions, .statistics, .budgets, .goals, .commitments]
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .overview: return L10n.text(language, en: "Overview", vi: "Tổng quan", zh: "概览")
        case .transactions: return L10n.text(language, en: "Transactions", vi: "Giao dịch", zh: "账单")
        case .statistics: return L10n.text(language, en: "Statistics", vi: "Thống kê", zh: "统计")
        case .budgets: return L10n.text(language, en: "Budgets", vi: "Ngân sách", zh: "预算")
        case .goals: return L10n.text(language, en: "Goals", vi: "Mục tiêu", zh: "目标")
        case .commitments: return L10n.text(language, en: "Commitments", vi: "Khoản cam kết", zh: "分期与贷款")
        case .settings: return L10n.text(language, en: "Settings", vi: "Cài đặt", zh: "设置")
        }
    }

    var shortcutHint: String? {
        switch self {
        case .overview: return "⌘1"
        case .transactions: return "⌘2"
        case .statistics: return "⌘3"
        case .budgets: return "⌘4"
        case .goals: return "⌘5"
        case .commitments: return "⌘6"
        case .settings: return "⌘,"
        }
    }
}

@MainActor
@Observable
final class TabRouter {
    var selectedTab: TallyTab = .overview
    var planSegment: PlanSegment = .budgets

    var activeDestination: SidebarDestination {
        get {
            switch selectedTab {
            case .overview: return .overview
            case .transactions: return .transactions
            case .statistics: return .statistics
            case .budgets:
                switch planSegment {
                case .budgets: return .budgets
                case .goals: return .goals
                case .commitments: return .commitments
                }
            case .settings: return .settings
            }
        }
        set {
            switch newValue {
            case .overview: selectedTab = .overview
            case .transactions: selectedTab = .transactions
            case .statistics: selectedTab = .statistics
            case .budgets:
                planSegment = .budgets
                selectedTab = .budgets
            case .goals:
                planSegment = .goals
                selectedTab = .budgets
            case .commitments:
                planSegment = .commitments
                selectedTab = .budgets
            case .settings:
                selectedTab = .settings
            }
        }
    }

    func goToOverview() {
        CozyHaptics.selection()
        selectedTab = .overview
    }

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

    func goToCommitments() {
        CozyHaptics.selection()
        planSegment = .commitments
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
                    onSelectCommitments: router.goToCommitments,
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
    @Bindable var router: TabRouter

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(CloudSync.self) private var cloudSync
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var tabBarVisibility = TabBarVisibility()
    @State private var loadedTabs: Set<TallyTab> = [.overview]
    @State private var planToCreate: PlanSegment?
    @State private var celebrationTrigger = 0
    @State private var lastTransactionCount = -1
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var usesSidebarShell: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Group {
            if usesSidebarShell {
                sidebarShell(lang: lang)
            } else {
                compactTabShell(lang: lang)
            }
        }
        .onAppear {
            lastTransactionCount = store.activeTransactions.count
        }
        .task {
            CozySounds.warmUp()
            // Pre-warm the remaining tabs on phone so the first tap is instant, but only while the
            // user is NOT scrolling. Building a whole tab (Charts, calendars, lists) costs several
            // frames on the main thread; doing that mid-scroll on launch was the source of the
            // "laggy for the first few scrolls" jank on Overview.
            guard !usesSidebarShell else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            let tabsToWarm: [TallyTab] = [.transactions, .budgets, .statistics, .settings]
            for tab in tabsToWarm {
                guard !Task.isCancelled else { break }
                guard !loadedTabs.contains(tab) else { continue }
                await Self.waitUntilScrollIdle()
                guard !Task.isCancelled else { break }
                loadedTabs.insert(tab)
                try? await Task.sleep(for: .milliseconds(400))
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
        .sheet(item: $planToCreate) { segment in
            switch segment {
            case .budgets: BudgetEditorSheet()
            case .goals: GoalEditorSheet()
            case .commitments: InstallmentPlanEditorSheet()
            }
        }
        .sheet(isPresented: $settings.isShowingQuickAdd) {
            TransactionEditorSheet()
        }
        .sheet(isPresented: $settings.isShowingAskTally) {
            AskTallyView()
        }
        .onChange(of: settings.isShowingSettings) { _, wantsSettings in
            guard wantsSettings else { return }
            settings.isShowingAskTally = false
            settings.isShowingQuickAdd = false
            CozyHaptics.selection()
            router.selectedTab = .settings
            settings.isShowingSettings = false
        }
    }

    /// Suspends until the main run loop has left scroll tracking mode (finger down or
    /// decelerating) and stayed idle briefly, so background view building never steals scroll frames.
    private static func waitUntilScrollIdle() async {
        #if os(iOS)
        var idleChecks = 0
        while idleChecks < 2, !Task.isCancelled {
            if RunLoop.current.currentMode == .tracking {
                idleChecks = 0
            } else {
                idleChecks += 1
            }
            try? await Task.sleep(for: .milliseconds(150))
        }
        #endif
    }

    // MARK: - iPhone Compact Tab Bar Shell

    private func compactTabShell(lang: AppLanguage) -> some View {
        let activePlan = router.selectedTab == .budgets ? router.planSegment : nil
        let hidesTabBar = tabBarVisibility.isHidden(for: router.selectedTab.rawValue)
        let tabItems = TallyTab.allCases.map { tab in
            CozyTabBarItem(
                id: tab,
                icon: tab.cozyIcon,
                accessibilityLabel: tab.title(in: lang),
                badgeCount: tab == .overview ? store.pendingReviewTransactions.count : 0
            )
        }

        return ZStack {
            TabPagesHost(router: router, loadedTabs: loadedTabs)
                .environment(\.tabBarVisibility, tabBarVisibility)
        }
        .overlay(alignment: .bottom) {
            CozyFloatingTabBar(items: tabItems, selection: $router.selectedTab)
                .offset(y: hidesTabBar ? 110 : 0)
                .opacity(hidesTabBar ? 0 : 1)
                .allowsHitTesting(!hidesTabBar)
                .animation(.spring(response: 0.28, dampingFraction: 0.86), value: hidesTabBar)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .overlay(alignment: .bottom) {
            CozyCelebrationOverlay(trigger: celebrationTrigger)
                .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            Group {
                if router.selectedTab != .settings && !hidesTabBar {
                    FloatingTallyActionDock(
                        language: lang,
                        onAskTally: { settings.isShowingAskTally = true },
                        addTitle: activePlan?.addTitle(in: lang) ?? L10n.text(lang, en: "Add transaction", vi: "Thêm giao dịch", zh: "记一笔"),
                        onQuickAdd: {
                            if let activePlan {
                                planToCreate = activePlan
                            } else {
                                settings.isShowingQuickAdd = true
                            }
                        }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 84)
                    .transition(.scale(scale: 0.88).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: router.selectedTab == .settings || hidesTabBar)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    // MARK: - iPad & Mac Cozy Sidebar Shell

    private func sidebarShell(lang: AppLanguage) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CozySidebarView(
                router: router,
                language: lang,
                pendingCount: store.pendingReviewTransactions.count,
                cloudSync: cloudSync,
                syncsWithICloud: settings.syncsWithICloud,
                onQuickAdd: {
                    CozyHaptics.medium()
                    CozySounds.play(.pop)
                    settings.isShowingQuickAdd = true
                },
                onAskTally: {
                    CozyHaptics.light()
                    CozySounds.play(.pop)
                    settings.isShowingAskTally = true
                }
            )
            .navigationSplitViewColumnWidth(min: 224, ideal: 244, max: 276)
        } detail: {
            detailPage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.tabBarBottomInset, 24)
                .overlay(alignment: .bottom) {
                    CozyCelebrationOverlay(trigger: celebrationTrigger)
                        .padding(.bottom, 32)
                }
        }
    }

    @ViewBuilder
    private var detailPage: some View {
        switch router.activeDestination {
        case .overview:
            OverviewView(
                onSelectTransactions: router.goToTransactions,
                onSelectStatistics: router.goToStatistics,
                onSelectBudgets: router.goToBudgets,
                onSelectGoals: router.goToGoals,
                onSelectCommitments: router.goToCommitments,
                onSelectSettings: router.goToSettings
            )
        case .transactions:
            TransactionsView()
        case .statistics:
            StatisticsView(onSelectTransactions: router.goToTransactions)
        case .budgets:
            BudgetsView(embedded: false)
        case .goals:
            GoalsView(embedded: false)
        case .commitments:
            CommitmentsView(embedded: false)
        case .settings:
            SettingsView(isModal: false)
        }
    }
}

// MARK: - Cozy Paws & Cream Sidebar

private struct CozySidebarView: View {
    @Bindable var router: TabRouter
    let language: AppLanguage
    let pendingCount: Int
    let cloudSync: CloudSync
    let syncsWithICloud: Bool
    let onQuickAdd: () -> Void
    let onAskTally: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var petBounce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(SidebarDestination.primaryCases) { destination in
                        SidebarNavRow(
                            destination: destination,
                            language: language,
                            isSelected: router.activeDestination == destination,
                            badgeCount: destination == .overview ? pendingCount : 0
                        ) {
                            CozyHaptics.selection()
                            CozySounds.play(.tick)
                            withAnimation(.snappy(duration: 0.16)) {
                                router.activeDestination = destination
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)

            VStack(spacing: 10) {
                Divider().overlay(Color.hairline)

                Button(action: onQuickAdd) {
                    HStack(spacing: 6) {
                        CozyUIIcon(.plus, size: 15, color: Color.onInk, lineWidthScale: 1.1)
                        Text(L10n.text(language, en: "Add expense", vi: "Ghi chi tiêu", zh: "记一笔"))
                            .font(.appControl)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .foregroundStyle(Color.onInk)
                    .background(Color.ink, in: Capsule())
                    .shadow(color: Color.ink.opacity(0.18), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                #if os(macOS)
                .help(L10n.text(language, en: "New Transaction (⌘N)", vi: "Thêm giao dịch (⌘N)", zh: "新建账单 (⌘N)"))
                #endif

                // Cozy Pet AI Companion card
                askTallyCard

                SidebarNavRow(
                    destination: .settings,
                    language: language,
                    isSelected: router.activeDestination == .settings,
                    badgeCount: 0
                ) {
                    CozyHaptics.selection()
                    CozySounds.play(.tick)
                    withAnimation(.snappy(duration: 0.16)) {
                        router.activeDestination = .settings
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Color.sidebarBackground.ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .ignoresSafeArea()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            brandArtwork

            VStack(alignment: .leading, spacing: 2) {
                Text("Tally")
                    .font(.appHeading)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Button {
                    if cloudSync.phase == .running {
                        cloudSync.syncNow()
                    } else {
                        router.goToSettings()
                    }
                } label: {
                    iCloudStatusPill
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text(language, en: "iCloud sync status", vi: "Trạng thái đồng bộ iCloud", zh: "iCloud 同步状态"))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var brandArtwork: some View {
        #if os(macOS)
        Image(nsImage: NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
        #else
        CoupleAvatarsBadge(avatarSize: 28, showHeart: false)
            .accessibilityHidden(true)
        #endif
    }

    private var iCloudStatusPill: some View {
        HStack(spacing: 5) {
            if cloudSync.isSyncing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.75)
            } else {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6.5, height: 6.5)
            }
            Text(statusText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Color.softFill, in: Capsule())
    }

    private var statusDotColor: Color {
        guard syncsWithICloud else { return .textSecondary }
        switch cloudSync.phase {
        case .running: return .positive
        case .checkingAccount: return .info
        case .noAccount, .accountUnavailable, .unavailable: return .caution
        case .off: return .textSecondary
        }
    }

    private var statusText: String {
        if cloudSync.isSyncing {
            return L10n.text(language, en: "Syncing", vi: "Đang đồng bộ", zh: "同步中")
        }
        guard syncsWithICloud else {
            return L10n.text(language, en: "iCloud off", vi: "Tắt iCloud", zh: "已关闭")
        }
        switch cloudSync.phase {
        case .running:
            if cloudSync.isSharedHouseholdActive {
                return L10n.text(language, en: "iCloud · Shared", vi: "iCloud · Chung", zh: "iCloud · 共享")
            }
            return "iCloud"
        case .checkingAccount:
            return L10n.text(language, en: "Checking…", vi: "Đang kiểm tra…", zh: "检查中…")
        case .noAccount:
            return L10n.text(language, en: "Sign in iCloud", vi: "Chưa có iCloud", zh: "未登录 iCloud")
        case .accountUnavailable, .unavailable:
            return L10n.text(language, en: "iCloud paused", vi: "Tạm ngưng", zh: "iCloud 暂停")
        case .off:
            return L10n.text(language, en: "iCloud off", vi: "Tắt iCloud", zh: "已关闭")
        }
    }

    private var askTallyCard: some View {
        let isDark = colorScheme == .dark
        let gradientColors: [Color] = isDark
            ? [Color(hex: 0x3D2E29), Color(hex: 0x2F2220)]
            : [Color(hex: 0xFFE9D8), Color(hex: 0xFFF7EC)]
        let borderColor = isDark ? Color.accent.opacity(0.32) : Color(hex: 0xE67360, alpha: 0.22)

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                petBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                petBounce = false
            }
            onAskTally()
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    GoldenPuppyView(mood: .happy, size: 32, isBouncing: petBounce)
                        .frame(width: 34, height: 34)
                    ZStack {
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 14, height: 14)
                        CozyUIIcon(.sparkles, size: 8, color: Color.onAccent)
                    }
                    .offset(x: 2, y: -2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text(language, en: "Ask Tally AI", vi: "Hỏi Tally AI", zh: "问问 Tally AI"))
                        .font(.appControl)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(L10n.text(language, en: "Chat or dictate", vi: "Chat hoặc nói", zh: "对话或语音记账"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                #if os(macOS)
                Text("⌘K")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary.opacity(0.8))
                #endif
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.cozyCard)
        .accessibilityLabel(L10n.text(language, en: "Ask Tally AI", vi: "Hỏi Trợ lý Tally AI", zh: "问问 Tally AI"))
    }
}

private struct SidebarNavRow: View {
    let destination: SidebarDestination
    let language: AppLanguage
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var activeFill: Color {
        colorScheme == .dark ? Color(hex: 0x4E3B34) : Color(hex: 0xFFE9DB)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                rowIcon
                    .frame(width: 24, height: 24)

                Text(destination.title(in: language))
                    .font(.appControl)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textPrimary.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if badgeCount > 0 {
                    Text("\(min(badgeCount, 99))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.onAccent)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(Color.accent, in: Capsule())
                } else if let hint = destination.shortcutHint {
                    #if os(macOS)
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.textSecondary.opacity(0.65))
                    #endif
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? activeFill : (isHovering ? Color.rowHover : Color.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var rowIcon: some View {
        switch destination {
        case .overview:
            CozyTabIconView(kind: .overview, isSelected: isSelected)
                .scaleEffect(0.82)
        case .transactions:
            CozyTabIconView(kind: .transactions, isSelected: isSelected)
                .scaleEffect(0.82)
        case .statistics:
            CozyTabIconView(kind: .statistics, isSelected: isSelected)
                .scaleEffect(0.82)
        case .budgets:
            CozyTabIconView(kind: .budgets, isSelected: isSelected)
                .scaleEffect(0.82)
        case .goals:
            CozyGoalIcon(
                goal: .target,
                size: 21,
                style: isSelected ? .watercolor : .tinted(Color.textSecondary.opacity(0.75))
            )
        case .commitments:
            CozyUIIcon(
                .creditCard,
                size: 21,
                color: isSelected ? Color.accent : Color.textSecondary.opacity(0.75)
            )
        case .settings:
            CozyTabIconView(kind: .settings, isSelected: isSelected)
                .scaleEffect(0.82)
        }
    }
}

/// Hosts Budgets, Savings Goals and Commitments cleanly under the 4th tab on compact iPhone width so all 5 primary
/// tabs stay visible without overflowing into iOS's "More" tab.
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
                                    case .commitments:
                                        CozyUIIcon(.creditCard, size: 18, color: selected ? Color.onInk : Color.accent)
                                    }
                                    Text(option.segmentTitle(in: lang))
                                        .font(.appControl)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .foregroundStyle(selected ? Color.onInk : Color.textPrimary)
                                // Each segment only publishes its frame; the single pill below follows the
                                // selected one, so it slides at full opacity instead of fading out and back in.
                                .background {
                                    Color.clear
                                        .matchedGeometryEffect(id: option, in: segmentNamespace)
                                }
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background {
                        Capsule()
                            .fill(Color.ink)
                            .matchedGeometryEffect(id: router.planSegment, in: segmentNamespace, isSource: false)
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
                    case .commitments:
                        CommitmentsView(embedded: true)
                    }
                }
                .documentColumn()
            }
            .pageBackground()
            .navigationTitle(router.planSegment.title(in: lang))
        }
    }
}

/// Floating bottom-right action dock featuring the animated Pet AI Companion (Ask Tally)
/// and a tactile `+` Add Expense button.
private struct FloatingTallyActionDock: View {
    let language: AppLanguage
    let onAskTally: () -> Void
    let addTitle: String
    let onQuickAdd: () -> Void

    private let tab = UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 16)

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Button {
                CozyHaptics.light()
                CozySounds.play(.pop)
                onAskTally()
            } label: {
                Text(L10n.text(language, en: "Ask Tally", vi: "Hỏi Tally", zh: "问问 Tally"))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.editorBackground, in: tab)
                    .overlay(tab.strokeBorder(Color.ink.opacity(0.18), lineWidth: 1))
                    .background(alignment: .topTrailing) {
                        GoldenPuppyView(mood: .happy, size: 40)
                            .offset(x: 5, y: -29)
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .topTrailing) {
                        GoldenPaw().offset(x: -23, y: -4)
                    }
                    .overlay(alignment: .topTrailing) {
                        GoldenPaw().rotationEffect(.degrees(-20)).offset(x: 8, y: -9)
                    }
                    .padding(.top, 29)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BookmarkPressStyle(travel: -2))
            .zIndex(1)

            addButton
        }
        .shadow(color: Color(hex: 0x6B4423).opacity(0.16), radius: 4, y: 3)
    }

    private var addButton: some View {
        Button {
            CozyHaptics.medium()
            CozySounds.play(.pop)
            onQuickAdd()
        } label: {
            let cover = RoundedRectangle(cornerRadius: 6, style: .continuous)
            CozyUIIcon(.pencil, size: 22, color: Color.ink)
            .padding(.leading, 4)
            .frame(width: 52, height: 36)
            .background(Color.editorBackground, in: cover)
            .overlay(cover.strokeBorder(Color.ink.opacity(0.5), lineWidth: 1))
            .background {
                cover.fill(Color.cardBackground)
                    .overlay(cover.strokeBorder(Color.ink.opacity(0.35), lineWidth: 1))
                    .offset(y: 3)
            }
            .overlay(alignment: .leading) {
                VStack(spacing: 8) {
                    ForEach(0..<2) { _ in
                        Capsule().strokeBorder(Color.ink, lineWidth: 1.5)
                            .frame(width: 10, height: 5)
                    }
                }
                .offset(x: -3)
            }
            .rotationEffect(.degrees(-4))
            .padding(.horizontal, 4)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(BookmarkPressStyle(travel: 2))
        .accessibilityLabel(addTitle)
    }
}

private struct GoldenPaw: View {
    var body: some View {
        Capsule().fill(Color(hex: 0xF2BE70))
            .overlay(Capsule().strokeBorder(Color(hex: 0x4E382F), lineWidth: 1))
            .frame(width: 11, height: 8)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct BookmarkPressStyle: ButtonStyle {
    let travel: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed && !reduceMotion ? travel : 0)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
