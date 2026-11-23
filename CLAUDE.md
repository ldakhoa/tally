# Tally (iOS + Web)

Personal & household budget tracker for iPhone and iPad (iOS 17+), styled with Onsite's design system and Avenir Next typography.

## Where things are

- `Tally/`: thin iOS app target (`App/` composition + `AppIntents/` for Apple Shortcuts + `Assets.xcassets`). File-system-synchronized (`PBXFileSystemSynchronizedRootGroup`): adding a file under `Tally/` adds it to the build automatically.
- `Packages/`: local Swift package `Tally` holding all domain logic, design system, persistence, services, and feature screens in strict downward-only layers (see `docs/ARCHITECTURE.md`).
- `tools/install-device`: Release build & install onto a paired iPhone/iPad (without uninstalling or losing data).
- `dist/`: original Tally static web prototype (its JSON backups are 100% importable/exportable in the iOS app).

## Rules

- Keep domain logic in `TallyCore`, `ThemeTokens`, `ClaudeKit`, `BudgetKit`, or `SyncKit` with unit tests in `Packages/Tests/<Module>Tests/`.
- Never import upward or sideways across feature module tiers.
- Keep the Anthropic API key only in Keychain (`KeychainStore`); never log it or sync it through CloudKit records.
- Never call `CKSyncEngine.sendChanges` or `fetchChanges` directly inside engine delegate callbacks — always dispatch from a detached task.
- Never uninstall from a physical device to reinstall: install over the existing app with `tools/install-device`.
