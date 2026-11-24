import AppServices
import DesignSystem
import SwiftUI
import TallyCore

struct EmailInboxSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(EmailInboxSync.self) private var emailInbox

    @State private var urlDraft = ""
    @State private var secretDraft = ""
    @State private var testStatus: String?
    @State private var testIsError = false
    @State private var isTesting = false
    @State private var confirmingDisconnect = false

    var body: some View {
        let lang = settings.language

        Form {
            // Status card
            Section {
                HStack(alignment: .top, spacing: 12) {
                    SettingsIconTile(
                        symbol: settings.isEmailInboxConfigured ? "envelope.badge.fill" : "envelope",
                        tint: settings.isEmailInboxConfigured ? .positive : .caution,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            settings.isEmailInboxConfigured
                                ? L10n.text(lang, en: "Cloud Email Inbox connected", vi: "Đã kết nối Hộp thư Ngân hàng", zh: "云端银行邮件收件箱已连接")
                                : L10n.text(lang, en: "Zero-Shortcuts Bank Email Sync", vi: "Tự động đọc Email ngân hàng", zh: "免快捷指令同步银行邮件")
                        )
                        .font(.appHeading)

                        Text(
                            settings.isEmailInboxConfigured
                                ? L10n.text(
                                    lang,
                                    en: "Pulls forwarded DBS, OCBC, UOB, Trust & VN bank emails automatically whenever Tally opens.",
                                    vi: "Tự động lấy email DBS, OCBC, UOB, Trust & ngân hàng VN mỗi khi mở Tally.",
                                    zh: "每次打开 Tally 时自动拉取转发的银行交易邮件。"
                                )
                                : L10n.text(
                                    lang,
                                    en: "Deploy tools/email-inbox on Cloudflare Workers (free) and forward Gmail alerts — works for both you and your wife with zero Shortcuts.",
                                    vi: "Deploy tools/email-inbox lên Cloudflare Workers (miễn phí) rồi chuyển tiếp email Gmail — tự động cho cả hai vợ chồng, không cần Phím tắt.",
                                    zh: "在 Cloudflare Workers（免费）上部署 tools/email-inbox 并转发 Gmail 银行通知——夫妻双方均可使用，无需快捷指令。"
                                )
                        )
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)

                        if settings.isEmailInboxConfigured {
                            HStack(spacing: 10) {
                                Button {
                                    emailInbox.syncNow(settings: settings, store: store)
                                } label: {
                                    if emailInbox.isSyncing {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.small)
                                            Text(L10n.text(lang, en: "Checking…", vi: "Đang kiểm tra…", zh: "检查中…"))
                                        }
                                    } else {
                                        HStack(spacing: 6) {
                                            CozyUIIcon(.refresh, size: 14, color: Color.onInk)
                                            Text(L10n.text(lang, en: "Check inbox now", vi: "Kiểm tra ngay", zh: "立即检查"))
                                        }
                                    }
                                }
                                .pillButton(prominent: true)
                                .disabled(emailInbox.isSyncing)

                                Button(L10n.text(lang, en: "Disconnect", vi: "Ngắt kết nối", zh: "断开连接"), role: .destructive) {
                                    confirmingDisconnect = true
                                }
                                .pillButton()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 4)

                if let last = emailInbox.lastSynced {
                    HStack {
                        Text(L10n.text(lang, en: "Last checked", vi: "Kiểm tra gần nhất", zh: "上次检查"))
                        Spacer()
                        Text(last, style: .relative).foregroundStyle(Color.textSecondary)
                    }
                    if emailInbox.lastPulledCount > 0 {
                        HStack {
                            Text(L10n.text(lang, en: "Last sync result", vi: "Kết quả gần nhất", zh: "上次同步结果"))
                            Spacer()
                            Text(L10n.text(
                                lang,
                                en: "\(emailInbox.lastIngestedCount) saved · \(emailInbox.lastSkippedCount) filtered",
                                vi: "\(emailInbox.lastIngestedCount) đã lưu · \(emailInbox.lastSkippedCount) bỏ qua",
                                zh: "已保存 \(emailInbox.lastIngestedCount) · 已过滤 \(emailInbox.lastSkippedCount)"
                            ))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                if let err = emailInbox.lastError {
                    Text(err).font(.appCaption).foregroundStyle(Color.negative)
                }
            }

            // Connection credentials
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Worker URL", vi: "Địa chỉ Worker", zh: "Worker 地址"))
                    TextField("https://tally-email-inbox.<you>.workers.dev", text: $urlDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Inbox Secret (INBOX_SECRET)", vi: "Mã bí mật (INBOX_SECRET)", zh: "收件箱密钥（INBOX_SECRET）"))
                    SecureField(
                        settings.hasEmailInboxSecret
                            ? L10n.text(lang, en: "Saved in Keychain (leave blank to keep)", vi: "Đã lưu trong Keychain (để trống để giữ nguyên)", zh: "已保存在钥匙串中（留空保持不变）")
                            : L10n.text(lang, en: "Paste your INBOX_SECRET", vi: "Dán INBOX_SECRET của bạn", zh: "粘贴您的 INBOX_SECRET"),
                        text: $secretDraft
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .tallyField()
                }

                Button {
                    Task { await saveAndTest() }
                } label: {
                    if isTesting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(lang, en: "Testing…", vi: "Đang kiểm tra…", zh: "测试中…"))
                        }
                    } else {
                        Text(L10n.text(lang, en: "Save & test connection", vi: "Lưu & kiểm tra kết nối", zh: "保存并测试连接"))
                    }
                }
                .blockButton(prominent: true)
                .disabled(urlDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)

                if let testStatus {
                    Text(testStatus)
                        .font(.appCaption)
                        .foregroundStyle(testIsError ? Color.negative : Color.positive)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Connection", vi: "Kết nối Worker", zh: "连接设置"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Your Inbox Secret is stored only in Apple Keychain. Emails are deleted from Cloudflare immediately after Tally pulls them.",
                    vi: "Mã bí mật chỉ lưu trong Apple Keychain. Email được xoá khỏi Cloudflare ngay sau khi Tally tải về.",
                    zh: "您的密钥仅保存在 Apple 钥匙串中。Tally 拉取邮件后会立即将其从 Cloudflare 删除。"
                ))
            }

            // Setup instructions
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text(lang, en: "1. Deploy the Cloudflare Worker", vi: "1. Deploy Cloudflare Worker", zh: "1. 部署 Cloudflare Worker"))
                        .font(.appHeading)
                    Text("cd tools/email-inbox && npm install && npx wrangler deploy && npx wrangler secret put INBOX_SECRET")
                        .font(.appCaption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(lang, en: "2. Forward Gmail Alerts (No custom domain)", vi: "2. Tự động gửi từ Gmail (Không cần tên miền)", zh: "2. 转发 Gmail 通知（无需自定义域名）"))
                        .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Paste tools/email-inbox/gmail-forwarder.gs into script.google.com on your Gmail (and optionally your wife's Gmail) with a 5-minute trigger. It watches DBS, POSB, OCBC, UOB, Trust, Grab, PayNow & VN banks.",
                        vi: "Dán file tools/email-inbox/gmail-forwarder.gs vào script.google.com trên Gmail của bạn (và Gmail vợ bạn) với lịch chạy mỗi 5 phút. Hỗ trợ sẵn DBS, POSB, OCBC, UOB, Trust, Grab, PayNow & ngân hàng VN.",
                        zh: "将 tools/email-inbox/gmail-forwarder.gs 粘贴到您（及伴侣）Gmail 的 script.google.com 中并设置每 5 分钟触发。内置支持 DBS、POSB、OCBC、UOB、Trust、Grab、PayNow 及越南银行。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(lang, en: "Or: Cloudflare Email Routing", vi: "Hoặc: Cloudflare Email Routing", zh: "或者：Cloudflare 邮件路由"))
                        .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Route tally@yourdomain.com (or tally+wife@yourdomain.com) directly to the Worker in Cloudflare Dashboard.",
                        vi: "Trỏ tally@tenmien.com (hoặc tally+vo@tenmien.com) thẳng vào Worker trên Cloudflare Dashboard.",
                        zh: "在 Cloudflare 控制台将 tally@yourdomain.com 直接路由到 Worker。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)
            } header: {
                formSectionHeader(L10n.text(lang, en: "Setup Guide", vi: "Hướng dẫn thiết lập", zh: "设置指南"))
            }
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "Cloud Email Inbox", vi: "Hộp thư Ngân hàng", zh: "云端邮件收件箱"))
        .onAppear {
            urlDraft = settings.emailInboxURL
        }
        .confirmationDialog(
            L10n.text(lang, en: "Disconnect Cloud Email Inbox?", vi: "Ngắt kết nối Hộp thư Ngân hàng?", zh: "断开云端邮件收件箱？"),
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Disconnect", vi: "Ngắt kết nối", zh: "断开连接"), role: .destructive) {
                settings.disconnectEmailInbox()
                urlDraft = ""
                secretDraft = ""
                testStatus = nil
            }
        }
    }

    private func saveAndTest() async {
        isTesting = true
        testStatus = nil
        defer { isTesting = false }

        let result = await emailInbox.testConnection(url: urlDraft, secret: secretDraft, language: settings.language)
        switch result {
        case .success(let pendingCount):
            _ = settings.saveEmailInbox(url: urlDraft, secret: secretDraft)
            secretDraft = ""
            testIsError = false
            testStatus = L10n.text(
                settings.language,
                en: "Connected! \(pendingCount) pending alert(s) ready to pull.",
                vi: "Kết nối thành công! Có \(pendingCount) thông báo đang chờ tải.",
                zh: "连接成功！有 \(pendingCount) 条待同步通知。"
            )
            emailInbox.syncNow(settings: settings, store: store)
        case .failure(let error):
            testIsError = true
            testStatus = error.localizedDescription
        }
    }
}
