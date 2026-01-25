# Auralyst

Symptom journaling and medication tracking app built with SwiftUI, SQLiteData, and The Composable Architecture (TCA). Supports CloudKit sync/sharing and runs on iOS and macOS.

## Tech stack

- Swift, SwiftUI
- The Composable Architecture (TCA)
- SQLiteData (GRDB + CloudKit sync)
- XCTest for unit and UI tests

## Project layout

- `AuralystApp/` app source (features, views, models, persistence)
- `AuralystAppTests/` unit tests
- `AuralystAppUITests/` UI tests
- `AuralystApp.xcodeproj/` Xcode project and SwiftPM resolution

## Requirements

- Xcode (latest stable recommended)
- iOS Simulator or a connected device

## Build

Open in Xcode:

```
open AuralystApp.xcodeproj
```

Or build from CLI:

```
xcodebuild -project AuralystApp.xcodeproj -scheme AuralystApp -destination 'generic/platform=iOS' build
```

## Tests

Unit tests (simulator):

```
xcodebuild -project AuralystApp.xcodeproj -scheme AuralystApp -destination 'platform=iOS Simulator,name=iPhone 15' test
```

UI tests run as part of the same scheme. The launch performance test runs only on simulator and is skipped on device.

## Environment variables

- `AURALYST_SYNC_STATUS`: override sync indicator (values: `idle`, `syncing`, `up_to_date`, `error:message`)
- `AURALYST_SKIP_INITIAL_OVERLAY=1`: bypass initial sync overlay
- `AURALYST_UI_FIXTURE=as_needed_quicklog`: seeds fixture data for UI automation
- `FORCE_FULL_APP=1`: treat run as non-test even under XCTest

## Notes

- CloudKit sync is configured in `AuralystApp/App/AppBootstrap.swift`.
- SQLiteData is pinned via SwiftPM in the Xcode project.
