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
                Toggle(L10n.text(lang, en: "Sync with iCloud", vi: "Đồng bộ iCloud"), isOn: $settings.syncsWithICloud)
                    .onChange(of: settings.syncsWithICloud) { _, _ in
                        cloudSync.reconcile()
                    }

                HStack {
                    Text(L10n.text(lang, en: "Status", vi: "Trạng thái"))
                    Spacer()
                    Text(phaseDescription(lang: lang))
                        .foregroundStyle(Color.textSecondary)
                }

                if let last = cloudSync.lastSynced {
                    HStack {
                        Text(L10n.text(lang, en: "Last synced", vi: "Đồng bộ gần nhất"))
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
                            Text(L10n.text(lang, en: "Syncing…", vi: "Đang đồng bộ…"))
                        }
                    } else {
                        Label(L10n.text(lang, en: "Sync now", vi: "Đồng bộ ngay"), systemImage: "arrow.triangle.2.circlepath")
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
                                ? L10n.text(lang, en: "Joined partner's household", vi: "Đang dùng sổ chung của gia đình")
                                : L10n.text(lang, en: "Household owner", vi: "Chủ sổ gia đình")
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
                                Text(L10n.text(lang, en: "Preparing iCloud invite…", vi: "Đang tạo lời mời iCloud…"))
                            }
                        } else {
                            Label(
                                cloudSync.activeShare == nil
                                    ? L10n.text(lang, en: "Invite wife / partner via iCloud", vi: "Mời vợ / chồng qua iCloud")
                                    : L10n.text(lang, en: "Manage household sharing", vi: "Quản lý chia sẻ gia đình"),
                                systemImage: "person.badge.plus"
                            )
                        }
                    }
                    .pillButton(prominent: true)
                    .disabled(isPreparingShare || cloudSync.phase != .running)
                } else {
                    Button(L10n.text(lang, en: "Leave shared household", vi: "Rời sổ gia đình chung"), role: .destructive) {
                        confirmingLeave = true
                    }
                }

                if let shareError {
                    Text(shareError)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                }
            } header: {
                formSectionHeader(L10n.text(lang, en: "Share with Wife / Partner", vi: "Chia sẻ với vợ / chồng"))
            } footer: {
                formSectionFooter(L10n.text(
                    lang,
                    en: "Uses Apple iCloud Zone Sharing (CKShare). Send the invite link via iMessage or AirDrop — once accepted on your wife's iPhone, both phones stay in sync automatically with separate Apple IDs.",
                    vi: "Dùng Apple iCloud Zone Sharing (CKShare). Gửi link mời qua iMessage hoặc AirDrop — khi vợ bạn mở link trên iPhone, hai máy sẽ tự động đồng bộ dù dùng 2 tài khoản Apple ID khác nhau."
                ))
            }
        }
        .scrollContentBackground(.hidden)
        .pageBackground()
        .navigationTitle(L10n.text(lang, en: "iCloud & Household", vi: "iCloud & Gia đình"))
        #if os(iOS)
        .sheet(item: $shareItem) { item in
            CloudSharingControllerView(share: item.share, container: item.container) {
                Task { await cloudSync.refreshShareSummary() }
            }
        }
        #endif
        .confirmationDialog(
            L10n.text(lang, en: "Switch back to your private budget?", vi: "Chuyển về sổ chi tiêu riêng?"),
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button(L10n.text(lang, en: "Leave shared household", vi: "Rời sổ chung"), role: .destructive) {
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
            shareItem = SharePresentation(share: share, container: container)
        } catch {
            shareError = error.localizedDescription
        }
    }

    private func householdSubtitle(lang: AppLanguage) -> String {
        if settings.cloudZoneRole.isSharedParticipant {
            let owner = cloudSync.participantNames.first ?? L10n.text(lang, en: "partner", vi: "người thân")
            return L10n.text(lang, en: "Syncing read & write with \(owner)'s iCloud zone.", vi: "Đang đồng bộ 2 chiều với iCloud của \(owner).")
        }
        if !cloudSync.participantNames.isEmpty {
            return L10n.text(lang, en: "Shared with: \(cloudSync.participantNames.joined(separator: ", "))", vi: "Đang chia sẻ với: \(cloudSync.participantNames.joined(separator: ", "))")
        }
        return L10n.text(lang, en: "Private to your Apple ID until you invite your partner.", vi: "Chỉ đồng bộ các máy của bạn cho đến khi bạn gửi lời mời.")
    }

    private func phaseDescription(lang: AppLanguage) -> String {
        switch cloudSync.phase {
        case .running: return L10n.text(lang, en: "Connected", vi: "Đang hoạt động")
        case .off: return L10n.text(lang, en: "Turned off", vi: "Đã tắt")
        case .noAccount: return L10n.text(lang, en: "Not signed in to iCloud", vi: "Chưa đăng nhập iCloud")
        case .accountUnavailable: return L10n.text(lang, en: "iCloud unavailable", vi: "iCloud tạm thời không khả dụng")
        case .checkingAccount: return L10n.text(lang, en: "Checking iCloud…", vi: "Đang kiểm tra iCloud…")
        case .unavailable: return L10n.text(lang, en: "Needs signed iCloud build", vi: "Cần bản build có quyền iCloud")
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
#endif
