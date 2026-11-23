import AppServices
import ClaudeKit
import DesignSystem
import SwiftUI
import TallyCore

struct ClaudeSettingsPane: View {
    @Environment(AppSettings.self) private var settings

    @State private var keyDraft = ""
    @State private var isReplacing = false
    @State private var workspaceDraft = ""
    @State private var isEditingWorkspace = false
    @State private var confirmingRemoval = false
    @State private var keyError: String?

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            // Connection status card (Onsite style)
            Section {
                HStack(alignment: .top, spacing: 12) {
                    SettingsIconTile(symbol: statusSymbol, tint: statusTint, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusHeadline(lang: lang)).font(.appHeading)
                        Text(statusDetail(lang: lang))
                            .font(.appSecondary)
                            .foregroundStyle(isFailed ? Color.negative : Color.textSecondary)
                        if settings.isAIReady {
                            Button {
                                settings.checkConnection()
                            } label: {
                                if settings.connectionStatus == .checking {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text(L10n.text(lang, en: "Testing…", vi: "Đang kiểm tra…"))
                                    }
                                } else {
                                    Text(L10n.text(lang, en: "Test connection", vi: "Kiểm tra kết nối"))
                                }
                            }
                            .pillButton()
                            .padding(.top, 4)
                            .disabled(settings.connectionStatus == .checking)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // API key & Workspace ID
            Section {
                if settings.hasAPIKey && !isReplacing {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "key.fill", size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("API key").font(.appBodyMedium)
                            HStack(spacing: 6) {
                                if let hint = settings.apiKeyHint {
                                    Text(verbatim: hint).font(.appCaption.monospaced())
                                    Text("·")
                                }
                                Text(settings.apiKeyIsShared ? "iCloud Keychain" : "Keychain")
                            }
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Button(L10n.text(lang, en: "Replace", vi: "Đổi")) {
                            keyDraft = ""
                            isReplacing = true
                        }
                        .pillButton()

                        Button(L10n.text(lang, en: "Remove", vi: "Xoá"), role: .destructive) {
                            confirmingRemoval = true
                        }
                        .pillButton()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("sk-ant-…", text: $keyDraft)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .tallyField()

                        HStack {
                            if isReplacing {
                                Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) {
                                    keyDraft = ""
                                    isReplacing = false
                                }
                                .pillButton()
                            }
                            Spacer()
                            Button(L10n.text(lang, en: "Save key", vi: "Lưu key")) {
                                saveKey()
                            }
                            .pillButton(prominent: true)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let url = URL(string: "https://platform.claude.com/settings/keys") {
                            Link(destination: url) {
                                Label(
                                    L10n.text(lang, en: "Create a key in Claude Console", vi: "Tạo API key trên Claude Console"),
                                    systemImage: "arrow.up.right.square"
                                )
                                .font(.appSecondary)
                            }
                        }
                        if let keyError {
                            Text(keyError).font(.appCaption).foregroundStyle(Color.negative)
                        }
                    }
                }

                // Optional Workspace ID
                if isEditingWorkspace {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("wrkspc_…", text: $workspaceDraft)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .tallyField()
                        HStack {
                            Button(L10n.text(lang, en: "Cancel", vi: "Huỷ")) {
                                workspaceDraft = settings.workspaceID
                                isEditingWorkspace = false
                            }
                            .pillButton()
                            Spacer()
                            Button(L10n.text(lang, en: "Save", vi: "Lưu")) {
                                _ = settings.setWorkspaceID(workspaceDraft)
                                isEditingWorkspace = false
                                if settings.hasAPIKey { settings.checkConnection() }
                            }
                            .pillButton(prominent: true)
                        }
                    }
                } else {
                    Button {
                        workspaceDraft = settings.workspaceID
                        isEditingWorkspace = true
                    } label: {
                        HStack {
                            Text("Workspace ID").foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(settings.workspaceID.isEmpty ? L10n.text(lang, en: "Optional", vi: "Tuỳ chọn") : settings.workspaceID)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            } header: {
                formSectionHeader("Anthropic API key")
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Stored only in Apple Keychain and sent only to api.anthropic.com. Never uploaded to CloudKit records.",
                    vi: "Chỉ lưu trong Apple Keychain và chỉ gửi tới api.anthropic.com. Không bao giờ lưu vào CloudKit."
                ))
            }

            // Model selection
            Section {
                ForEach(ClaudeModel.all) { model in
                    Button {
                        settings.modelID = model.id
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name).font(.appBodyMedium)
                                Text(model.blurb(in: lang)).font(.appCaption).foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            if settings.modelID == model.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accent)
                            }
                        }
                    }
                    .buttonStyle(.themedPlain)
                }

                Toggle(isOn: $settings.autoParseWithAI) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text(lang, en: "Use Claude for bank alert parsing", vi: "Dùng Claude đọc thông báo ngân hàng"))
                        Text(L10n.text(lang, en: "Falls back to offline parser if unavailable.", vi: "Tự dùng bộ đọc nội bộ nếu không có mạng."))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Model & Parsing", vi: "Model & Phân tích"))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle("Claude AI")
        .onAppear {
            settings.refreshKeychain()
            workspaceDraft = settings.workspaceID
        }
        .confirmationDialog(
            L10n.text(lang, en: "Remove API key?", vi: "Xoá API key?"),
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Remove", vi: "Xoá"), role: .destructive) {
                _ = settings.setAPIKey("")
            }
        }
    }

    private func saveKey() {
        keyError = nil
        if settings.setAPIKey(keyDraft) {
            keyDraft = ""
            isReplacing = false
            settings.checkConnection()
        } else {
            keyError = L10n.text(settings.language, en: "Could not save key to Keychain.", vi: "Không thể lưu key vào Keychain.")
        }
    }

    private var isFailed: Bool {
        if case .failed = settings.connectionStatus { return true }
        return false
    }

    private var statusSymbol: String {
        guard settings.isAIReady else { return "exclamationmark" }
        switch settings.connectionStatus {
        case .connected: return "checkmark"
        case .failed: return "xmark"
        default: return "sparkles"
        }
    }

    private var statusTint: Color? {
        guard settings.isAIReady else { return .caution }
        switch settings.connectionStatus {
        case .connected: return .positive
        case .failed: return .negative
        default: return nil
        }
    }

    private func statusHeadline(lang: AppLanguage) -> String {
        guard settings.isAIReady else {
            return L10n.text(lang, en: "Claude is not set up", vi: "Chưa kết nối Claude")
        }
        switch settings.connectionStatus {
        case .unchecked: return L10n.text(lang, en: "Claude is ready", vi: "Claude đã sẵn sàng")
        case .checking: return L10n.text(lang, en: "Checking connection…", vi: "Đang kiểm tra kết nối…")
        case .connected: return L10n.text(lang, en: "Claude is connected", vi: "Đã kết nối Claude")
        case .failed: return L10n.text(lang, en: "Connection failed", vi: "Kết nối thất bại")
        }
    }

    private func statusDetail(lang: AppLanguage) -> String {
        guard settings.isAIReady else {
            return L10n.text(lang, en: "Paste your Anthropic API key below to start.", vi: "Dán Anthropic API key bên dưới để bắt đầu.")
        }
        switch settings.connectionStatus {
        case .unchecked: return L10n.text(lang, en: "Model: \(settings.model.name)", vi: "Model: \(settings.model.name)")
        case .checking: return L10n.text(lang, en: "Sending a short test request.", vi: "Đang gửi yêu cầu kiểm tra ngắn.")
        case .connected(let msg), .failed(let msg): return msg
        }
    }
}
