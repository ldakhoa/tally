import AppServices
import DesignSystem
import SwiftUI
import TallyCore

public struct TopToolbarControls: ToolbarContent {
    @Environment(AppSettings.self) private var settings

    public init() {}

    public var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                settings.isShowingSmartCapture = true
            } label: {
                CozyUIIcon(.bolt, size: 19, color: Color.accent)
            }
            .accessibilityLabel(L10n.text(settings.language, en: "Smart paste", vi: "Nhập nhanh AI", zh: "AI 智能记账"))
        }
    }
}
