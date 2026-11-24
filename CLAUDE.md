# Tally (iOS, iPadOS, macOS + Web)

Personal & household budget tracker for iPhone (iOS 17+), iPad (iPadOS 17+), and Mac (macOS 14+), styled with the **Paws & Cream** cozy hand-drawn design system and **SF Pro Rounded** typography (see `docs/DESIGN_SYSTEM.md`).

## Where things are

- `Tally/`: thin multiplatform app target (`App/` composition + `AppIntents/` for Apple Shortcuts + `Assets.xcassets`). File-system-synchronized (`PBXFileSystemSynchronizedRootGroup`): adding a file under `Tally/` adds it to the build automatically.
- `Tally-iOS.entitlements` / `Tally-macOS.entitlements`: platform entitlements sharing CloudKit container `iCloud.com.ldakhoa.tally` and bundle ID `com.ldakhoa.tally` so iPhone, iPad, and Mac stay synced via iCloud + iCloud Keychain.
- `Packages/`: local Swift package `Tally` holding all domain logic, design system, persistence, services, and feature screens in strict downward-only layers (see `docs/ARCHITECTURE.md`).
- `Packages/Sources/DesignSystem/Resources/`: bundled hand-painted Japanese watercolor PNGs (`chibi_*`, `icon_*`, `cat_*`, `goal_*`, `settings_*`, `kpi_*`), loaded once via in-memory cache (`CozyWatercolorAsset`, with automatic SwiftUI vector fallback if a PNG asset is absent).
- `tools/install-device`: Release build & install onto a paired iPhone/iPad (without uninstalling or losing data).
- `tools/install-mac`: Release build & install into `/Applications/Tally.app` (without losing data or iCloud state).
- `dist/`: original Tally static web prototype (its JSON backups are 100% importable/exportable in the native app).

## Design & Icon Rules (Hybrid Architecture)

Read `docs/DESIGN_SYSTEM.md` before changing UI, colors, or icons:
- **Hybrid Icon System (Performance + Craft):**
  - **Hero sticker tiles (32–44pt):** Use cached `256×256` hand-painted Japanese watercolor PNGs in `Packages/Sources/DesignSystem/Resources/` (`cat_*.png` for all 11 categories, `goal_*.png` for all 6 goals, `settings_*.png` for main Settings rows, `icon_*.png` for Overview metric cards, `kpi_*.png` for Statistics KPI tiles like `kpi_leaf` & `kpi_flame`, `chibi_*.png` for couple avatars). Loaded once through an in-memory cache (`CozyWatercolorAsset`) so scrolling lists render a single GPU texture quad with zero disk I/O, and automatically falls back to the matching hand-drawn SwiftUI vector whenever a PNG asset is absent.
  - **UI glyphs, dark-pill states & Tab Bar (12–28pt):** Use procedural SwiftUI vectors (`CozyUIIcon`, `CozyCategoryIcon(..., style: .tinted(...))`, `CozyGoalIcon(..., style: .tinted(...))`, `CozyTabIconView`) with warm cocoa ink (`#4E382F` / `#FAF0E6`) and round line caps/joins. Avoid raw system emojis or cold SF Symbols in primary UI.
- **No pure black or cold shadows:** Use warm espresso/cocoa ink (`#3D2C26` / `#4E382F`) and warm brown-tinted shadows (`#6B4423`).

## Engineering Rules

- Keep domain logic in `TallyCore`, `ThemeTokens`, `ClaudeKit`, `BudgetKit`, or `SyncKit` with unit tests in `Packages/Tests/<Module>Tests/`.
- Never import upward or sideways across feature module tiers.
- Do deterministically whatever can be deterministic, and use the LLM only where it is needed (and vice versa). In Ask Tally, calculations, totals, date maths, validation, fixed-rule ranking and permission/state flows live in code with unit tests and reach the model as context or tool results; the model handles understanding the request, reading images, judgement and wording. The same applies to how work is done here: prefer a script, test or build over asking a model to judge something that can be checked mechanically.
- Keep the Anthropic API key only in Keychain (`KeychainStore`); never log it or sync it through CloudKit records.
- Never call `CKSyncEngine.sendChanges` or `fetchChanges` directly inside engine delegate callbacks — always dispatch from a detached task.
- Never uninstall from a physical device to reinstall: install over the existing app with `tools/install-device`.
