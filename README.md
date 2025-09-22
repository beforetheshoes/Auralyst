# Comprehensive Technical Documentation

## Medication Intake Editing
- `DataStore.updateMedicationIntake(_:)` now hydrates existing records before applying changes so schedule linkage fields (`scheduleID`, `entryID`, `scheduledDate`, `origin`) persist through edits. Callers may pass only the user-editable fields (`amount`, `unit`, `timestamp`, `notes`), and the store will merge them with the original linkage metadata.
- `SQLiteMedicationIntake.mergingEditableFields` is the canonical helper for producing an updated record while keeping linkage metadata intact. UI layers such as `MedicationIntakeEditorView` should use this helper when constructing edits to avoid unintentionally dropping schedule associations.

-## Medication Quick Log Refresh
- `MedicationQuickLogLoader` centralizes fetching of medications, schedules, and day-bound intakes. `MedicationQuickLogSection` refreshes its snapshot via this loader on appearance, when the selected date changes, and whenever `.medicationsDidChange` is posted.
- `MedicationEditorView` emits the `.medicationsDidChange` notification after saving so downstream surfaces (quick log, day summaries) pick up schedule changes immediately without re-navigation.
- As-needed logging now navigates to an `AsNeededIntakeView` instead of presenting a sheet, which keeps the macOS experience stable while still posting `.medicationIntakesDidChange` after a dose is recorded.
- Day detail rows keep using navigation links to `MedicationIntakeEditorView` and refresh their local intake lists when notifications fire, so editing a scheduled dose updates summaries right away.

## Testing Coverage
- Regression tests live in `AuralystTests/DataStoreTests.swift`, `AuralystTests/MedicationIntakeUpdateTests.swift`, and `AuralystTests/MedicationQuickLogLoaderTests.swift`. They verify that linkage metadata survives edits and that the quick log loader returns newly persisted schedules.
