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
                                ? L10n.text(lang, en: "Cloud Email Inbox connected", vi: "Đã kết nối Hộp thư Ngân hàng")
                                : L10n.text(lang, en: "Zero-Shortcuts Bank Email Sync", vi: "Tự động đọc Email ngân hàng")
                        )
                        .font(.appHeading)

                        Text(
                            settings.isEmailInboxConfigured
                                ? L10n.text(
                                    lang,
                                    en: "Pulls forwarded DBS, OCBC, UOB, Trust & VN bank emails automatically whenever Tally opens.",
                                    vi: "Tự động lấy email DBS, OCBC, UOB, Trust & ngân hàng VN mỗi khi mở Tally."
                                )
                                : L10n.text(
                                    lang,
                                    en: "Deploy tools/email-inbox on Cloudflare Workers (free) and forward Gmail alerts — works for both you and your wife with zero Shortcuts.",
                                    vi: "Deploy tools/email-inbox lên Cloudflare Workers (miễn phí) rồi chuyển tiếp email Gmail — tự động cho cả hai vợ chồng, không cần Phím tắt."
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
                                            Text(L10n.text(lang, en: "Checking…", vi: "Đang kiểm tra…"))
                                        }
                                    } else {
                                        Label(L10n.text(lang, en: "Check inbox now", vi: "Kiểm tra ngay"), systemImage: "arrow.clockwise")
                                    }
                                }
                                .pillButton(prominent: true)
                                .disabled(emailInbox.isSyncing)

                                Button(L10n.text(lang, en: "Disconnect", vi: "Ngắt kết nối"), role: .destructive) {
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
                        Text(L10n.text(lang, en: "Last checked", vi: "Kiểm tra gần nhất"))
                        Spacer()
                        Text(last, style: .relative).foregroundStyle(Color.textSecondary)
                    }
                }
                if let err = emailInbox.lastError {
                    Text(err).font(.appCaption).foregroundStyle(Color.negative)
                }
            }

            // Connection credentials
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Worker URL", vi: "Địa chỉ Worker"))
                    TextField("https://tally-email-inbox.<you>.workers.dev", text: $urlDraft)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .tallyField()
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Inbox Secret (INBOX_SECRET)", vi: "Mã bí mật (INBOX_SECRET)"))
                    SecureField(
                        settings.hasEmailInboxSecret
                            ? L10n.text(lang, en: "Saved in Keychain (leave blank to keep)", vi: "Đã lưu trong Keychain (để trống để giữ nguyên)")
                            : L10n.text(lang, en: "Paste your INBOX_SECRET", vi: "Dán INBOX_SECRET của bạn"),
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
                            Text(L10n.text(lang, en: "Testing…", vi: "Đang kiểm tra…"))
                        }
                    } else {
                        Text(L10n.text(lang, en: "Save & test connection", vi: "Lưu & kiểm tra kết nối"))
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
                formSectionHeader(L10n.text(lang, en: "Connection", vi: "Kết nối Worker"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Your Inbox Secret is stored only in Apple Keychain. Emails are deleted from Cloudflare immediately after Tally pulls them.",
                    vi: "Mã bí mật chỉ lưu trong Apple Keychain. Email được xoá khỏi Cloudflare ngay sau khi Tally tải về."
                ))
            }

            // Setup instructions
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text(lang, en: "1. Deploy the Cloudflare Worker", vi: "1. Deploy Cloudflare Worker"))
                        .font(.appHeading)
                    Text("cd tools/email-inbox && npm install && npx wrangler deploy && npx wrangler secret put INBOX_SECRET")
                        .font(.appCaption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(lang, en: "2. Forward Gmail Alerts (No custom domain)", vi: "2. Tự động gửi từ Gmail (Không cần tên miền)"))
                        .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Paste tools/email-inbox/gmail-forwarder.gs into script.google.com on your Gmail (and optionally your wife's Gmail) with a 5-minute trigger. It watches DBS, POSB, OCBC, UOB, Trust, Grab, PayNow & VN banks.",
                        vi: "Dán file tools/email-inbox/gmail-forwarder.gs vào script.google.com trên Gmail của bạn (và Gmail vợ bạn) với lịch chạy mỗi 5 phút. Hỗ trợ sẵn DBS, POSB, OCBC, UOB, Trust, Grab, PayNow & ngân hàng VN."
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(lang, en: "Or: Cloudflare Email Routing", vi: "Hoặc: Cloudflare Email Routing"))
                        .font(.appHeading)
                    Text(L10n.text(
                        lang,
                        en: "Route tally@yourdomain.com (or tally+wife@yourdomain.com) directly to the Worker in Cloudflare Dashboard.",
                        vi: "Trỏ tally@tenmien.com (hoặc tally+vo@tenmien.com) thẳng vào Worker trên Cloudflare Dashboard."
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, 4)
            } header: {
                formSectionHeader(L10n.text(lang, en: "Setup Guide", vi: "Hướng dẫn thiết lập"))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "Cloud Email Inbox", vi: "Hộp thư Ngân hàng"))
        .onAppear {
            urlDraft = settings.emailInboxURL
        }
        .confirmationDialog(
            L10n.text(lang, en: "Disconnect Cloud Email Inbox?", vi: "Ngắt kết nối Hộp thư Ngân hàng?"),
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Disconnect", vi: "Ngắt kết nối"), role: .destructive) {
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
                vi: "Kết nối thành công! Có \(pendingCount) thông báo đang chờ tải."
            )
            emailInbox.syncNow(settings: settings, store: store)
        case .failure(let error):
            testIsError = true
            testStatus = error.localizedDescription
        }
    }
}
