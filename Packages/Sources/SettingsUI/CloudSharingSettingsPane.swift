import AppServices
import CloudKit
import DesignSystem
import SwiftUI
import SyncKit
import TallyCore

struct CloudSharingSettingsPane: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSync.self) private var cloudSync

    @State private var isPreparingShare = false
    @State private var shareItem: SharePresentation?
    @State private var shareError: String?
    @State private var confirmingLeave = false
    #if os(macOS)
    @State private var macSharePresenter = MacCloudSharePresenter()
    #endif

    struct SharePresentation: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
    }

    var body: some View {
        @Bindable var settings = settings
        let lang = settings.language

        Form {
            Section {
                Toggle(L10n.text(lang, en: "Sync with iCloud", vi: "Đồng bộ iCloud", zh: "iCloud 同步"), isOn: $settings.syncsWithICloud)
                    .onChange(of: settings.syncsWithICloud) { _, _ in
                        cloudSync.reconcile()
                    }

                HStack {
                    Text(L10n.text(lang, en: "Status", vi: "Trạng thái", zh: "状态"))
                    Spacer()
                    Text(phaseDescription(lang: lang))
                        .foregroundStyle(Color.textSecondary)
                }

                if let last = cloudSync.lastSynced {
                    HStack {
                        Text(L10n.text(lang, en: "Last synced", vi: "Đồng bộ gần nhất", zh: "上次同步"))
                        Spacer()
                        Text(last, style: .relative)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                if let problem = cloudSync.problem {
                    Text(problem)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                }

                Button {
                    cloudSync.syncNow()
                } label: {
                    if cloudSync.isSyncing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(lang, en: "Syncing…", vi: "Đang đồng bộ…", zh: "同步中…"))
                        }
                    } else {
                        HStack(spacing: 8) {
                            CozyUIIcon(.refresh, size: 16, color: Color.accent)
                            Text(L10n.text(lang, en: "Sync now", vi: "Đồng bộ ngay", zh: "立即同步"))
                        }
                    }
                }
                .disabled(!settings.syncsWithICloud || cloudSync.isSyncing)
            } header: {
                formSectionHeader("iCloud")
            }

            // Household Sharing (Husband <-> Wife)
            Section {
                HStack(spacing: 12) {
                    SettingsIconTile(symbol: "person.2.fill", tint: .positive, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            settings.cloudZoneRole.isSharedParticipant
                                ? L10n.text(lang, en: "Joined partner's household", vi: "Đang dùng sổ chung của gia đình", zh: "已加入伴侣的家庭账本")
                                : L10n.text(lang, en: "Household owner", vi: "Chủ sổ gia đình", zh: "家庭账本创建者")
                        )
                        .font(.appHeading)
                        Text(householdSubtitle(lang: lang))
                            .font(.appCaption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.vertical, 4)

                if !settings.cloudZoneRole.isSharedParticipant {
                    Button {
                        Task { await openShareSheet() }
                    } label: {
                        if isPreparingShare {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(L10n.text(lang, en: "Preparing iCloud invite…", vi: "Đang tạo lời mời iCloud…", zh: "正在准备 iCloud 邀请…"))
                            }
                        } else {
                            HStack(spacing: 7) {
                                CozyUIIcon(.people, size: 16, color: Color.onInk)
                                Text(
                                    cloudSync.activeShare == nil
                                        ? L10n.text(lang, en: "Invite wife / partner via iCloud", vi: "Mời vợ / chồng qua iCloud", zh: "通过 iCloud 邀请伴侣")
                                        : L10n.text(lang, en: "Manage household sharing", vi: "Quản lý chia sẻ gia đình", zh: "管理家庭共享")
                                )
                            }
                        }
                    }
                    .pillButton(prominent: true)
                    .disabled(isPreparingShare || cloudSync.phase != .running)
                } else {
                    Button(L10n.text(lang, en: "Leave shared household", vi: "Rời sổ gia đình chung", zh: "退出共享家庭账本"), role: .destructive) {
                        confirmingLeave = true
                    }
                }

                if let shareError {
                    Text(shareError)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Share with Wife / Partner", vi: "Chia sẻ với vợ / chồng", zh: "与伴侣共享"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Uses Apple iCloud Zone Sharing (CKShare). Send the invite link via iMessage or AirDrop — once accepted on your partner's iPhone, iPad, or Mac, all devices stay in sync automatically with separate Apple IDs.",
                    vi: "Dùng Apple iCloud Zone Sharing (CKShare). Gửi link mời qua iMessage hoặc AirDrop — khi vợ/chồng mở link trên iPhone, iPad hoặc Mac, mọi thiết bị sẽ tự động đồng bộ dù dùng 2 tài khoản Apple ID khác nhau.",
                    zh: "使用 Apple iCloud 区域共享（CKShare）。通过 iMessage 或隔空投送发送邀请链接，伴侣在 iPhone、iPad 或 Mac 上接受后，不同 Apple ID 即可自动实时同步。"
                ))
            }
        }
        .cozyGroupedForm()
        .navigationTitle(L10n.text(lang, en: "iCloud & Household", vi: "iCloud & Gia đình", zh: "iCloud 与家庭"))
        #if os(iOS)
        .sheet(item: $shareItem) { item in
            CloudSharingControllerView(share: item.share, container: item.container) {
                Task { await cloudSync.refreshShareSummary() }
            }
        }
        #endif
        .confirmationDialog(
            L10n.text(lang, en: "Switch back to your private budget?", vi: "Chuyển về sổ chi tiêu riêng?", zh: "切换回个人账本？"),
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Leave shared household", vi: "Rời sổ chung", zh: "退出共享"), role: .destructive) {
                Task { await cloudSync.switchToPrivateHousehold() }
            }
        }
    }

    private func openShareSheet() async {
        isPreparingShare = true
        shareError = nil
        defer { isPreparingShare = false }
        do {
            let (share, container) = try await cloudSync.prepareHouseholdShare()
            #if os(macOS)
            macSharePresenter.present(
                share: share,
                container: container,
                onFinish: { Task { await cloudSync.refreshShareSummary() } },
                onError: { message in shareError = message }
            )
            #else
            shareItem = SharePresentation(share: share, container: container)
            #endif
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func householdSubtitle(lang: AppLanguage) -> String {
        if settings.cloudZoneRole.isSharedParticipant {
            let owner = cloudSync.participantNames.first ?? L10n.text(lang, en: "partner", vi: "người thân", zh: "伴侣")
            return L10n.text(lang, en: "Syncing read & write with \(owner)'s iCloud zone.", vi: "Đang đồng bộ 2 chiều với iCloud của \(owner).", zh: "正在与 \(owner) 的 iCloud 双向同步。")
        }
        if !cloudSync.participantNames.isEmpty {
            return L10n.text(lang, en: "Shared with: \(cloudSync.participantNames.joined(separator: ", "))", vi: "Đang chia sẻ với: \(cloudSync.participantNames.joined(separator: ", "))", zh: "已共享给：\(cloudSync.participantNames.joined(separator: ", "))")
        }
        return L10n.text(lang, en: "Private to your Apple ID until you invite your partner.", vi: "Chỉ đồng bộ các máy của bạn cho đến khi bạn gửi lời mời.", zh: "在邀请伴侣前仅同步您自己的 Apple ID 设备。")
    }

    private func phaseDescription(lang: AppLanguage) -> String {
        switch cloudSync.phase {
        case .running: return L10n.text(lang, en: "Connected", vi: "Đang hoạt động", zh: "已连接")
        case .off: return L10n.text(lang, en: "Turned off", vi: "Đã tắt", zh: "已关闭")
        case .noAccount: return L10n.text(lang, en: "Not signed in to iCloud", vi: "Chưa đăng nhập iCloud", zh: "未登录 iCloud")
        case .accountUnavailable: return L10n.text(lang, en: "iCloud unavailable", vi: "iCloud tạm thời không khả dụng", zh: "iCloud 暂不可用")
        case .checkingAccount: return L10n.text(lang, en: "Checking iCloud…", vi: "Đang kiểm tra iCloud…", zh: "正在检查 iCloud…")
        case .unavailable: return L10n.text(lang, en: "Needs signed iCloud build", vi: "Cần bản build có quyền iCloud", zh: "需要启用 iCloud 签名构建")
        }
    }
}

#if os(iOS)
import UIKit

private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
        func itemTitle(for csc: UICloudSharingController) -> String? { "Tally Household Budget" }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onFinish() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onFinish() }
    }
}
#elseif os(macOS)
import AppKit

private final class MacCloudSharePresenter: NSObject, NSCloudSharingServiceDelegate {
    private var onFinish: (@MainActor () -> Void)?
    private var onError: (@MainActor (String) -> Void)?

    @MainActor
    func present(
        share: CKShare,
        container: CKContainer,
        onFinish: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) {
        self.onFinish = onFinish
        self.onError = onError

        let provider = NSItemProvider()
        provider.registerCloudKitShare(share, container: container)
        guard let service = NSSharingService(named: .cloudSharing) else {
            onError("iCloud sharing panel is unavailable on this Mac.")
            return
        }
        service.delegate = self
        service.perform(withItems: [provider])
    }

    func itemTitle(for sharingService: NSSharingService) -> String? {
        "Tally Household Budget"
    }

    func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) {
        let callback = onFinish
        Task { @MainActor in callback?() }
    }

    func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) {
        let callback = onFinish
        Task { @MainActor in callback?() }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let callback = onError
        let message = error.localizedDescription
        Task { @MainActor in callback?(message) }
    }
}
#endif
