import AppServices
import DesignSystem
import MCPKit
import SwiftUI
import TallyCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Cross-platform MCP & AI Assistants pane:
/// - 1-tap Cloudflare Worker deployment on Mac (synced via iCloud Keychain to iPhone & iPad)
/// - 1-tap auto-configuration of Claude Code, Codex, Claude Desktop, Antigravity & Cursor on Mac
/// - 1-URL quick connector + OAuth 2.1 6-digit pairing for Claude iOS/Web, ChatGPT, and Muse
/// - QR code & AirDrop pairing for iPhone / partner devices
struct MCPSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(MCPServer.self) private var server
    @Environment(RemoteMCPSync.self) private var remoteMCP
    @Environment(\.openURL) private var openURL

    @State private var portDraft = ""
    @State private var localToken: String?
    @State private var cloudCreds: KeychainStore.CloudMCPCredentials?
    @State private var copiedID: String?
    @State private var pasteFeedback: String?

    @State private var isDeploying = false
    @State private var deployProgress = ""
    @State private var deployError: String?
    @State private var deploySuccessMessage: String?

    #if os(macOS)
    @State private var detectedClients: [DetectedMCPClient] = []
    @State private var clientError: String?
    #endif

    @State private var showingQRCode = false
    @State private var showingQRScanner = false
    @State private var showingOAuthSection = false
    @State private var showingAdvanced = false
    @State private var confirmingRegenerateCloud = false
    @State private var confirmingRegenerateLocal = false
    @State private var confirmingDisconnectCloud = false

    // Manual Cloud entry drafts (inside Advanced)
    @State private var manualURLDraft = ""
    @State private var manualSyncDraft = ""
    @State private var manualTokenDraft = ""
    @State private var manualTestStatus: String?
    @State private var manualTestIsError = false
    @State private var isTestingManual = false

    private var localURL: String {
        if case .running(let port) = server.state { return MCPServer.url(port: port) }
        return MCPServer.url(port: settings.mcpPort)
    }

    private var parsedPort: Int? {
        guard let port = Int(portDraft.trimmingCharacters(in: .whitespaces)),
              AppSettings.mcpPortRange.contains(port)
        else { return nil }
        return port
    }

    private var cloudBaseURL: URL? {
        guard settings.isCloudMCPConfigured else { return nil }
        return MCPSetupLink.normalizeWorkerURL(settings.cloudMCPURL)
    }

    private var activeEndpoint: MCPEndpointConfig? {
        if let base = cloudBaseURL, let token = cloudCreds?.accessToken {
            return MCPEndpointConfig(
                url: MCPSetupLink.mcpURL(baseURL: base),
                quickURL: MCPSetupLink.quickConnectorURL(baseURL: base, token: token),
                token: token
            )
        }
        #if os(macOS)
        if settings.mcpServerEnabled, let localToken {
            let port: Int = {
                if case .running(let p) = server.state { return p }
                return settings.mcpPort
            }()
            return MCPEndpointConfig(
                url: MCPServer.url(port: port),
                quickURL: MCPSetupLink.localQuickURL(port: port, token: localToken),
                token: localToken
            )
        }
        #endif
        return nil
    }

    private var pairingDeepLink: URL? {
        guard let base = cloudBaseURL, let creds = cloudCreds else { return nil }
        return MCPSetupLink.pairingDeepLink(
            baseURL: base,
            syncSecret: creds.syncSecret,
            accessToken: creds.accessToken
        )
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            heroSection(lang: lang)

            #if os(macOS)
            if let endpoint = activeEndpoint {
                macClientsSection(endpoint: endpoint, lang: lang)
            }
            #endif

            if let endpoint = activeEndpoint, settings.isCloudMCPConfigured {
                mobileAndWebConnectorsSection(endpoint: endpoint, lang: lang)
                pairDeviceSection(lang: lang)
            }

            accessAndPrivacySection(lang: lang)

            advancedSection(lang: lang)
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "MCP & AI Assistants", vi: "MCP & Trợ lý AI", zh: "MCP 与 AI 助手"))
        .onAppear {
            portDraft = String(settings.mcpPort)
            manualURLDraft = settings.cloudMCPURL
            refreshState()
        }
        .onChange(of: settings.mcpServerEnabled) { _, _ in refreshState() }
        .onChange(of: settings.mcpPort) { _, _ in refreshState() }
        .onChange(of: settings.cloudMCPEnabled) { _, _ in
            refreshState()
            if settings.isCloudMCPConfigured {
                Task { await remoteMCP.pushConfig(settings: settings) }
            }
        }
        .onChange(of: settings.mcpAllowsChanges) { _, _ in
            if settings.isCloudMCPConfigured {
                Task { await remoteMCP.pushConfig(settings: settings) }
            }
        }
        .sheet(isPresented: $showingQRCode) {
            if let url = pairingDeepLink {
                MCPQRCodeSheet(
                    pairingURL: url,
                    workerHost: cloudBaseURL?.host ?? settings.cloudMCPURL,
                    language: lang
                )
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingQRScanner) {
            MCPQRScannerSheet(language: lang) { payload in
                Task { await applyPairingPayload(payload) }
            }
        }
        #endif
        .confirmationDialog(
            L10n.text(lang, en: "Create a new Cloud access token?", vi: "Tạo mã truy cập Cloud mới?", zh: "生成新的云端访问令牌？"),
            isPresented: $confirmingRegenerateCloud,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Create new token", vi: "Tạo mã mới", zh: "生成新令牌"), role: .destructive) {
                Task { await rotateCloudToken() }
            }
        } message: {
            Text(L10n.text(
                lang,
                en: "Existing assistants and OAuth sessions will stop working until you tap Update on them.",
                vi: "Các trợ lý và phiên OAuth hiện tại sẽ ngừng hoạt động cho đến khi bạn bấm Cập nhật lại.",
                zh: "现有的助手和 OAuth 会话将停止工作，直到您重新更新配置。"
            ))
        }
        .confirmationDialog(
            L10n.text(lang, en: "Create a new Mac access token?", vi: "Tạo mã truy cập Mac mới?", zh: "生成新的 Mac 访问令牌？"),
            isPresented: $confirmingRegenerateLocal,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Create new token", vi: "Tạo mã mới", zh: "生成新令牌"), role: .destructive) {
                _ = KeychainStore.regenerateMCPToken()
                refreshState()
            }
        }
        .confirmationDialog(
            L10n.text(lang, en: "Disconnect Cloud MCP?", vi: "Ngắt kết nối Cloud MCP?", zh: "断开 Cloud MCP？"),
            isPresented: $confirmingDisconnectCloud,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Disconnect", vi: "Ngắt kết nối", zh: "断开连接"), role: .destructive) {
                settings.disconnectCloudMCP()
                remoteMCP.resetStateOnDisconnect()
                manualURLDraft = ""
                manualSyncDraft = ""
                manualTokenDraft = ""
                refreshState()
            }
        }
    }

    // MARK: - Section 1: Hero & 1-Tap Setup

    @ViewBuilder
    private func heroSection(lang: AppLanguage) -> some View {
        @Bindable var settings = settings

        Section {
            HStack(alignment: .top, spacing: 12) {
                SettingsIconTile(symbol: "message.fill", tint: heroTint, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle(lang))
                        .font(.appHeading)
                    Text(heroSubtitle(lang))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)

            if settings.isCloudMCPConfigured {
                Toggle(L10n.text(lang, en: "Cloud MCP (24/7)", vi: "Cloud MCP (24/7)", zh: "云端 MCP（全天候）"), isOn: $settings.cloudMCPEnabled)

                HStack {
                    Text(L10n.text(lang, en: "Status", vi: "Trạng thái", zh: "状态"))
                    Spacer()
                    if remoteMCP.isSyncing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(lang, en: "Syncing…", vi: "Đang đồng bộ…", zh: "正在同步…"))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else if let err = remoteMCP.lastError {
                        Text(err)
                            .font(.appCaption)
                            .foregroundStyle(Color.negative)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(settings.cloudMCPEnabled
                            ? L10n.text(lang, en: "Online · \(cloudBaseURL?.host ?? "")", vi: "Trực tuyến · \(cloudBaseURL?.host ?? "")", zh: "在线 · \(cloudBaseURL?.host ?? "")")
                            : L10n.text(lang, en: "Paused", vi: "Tạm dừng", zh: "已暂停"))
                            .foregroundStyle(settings.cloudMCPEnabled ? Color.positive : Color.textSecondary)
                            .lineLimit(1)
                    }
                }

                if let last = remoteMCP.lastSynced {
                    HStack {
                        Text(L10n.text(lang, en: "Last synced", vi: "Đồng bộ gần nhất", zh: "上次同步"))
                        Spacer()
                        Text(last, style: .relative).foregroundStyle(Color.textSecondary)
                    }
                }

                if let lastCall = remoteMCP.lastMCPCallAt, let tool = remoteMCP.lastMCPTool {
                    HStack {
                        Text(L10n.text(lang, en: "Last assistant call", vi: "Lần trợ lý gọi gần nhất", zh: "最近助手调用"))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(tool).font(.appCaption.monospaced())
                            Text(lastCall, style: .relative).font(.appCaption).foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await remoteMCP.syncNow(settings: settings, store: store) }
                    } label: {
                        HStack(spacing: 6) {
                            CozyUIIcon(.refresh, size: 14, color: Color.onInk)
                            Text(L10n.text(lang, en: "Sync now", vi: "Đồng bộ ngay", zh: "立即同步"))
                        }
                    }
                    .pillButton(prominent: true)
                    .disabled(remoteMCP.isSyncing)

                    Spacer()
                }
            } else {
                #if os(macOS)
                Button {
                    Task { await runOneTapMacDeploy(lang: lang) }
                } label: {
                    if isDeploying {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(deployProgress.isEmpty
                                ? L10n.text(lang, en: "Setting up Cloud MCP…", vi: "Đang thiết lập Cloud MCP…", zh: "正在配置 Cloud MCP…")
                                : deployProgress)
                        }
                    } else {
                        HStack(spacing: 8) {
                            CozyUIIcon(.sparkles, size: 16, color: Color.onInk)
                            Text(L10n.text(lang, en: "1-Tap Set Up Cloud MCP", vi: "Cài đặt Cloud MCP (1 chạm)", zh: "一键配置云端 MCP"))
                        }
                    }
                }
                .blockButton(prominent: true)
                .disabled(isDeploying)

                HStack(spacing: 10) {
                    Button {
                        pastePairingLinkFromClipboard(lang: lang)
                    } label: {
                        HStack(spacing: 5) {
                            CozyUIIcon(.copy, size: 13, color: Color.textPrimary)
                            Text(L10n.text(lang, en: "Paste Setup Link", vi: "Dán liên kết thiết lập", zh: "粘贴设置链接"))
                        }
                    }
                    .pillButton()

                    Spacer()
                }

                Toggle(L10n.text(lang, en: "Use Local Mac Server Only", vi: "Chỉ dùng máy chủ nội bộ trên Mac", zh: "仅使用本机 Mac 服务器"), isOn: $settings.mcpServerEnabled)
                #else
                Button {
                    showingQRScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                        Text(L10n.text(lang, en: "Scan Setup QR Code", vi: "Quét mã QR thiết lập", zh: "扫描设置二维码"))
                    }
                }
                .blockButton(prominent: true)

                Button {
                    pastePairingLinkFromClipboard(lang: lang)
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.copy, size: 14, color: Color.textPrimary)
                        Text(L10n.text(lang, en: "Paste Setup Link", vi: "Dán liên kết thiết lập", zh: "粘贴设置链接"))
                    }
                }
                .pillButton()
                #endif

                if let deployError {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(deployError)
                            .font(.appCaption)
                            .foregroundStyle(Color.negative)
                        #if os(macOS)
                        if deployError.localizedCaseInsensitiveContains("wrangler login") {
                            Button(L10n.text(lang, en: "Copy Cloudflare Login Command", vi: "Chép lệnh đăng nhập Cloudflare", zh: "拷贝 Cloudflare 登录命令")) {
                                let root = MCPCloudDeployer.findRepoRoot(preferredPath: settings.mcpRepoPath)?.path ?? "budget"
                                copy("cd \"\(root)/tools/mcp-server\" && npx wrangler login")
                                copiedID = "wrangler-login"
                            }
                            .pillButton()
                        }
                        #endif
                    }
                }

                if let pasteFeedback {
                    Text(pasteFeedback)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                }
            }

            if let deploySuccessMessage {
                Text(deploySuccessMessage)
                    .font(.appCaption)
                    .foregroundStyle(Color.positive)
            }
        }
    }

    // MARK: - Section 2: Mac 1-Tap Clients

    #if os(macOS)
    @ViewBuilder
    private func macClientsSection(endpoint: MCPEndpointConfig, lang: AppLanguage) -> some View {
        let installed = detectedClients.filter(\.isInstalled)
        let displayed = installed.isEmpty ? detectedClients : installed
        let anyNeedsAction = displayed.contains { $0.state != .connected }
        let anyNeedsUpdate = displayed.contains { $0.state == .needsUpdate }

        Section {
            if anyNeedsAction {
                Button {
                    connectAllMacClients(endpoint: endpoint, lang: lang)
                } label: {
                    HStack(spacing: 8) {
                        CozyUIIcon(.bolt, size: 15, color: Color.onInk)
                        Text(anyNeedsUpdate
                            ? L10n.text(lang, en: "Update All Detected Apps", vi: "Cập nhật tất cả ứng dụng", zh: "更新所有已检测应用")
                            : L10n.text(lang, en: "Connect All Detected Apps", vi: "Kết nối tất cả ứng dụng", zh: "一键连接所有已检测应用"))
                    }
                }
                .blockButton(prominent: true)
            }

            ForEach(displayed) { client in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(client.kind.displayName).font(.appBodyMedium)
                            clientStateTag(client.state, lang: lang)
                        }
                        if !client.isInstalled {
                            Text(L10n.text(lang, en: "Not detected on this Mac", vi: "Chưa thấy trên máy Mac này", zh: "未在此 Mac 上检测到"))
                                .font(.appCaption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Spacer()
                    if client.state == .connected {
                        Button(L10n.text(lang, en: "Remove", vi: "Gỡ", zh: "移除")) {
                            disconnectMacClient(client.kind)
                        }
                        .pillButton()
                    } else {
                        Button(client.state == .needsUpdate
                            ? L10n.text(lang, en: "Update", vi: "Cập nhật", zh: "更新")
                            : L10n.text(lang, en: "Connect", vi: "Kết nối", zh: "连接")) {
                            connectMacClient(client.kind, endpoint: endpoint)
                        }
                        .pillButton(prominent: true)
                    }
                }
                .padding(.vertical, 2)
            }

            if let clientError {
                Text(clientError)
                    .font(.appCaption)
                    .foregroundStyle(Color.negative)
            }
        } header: {
            formSectionHeader(L10n.text(lang, en: "Connect on This Mac", vi: "Kết nối trên máy Mac này", zh: "在此 Mac 上连接"))
        } footer: {
            formSectionFooter(
                settings.isCloudMCPConfigured
                    ? L10n.text(lang, en: "Writes your Cloud MCP endpoint into each app's config file cleanly without overwriting your other MCP servers. Restart open apps once if they don't reload automatically.", vi: "Ghi địa chỉ Cloud MCP vào tệp cấu hình của từng ứng dụng mà không làm mất các máy chủ khác.", zh: "将云端 MCP 地址写入各应用配置（保留原有其他服务器）。部分桌面应用可能需要重启以加载新配置。")
                    : L10n.text(lang, en: "Writes your local Mac MCP endpoint (127.0.0.1) into each app's config file.", vi: "Ghi địa chỉ MCP nội bộ (127.0.0.1) vào từng ứng dụng.", zh: "将本机 Mac MCP 地址（127.0.0.1）写入各应用配置。")
            )
        }
    }

    @ViewBuilder
    private func clientStateTag(_ state: MCPClientConnectionState, lang: AppLanguage) -> some View {
        switch state {
        case .connected:
            Tag(text: L10n.text(lang, en: "Connected", vi: "Đã kết nối", zh: "已连接"), color: .positive)
        case .needsUpdate:
            Tag(text: L10n.text(lang, en: "Update", vi: "Cần cập nhật", zh: "需更新"), color: .caution)
        case .notConfigured:
            Tag(text: L10n.text(lang, en: "Not connected", vi: "Chưa kết nối", zh: "未连接"), color: .textSecondary)
        }
    }
    #endif

    // MARK: - Section 3: Mobile, Web & Muse Connectors

    @ViewBuilder
    private func mobileAndWebConnectorsSection(endpoint: MCPEndpointConfig, lang: AppLanguage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "1-URL Quick Connector", vi: "Liên kết kết nối nhanh (1 URL)", zh: "单链接快速连接器"))
                            .font(.appHeading)
                        Text(L10n.text(lang, en: "Works in Claude iOS/Web, ChatGPT, and Muse without extra headers", vi: "Dùng cho Claude iOS/Web, ChatGPT và Muse, không cần điền header", zh: "适用于 Claude iOS/Web、ChatGPT 和 Muse，无需手动配置请求头"))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    copyButton(id: "quick-url", text: endpoint.quickURL, lang: lang)
                }

                Text(endpoint.quickURL.replacingOccurrences(of: endpoint.token, with: MCPClientSetup.masked(endpoint.token)))
                    .font(.appCaption.monospaced())
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)

            quickAppRow(
                id: "claude-web",
                title: L10n.text(lang, en: "Claude (iPhone, Web & Desktop)", vi: "Claude (iPhone, Web & Desktop)", zh: "Claude（iPhone、网页与桌面端）"),
                subtitle: L10n.text(lang, en: "Copies link & opens Claude Connectors — add custom connector & paste", vi: "Chép liên kết & mở Claude Connectors — thêm connector và dán", zh: "拷贝链接并打开 Claude 连接器 — 添加自定义连接器并粘贴"),
                buttonLabel: copiedID == "claude-web"
                    ? L10n.text(lang, en: "Copied!", vi: "Đã chép!", zh: "已拷贝！")
                    : L10n.text(lang, en: "Copy & Open", vi: "Chép & Mở", zh: "拷贝并打开"),
                lang: lang
            ) {
                copyAndMark("claude-web", text: endpoint.quickURL)
                if let target = URL(string: "https://claude.ai/settings/connectors") {
                    openURL(target)
                }
            }

            quickAppRow(
                id: "chatgpt-web",
                title: "ChatGPT",
                subtitle: L10n.text(lang, en: "Copies link & opens ChatGPT Connectors", vi: "Chép liên kết & mở ChatGPT Connectors", zh: "拷贝链接并打开 ChatGPT 连接器"),
                buttonLabel: copiedID == "chatgpt-web"
                    ? L10n.text(lang, en: "Copied!", vi: "Đã chép!", zh: "已拷贝！")
                    : L10n.text(lang, en: "Copy & Open", vi: "Chép & Mở", zh: "拷贝并打开"),
                lang: lang
            ) {
                copyAndMark("chatgpt-web", text: endpoint.quickURL)
                if let target = URL(string: "https://chatgpt.com/#settings/Connectors") {
                    openURL(target)
                }
            }

            quickAppRow(
                id: "muse-copy",
                title: "Muse",
                subtitle: L10n.text(lang, en: "Paste into Muse's MCP Connector URL (or use clean URL + 6-digit code below)", vi: "Dán vào cài đặt MCP của Muse (hoặc dùng URL gọn + mã 6 số bên dưới)", zh: "粘贴到 Muse 的 MCP 连接器地址（或使用下方标准 URL 与 6 位配对码）"),
                buttonLabel: copiedID == "muse-copy"
                    ? L10n.text(lang, en: "Copied!", vi: "Đã chép!", zh: "已拷贝！")
                    : L10n.text(lang, en: "Copy Link", vi: "Chép liên kết", zh: "拷贝链接"),
                lang: lang
            ) {
                copyAndMark("muse-copy", text: endpoint.quickURL)
            }

            DisclosureGroup(isExpanded: $showingOAuthSection) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.text(lang, en: "Clean OAuth MCP URL", vi: "URL MCP chuẩn OAuth", zh: "标准 OAuth MCP URL"))
                                .font(.appBodyMedium)
                            Text(endpoint.url)
                                .font(.appCaption.monospaced())
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        copyButton(id: "oauth-url", text: endpoint.url, lang: lang)
                    }

                    if let code = remoteMCP.pairingCode {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.text(lang, en: "6-Digit Pairing Code", vi: "Mã ghép nối 6 chữ số", zh: "6 位配对码"))
                                    .font(.appCaption)
                                    .foregroundStyle(Color.textSecondary)
                                Text(code)
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .tracking(4)
                                if let exp = remoteMCP.pairingCodeExpiresAt {
                                    Text(L10n.text(lang, en: "Expires ", vi: "Hết hạn ", zh: "过期时间 ") + exp.formatted(date: .omitted, time: .shortened))
                                        .font(.appCaption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            Spacer()
                            copyButton(id: "oauth-code", text: code, lang: lang)
                        }
                        .padding(12)
                        .background(Color.fieldBackground, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                    }

                    Button {
                        Task { await remoteMCP.requestPairingCode(settings: settings) }
                    } label: {
                        if remoteMCP.isRequestingPairingCode {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.text(lang, en: "Generating…", vi: "Đang tạo…", zh: "生成中…"))
                            }
                        } else {
                            Text(remoteMCP.pairingCode == nil
                                ? L10n.text(lang, en: "Generate 6-Digit Pairing Code", vi: "Tạo mã ghép nối 6 số", zh: "生成 6 位配对码")
                                : L10n.text(lang, en: "Generate New Code", vi: "Tạo mã mới", zh: "重新生成配对码"))
                        }
                    }
                    .pillButton(prominent: true)
                    .disabled(remoteMCP.isRequestingPairingCode)
                }
                .padding(.vertical, 4)
            } label: {
                Text(L10n.text(lang, en: "OAuth Login (Clean URL + 6-Digit Code)", vi: "Đăng nhập OAuth (URL gọn + mã 6 số)", zh: "OAuth 登录（标准 URL + 6 位配对码）"))
                    .font(.appBodyMedium)
            }
        } header: {
            formSectionHeader(L10n.text(lang, en: "Connect on iPhone, Web & Muse", vi: "Kết nối trên iPhone, Web & Muse", zh: "在 iPhone、网页与 Muse 上连接"))
        }
    }

    // MARK: - Section 4: Pair iPhone / Partner

    @ViewBuilder
    private func pairDeviceSection(lang: AppLanguage) -> some View {
        Section {
            HStack(spacing: 10) {
                Button {
                    showingQRCode = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                        Text(L10n.text(lang, en: "Show Setup QR Code", vi: "Hiện mã QR thiết lập", zh: "显示设置二维码"))
                    }
                }
                .pillButton(prominent: true)

                if let pairingDeepLink {
                    ShareLink(item: pairingDeepLink) {
                        HStack(spacing: 6) {
                            CozyUIIcon(.exportBox, size: 14, color: Color.textPrimary)
                            Text(L10n.text(lang, en: "Share Setup Link", vi: "Chia sẻ liên kết", zh: "分享设置链接"))
                        }
                    }
                    .pillButton()
                }
            }
        } header: {
            formSectionHeader(L10n.text(lang, en: "Pair iPhone or Partner", vi: "Ghép nối iPhone hoặc Vợ/Chồng", zh: "配对 iPhone 或伴侣设备"))
        } footer: {
            formSectionFooter(L10n.text(
                lang,
                en: "Your own iPhone & iPad receive credentials automatically via iCloud Keychain. Use the QR code or Share Link for a partner's Apple ID or instant pairing.",
                vi: "iPhone & iPad cùng Apple ID sẽ tự nhận cấu hình qua iCloud Keychain. Dùng mã QR hoặc Chia sẻ cho máy khác Apple ID.",
                zh: "同一 Apple ID 的 iPhone 和 iPad 会通过 iCloud 钥匙串自动获取配置。可使用二维码或分享链接为伴侣设备快速配对。"
            ))
        }
    }

    // MARK: - Section 5: Access & Privacy

    @ViewBuilder
    private func accessAndPrivacySection(lang: AppLanguage) -> some View {
        @Bindable var settings = settings
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
            formSectionHeader(L10n.text(lang, en: "Access & Privacy", vi: "Quyền truy cập & Riêng tư", zh: "权限与隐私"))
        } footer: {
            formSectionFooter(L10n.text(
                lang,
                en: "Salary follows the eye button: while salary is hidden in Tally, assistants receive \"locked (salary hidden)\" and salary rows are left out.",
                vi: "Lương tuân theo nút con mắt: khi lương đang ẩn trong Tally, trợ lý không nhận được số lương hay tổng có chứa lương.",
                zh: "工资遵循“眼睛”按钮：当工资在 Tally 中隐藏时，助手不会收到工资数字或包含工资的合计。"
            ))
        }
    }

    // MARK: - Section 6: Advanced

    @ViewBuilder
    private func advancedSection(lang: AppLanguage) -> some View {
        @Bindable var settings = settings
        Section {
            DisclosureGroup(
                L10n.text(lang, en: "Advanced & Manual Setup", vi: "Nâng cao & Thiết lập thủ công", zh: "高级设置与手动配置"),
                isExpanded: $showingAdvanced
            ) {
                if settings.isCloudMCPConfigured, let creds = cloudCreds {
                    HStack {
                        Text(L10n.text(lang, en: "Cloud access token", vi: "Mã truy cập Cloud", zh: "云端访问令牌"))
                        Spacer()
                        Text(MCPClientSetup.masked(creds.accessToken))
                            .font(.appCaption.monospaced())
                            .foregroundStyle(Color.textSecondary)
                        copyButton(id: "cloud-token", text: creds.accessToken, lang: lang)
                    }

                    Button(L10n.text(lang, en: "Rotate Cloud access token…", vi: "Đổi mã truy cập Cloud…", zh: "重置云端访问令牌…"), role: .destructive) {
                        confirmingRegenerateCloud = true
                    }
                    .pillButton()

                    Button(L10n.text(lang, en: "Disconnect Cloud MCP…", vi: "Ngắt kết nối Cloud MCP…", zh: "断开 Cloud MCP…"), role: .destructive) {
                        confirmingDisconnectCloud = true
                    }
                    .pillButton()
                }

                #if os(macOS)
                Toggle(L10n.text(lang, en: "Local Mac MCP server (127.0.0.1)", vi: "Máy chủ MCP nội bộ (127.0.0.1)", zh: "本机 Mac MCP 服务器 (127.0.0.1)"), isOn: $settings.mcpServerEnabled)

                HStack {
                    Text(L10n.text(lang, en: "Local status", vi: "Trạng thái nội bộ", zh: "本机状态"))
                    Spacer()
                    Text(localStatusText(lang))
                        .foregroundStyle(localStatusIsError ? Color.negative : Color.textSecondary)
                }

                if settings.mcpServerEnabled, let localToken {
                    HStack {
                        Text(L10n.text(lang, en: "Local token", vi: "Mã nội bộ", zh: "本机令牌"))
                        Spacer()
                        Text(MCPClientSetup.masked(localToken))
                            .font(.appCaption.monospaced())
                            .foregroundStyle(Color.textSecondary)
                        copyButton(id: "local-token", text: localToken, lang: lang)
                    }
                    Button(L10n.text(lang, en: "Rotate local token…", vi: "Đổi mã nội bộ…", zh: "重置本机令牌…"), role: .destructive) {
                        confirmingRegenerateLocal = true
                    }
                    .pillButton()
                }

                HStack(spacing: 10) {
                    TextField(String(AppSettings.defaultMCPPort), text: $portDraft)
                        .autocorrectionDisabled()
                        .tallyField()
                    Button(L10n.text(lang, en: "Apply Port", vi: "Đổi cổng", zh: "应用端口")) {
                        if let parsedPort { settings.mcpPort = parsedPort }
                    }
                    .pillButton(prominent: true)
                    .disabled(parsedPort == nil || parsedPort == settings.mcpPort)
                }
                #endif

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(L10n.text(lang, en: "Manual Worker Credentials", vi: "Nhập thủ công Cloudflare Worker", zh: "手动配置 Worker 凭据"))
                    TextField("https://tally-mcp-server.<you>.workers.dev", text: $manualURLDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()
                    SecureField("TALLY_SYNC_SECRET", text: $manualSyncDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()
                    SecureField(L10n.text(lang, en: "MCP Access Token", vi: "Mã truy cập MCP", zh: "MCP 访问令牌"), text: $manualTokenDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()

                    Button {
                        Task { await saveManualCloud(lang: lang) }
                    } label: {
                        if isTestingManual {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L10n.text(lang, en: "Testing…", vi: "Đang kiểm tra…", zh: "测试中…"))
                            }
                        } else {
                            Text(L10n.text(lang, en: "Save & Test Connection", vi: "Lưu & kiểm tra kết nối", zh: "保存并测试连接"))
                        }
                    }
                    .pillButton(prominent: true)
                    .disabled(
                        isTestingManual
                            || manualURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || manualSyncDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || manualTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if let manualTestStatus {
                        Text(manualTestStatus)
                            .font(.appCaption)
                            .foregroundStyle(manualTestIsError ? Color.negative : Color.positive)
                    }
                }
                .padding(.vertical, 4)

                if let endpoint = activeEndpoint {
                    snippetRow(id: "s-claude", title: "Claude Code", detail: L10n.text(lang, en: "Run in Terminal", vi: "Chạy trong Terminal", zh: "在终端中运行"), text: MCPClientSetup.claudeCode(url: endpoint.url, token: endpoint.token), token: endpoint.token, lang: lang)
                    snippetRow(id: "s-codex", title: "Codex", detail: "~/.codex/config.toml", text: MCPClientSetup.codex(url: endpoint.url, token: endpoint.token), token: endpoint.token, lang: lang)
                    snippetRow(id: "s-agy", title: "Antigravity", detail: "~/.gemini/config/mcp_config.json", text: MCPClientSetup.antigravity(quickURL: endpoint.quickURL), token: endpoint.token, lang: lang)
                    snippetRow(id: "s-cd", title: "Claude Desktop", detail: "claude_desktop_config.json", text: MCPClientSetup.claudeDesktopBridge(quickURL: endpoint.quickURL), token: endpoint.token, lang: lang)
                    snippetRow(id: "s-other", title: L10n.text(lang, en: "Generic JSON", vi: "JSON chuẩn", zh: "通用 JSON"), detail: "mcpServers", text: MCPClientSetup.genericJSON(url: endpoint.url, token: endpoint.token), token: endpoint.token, lang: lang)
                }
            }
        }
    }

    // MARK: - Actions & State

    private func refreshState() {
        settings.refreshKeychain()
        cloudCreds = KeychainStore.readCloudMCPCredentials()
        #if os(macOS)
        server.apply(settings: settings, store: store)
        localToken = settings.mcpServerEnabled ? KeychainStore.readMCPToken() : nil
        if let endpoint = activeEndpoint {
            detectedClients = MCPClientInstaller.detectAll(endpoint: endpoint)
        } else {
            detectedClients = []
        }
        #endif
    }

    #if os(macOS)
    private func runOneTapMacDeploy(lang: AppLanguage) async {
        deployError = nil
        deploySuccessMessage = nil

        var repoRoot = MCPCloudDeployer.findRepoRoot(preferredPath: settings.mcpRepoPath)
        if repoRoot == nil {
            repoRoot = pickRepoFolder(lang: lang)
        }
        guard let repoRoot else {
            deployError = L10n.text(
                lang,
                en: "Select your Tally repository folder (containing tools/deploy-mcp) to deploy.",
                vi: "Hãy chọn thư mục mã nguồn Tally (có tools/deploy-mcp) để triển khai.",
                zh: "请选择包含 tools/deploy-mcp 的 Tally 源码文件夹。"
            )
            return
        }
        settings.mcpRepoPath = repoRoot.path

        isDeploying = true
        deployProgress = L10n.text(lang, en: "Deploying Cloudflare Worker…", vi: "Đang triển khai Worker…", zh: "正在部署 Cloudflare Worker…")
        defer { isDeploying = false }

        do {
            let payload = try await MCPCloudDeployer.deploy(repoRoot: repoRoot) { line in
                deployProgress = line.replacingOccurrences(of: "== ", with: "")
            }
            let result = await remoteMCP.connectAndSync(
                url: payload.baseURL.absoluteString,
                syncSecret: payload.syncSecret,
                accessToken: payload.accessToken,
                settings: settings,
                store: store
            )
            switch result {
            case .success:
                refreshState()
                if let endpoint = activeEndpoint {
                    let batch = MCPClientInstaller.connectAllInstalled(endpoint: endpoint)
                    refreshState()
                    if !batch.connected.isEmpty {
                        let names = batch.connected.map(\.displayName).joined(separator: ", ")
                        deploySuccessMessage = L10n.text(
                            lang,
                            en: "Cloud MCP is live and connected: \(names).",
                            vi: "Cloud MCP đã sẵn sàng và tự động kết nối: \(names).",
                            zh: "云端 MCP 已上线并自动连接：\(names)。"
                        )
                    } else {
                        deploySuccessMessage = L10n.text(
                            lang,
                            en: "Cloud MCP is live and synced via iCloud Keychain.",
                            vi: "Cloud MCP đã sẵn sàng và đồng bộ qua iCloud Keychain.",
                            zh: "云端 MCP 已上线并通过 iCloud 钥匙串同步。"
                        )
                    }
                }
            case .failure(let error):
                deployError = error.localizedDescription
            }
        } catch {
            deployError = error.localizedDescription
        }
    }

    private func pickRepoFolder(lang: AppLanguage) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = L10n.text(
            lang,
            en: "Select the Tally project folder (containing tools/deploy-mcp)",
            vi: "Chọn thư mục dự án Tally (chứa tools/deploy-mcp)",
            zh: "选择包含 tools/deploy-mcp 的 Tally 项目文件夹"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return MCPCloudDeployer.isValidRepoRoot(url) ? url : nil
    }

    private func connectAllMacClients(endpoint: MCPEndpointConfig, lang: AppLanguage) {
        clientError = nil
        let res = MCPClientInstaller.connectAllInstalled(endpoint: endpoint)
        if !res.failures.isEmpty {
            clientError = res.failures.map { "\($0.kind.displayName): \($0.message)" }.joined(separator: "\n")
        } else if !res.connected.isEmpty {
            deploySuccessMessage = L10n.text(
                lang,
                en: "Connected: \(res.connected.map(\.displayName).joined(separator: ", ")).",
                vi: "Đã kết nối: \(res.connected.map(\.displayName).joined(separator: ", ")).",
                zh: "已连接：\(res.connected.map(\.displayName).joined(separator: ", "))。"
            )
        }
        refreshState()
    }

    private func connectMacClient(_ kind: MCPClientKind, endpoint: MCPEndpointConfig) {
        clientError = nil
        do {
            try MCPClientInstaller.connect(kind, endpoint: endpoint)
        } catch {
            clientError = "\(kind.displayName): \(error.localizedDescription)"
        }
        refreshState()
    }

    private func disconnectMacClient(_ kind: MCPClientKind) {
        clientError = nil
        do {
            try MCPClientInstaller.disconnect(kind)
        } catch {
            clientError = "\(kind.displayName): \(error.localizedDescription)"
        }
        refreshState()
    }
    #endif

    private func rotateCloudToken() async {
        guard let updated = KeychainStore.regenerateCloudMCPAccessToken() else { return }
        cloudCreds = updated
        remoteMCP.clearPairingCode()
        _ = await remoteMCP.pushConfig(settings: settings)
        refreshState()
    }

    private func pastePairingLinkFromClipboard(lang: AppLanguage) {
        pasteFeedback = nil
        let raw: String? = {
            #if os(macOS)
            return NSPasteboard.general.string(forType: .string)
            #elseif os(iOS)
            return UIPasteboard.general.string
            #endif
        }()
        guard let raw, let payload = MCPSetupLink.parsePairingText(raw) else {
            pasteFeedback = L10n.text(
                lang,
                en: "Clipboard does not contain a Tally setup link (tally://mcp?...).",
                vi: "Bộ nhớ tạm không có liên kết thiết lập Tally (tally://mcp?...).",
                zh: "剪贴板中没有有效的 Tally 设置链接（tally://mcp?...）。"
            )
            return
        }
        Task { await applyPairingPayload(payload) }
    }

    private func applyPairingPayload(_ payload: MCPPairingPayload) async {
        pasteFeedback = nil
        deployError = nil
        let result = await remoteMCP.connectAndSync(
            url: payload.baseURL.absoluteString,
            syncSecret: payload.syncSecret,
            accessToken: payload.accessToken,
            settings: settings,
            store: store
        )
        switch result {
        case .success:
            refreshState()
        case .failure(let error):
            pasteFeedback = error.localizedDescription
            deployError = error.localizedDescription
        }
    }

    private func saveManualCloud(lang: AppLanguage) async {
        isTestingManual = true
        manualTestStatus = nil
        defer { isTestingManual = false }

        let result = await remoteMCP.connectAndSync(
            url: manualURLDraft,
            syncSecret: manualSyncDraft,
            accessToken: manualTokenDraft,
            settings: settings,
            store: store
        )
        switch result {
        case .success:
            manualTestIsError = false
            manualSyncDraft = ""
            manualTokenDraft = ""
            manualTestStatus = L10n.text(lang, en: "Connected & synced!", vi: "Đã kết nối & đồng bộ!", zh: "已连接并同步！")
            refreshState()
        case .failure(let error):
            manualTestIsError = true
            manualTestStatus = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var heroTint: Color {
        if settings.isCloudMCPConfigured {
            if remoteMCP.lastError != nil { return .caution }
            return settings.cloudMCPEnabled ? .positive : .info
        }
        if case .running = server.state { return .positive }
        if case .failed = server.state { return .caution }
        return .accent
    }

    private func heroTitle(_ lang: AppLanguage) -> String {
        if settings.isCloudMCPConfigured {
            return L10n.text(lang, en: "Always-on Cloud MCP active", vi: "Cloud MCP đang hoạt động 24/7", zh: "云端 MCP 已全天候就绪")
        }
        return L10n.text(lang, en: "1-Tap AI Assistant Setup", vi: "Kết nối trợ lý AI chỉ 1 chạm", zh: "一键连接外部 AI 助手")
    }

    private func heroSubtitle(_ lang: AppLanguage) -> String {
        if settings.isCloudMCPConfigured {
            return L10n.text(
                lang,
                en: "Works 24/7 from Claude, ChatGPT, Codex, Antigravity & Muse on iPhone, iPad, and Mac — even when your Mac is asleep.",
                vi: "Hoạt động 24/7 với Claude, ChatGPT, Codex, Antigravity & Muse trên iPhone, iPad và Mac — ngay cả khi Mac đang ngủ.",
                zh: "在 iPhone、iPad 和 Mac 上全天候连接 Claude、ChatGPT、Codex、Antigravity 与 Muse——即使 Mac 休眠也可使用。"
            )
        }
        #if os(macOS)
        return L10n.text(
            lang,
            en: "Deploys your private Cloudflare MCP server, syncs credentials to your iPhone via iCloud Keychain, and auto-connects apps on this Mac.",
            vi: "Tự triển khai máy chủ MCP riêng trên Cloudflare, đồng bộ sang iPhone qua iCloud Keychain và tự kết nối các ứng dụng trên Mac.",
            zh: "部署您的私有 Cloudflare MCP 服务器，通过 iCloud 钥匙串同步到 iPhone，并自动配置此 Mac 上的应用。"
        )
        #else
        return L10n.text(
            lang,
            en: "Set up on your Mac once and iPhone syncs automatically via iCloud Keychain — or scan the setup QR code from Mac.",
            vi: "Cài một lần trên Mac là iPhone tự đồng bộ qua iCloud Keychain — hoặc quét mã QR từ máy Mac.",
            zh: "在 Mac 上配置一次后，iPhone 会通过 iCloud 钥匙串自动同步——也可扫描 Mac 上的二维码立即配对。"
        )
        #endif
    }

    private var localStatusIsError: Bool {
        if case .failed = server.state { return true }
        return false
    }

    private func localStatusText(_ lang: AppLanguage) -> String {
        switch server.state {
        case .stopped: return L10n.text(lang, en: "Off", vi: "Tắt", zh: "已关闭")
        case .starting: return L10n.text(lang, en: "Starting…", vi: "Đang khởi động…", zh: "正在启动…")
        case .running(let port): return L10n.text(lang, en: "Running at \(MCPServer.url(port: port))", vi: "Đang chạy tại \(MCPServer.url(port: port))", zh: "运行于 \(MCPServer.url(port: port))")
        case .failed(let message): return message
        }
    }

    private func quickAppRow(
        id: String,
        title: String,
        subtitle: String,
        buttonLabel: String,
        lang: AppLanguage,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.appBodyMedium)
                Text(subtitle)
                    .font(.appCaption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(buttonLabel, action: action)
                .pillButton(prominent: copiedID != id)
        }
        .padding(.vertical, 2)
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
            Text(text.replacingOccurrences(of: token, with: MCPClientSetup.masked(token)))
                .font(.appCaption.monospaced())
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func copyButton(id: String, text: String, lang: AppLanguage) -> some View {
        Button {
            copyAndMark(id, text: text)
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

    private func copyAndMark(_ id: String, text: String) {
        copy(text)
        copiedID = id
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copiedID == id { copiedID = nil }
        }
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
