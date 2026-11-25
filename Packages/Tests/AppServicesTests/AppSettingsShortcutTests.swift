@testable import AppServices
import BudgetKit
import XCTest

@MainActor
final class AppSettingsShortcutTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() async throws {
        suites.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
        suites = []
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "tally.tests.shortcuts.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testICloudShortcutLinksPersistAndRejectInvalidURLs() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertNil(settings.shortcutICloudURL(for: .shareSheet))
        XCTAssertEqual(settings.shortcutICloudLinkString(for: .shareSheet), "")

        XCTAssertTrue(settings.setShortcutICloudLink("icloud.com/shortcuts/0123456789abcdef/", for: .shareSheet))
        XCTAssertEqual(
            settings.shortcutICloudURL(for: .shareSheet)?.absoluteString,
            "https://www.icloud.com/shortcuts/0123456789abcdef"
        )

        // Invalid link leaves existing stored URL untouched.
        XCTAssertFalse(settings.setShortcutICloudLink("https://evil.com/shortcuts/0123456789abcdef", for: .shareSheet))
        XCTAssertEqual(
            settings.shortcutICloudURL(for: .shareSheet)?.absoluteString,
            "https://www.icloud.com/shortcuts/0123456789abcdef"
        )

        // Reload from same UserDefaults verifies persistence.
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(
            reloaded.shortcutICloudURL(for: .shareSheet)?.absoluteString,
            "https://www.icloud.com/shortcuts/0123456789abcdef"
        )

        // Clearing removes the saved link.
        XCTAssertTrue(reloaded.setShortcutICloudLink("   ", for: .shareSheet))
        XCTAssertNil(reloaded.shortcutICloudURL(for: .shareSheet))
    }

    func testCompletedShortcutGuidesPersistAcrossReloads() throws {
        let defaults = try makeDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.isShortcutGuideCompleted(.applePay))
        XCTAssertFalse(settings.isShortcutGuideCompleted(.bankEmail))

        settings.setShortcutGuideCompleted(true, for: .applePay)
        settings.setShortcutGuideCompleted(true, for: .bankSMS)

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertTrue(reloaded.isShortcutGuideCompleted(.applePay))
        XCTAssertFalse(reloaded.isShortcutGuideCompleted(.bankEmail))
        XCTAssertTrue(reloaded.isShortcutGuideCompleted(.bankSMS))

        reloaded.setShortcutGuideCompleted(false, for: .applePay)
        let reloadedAgain = AppSettings(defaults: defaults)
        XCTAssertFalse(reloadedAgain.isShortcutGuideCompleted(.applePay))
        XCTAssertTrue(reloadedAgain.isShortcutGuideCompleted(.bankSMS))
    }
}
