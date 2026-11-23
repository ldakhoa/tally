# Tally iOS Architecture

Tally follows the same layered modular architecture as Onsite: all business logic, design tokens, persistence, services, and screens live inside the local Swift Package (`Packages/`), while the `Tally/` app target holds only composition and App Intents glue.

## Module Layers (strict downward-only imports)

1. **Domain modules** (pure Foundation — no SwiftUI, SwiftData, or UIKit; 100% unit-tested):
   - `TallyCore`: `JSONValue`, `CurrencyCode`, `MoneyFormat`, `DateKey`, `AppLanguage` (EN / VI), `L10n`, `HouseholdMember`
   - `ThemeTokens`: `AppTheme` (Ink & Vermilion, Rosé Pine, Rosé Pine Moon), `AppAppearance`, `ThemeColor`, `ThemePalette`
   - `ClaudeKit`: streaming Anthropic Messages API client (`ClaudeClient`), structured JSON output (`completeJSON`), `ClaudeModel`, `APIKeyKeychain`, `ConnectionCheck`
   - `BudgetKit`: `TransactionRecord`, `BudgetLimitRecord`, `SavingsGoalRecord`, `MonthlySnapshot`, `LocalTransactionParser` (offline VN/SG/Apple Pay bank alert parser), `AITransactionParser` (Claude structured extraction with offline fallback), `BudgetAssistantPrompt`, `WebBackupCodec` (compatible with Tally Web JSON)
   - `SyncKit`: `CloudZoneRole`, `SyncRecordKind`, `SyncMerge` (deterministic LWW + tombstone deletion rules)

2. **Platform & Service modules**:
   - `DesignSystem`: Onsite-style live `ThemeRuntime`, Avenir Next typography scale (from Tally Web, full Vietnamese diacritic support), floating 24pt cards in light mode / hairline borders in dark mode, ink capsules, `ChipPicker`, `SettingsIconTile`, `TallyProgressBar`
   - `Persistence`: SwiftData models (`SDTransaction`, `SDBudgetLimit`, `SDSavingsGoal`) and shared `AppStore.container`
   - `AppServices`: `AppSettings`, `KeychainStore` (Anthropic key only in Keychain, never in CloudKit), `BudgetStore` (CRUD + shortcut ingestion), `CloudSync` (`CKSyncEngine` private + shared database + `CKShare` household sharing), `AssistantService`

3. **Feature UI modules (tiered)**:
   - Tier 0: `SharedUI` (`MonthSwitcher`, `MemberFilterBar`, `TransactionRow`, `TransactionEditorSheet`, `SmartCaptureSheet`, `TopToolbarControls`)
   - Tier 1: `OverviewUI`, `TransactionsUI`, `BudgetsUI`, `GoalsUI`, `AssistantUI`
   - Tier 2: `SettingsUI` (`GeneralSettingsPane`, `ClaudeSettingsPane`, `ShortcutsSettingsPane`, `CloudSharingSettingsPane`, `BackupSettingsPane`)

4. **App Target (`Tally/`)**:
   - `Tally/App/TallyApp.swift`: composition root, CloudKit share acceptance delegate (`UISceneDelegate` / `UIApplicationDelegate`), `tally://` URL scheme fallback
   - `Tally/App/RootTabs.swift`: 4-tab layout + modal sheets
   - `Tally/AppIntents/TallyShortcuts.swift`: native Apple Shortcuts & Siri intents (`LogApplePayTransactionIntent`, `LogTransactionFromTextIntent`, `QuickLogExpenseIntent`, `GetSpendingSummaryIntent`)

## Household Sync (Husband & Wife on Separate Apple IDs)

- The household owner writes to custom zone `TallyHousehold` in `privateCloudDatabase` via `CKSyncEngine`.
- Inviting a partner creates a zone-wide `CKShare(recordZoneID:)` and opens Apple's native `UICloudSharingController`.
- When the partner opens the iCloud link on their iPhone, `TallySceneDelegate` accepts the share, switches `cloudZoneRole` to `.sharedParticipant`, and runs `CKSyncEngine` against `sharedCloudDatabase` for read/write sync.
- Conflicts resolve deterministically via `SyncMerge` (Last-Write-Wins on `updatedAt` with soft-delete tombstones).

## Commands

```bash
swift test --package-path Packages
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
tools/install-device
tools/install-device "Wife's iPhone"
```
