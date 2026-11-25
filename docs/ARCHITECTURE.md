# Tally Multiplatform Architecture

Tally follows the same layered modular architecture as Onsite: all business logic, design tokens, persistence, services, and screens live inside the local Swift Package (`Packages/`), while the `Tally/` app target holds only composition, menu/keyboard commands, and App Intents glue for iPhone, iPad, and Mac.

## Module Layers (strict downward-only imports)

1. **Domain modules** (pure Foundation — no SwiftUI, SwiftData, AppKit, or UIKit; 100% unit-tested):
   - `TallyCore`: `JSONValue`, `CurrencyCode`, `MoneyFormat`, `DateKey`, `DatePeriod`, `AmountKeypadEngine`, `AppLanguage` (EN / VI / ZH), `L10n`, `HouseholdMember`, `AIProvider`
   - `ThemeTokens`: `AppTheme` (Paws & Cream, Ink & Vermilion, Rosé Pine, Rosé Pine Moon), `AppAppearance`, `ThemeColor`, `ThemePalette`
   - `ClaudeKit`: streaming Anthropic Messages API client (`ClaudeClient`), structured JSON output (`completeJSON`), `ClaudeModel`, `APIKeyKeychain`, `ConnectionCheck`
   - `MCPKit`: Model Context Protocol server pieces with no app knowledge: `MCPServerCore` (JSON-RPC: `initialize`, `tools/list`, `tools/call`), `MCPHTTPEndpoint` (Streamable HTTP on `/mcp` and `/u/<token>/mcp`, bearer token, local `Host`/`Origin` only), `HTTPRequestParser`, `MCPSetupLink` (`tally://mcp?...` pairing deep links & URL normalization), `MCPClientConfig` (JSON & Codex TOML config editors)
   - `BudgetKit`: `TransactionRecord`, `BudgetLimitRecord`, `SavingsGoalRecord`, `InstallmentPlanRecord` (installment/loan schedule, amortization, progress, `InstallmentHint`), `MonthlySnapshot`, `StatisticsSnapshot`, `LocalTransactionParser` (offline VN/SG/Apple Pay bank alert parser), `AITransactionParser` (Claude structured extraction with offline fallback), `BudgetAssistantPrompt`, `EmailInboxClient`, `TransactionDeduplicator`, `WebBackupCodec` (compatible with Tally Web JSON), `SalaryPrivacy` (the single "hide salary" rule: salary transactions and any aggregate containing one are masked, other income and spending never), adviser figures for Ask Tally (`AdviserMetrics`: cash-flow history, fixed vs variable, budget adherence, period totals, runway; `AdviserDebtAndGoals`: debt overview, affordability, goal timelines; `AdviserTools`: the read-only tools and calculators that hand those figures to the model, plus resolved dates; `SalaryAccess`: the `request_salary_access` protocol and consent record)
   - `SyncKit`: `CloudZoneRole`, `SyncRecordKind`, `SyncMerge` (deterministic LWW + tombstone deletion rules)

