import ThemeTokens
import XCTest

final class ThemeTokensTests: XCTestCase {
    func testAllThemesHaveReadableTextContrast() {
        for theme in AppTheme.allCases {
            for dark in [false, true] {
                let palette = theme.palette(dark: dark)
                let pageContrast = ThemeColor.contrast(palette.text, on: palette.ios.page)
                let cardContrast = ThemeColor.contrast(palette.text, on: palette.ios.card)
                XCTAssertGreaterThan(pageContrast, 4.5, "\(theme) dark=\(dark) page contrast too low")
                XCTAssertGreaterThan(cardContrast, 4.5, "\(theme) dark=\(dark) card contrast too low")
            }
        }
    }

    func testThemeChoicePreservesRosePineMoonInLight() {
        let current = AppTheme.rosePineMoon
        XCTAssertEqual(current.choosing(.rosePine, dark: false), .rosePineMoon)
        XCTAssertEqual(current.choosing(.ink, dark: false), .ink)
    }
}
