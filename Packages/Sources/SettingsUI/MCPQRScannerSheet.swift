#if os(iOS)
import AVFoundation
import DesignSystem
import MCPKit
import SwiftUI
import TallyCore
import UIKit

struct MCPQRScannerSheet: View {
    let language: AppLanguage
    let onScanned: (MCPPairingPayload) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var cameraState: CameraAvailability = .checking
    @State private var feedbackMessage: String?

    enum CameraAvailability: Equatable {
        case checking
        case ready
        case denied
        case unavailable
    }

    var body: some View {
        let lang = language
        NavigationStack {
            VStack(spacing: 16) {
                switch cameraState {
                case .checking:
                    Spacer()
                    ProgressView()
                    Spacer()
                case .ready:
                    ZStack {
                        QRScannerRepresentable { rawValue in
                            handleScannedCode(rawValue, lang: lang)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Color.hairlineStrong, lineWidth: 1.5)
                        )

                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accent.opacity(0.9), lineWidth: 2.5)
                            .frame(width: 210, height: 210)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 340)
                    .padding(.top, 8)

                    Text(L10n.text(
                        lang,
                        en: "Point the camera at the QR code shown in Tally on your Mac.",
                        vi: "Hướng camera vào mã QR hiển thị trong Tally trên máy Mac.",
                        zh: "将相机对准 Mac 版 Tally 上显示的二维码。"
                    ))
                    .font(.appSecondary)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                case .denied:
                    Spacer()
                    VStack(spacing: 12) {
                        SettingsIconTile(symbol: "exclamationmark.triangle.fill", tint: .caution, size: 48)
                        Text(L10n.text(
                            lang,
                            en: "Camera access is turned off",
                            vi: "Quyền camera đang bị tắt",
                            zh: "相机权限已关闭"
                        ))
                        .font(.appHeading)
                        Text(L10n.text(
                            lang,
                            en: "Allow camera access in Settings to scan the setup QR code, or paste a pairing link.",
                            vi: "Bật quyền camera trong Cài đặt để quét mã QR, hoặc dán liên kết ghép nối.",
                            zh: "请在系统设置中允许相机权限以扫描设置二维码，或直接粘贴配对链接。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)

                        Button(L10n.text(lang, en: "Open Settings", vi: "Mở Cài đặt", zh: "打开系统设置")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        .pillButton()
                    }
                    Spacer()

                case .unavailable:
                    Spacer()
                    VStack(spacing: 12) {
                        SettingsIconTile(symbol: "icloud.fill", tint: .info, size: 48)
                        Text(L10n.text(
                            lang,
                            en: "Camera unavailable on this device",
                            vi: "Thiết bị này không có camera khả dụng",
                            zh: "此设备无可用相机"
                        ))
                        .font(.appHeading)
                        Text(L10n.text(
                            lang,
                            en: "Copy the pairing link from your Mac (or AirDrop it) and tap Paste Setup Link below.",
                            vi: "Chép liên kết ghép nối từ Mac (hoặc gửi qua AirDrop) rồi bấm Dán liên kết thiết lập bên dưới.",
                            zh: "从 Mac 拷贝配对链接（或隔空投送），然后点击下方的“粘贴设置链接”。"
                        ))
                        .font(.appSecondary)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    }
                    Spacer()
                }

                if let feedbackMessage {
                    Text(feedbackMessage)
                        .font(.appCaption)
                        .foregroundStyle(Color.negative)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 0)

                Button {
                    pasteFromClipboard(lang: lang)
                } label: {
                    HStack(spacing: 6) {
                        CozyUIIcon(.copy, size: 15, color: Color.onInk)
                        Text(L10n.text(lang, en: "Paste Setup Link", vi: "Dán liên kết thiết lập", zh: "粘贴设置链接"))
                    }
                }
                .blockButton(prominent: true)
            }
            .padding(22)
            .pageBackground()
            .cozySheetToolbar(
                title: L10n.text(lang, en: "Scan Setup QR Code", vi: "Quét mã QR thiết lập", zh: "扫描设置二维码"),
                leading: {
                    Button(L10n.text(lang, en: "Cancel", vi: "Huỷ", zh: "取消")) { dismiss() }
                }
            )
            .task {
                await resolveCameraPermission()
            }
        }
    }

    private func resolveCameraPermission() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            cameraState = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .ready
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraState = granted ? .ready : .denied
        case .denied, .restricted:
            cameraState = .denied
        @unknown default:
            cameraState = .unavailable
        }
    }

    private func handleScannedCode(_ raw: String, lang: AppLanguage) {
        if let payload = MCPSetupLink.parsePairingText(raw) {
            onScanned(payload)
            dismiss()
        } else {
            feedbackMessage = L10n.text(
                lang,
                en: "That QR code is not a Tally MCP pairing code.",
                vi: "Mã QR này không phải mã ghép nối Tally MCP.",
                zh: "此二维码不是 Tally MCP 配对码。"
            )
        }
    }

    private func pasteFromClipboard(lang: AppLanguage) {
        guard let raw = UIPasteboard.general.string,
              let payload = MCPSetupLink.parsePairingText(raw)
        else {
            feedbackMessage = L10n.text(
                lang,
                en: "No Tally pairing link found on the clipboard.",
                vi: "Không tìm thấy liên kết ghép nối Tally trong bộ nhớ tạm.",
                zh: "剪贴板中未找到 Tally 配对链接。"
            )
            return
        }
        onScanned(payload)
        dismiss()
    }
}

private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        private var lastEmitted: String?
        private var lastEmittedAt: Date = .distantPast

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr,
                  let value = obj.stringValue,
                  !value.isEmpty
            else { return }

            let now = Date()
            if value == lastEmitted && now.timeIntervalSince(lastEmittedAt) < 1.5 {
                return
            }
            lastEmitted = value
            lastEmittedAt = now
            Task { @MainActor [onCode] in
                onCode(value)
            }
        }
    }

    final class ScannerViewController: UIViewController {
        weak var delegate: Coordinator?
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "com.ldakhoa.tally.qr-scanner")
        private var previewLayer: AVCaptureVideoPreviewLayer?
        private var configured = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            self.previewLayer = preview
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let delegate = self.delegate
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.configured {
                    self.configured = true
                    guard let device = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: device),
                          self.session.canAddInput(input)
                    else { return }
                    self.session.addInput(input)

                    let output = AVCaptureMetadataOutput()
                    guard self.session.canAddOutput(output) else { return }
                    self.session.addOutput(output)
                    output.setMetadataObjectsDelegate(delegate, queue: .main)
                    output.metadataObjectTypes = [.qr]
                }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }
    }
}
#endif
