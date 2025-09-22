# Auralyst — Technical Implementation Spec

**One-liner:** Auralyst keeps the log, spots the patterns, and nudges when it matters.

- **Platforms:** iOS (primary), macOS (optional), watchOS (optional)
- **UI:** SwiftUI
- **Persistence & Sync:** SQLiteData + CloudKit SyncEngine
- **Collaboration:** CloudKit zone sharing (read/write) between iCloud users
- **Offline:** Full offline capability; eventual cloud sync
- **Privacy:** iCloud (Apple ID auth), on-device SQLite store

---

## 0. Branding & Visual System

**Name:** Auralyst  
**Tone:** Calm, capable, quietly helpful (assistant vibe, not AI-forward)

**Palette**

- Ink (text): `#0F172A` (slate-900)
- Primary (actions/line): `#2563EB` (blue-600)
- Primary (dark mode line): `#60A5FA` (blue-400)
- Accent (cue/insight): `#F59E0B` (amber-500) / dark `#FBBF24`
- Surface light: `#F8FAFC` (slate-50)
- Surface dark: `#0B1220`

**Typography**

- UI: SF Pro (system); Display: **Manrope** _or_ **Inter** (TBD)
- Weight usage: 600/700 for headings; 400/500 for body

**Icon**

- “Quiet Trendline”: rising line with two round nodes (owner + collaborator). Keep line thin; grid subtle.

**Microcopy**

- Empty state: “Start with today. Auralyst will trace the line.”
- Insight toast: “Noticed 3 mornings this week with level ≥7. Tag wake time?”
- Share CTA: “Invite a partner to add notes. You stay in control.”

---

## 1. Persistence Strategy (SQLiteData + CloudKit SyncEngine)

The production app now runs entirely on **SQLiteData** backed by **GRDB** with CloudKit mirroring provided by `SyncEngine`. We chose this stack over Core Data/SwiftData because it gives us:

- Type-safe SQL via `@Table` models and StructuredQueries.
- First-class CloudKit zone sharing with direct access to CKRecord metadata.
- Predictable migrations defined in `Database.swift`.
- Great performance for growing symptom logs.

SwiftData still lacks multi-account collaboration and Core Data served only as an interim bridge. Historical guidance remains in version control for reference.

---

## 2. Data Model (SQLiteData)

Models live in `Auralyst/Models` and conform to SQLiteData’s expectations.

### `SQLiteJournal`
- Root share boundary, minimal columns (`id`, `createdAt`).
- `shareableTables` extension informs the sync engine which related tables to publish.

### `SQLiteSymptomEntry`
- Captures timestamp, severity metrics, menstruation flag, free-form text, and sentiment placeholders.
- References the parent journal via `journalID`.

### `SQLiteMedication`
- Stores medication metadata and default dosage hints.
- Timestamp columns support change auditing.

### `SQLiteMedicationIntake`
- Represents individual medication events.
- Optional links to symptom entries and future schedules.

### `SQLiteCollaboratorNote`
- Keeps collaborator input in a separate record type to reduce merge conflicts.

### `SQLiteMedicationSchedule`
- Encodes interval/cadence metadata for upcoming reminders.

When adding new tables, mirror the style above and extend both migrations and sync bootstrap lists.

---

## 3. Database & Sync Bootstrap

- `Persistence/Database.swift` configures GRDB, registers migrations, and attaches the CloudKit metadata store (`attachMetadatabase`).
- `SQLiteDataDocs/DependencyValues+Bootstrap.swift` exposes `bootstrapDatabase()` to assign `defaultDatabase` and configure `SyncEngine` with shareable tables.
- `AuralystApp` calls `prepareDependencies` in `init` to ensure previews/tests receive a deterministic database environment.
- Debug builds enable GRDB tracing for insight into SQL/CloudKit operations.

```swift
try prepareDependencies {
    try $0.bootstrapDatabase()
}

@Dependency(\.defaultDatabase) var database
@Dependency(\.defaultSyncEngine) var syncEngine
```

