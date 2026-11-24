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

public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case ai
    case shortcuts
    case emailInbox
    case cloud
    case mcp
    case backup

    public var id: String { rawValue }

    /// The categories this platform offers. The MCP server runs in the Mac app only.
    public static var available: [SettingsCategory] {
        #if os(macOS)
        return allCases
        #else
        return allCases.filter { $0 != .mcp }
        #endif
    }
}

public struct SettingsView: View {
    public var isModal: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(CloudSync.self) private var cloudSync
    @Environment(MCPServer.self) private var mcpServer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarBottomInset) private var tabBarBottomInset
    @Environment(\.tabBarVisibility) private var tabBarVisibility
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @State private var path: [SettingsCategory] = []
    @State private var selectedCategory: SettingsCategory = .general

    public init(isModal: Bool = false) {
        self.isModal = isModal
    }

    private var isWideLayout: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    public var body: some View {
        let lang = settings.language
        Group {
            if isWideLayout {
                wideWorkspace(lang: lang)
            } else {
                compactListStack(lang: lang)
            }
        }
        .onAppear {
            if !isModal && !isWideLayout {
                tabBarVisibility?.setHidden(!path.isEmpty, for: "settings")
            }
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            if !isModal && !isWideLayout {
                tabBarVisibility?.setHidden(!isEmpty, for: "settings")
            }
        }
        .onChange(of: isWideLayout) { _, wide in
            if wide {
                tabBarVisibility?.setHidden(false, for: "settings")
            } else if !isModal {
                tabBarVisibility?.setHidden(!path.isEmpty, for: "settings")
            }
        }
    }

    // MARK: - Compact iPhone Single-Column Flow

    private func compactListStack(lang: AppLanguage) -> some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(SettingsCategory.available) { category in
                        NavigationLink(value: category) {
                            settingsRow(for: category, lang: lang)
                        }
                    }
                }

                if !isModal && tabBarBottomInset > 0 {
                    Section {
                        Color.clear
                            .frame(height: tabBarBottomInset)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .pageBackground()
            .navigationTitle(L10n.text(lang, en: "Settings", vi: "Cài đặt", zh: "设置"))
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
                    }
                }
            }
            .navigationDestination(for: SettingsCategory.self) { category in
                detailPane(for: category)
                    .environment(\.tabBarBottomInset, 0)
            }
        }
    }

    // MARK: - Wide iPad & Mac 2-Pane Workspace

    private func wideWorkspace(lang: AppLanguage) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(L10n.text(lang, en: "Settings", vi: "Cài đặt", zh: "设置"))
                        .font(.appTitle)
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    if isModal {
                        Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
                            .pillButton()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SettingsCategory.available) { category in
                            WideSettingsCategoryRow(
                                meta: categoryMeta(for: category, lang: lang),
                                isSelected: selectedCategory == category
                            ) {
                                CozyHaptics.selection()
                                CozySounds.play(.tick)
                                withAnimation(.snappy(duration: 0.16)) {
                                    selectedCategory = category
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 268)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)

            Rectangle()
                .fill(Color.hairline)
                .frame(width: 1)
                .ignoresSafeArea()

            NavigationStack {
                detailPane(for: selectedCategory)
                    .id(selectedCategory)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.tabBarBottomInset, 0)
        }
        .pageBackground()
    }

    // MARK: - Shared Row & Pane Builders

    private struct CategoryMeta {
        let symbol: String
        let tint: Color?
        let title: String
        let detail: String
    }

    private func categoryMeta(for category: SettingsCategory, lang: AppLanguage) -> CategoryMeta {
        switch category {
        case .general:
            return CategoryMeta(
                symbol: "slider.horizontal.3",
                tint: nil,
                title: L10n.text(lang, en: "General & Appearance", vi: "Chung & Giao diện", zh: "通用与外观"),
                detail: "\(settings.currency.rawValue) · \(settings.language.title(in: lang))"
            )
        case .ai:
            return CategoryMeta(
                symbol: "sparkles",
                tint: settings.isAIReady ? .positive : .caution,
                title: L10n.text(lang, en: "AI Assistant", vi: "Trợ lý AI", zh: "AI 助手"),
                detail: settings.activeProviderSummary(in: lang)
            )
        case .shortcuts:
            return CategoryMeta(
                symbol: "bolt.horizontal.fill",
                tint: .accent,
                title: L10n.text(lang, en: "Auto-Capture & Shortcuts", vi: "Tự động ghi & Phím tắt", zh: "自动记账与快捷指令"),
                detail: L10n.text(lang, en: "Apple Pay, Bank Email & SMS", vi: "Apple Pay, Email & SMS ngân hàng", zh: "Apple Pay、银行邮件与短信")
            )
        case .emailInbox:
            return CategoryMeta(
                symbol: "envelope.badge.fill",
                tint: settings.isEmailInboxConfigured ? .positive : .info,
                title: L10n.text(lang, en: "Cloud Bank Email Inbox", vi: "Hộp thư Email ngân hàng", zh: "云端银行邮件收件箱"),
                detail: settings.isEmailInboxConfigured
                    ? L10n.text(lang, en: "Connected", vi: "Đã kết nối", zh: "已连接")
                    : L10n.text(lang, en: "Zero-Shortcuts Gmail / Mail sync", vi: "Tự động từ Gmail, không cần Phím tắt", zh: "无需快捷指令自动同步 Gmail")
            )
        case .cloud:
            return CategoryMeta(
                symbol: "icloud.fill",
                tint: cloudSync.phase == .running ? .info : .textSecondary,
                title: L10n.text(lang, en: "iCloud & Household", vi: "iCloud & Gia đình", zh: "iCloud 与家庭共享"),
                detail: cloudStatusShort(lang: lang)
            )
        case .mcp:
            return CategoryMeta(
                symbol: "message.fill",
                tint: mcpTint,
                title: L10n.text(lang, en: "MCP Server", vi: "Máy chủ MCP", zh: "MCP 服务器"),
                detail: mcpStatusShort(lang: lang)
            )
        case .backup:
            return CategoryMeta(
                symbol: "arrow.up.arrow.down.circle",
                tint: nil,
                title: L10n.text(lang, en: "Backup & Data", vi: "Sao lưu & Dữ liệu", zh: "备份与数据"),
                detail: L10n.text(lang, en: "JSON import / export", vi: "Nhập / xuất JSON", zh: "JSON 导入 / 导出")
            )
        }
    }

    @ViewBuilder
    private func detailPane(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            GeneralSettingsPane()
        case .ai:
            ClaudeSettingsPane()
        case .shortcuts:
            ShortcutsSettingsPane()
        case .emailInbox:
            EmailInboxSettingsPane()
        case .cloud:
            CloudSharingSettingsPane()
        case .mcp:
            MCPSettingsPane()
        case .backup:
            BackupSettingsPane()
        }
    }

    private func settingsRow(for category: SettingsCategory, lang: AppLanguage) -> some View {
        let meta = categoryMeta(for: category, lang: lang)
        return HStack(spacing: 12) {
            SettingsIconTile(symbol: meta.symbol, tint: meta.tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.title).font(.appBodyMedium)
                Text(meta.detail).font(.appCaption).foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var mcpTint: Color {
        switch mcpServer.state {
        case .running: return .positive
        case .failed: return .caution
        case .stopped, .starting: return .info
        }
    }

    private func mcpStatusShort(lang: AppLanguage) -> String {
        switch mcpServer.state {
        case .running:
            return settings.mcpAllowsChanges
                ? L10n.text(lang, en: "On · can make changes", vi: "Bật · được thay đổi", zh: "已开启 · 可更改")
                : L10n.text(lang, en: "On · read-only", vi: "Bật · chỉ đọc", zh: "已开启 · 只读")
        case .starting: return L10n.text(lang, en: "Starting…", vi: "Đang khởi động…", zh: "正在启动…")
        case .failed: return L10n.text(lang, en: "Not running", vi: "Không chạy", zh: "未运行")
        case .stopped: return L10n.text(lang, en: "Claude Code, Codex & more", vi: "Claude Code, Codex và hơn nữa", zh: "Claude Code、Codex 等")
        }
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

    private struct WideSettingsCategoryRow: View {
        let meta: CategoryMeta
        let isSelected: Bool
        let action: () -> Void

        @Environment(\.colorScheme) private var colorScheme
        @State private var isHovering = false

        private var activeFill: Color {
            colorScheme == .dark ? Color(hex: 0x4E3B34) : Color(hex: 0xFFE9DB)
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    SettingsIconTile(symbol: meta.symbol, tint: meta.tint, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meta.title)
                            .font(.appControl)
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(meta.detail)
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? activeFill : (isHovering ? Color.rowHover : Color.clear))
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
        }
    }
}
