# Tally Multiplatform Architecture

Tally follows the same layered modular architecture as Onsite: all business logic, design tokens, persistence, services, and screens live inside the local Swift Package (`Packages/`), while the `Tally/` app target holds only composition, menu/keyboard commands, and App Intents glue for iPhone, iPad, and Mac.

## Module Layers (strict downward-only imports)

1. **Domain modules** (pure Foundation — no SwiftUI, SwiftData, AppKit, or UIKit; 100% unit-tested):
   - `TallyCore`: `JSONValue`, `CurrencyCode`, `MoneyFormat`, `DateKey`, `DatePeriod`, `AmountKeypadEngine`, `AppLanguage` (EN / VI / ZH), `L10n`, `HouseholdMember`, `AIProvider`
   - `ThemeTokens`: `AppTheme` (Paws & Cream, Ink & Vermilion, Rosé Pine, Rosé Pine Moon), `AppAppearance`, `ThemeColor`, `ThemePalette`
   - `ClaudeKit`: streaming Anthropic Messages API client (`ClaudeClient`), structured JSON output (`completeJSON`), `ClaudeModel`, `APIKeyKeychain`, `ConnectionCheck`
   - `BudgetKit`: `TransactionRecord`, `BudgetLimitRecord`, `SavingsGoalRecord`, `MonthlySnapshot`, `StatisticsSnapshot`, `LocalTransactionParser` (offline VN/SG/Apple Pay bank alert parser), `AITransactionParser` (Claude structured extraction with offline fallback), `BudgetAssistantPrompt`, `EmailInboxClient`, `TransactionDeduplicator`, `WebBackupCodec` (compatible with Tally Web JSON)
   - `SyncKit`: `CloudZoneRole`, `SyncRecordKind`, `SyncMerge` (deterministic LWW + tombstone deletion rules)

2. **Platform & Service modules**:
   - `DesignSystem`: cross-platform live `ThemeRuntime` (`UIColor` / `NSColor` + window appearance), SF Pro Rounded typography scale, floating 26pt cards with warm cocoa shadows in light mode / hairline borders in dark mode, watercolor PNG + vector hybrid icons, `HorizonPeriodCalendarView`, `AmountKeypadView` (touch + hardware keyboard), `CozyTabBar`
   - `Persistence`: SwiftData models (`SDTransaction`, `SDBudgetLimit`, `SDSavingsGoal`) and shared `AppStore.container`
   - `AppServices`: `AppSettings`, `KeychainStore` (API key & inbox secret only in Keychain, never in CloudKit), `BudgetStore`, `CloudSync` (`CKSyncEngine` private + shared database + `CKShare` household sharing), `AssistantService`, `VoiceDictationManager`, `EmailInboxSync`

3. **Feature UI modules (tiered)**:
   - Tier 0: `SharedUI` (`MonthSwitcher`, `PeriodPickerSheet`, `MemberFilterBar`, `TransactionRow`, `TransactionEditorSheet`, `SmartCaptureSheet`, `TopToolbarControls`)
   - Tier 1: `OverviewUI`, `TransactionsUI`, `StatisticsUI`, `BudgetsUI`, `GoalsUI`, `AssistantUI`
   - Tier 2: `SettingsUI` (compact push navigation on phone, 2-pane workspace on iPad & Mac; `GeneralSettingsPane`, `ClaudeSettingsPane`, `ShortcutsSettingsPane`, `EmailInboxSettingsPane`, `CloudSharingSettingsPane` with `UICloudSharingController` / `NSSharingService`, `BackupSettingsPane`)

4. **App Target (`Tally/`)**:
   - `Tally/App/TallyApp.swift`: composition root, CloudKit share acceptance delegates (`UIApplicationDelegate` / `UIWindowSceneDelegate` on iOS & iPadOS; `NSApplicationDelegate` on macOS), remote notification registration, `tally://` URL scheme fallback
   - `Tally/App/RootTabs.swift`: adaptive shell — floating cozy tab bar + action dock on compact widths (iPhone / narrow Split View) and cozy **Paws & Cream** `NavigationSplitView` sidebar on wide iPad & Mac layouts
   - `Tally/App/TallyCommands.swift`: menu bar & hardware keyboard shortcuts (`⌘N`, `⇧⌘V`, `⌘K`, `⇧⌘R`, `⌘1`–`⌘5`, `⌘[`, `⌘]`, `⌘,`)
   - `Tally/AppIntents/TallyShortcuts.swift`: native Apple Shortcuts & Siri intents (`TellTallyIntent`, `AutoLogTransactionIntent`, `LogApplePayTransactionIntent`, `LogTransactionFromTextIntent`, `QuickLogExpenseIntent`, `GetSpendingSummaryIntent`)

## Household Sync (iPhone, iPad & Mac + Husband & Wife on Separate Apple IDs)

- All platforms share bundle ID `com.ldakhoa.tally` and CloudKit container `iCloud.com.ldakhoa.tally` (`Tally-iOS.entitlements` and `Tally-macOS.entitlements`), so your own iPhone, iPad, and Mac sync automatically via `privateCloudDatabase` zone `TallyHousehold` (plus iCloud Keychain for API keys).
- Inviting a partner creates a zone-wide `CKShare(recordZoneID:)` and opens Apple's native sharing sheet (`UICloudSharingController` on iOS/iPadOS, `NSSharingService(named: .cloudSharing)` on macOS).
- When the partner opens the iCloud link on iPhone, iPad, or Mac, the platform delegate accepts the share via `CloudSync.acceptShareWhenReady(_:)`, switches `cloudZoneRole` to `.sharedParticipant`, and runs `CKSyncEngine` against `sharedCloudDatabase` for read/write sync.
- Conflicts resolve deterministically via `SyncMerge` (Last-Write-Wins on `updatedAt` with soft-delete tombstones).

## Commands

```bash
swift test --package-path Packages
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
tools/install-mac
tools/install-device
tools/install-device "Wife's iPhone"
```