2. **Platform & Service modules**:
   - `DesignSystem`: cross-platform live `ThemeRuntime` (`UIColor` / `NSColor` + window appearance), SF Pro Rounded typography scale, floating 26pt cards with warm cocoa shadows in light mode / hairline borders in dark mode, watercolor PNG + vector hybrid icons, `HorizonPeriodCalendarView`, `AmountKeypadView` (touch + hardware keyboard), `CozyTabBar`
   - `Persistence`: SwiftData models (`SDTransaction`, `SDBudgetLimit`, `SDSavingsGoal`, `SDInstallmentPlan`) and shared `AppStore.container`
   - `AppServices`: `AppSettings`, `KeychainStore` (API key, inbox secret & Cloud MCP credentials only in Keychain, never in CloudKit), `BudgetStore`, `CloudSync` (`CKSyncEngine` private + shared database + `CKShare` household sharing), `AssistantService`, `VoiceDictationManager`, `EmailInboxSync`, `RemoteMCPSync` (bidirectional Cloud MCP sync + config push), `MCPServer`, `MCPClientInstaller` / `MCPCloudDeployer` (Mac 1-tap Cloudflare deploy & desktop client config), `SalaryVisibilityGate` (hide-salary state + optional Face ID / Touch ID / passcode to reveal, `LocalAuthentication` behind a `SalaryAuthenticating` protocol), `SalaryAccessBroker` (the assistant's salary consent card: suspends the tool loop until Allow / Not now, unlocks only through the gate, once per user message)

3. **Feature UI modules (tiered)**:
   - Tier 0: `SharedUI` (`MonthSwitcher`, `PeriodPickerSheet`, `MemberFilterBar`, `TransactionRow`, `TransactionEditorSheet`)
   - Tier 1: `OverviewUI`, `TransactionsUI`, `StatisticsUI`, `BudgetsUI`, `GoalsUI` (`GoalsView` savings goals, `CommitmentsView` installment plans & loans), `AssistantUI`
   - Tier 2: `SettingsUI` (compact push navigation on phone, 2-pane workspace on iPad & Mac; `GeneralSettingsPane`, `ClaudeSettingsPane`, `ShortcutsSettingsPane`, `EmailInboxSettingsPane`, `CloudSharingSettingsPane` with `UICloudSharingController` / `NSSharingService`, `MCPSettingsPane` (iPhone, iPad & Mac) + `MCPQRCodeSheet` + `MCPQRScannerSheet` + `MCPPairingConfirmationSheet`, `BackupSettingsPane`)

4. **App Target (`Tally/`)**:
   - `Tally/App/TallyApp.swift`: composition root, CloudKit share acceptance delegates (`UIApplicationDelegate` / `UIWindowSceneDelegate` on iOS & iPadOS; `NSApplicationDelegate` on macOS), remote notification registration, `tally://` URL scheme fallback
   - `Tally/App/RootTabs.swift`: adaptive shell — floating cozy tab bar + action dock on compact widths (the 4th tab hosts a Budgets / Goals / Commitments segmented control) (iPhone / narrow Split View) and cozy **Paws & Cream** `NavigationSplitView` sidebar on wide iPad & Mac layouts
   - `Tally/App/TallyCommands.swift`: menu bar & hardware keyboard shortcuts (`⌘N`, `⇧⌘V`, `⌘K`, `⇧⌘R`, `⌘1`–`⌘6`, `⌘[`, `⌘]`, `⌘,`)
   - `Tally/AppIntents/TallyShortcuts.swift`: native Apple Shortcuts & Siri intents (`TellTallyIntent`, `AutoLogTransactionIntent`, `LogApplePayTransactionIntent`, `LogTransactionFromTextIntent`, `QuickLogExpenseIntent`, `GetSpendingSummaryIntent`)

## Household Sync (iPhone, iPad & Mac + Husband & Wife on Separate Apple IDs)

- All platforms share bundle ID `com.ldakhoa.tally` and CloudKit container `iCloud.com.ldakhoa.tally` (`Tally-iOS.entitlements` and `Tally-macOS.entitlements`), so your own iPhone, iPad, and Mac sync automatically via `privateCloudDatabase` zone `TallyHousehold` (plus iCloud Keychain for API keys).
- Inviting a partner creates a zone-wide `CKShare(recordZoneID:)` and opens Apple's native sharing sheet (`UICloudSharingController` on iOS/iPadOS, `NSSharingService(named: .cloudSharing)` on macOS).
- When the partner opens the iCloud link on iPhone, iPad, or Mac, the platform delegate accepts the share via `CloudSync.acceptShareWhenReady(_:)`, switches `cloudZoneRole` to `.sharedParticipant`, and runs `CKSyncEngine` against `sharedCloudDatabase` for read/write sync.
- Conflicts resolve deterministically via `SyncMerge` (Last-Write-Wins on `updatedAt` with soft-delete tombstones). Plan payments (`"<planID>#<index>"`) instead carry a `PlanPaymentState` with two components merged independently: the latest explicit user operation (LWW, always decides when present) and the automatic schedule state (ordered by the plan revision it was derived from, then booked over withdrawn). Every merge is a join (commutative, associative, idempotent).
- Zone loss (`CloudSyncPolicy`): a zone deleted, purged or reset (encrypted data) pauses sync instead of deleting local data or re-uploading: pending changes and cached system fields are dropped, the iCloud toggle turns off and the settings pane explains how to resume. Only a missing zone that never held this record, on the owner's device, is recreated automatically.

## MCP Server (Cloud 24/7 + Local Mac)

Other assistants (Claude iOS/Web/Desktop, ChatGPT, Muse, Claude Code, Codex, Antigravity, Cursor) can work with the household's data through Tally's MCP integration in **Settings → MCP & AI Assistants**.

- **Always-on Cloud MCP (`tools/mcp-server` on Cloudflare Workers):**
  - Deployed in 1 tap from the Mac app (or `tools/deploy-mcp`) into a private SQLite Durable Object (`TallyVault`). Credentials (`url`, `syncSecret`, `accessToken`) live in iCloud Keychain (`KeychainStore.CloudMCPCredentials`), so the user's iPhone & iPad connect automatically; partner devices or instant pairing use QR scan / `tally://mcp?...` AirDrop links.
  - `RemoteMCPSync` (`AppServices`) syncs local & iCloud changes to the Worker on launch, foreground, and 2 seconds after store edits, and pulls assistant-made changes via `sinceRevision` into `BudgetStore` with `notifyCloud: true` so they sync through `CKSyncEngine` to all household devices.
  - Supports `POST /mcp` (Bearer token or OAuth 2.1 + PKCE S256 + RFC 7591 Dynamic Client Registration using 6-digit pairing codes) and `POST /u/<token>/mcp` (1-URL zero-header connector for Claude, ChatGPT, Muse, and Antigravity).
  - Mirrors Tally's deterministic adviser & action tools, currency/FX table, timezone day key, salary hiding (`locked (salary hidden)`), and `Allow changes` gate (`tools/mcp-server/src/`).
- **1-Tap Mac Client Setup (`MCPClientInstaller`):**
  - Automatically detects and configures Claude Code (`~/.claude.json`), Codex (`~/.codex/config.toml`), Claude Desktop (`claude_desktop_config.json` via `mcp-remote`), Antigravity (`~/.gemini/config/mcp_config.json`), and Cursor (`~/.cursor/mcp.json`) while preserving unrelated entries and file permissions.
- **Local Mac Fallback (`MCPServer`):**
  - `MCPServer` (`AppServices`) can also run inside the Mac app with `NWListener` on `127.0.0.1:47821` (local Keychain token only), exposing the live `BudgetStore` through `ExternalToolCatalog` and `AssistantService.execute`.

## Commands

```bash
swift test --package-path Packages
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Tally.xcodeproj -scheme Tally -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO
tools/install-mac
tools/install-device
tools/install-device "Wife's iPhone"
```
