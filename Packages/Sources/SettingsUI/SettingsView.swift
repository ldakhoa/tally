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
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSync.self) private var cloudSync
    @Environment(\.dismiss) private var dismiss

    public init() {}

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
                            title: L10n.text(lang, en: "General & Appearance", vi: "Chung & Giao diện"),
                            detail: "\(settings.currency.rawValue) · \(settings.language.title(in: lang))"
                        )
                    }

                    NavigationLink {
                        ClaudeSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "sparkles",
                            tint: settings.isAIReady ? .positive : .caution,
                            title: "Claude AI",
                            detail: settings.isAIReady
                                ? settings.model.name
                                : L10n.text(lang, en: "Not set up", vi: "Chưa thiết lập")
                        )
                    }

                    NavigationLink {
                        ShortcutsSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "bolt.horizontal.fill",
                            tint: .accent,
                            title: L10n.text(lang, en: "Auto-Capture & Shortcuts", vi: "Tự động ghi & Phím tắt"),
                            detail: L10n.text(lang, en: "Apple Pay, Bank Email & SMS", vi: "Apple Pay, Email & SMS ngân hàng")
                        )
                    }

                    NavigationLink {
                        EmailInboxSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "envelope.badge.fill",
                            tint: settings.isEmailInboxConfigured ? .positive : .info,
                            title: L10n.text(lang, en: "Cloud Bank Email Inbox", vi: "Hộp thư Email ngân hàng"),
                            detail: settings.isEmailInboxConfigured
                                ? L10n.text(lang, en: "Connected", vi: "Đã kết nối")
                                : L10n.text(lang, en: "Zero-Shortcuts Gmail / Mail sync", vi: "Tự động từ Gmail, không cần Phím tắt")
                        )
                    }

                    NavigationLink {
                        CloudSharingSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "icloud.fill",
                            tint: cloudSync.phase == .running ? .info : .textSecondary,
                            title: L10n.text(lang, en: "iCloud & Household", vi: "iCloud & Gia đình"),
                            detail: cloudStatusShort(lang: lang)
                        )
                    }

                    NavigationLink {
                        BackupSettingsPane()
                    } label: {
                        settingsRow(
                            symbol: "arrow.up.arrow.down.circle",
                            tint: nil,
                            title: L10n.text(lang, en: "Backup & Data", vi: "Sao lưu & Dữ liệu"),
                            detail: L10n.text(lang, en: "JSON import / export", vi: "Nhập / xuất JSON")
                        )
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Settings", vi: "Cài đặt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(lang, en: "Done", vi: "Xong")) { dismiss() }
                }
            }
        }
    }

    private func settingsRow(symbol: String, tint: Color?, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            SettingsIconTile(symbol: symbol, tint: tint, size: 32)
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
                ? L10n.text(lang, en: "Joined household", vi: "Đã tham gia gia đình")
                : (cloudSync.participantNames.isEmpty
                    ? L10n.text(lang, en: "Synced", vi: "Đang đồng bộ")
                    : L10n.text(lang, en: "Shared with \(cloudSync.participantNames.joined(separator: ", "))", vi: "Chia sẻ với \(cloudSync.participantNames.joined(separator: ", "))"))
        case .off: return L10n.text(lang, en: "Off", vi: "Tắt")
        case .noAccount: return L10n.text(lang, en: "Sign in to iCloud", vi: "Chưa đăng nhập iCloud")
        case .unavailable: return L10n.text(lang, en: "Unavailable", vi: "Không khả dụng")
        case .checkingAccount, .accountUnavailable: return L10n.text(lang, en: "Checking…", vi: "Đang kiểm tra…")
        }
    }
}
