import AppServices
import DesignSystem
import SwiftUI
import TallyCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Mac only: the local MCP server that lets assistants such as Claude Code or Codex work with
/// this household's data.
struct MCPSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(MCPServer.self) private var server

    @State private var portDraft = ""
    @State private var token: String?
    @State private var copiedID: String?
    @State private var confirmingRegenerate = false

    private var url: String {
        if case .running(let port) = server.state { return MCPServer.url(port: port) }
        return MCPServer.url(port: settings.mcpPort)
    }

    private var parsedPort: Int? {
        guard let port = Int(portDraft.trimmingCharacters(in: .whitespaces)), AppSettings.mcpPortRange.contains(port) else { return nil }
        return port
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    SettingsIconTile(symbol: "message.fill", tint: statusTint, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(lang, en: "Talk to Tally from other assistants", vi: "Trò chuyện với Tally từ trợ lý khác", zh: "在其他助手中使用 Tally"))
                            .font(.appHeading)
                        Text(L10n.text(
                            lang,
                            en: "Runs an MCP server on this Mac so Claude Code, Codex and other MCP clients can read your budget with Tally's own calculations. It only accepts connections from this Mac, and only while Tally is open.",
                            vi: "Chạy một máy chủ MCP trên máy Mac này để Claude Code, Codex và các ứng dụng MCP khác đọc ngân sách của bạn bằng chính các phép tính của Tally. Chỉ nhận kết nối từ máy Mac này và chỉ khi Tally đang mở.",
                            zh: "在这台 Mac 上运行 MCP 服务器，让 Claude Code、Codex 等 MCP 客户端使用 Tally 自己的计算来读取您的预算。仅接受来自本机的连接，且仅在 Tally 打开时可用。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.vertical, 4)

                Toggle(L10n.text(lang, en: "MCP server", vi: "Máy chủ MCP", zh: "MCP 服务器"), isOn: $settings.mcpServerEnabled)

                HStack {
                    Text(L10n.text(lang, en: "Status", vi: "Trạng thái", zh: "状态"))
                    Spacer()
                    Text(statusText(lang))
                        .foregroundStyle(statusIsError ? Color.negative : Color.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Toggle(isOn: $settings.mcpAllowsChanges) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "Allow changes", vi: "Cho phép thay đổi", zh: "允许更改"))
                        Text(L10n.text(
                            lang,
                            en: "Off: assistants can only read. On: they can also add, edit and delete transactions, budgets, goals and plans.",
                            vi: "Tắt: trợ lý chỉ được đọc. Bật: trợ lý còn có thể thêm, sửa và xoá giao dịch, ngân sách, mục tiêu và khoản trả góp.",
                            zh: "关闭：助手只能读取。开启：助手还可以添加、编辑和删除账单、预算、目标和分期计划。"
                        ))
                        .font(.appCaption)
                        .foregroundStyle(Color.textSecondary)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Access", vi: "Quyền truy cập", zh: "访问权限"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Salary follows the eye button: while salary is hidden in Tally, assistants do not receive salary figures or totals that include them.",
                    vi: "Lương tuân theo nút con mắt: khi lương đang ẩn trong Tally, trợ lý không nhận được số lương hay các tổng có chứa lương.",
                    zh: "工资遵循“眼睛”按钮：当工资在 Tally 中隐藏时，助手不会收到工资数字或包含工资的合计。"
                ))
            }

            if settings.mcpServerEnabled, let token {
                Section {
                    snippetRow(id: "claude", title: "Claude Code", detail: L10n.text(lang, en: "Run in Terminal", vi: "Chạy trong Terminal", zh: "在终端中运行"), text: MCPClientSetup.claudeCode(url: url, token: token), token: token, lang: lang)
                    snippetRow(id: "codex", title: "Codex", detail: L10n.text(lang, en: "Add to ~/.codex/config.toml", vi: "Thêm vào ~/.codex/config.toml", zh: "添加到 ~/.codex/config.toml"), text: MCPClientSetup.codex(url: url, token: token), token: token, lang: lang)
                    snippetRow(id: "other", title: L10n.text(lang, en: "Other clients", vi: "Ứng dụng khác", zh: "其他客户端"), detail: L10n.text(lang, en: "Streamable HTTP with a bearer token", vi: "Streamable HTTP với bearer token", zh: "使用 Bearer 令牌的 Streamable HTTP"), text: MCPClientSetup.genericJSON(url: url, token: token), token: token, lang: lang)
                } header: {
                    formSectionHeader(L10n.text(lang, en: "Connect", vi: "Kết nối", zh: "连接"))
                } footer: {
                    formSectionFooter(L10n.text(
                        lang,
                        en: "Copy puts the full text, including the access token, on the clipboard.",
                        vi: "Sao chép sẽ đưa toàn bộ nội dung, gồm cả mã truy cập, vào bộ nhớ tạm.",
                        zh: "拷贝会将完整内容（包括访问令牌）放入剪贴板。"
                    ))
                }

                Section {
                    HStack {
                        Text(L10n.text(lang, en: "Access token", vi: "Mã truy cập", zh: "访问令牌"))
                        Spacer()
                        Text(MCPClientSetup.masked(token))
                            .font(.appCaption.monospaced())
                            .foregroundStyle(Color.textSecondary)
                        copyButton(id: "token", text: token, lang: lang)
                    }
                    Button(L10n.text(lang, en: "Create a new token…", vi: "Tạo mã mới…", zh: "生成新令牌…"), role: .destructive) {
                        confirmingRegenerate = true
                    }
                    .pillButton()
                } footer: {
                    formSectionFooter(L10n.text(
                        lang,
                        en: "The token is kept in this Mac's Keychain and is not synced. Anyone with it can reach your data from this Mac, so treat it like a password.",
                        vi: "Mã được lưu trong Keychain của máy Mac này và không đồng bộ. Ai có mã đều truy cập được dữ liệu từ máy này, hãy giữ nó như mật khẩu.",
                        zh: "令牌保存在这台 Mac 的钥匙串中，不会同步。任何持有令牌的人都能在本机访问您的数据，请像密码一样保管。"
                    ))
                }
            }

            Section {
                HStack(spacing: 10) {
                    TextField(String(AppSettings.defaultMCPPort), text: $portDraft)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()
                    Button(L10n.text(lang, en: "Apply", vi: "Áp dụng", zh: "应用")) {
                        if let parsedPort { settings.mcpPort = parsedPort }
                    }
                    .pillButton(prominent: true)
                    .disabled(parsedPort == nil || parsedPort == settings.mcpPort)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Port", vi: "Cổng", zh: "端口"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Change it only if another app already uses this port (\(AppSettings.mcpPortRange.lowerBound)–\(AppSettings.mcpPortRange.upperBound)). Clients must then be set up again with the new address.",
                    vi: "Chỉ đổi khi ứng dụng khác đã dùng cổng này (\(AppSettings.mcpPortRange.lowerBound)–\(AppSettings.mcpPortRange.upperBound)). Sau đó cần thiết lập lại các ứng dụng với địa chỉ mới.",
                    zh: "仅当其他应用已占用此端口时才需更改（\(AppSettings.mcpPortRange.lowerBound)–\(AppSettings.mcpPortRange.upperBound)）。更改后需用新地址重新设置客户端。"
                ))
            }
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "MCP Server", vi: "Máy chủ MCP", zh: "MCP 服务器"))
        .onAppear {
            portDraft = String(settings.mcpPort)
            refresh()
        }
        .onChange(of: settings.mcpServerEnabled) { _, _ in refresh() }
        .onChange(of: settings.mcpPort) { _, _ in refresh() }
        .confirmationDialog(
            L10n.text(lang, en: "Create a new access token?", vi: "Tạo mã truy cập mới?", zh: "生成新的访问令牌？"),
            isPresented: $confirmingRegenerate,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Create new token", vi: "Tạo mã mới", zh: "生成新令牌"), role: .destructive) {
                _ = KeychainStore.regenerateMCPToken()
                refresh()
            }
        } message: {
            Text(L10n.text(
                lang,
                en: "Assistants set up with the current token will stop working until you set them up again.",
                vi: "Các trợ lý đã thiết lập bằng mã hiện tại sẽ ngừng hoạt động cho đến khi bạn thiết lập lại.",
                zh: "使用当前令牌设置的助手将停止工作，直到您重新设置。"
            ))
        }
    }

    /// Brings the server in line with the settings, then shows the token it is using.
    private func refresh() {
        server.apply(settings: settings, store: store)
        token = settings.mcpServerEnabled ? KeychainStore.readMCPToken() : nil
    }

    private var statusIsError: Bool {
        if case .failed = server.state { return true }
        return false
    }

    private var statusTint: Color {
        switch server.state {
        case .running: return .positive
        case .failed: return .caution
        case .stopped, .starting: return .info
        }
    }

    private func statusText(_ lang: AppLanguage) -> String {
        switch server.state {
        case .stopped: return L10n.text(lang, en: "Off", vi: "Tắt", zh: "已关闭")
        case .starting: return L10n.text(lang, en: "Starting…", vi: "Đang khởi động…", zh: "正在启动…")
        case .running(let port): return L10n.text(lang, en: "Running at \(MCPServer.url(port: port))", vi: "Đang chạy tại \(MCPServer.url(port: port))", zh: "运行于 \(MCPServer.url(port: port))")
        case .failed(let message): return message
        }
    }

    private func snippetRow(id: String, title: String, detail: String, text: String, token: String, lang: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.appHeading)
                    Text(detail).font(.appCaption).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                copyButton(id: id, text: text, lang: lang)
            }
            // The token is masked on screen; Copy carries the real one.
            Text(text.replacingOccurrences(of: token, with: MCPClientSetup.masked(token)))
                .font(.appCaption.monospaced())
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func copyButton(id: String, text: String, lang: AppLanguage) -> some View {
        Button {
            copy(text)
            copiedID = id
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if copiedID == id { copiedID = nil }
            }
        } label: {
            HStack(spacing: 5) {
                CozyUIIcon(copiedID == id ? .checkmark : .copy, size: 13, color: Color.textPrimary)
                Text(copiedID == id
                    ? L10n.text(lang, en: "Copied", vi: "Đã chép", zh: "已拷贝")
                    : L10n.text(lang, en: "Copy", vi: "Sao chép", zh: "拷贝"))
            }
        }
        .pillButton()
    }

    private func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}