Any persistence change must:
1. Add/alter the migration in `Database.swift`.
2. Update associated `@Table` structs.
3. Include new entities when bootstrapping the sync engine.

---

## 4. Sharing Workflow (SyncEngine)

- `ShareManagementView` queries `SyncMetadata` to determine whether a journal is shared and surfaces CloudKit actions.
- `syncEngine.share(record:)` returns a `SharedRecord` that SwiftUI presents in a share sheet—no UIKit controller required.
- Collaborator acceptance happens automatically through CloudKit once the share link is opened.
- Revoke/manage access by calling the sync engine again; it will hand back fresh metadata for the UI.

Future share-aware features should read from `SyncMetadata` rather than caching assumptions locally.

---

## 5. SwiftUI App Structure

- `AuralystApp` places `AppSceneModel` and `DataStore` into the environment. `DataStore` wraps GRDB transactions on the main actor.
- Views rely on `@FetchAll`, `@FetchOne`, and `@Fetch` to stream database changes.
- Mutations (journal creation, symptom logging, medication edits, collaborator notes) live on `DataStore` so they can be reused across platforms.
- Helper models (`EntryFormModel`, etc.) are `@Observable` to work with SwiftUI’s modern observation.

```swift
struct ContentView: View {
    @FetchAll var journals: [SQLiteJournal]
    @Environment(DataStore.self) private var store
    // ...
}
```

macOS and watchOS targets can reuse the same dependencies when revived—avoid reintroducing legacy `@StateObject`/Combine patterns.

---

## 6. Insights & Trends

- Use SQLiteData aggregate queries to power Swift Charts (rolling averages, daily aggregates, medication correlation windows).
- Keep insights subtle; surface amber cues only when heuristics meet confidence thresholds.
- Ensure derived queries remain performant by indexing relevant columns during migration updates.

---

## 7. Privacy & Security

- Data resides in the on-device SQLite store; CloudKit mirrors encrypt data in transit and at rest.
- Zone sharing is explicit and revocable. Share actions live in `ShareManagementView` for consistency.
- The app remains fully functional offline; queue writes locally and allow CloudKit to catch up.
- Export flows (CSV/JSON) must run locally and request positive confirmation before leaving the device.

---

## 8. Testing Plan

- Lead with TDD: write failing tests, implement the feature, then rerun.
- Execute automated suites via `XCodeBuildMCP` targeting the iOS 18 simulator (`scheme Auralyst`).
- Expand unit coverage to include:
  - Journal lifecycle and share metadata queries.
  - Symptom entry CRUD with chronological ordering guarantees.
  - Medication + intake flows, including deletion cascades.
  - Collaborator note creation/readback.
  - Sync engine integration with mocked CloudKit responses.
- UI tests should smoke the primary navigation stack, add-entry form, medication quick log, and sharing surface.
- Add offline test scenarios by toggling simulator networking during the automated run.

---

## 9. Edge Cases & Operational Notes

- CloudKit is eventually consistent; provide optimistic UI with background refresh hooks.
- Resolve write conflicts via last-write-wins on scalar fields and separate records for multi-author content.
- Keep migrations idempotent—prefer additive changes and backfill scripts instead of destructive operations.
- Maintain accessibility essentials (Dynamic Type, VoiceOver labels, minimum contrast ratios) with every UI iteration.

---

## 10. Roadmap (Later)

- Finalize medication schedules and reminder notifications using `SQLiteMedicationSchedule`.
- HealthKit import/export once privacy review completes.
- Insight engine for spotting severity / medication correlations.
- Apple Intelligence summaries after on-device evaluation.

---

## Appendix: Historical Core Data Migration

The legacy Core Data + `NSPersistentCloudKitContainer` implementation has been removed. Consult Git history (`git show origin/core-data-era -- Auralyst-Tech-Spec.md`) only when auditing historical CloudKit data. All new work must follow the SQLiteData architecture described above.
