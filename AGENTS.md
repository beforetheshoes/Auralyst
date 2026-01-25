# AGENTS

## Project summary
Auralyst is a SwiftUI + TCA (Composable Architecture) app backed by Point-Free’s sqlite-data (GRDB + structured queries) with CloudKit sync. The codebase now uses `StoreOf` and reducers for most features.

## Toolchain
- Xcode 26.2 (Build 17C52)
- Simulator used in recent runs: iPhone 17 (26.2), id `86A1B10E-ED24-44E3-ABA2-A63D65D10832`

## Key dependencies
- swift-composable-architecture 1.23.1
- sqlite-data 1.5.0
- GRDB 7.9.0
- swift-structured-queries 0.28.0
- swift-navigation 2.6.0
- swift-perception 2.0.9

## High-level architecture
- Feature reducers: `AppFeature`, `SyncStatusFeature`, `ExportFeature`, `MedicationsFeature`, `MedicationQuickLogFeature`, `AsNeededIntakeFeature`, etc.
- Views are Store-driven (SwiftUI + TCA).
- Database access via `DatabaseClient` dependency.
- CloudKit sync driven by `SyncEngineClient`.

## Common pitfalls
- UUIDs are stored as TEXT in the database. In tests, insert UUIDs as `uuidString` to avoid “cannot store BLOB in TEXT” errors.
- Some queries in tests use raw SQL because structured queries + row decoding don’t always align with sqlite-data schema.
- Sync indicator (dot) goes yellow while sync is in-progress; green after successful sync. It can re-yellow if sync restarts or state changes.

## Tests
Run unit tests (sim):
```
xcodebuild -project AuralystApp.xcodeproj -scheme AuralystApp \
  -destination 'platform=iOS Simulator,id=86A1B10E-ED24-44E3-ABA2-A63D65D10832' test \
  COMPILER_INDEX_STORE_ENABLE=NO
```

UI tests:
- Should run only on simulator; skip on real devices.
- UI perf tests currently auto-skip on device.

## CI
Workflows (GitHub Actions):
- `ios.yml`: unit tests (skips UI tests)
- `xcode-build-analyze.yml`: build + analyze
- `ui-tests-nightly.yml`: nightly UI tests + manual trigger

## Repo layout notes
- App code in `AuralystApp/`
- Tests in `AuralystAppTests/` and `AuralystAppUITests/`
- Assets in `AuralystApp/Assets.xcassets`

## GitHub issues
Use labels for priority (`P0`, `P1`, `P2`, `P3`) and category tags (`ui`, `performance`, `sqlite-data`, `sync`, `tests`, etc.).

## Environment flags / behavior
- Sync is disabled for tests and enabled for normal runs.
- Some tests rely on `DatabaseClient.testValue` overrides.
