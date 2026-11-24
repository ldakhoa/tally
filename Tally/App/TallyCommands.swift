import AppServices
import DesignSystem
import SwiftUI
import TallyCore

/// Keyboard shortcuts & menu bar commands for Mac and iPad (with hardware keyboard).
struct TallyCommands: Commands {
    let router: TabRouter
    let settings: AppSettings
    let store: BudgetStore
    let cloudSync: CloudSync

    var body: some Commands {
        let lang = settings.language

        CommandGroup(replacing: .newItem) {
            Button(L10n.text(lang, en: "New Transaction", vi: "Thêm giao dịch", zh: "新建账单")) {
                CozyHaptics.medium()
                settings.isShowingQuickAdd = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button(L10n.text(lang, en: "Smart Paste", vi: "Dán thông báo", zh: "智能粘贴")) {
                CozyHaptics.light()
                settings.isShowingSmartCapture = true
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button(L10n.text(lang, en: "Ask Tally AI", vi: "Hỏi Trợ lý Tally AI", zh: "问问 Tally AI")) {
                CozyHaptics.light()
                settings.isShowingAskTally = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Divider()

            Button(L10n.text(lang, en: "Sync with iCloud Now", vi: "Đồng bộ iCloud ngay", zh: "立即同步 iCloud")) {
                cloudSync.syncNow()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!settings.syncsWithICloud || cloudSync.isSyncing)
        }

        CommandMenu(L10n.text(lang, en: "Go", vi: "Đi tới", zh: "前往")) {
            Button(L10n.text(lang, en: "Overview", vi: "Tổng quan", zh: "概览")) {
                router.goToOverview()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button(L10n.text(lang, en: "Transactions", vi: "Giao dịch", zh: "账单")) {
                router.goToTransactions()
            }
            .keyboardShortcut("2", modifiers: .command)

            Button(L10n.text(lang, en: "Statistics", vi: "Thống kê", zh: "统计")) {
                router.goToStatistics()
            }
            .keyboardShortcut("3", modifiers: .command)

            Button(L10n.text(lang, en: "Budgets", vi: "Ngân sách", zh: "预算")) {
                router.goToBudgets()
            }
            .keyboardShortcut("4", modifiers: .command)

            Button(L10n.text(lang, en: "Goals", vi: "Mục tiêu", zh: "目标")) {
                router.goToGoals()
            }
            .keyboardShortcut("5", modifiers: .command)

            Button(L10n.text(lang, en: "Commitments", vi: "Khoản cam kết", zh: "分期与贷款")) {
                router.goToCommitments()
            }
            .keyboardShortcut("6", modifiers: .command)

            Divider()

            Button(L10n.text(lang, en: "Previous Period", vi: "Kỳ trước", zh: "上一周期")) {
                CozyHaptics.light()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    store.shiftPeriod(by: -1)
                }
            }
            .keyboardShortcut("[", modifiers: .command)

            Button(L10n.text(lang, en: "Next Period", vi: "Kỳ sau", zh: "下一周期")) {
                CozyHaptics.light()
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    store.shiftPeriod(by: 1)
                }
            }
            .keyboardShortcut("]", modifiers: .command)

            #if os(iOS)
            Divider()

            Button(L10n.text(lang, en: "Settings", vi: "Cài đặt", zh: "设置")) {
                router.goToSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            #endif
        }

        #if os(macOS)
        CommandGroup(replacing: .appSettings) {
            Button(L10n.text(lang, en: "Settings…", vi: "Cài đặt…", zh: "设置…")) {
                router.goToSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        #endif
    }
}
