import AppServices
import CoreImage.CIFilterBuiltins
import DesignSystem
import MCPKit
import SwiftUI
import TallyCore
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum MCPQRCodeGenerator {
    static func cgImage(for text: String) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return context.createCGImage(transformed, from: transformed.extent)
    }
}

struct MCPQRCodeSheet: View {
    let pairingURL: URL
    let workerHost: String
    let language: AppLanguage

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let lang = language
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text(L10n.text(
                            lang,
                            en: "Pair iPhone, iPad, or Partner",
                            vi: "Ghép nối iPhone, iPad hoặc Vợ/Chồng",
                            zh: "配对 iPhone、iPad 或伴侣设备"
                        ))
                        .font(.appSection)
                        .multilineTextAlignment(.center)

                        Text(L10n.text(
                            lang,
                            en: "Open Tally on the other device → Settings → MCP & AI Assistants → Scan Setup QR Code.",
                            vi: "Mở Tally trên máy kia → Cài đặt → MCP & Trợ lý AI → Quét mã QR thiết lập.",
                            zh: "在另一台设备打开 Tally → 设置 → MCP 与 AI 助手 → 扫描设置二维码。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    }

                    if let cgImage = MCPQRCodeGenerator.cgImage(for: pairingURL.absoluteString) {
                        Image(decorative: cgImage, scale: 1.0)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(18)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(Color.hairline, lineWidth: 1)
                            )
                    }

                    Text(workerHost)
                        .font(.appCaption.monospaced())
                        .foregroundStyle(Color.textSecondary)

                    HStack(spacing: 12) {
                        ShareLink(item: pairingURL) {
                            HStack(spacing: 6) {
                                CozyUIIcon(.exportBox, size: 14, color: Color.onInk)
                                Text(L10n.text(lang, en: "AirDrop / Share", vi: "AirDrop / Chia sẻ", zh: "隔空投送 / 分享"))
                            }
                        }
                        .pillButton(prominent: true)

                        Button {
                            copyString(pairingURL.absoluteString)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(1.6))
                                copied = false
                            }
                        } label: {
                            HStack(spacing: 6) {
                                CozyUIIcon(copied ? .checkmark : .copy, size: 14, color: Color.textPrimary)
                                Text(copied
                                    ? L10n.text(lang, en: "Copied", vi: "Đã chép", zh: "已拷贝")
                                    : L10n.text(lang, en: "Copy Link", vi: "Chép liên kết", zh: "拷贝链接"))
                            }
                        }
                        .pillButton()
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .pageBackground()
            .cozySheetToolbar(
                title: L10n.text(lang, en: "Setup QR Code", vi: "Mã QR thiết lập", zh: "设置二维码"),
                leading: {
                    Button(L10n.text(lang, en: "Done", vi: "Xong", zh: "完成")) { dismiss() }
                }
            )
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 470)
        #endif
    }

    private func copyString(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }
}

/// Shown when Tally opens via a `tally://mcp?...` pairing link or AirDrop.
public struct MCPPairingConfirmationSheet: View {
    public let payload: MCPPairingPayload

    @Environment(AppSettings.self) private var settings
    @Environment(BudgetStore.self) private var store
    @Environment(RemoteMCPSync.self) private var remoteMCP
    @Environment(\.dismiss) private var dismiss

    @State private var isConnecting = false
    @State private var errorMessage: String?

    public init(payload: MCPPairingPayload) {
        self.payload = payload
    }

    public var body: some View {
        let lang = settings.language
        NavigationStack {
            VStack(spacing: 20) {
                SettingsIconTile(symbol: "icloud.fill", tint: .positive, size: 52)
                    .padding(.top, 12)

                VStack(spacing: 6) {
                    Text(L10n.text(
                        lang,
                        en: "Connect Tally Cloud MCP?",
                        vi: "Kết nối Tally Cloud MCP?",
                        zh: "连接 Tally Cloud MCP？"
                    ))
                    .font(.appTitle)
                    .multilineTextAlignment(.center)

                    Text(L10n.text(
                        lang,
                        en: "Syncs your budget with your private Cloudflare Worker so Claude, ChatGPT, Codex, and Muse work 24/7.",
                        vi: "Đồng bộ ngân sách với Cloudflare Worker riêng để Claude, ChatGPT, Codex và Muse hoạt động 24/7.",
                        zh: "将您的预算同步至私有 Cloudflare Worker，让 Claude、ChatGPT、Codex 和 Muse 24/7 全天候连接。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel(L10n.text(lang, en: "Server Address", vi: "Địa chỉ máy chủ", zh: "服务器地址"))
                    Text(payload.baseURL.absoluteString)
                        .font(.appCaption.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .cardSurface(cornerRadius: Radius.panel)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                Button {
                    Task { await connect() }
                } label: {
                    if isConnecting {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L10n.text(lang, en: "Connecting & syncing…", vi: "Đang kết nối & đồng bộ…", zh: "正在连接并同步…"))
                        }
                    } else {
                        Text(L10n.text(lang, en: "Connect & Sync", vi: "Kết nối & Đồng bộ", zh: "连接并同步"))
                    }
                }
                .blockButton(prominent: true)
                .disabled(isConnecting)
            }
            .padding(24)
            .pageBackground()
            .cozySheetToolbar(
                title: L10n.text(lang, en: "Pair Cloud MCP", vi: "Ghép nối Cloud MCP", zh: "配对 Cloud MCP"),
                leading: {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                        .disabled(isConnecting)
                }
            )
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        let result = await remoteMCP.connectAndSync(
            url: payload.baseURL.absoluteString,
            syncSecret: payload.syncSecret,
            accessToken: payload.accessToken,
            settings: settings,
            store: store
        )
        switch result {
        case .success:
            dismiss()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}
