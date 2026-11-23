import AppServices
import BudgetKit
import ClaudeKit
import DesignSystem
import SharedUI
import SwiftUI
import SyncKit
import TallyCore
import ThemeTokens
import UniformTypeIdentifiers

public struct SettingsView: View {
    public var isModal: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(CloudSync.self) private var cloudSync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarBottomInset) private var tabBarBottomInset

    public init(isModal: Bool = false) {
        self.isModal = isModal
    }

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "slider.horizontal.3",
                            tint: nil,
                            title: L10n.text(lang, en: "General & Appearance", vi: "Chung & Giao diện", zh: "通用与外观"),
                            detail: "\(settings.currency.rawValue) · \(settings.language.title(in: lang))"
                        )
                    }

                    NavigationLink {
                        ClaudeSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "sparkles",
                            tint: settings.isAIReady ? .positive : .caution,
                            title: L10n.text(lang, en: "AI Assistant", vi: "Trợ lý AI", zh: "AI 助手"),
                            detail: settings.activeProviderSummary(in: lang)
                        )
                    }

                    NavigationLink {
                        ShortcutsSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "bolt.horizontal.fill",
                            tint: .accent,
                            title: L10n.text(lang, en: "Auto-Capture & Shortcuts", vi: "Tự động ghi & Phím tắt", zh: "自动记账与快捷指令"),
                            detail: L10n.text(lang, en: "Apple Pay, Bank Email & SMS", vi: "Apple Pay, Email & SMS ngân hàng", zh: "Apple Pay、银行邮件与短信")
                        )
                    }

                    NavigationLink {
                        EmailInboxSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "envelope.badge.fill",
                            tint: settings.isEmailInboxConfigured ? .positive : .info,
                            title: L10n.text(lang, en: "Cloud Bank Email Inbox", vi: "Hộp thư Email ngân hàng", zh: "云端银行邮件收件箱"),
                            detail: settings.isEmailInboxConfigured
                                ? L10n.text(lang, en: "Connected", vi: "Đã kết nối", zh: "已连接")
                                : L10n.text(lang, en: "Zero-Shortcuts Gmail / Mail sync", vi: "Tự động từ Gmail, không cần Phím tắt", zh: "无需快捷指令自动同步 Gmail")
                        )
                    }

                    NavigationLink {
                        CloudSharingSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "icloud.fill",
                            tint: cloudSync.phase == .running ? .info : .textSecondary,
                            title: L10n.text(lang, en: "iCloud & Household", vi: "iCloud & Gia đình", zh: "iCloud 与家庭共享"),
                            detail: cloudStatusShort(lang: lang)
                        )
                    }

                    NavigationLink {
                        BackupSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "arrow.up.arrow.down.circle",
                            tint: nil,
                            title: L10n.text(lang, en: "Backup & Data", vi: "Sao lưu & Dữ liệu", zh: "备份与数据"),
                            detail: L10n.text(lang, en: "JSON import / export", vi: "Nhập / xuất JSON", zh: "JSON 导入 / 导出")
                        )
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, tabBarBottomInset, for: .scrollContent)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Settings", vi: "Cài đặt", zh: "设置"))
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
                    }
                }
            }
        }
    }

    private func settingsRow(symbol: String, tint: Color?, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            SettingsIconTile(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBodyMedium)
                Text(detail).font(.appCaption).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func cloudStatusShort(lang: AppLanguage) -> String {
        switch cloudSync.phase {
        case .running:
            return settings.cloudZoneRole.isSharedParticipant
                ? L10n.text(lang, en: "Joined household", vi: "Đã tham gia gia đình", zh: "已加入家庭")
                : (cloudSync.participantNames.isEmpty
                    ? L10n.text(lang, en: "Synced", vi: "Đang đồng bộ", zh: "已同步")
                    : L10n.text(lang, en: "Shared with \(cloudSync.participantNames.joined(separator: ", "))", vi: "Chia sẻ với \(cloudSync.participantNames.joined(separator: ", "))", zh: "已与 \(cloudSync.participantNames.joined(separator: ", ")) 共享"))
        case .off: return L10n.text(lang, en: "Off", vi: "Tắt", zh: "已关闭")
        case .noAccount: return L10n.text(lang, en: "Sign in to iCloud", vi: "Chưa đăng nhập iCloud", zh: "请登录 iCloud")
        case .unavailable: return L10n.text(lang, en: "Unavailable", vi: "Không khả dụng", zh: "不可用")
        case .checkingAccount, .accountUnavailable: return L10n.text(lang, en: "Checking…", vi: "Đang kiểm tra…", zh: "检查中…")
        }
    }
}
