# Comprehensive Technical Documentation

## Medication Intake Editing
- `DataStore.updateMedicationIntake(_:)` now hydrates existing records before applying changes so schedule linkage fields (`scheduleID`, `entryID`, `scheduledDate`, `origin`) persist through edits. Callers may pass only the user-editable fields (`amount`, `unit`, `timestamp`, `notes`), and the store will merge them with the original linkage metadata.
- `SQLiteMedicationIntake.mergingEditableFields` is the canonical helper for producing an updated record while keeping linkage metadata intact. UI layers such as `MedicationIntakeEditorView` should use this helper when constructing edits to avoid unintentionally dropping schedule associations.

## Medication Quick Log Refresh
- `MedicationQuickLogModel` observes medications, schedules, and intakes with `@FetchAll`, rebuilding its snapshot whenever the underlying tables change or the selected date shifts. `MedicationQuickLogSection` binds directly to the model so the list reflects Manage Medications edits without relying on manual notifications.
- `MedicationQuickLogLoader` remains the shared translator for snapshot structure. The model mirrors its day-bound filtering to keep CloudKit sync behaviour unchanged.
- As-needed logging still presents `AsNeededIntakeView`, and dose mutations trigger `model.refresh()` alongside the existing notifications for manual observers.
- Editing a medication now includes a destructive "Delete Medication" action with confirmation; the flow removes related schedules and intakes so quick logging stays in sync immediately.

## Testing Coverage
- Regression tests live in `AuralystTests/DataStoreTests.swift`, `AuralystTests/MedicationIntakeUpdateTests.swift`, `AuralystTests/MedicationQuickLogLoaderTests.swift`, and `AuralystTests/MedicationQuickLogModelTests.swift`. They verify that linkage metadata survives edits and that the quick log surfaces stream newly persisted schedules.
- UI coverage includes `AuralystUITests/AuralystUITests.swift::testQuickMedicationLogRefreshesAfterManaging`, which drives the Manage Medications flow and confirms the quick log updates in-place on iOS 18.

## Test Execution Notes
- Full suite exercised with `xcodebuild -scheme Auralyst -project Auralyst/Auralyst.xcodeproj -destination 'platform=iOS Simulator,id=B437D3EB-E9C7-4440-83AB-292844A82395' -skipPackagePluginValidation test` (iPhone 16 Pro, iOS 18.5).
- Result bundle: `/Users/ryan/Library/Developer/Xcode/DerivedData/Auralyst-aybtjhqcnaziqzcsyvggcofiuemi/Logs/Test/Test-Auralyst-2025.09.22_16-06-01--0400.xcresult`.
- Prefer `XCodeBuildMCP run --scheme Auralyst --destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' --actions test` when the MCP server is available to keep automation consistent.
