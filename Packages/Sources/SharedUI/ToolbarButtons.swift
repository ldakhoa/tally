import AppServices
import DesignSystem
import SwiftUI
import TallyCore

public struct TopToolbarControls: ToolbarContent {
    @Environment(AppSettings.self) private var settings

    public init() {}

    public var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                settings.isShowingSmartCapture = true
            } label: {
                Image(systemName: "bolt.horizontal.circle")
            }
            .accessibilityLabel(L10n.text(settings.language, en: "Smart paste", vi: "Nhập nhanh AI"))

            Button {
                settings.isShowingAskTally = true
            } label: {
                Image(systemName: "sparkles")
            }
            .accessibilityLabel(L10n.text(settings.language, en: "Ask Tally AI", vi: "Hỏi Tally AI"))

            Button {
                settings.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(L10n.text(settings.language, en: "Settings", vi: "Cài đặt"))
        }
    }
}
