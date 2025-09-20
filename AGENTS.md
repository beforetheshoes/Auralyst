# Auralyst — Agent Implementation Guide

## Mission
Auralyst keeps the log, spots the patterns, and nudges when it matters. Ship an iOS 18+ app that feels calm, capable, and quietly helpful while providing collaborative symptom tracking built on Core Data mirrored to CloudKit.

## Core Tenets
- **Platforms:** iOS first; macOS and watchOS follow the same model when we expand.
- **UI Framework:** SwiftUI with the new Observation API (`@Observable`, `@State`). Never use `ObservableObject` or `@StateObject`.
- **Persistence:** Core Data with `NSPersistentCloudKitContainer`.
- **Sync & Collaboration:** CloudKit zone sharing for one `Journal` root record shared across accounts.
- **Offline:** Full fidelity offline usage with eventual sync.
- **Privacy:** iCloud auth, on-device storage, no third-party services.

## Visual & Brand Cues
- **Tone:** Calm assistant, not AI-forward.
- **Palette:** Ink `#0F172A`, Primary `#2563EB` (light) / `#60A5FA` (dark), Accent `#F59E0B` / `#FBBF24`, Surface light `#F8FAFC`, Surface dark `#0B1220`.
- **Typography:** System SF Pro for UI; Manrope/Inter optional for display headers.
- **Microcopy:** Use provided strings for empty states, insights, sharing prompts.

## Architecture Checklist
- `PersistenceController` wrapping `NSPersistentCloudKitContainer` with private + shared stores, automatic history tracking, and remote change handling.
- Separate Core Data contexts: viewContext (main queue), background contexts for work queues.
- CloudKit sharing helpers (`ShareController`) for exposing a `Journal` via `CKShare` and managing `CKShare.Metadata`.
- SwiftUI layers driven by Observation-friendly view models using `@Observable` classes/structs backed by Core Data fetches via `@FetchRequest` or `@Query`.
- Notification handlers to merge remote changes into the main context on background thread.

## Data Model Summary
- **Journal**: `id`, `createdAt`, relationships to `SymptomEntry` and `CollaboratorNote`. Sharing root.
- **SymptomEntry**: `id`, `timestamp`, severity fielding (overall severity or per-symptom), medication, note, relationship to `Journal`.
- **CollaboratorNote**: `id`, `timestamp`, `text`, optional `authorName`, optional `entryRef`, relationship to `Journal`.

## Feature Pillars
1. **Logging:** Quick-add form for symptoms, meds, notes.
2. **Timeline:** Home view showing today + recent entries grouped by day.
3. **Detail:** Entry detail with collaborator notes presented alongside owner data.
4. **Insights:** Swift Charts delivering rolling trends and gentle cues triggered by meaningful patterns.
5. **Sharing:** Invite collaborators via CloudKit share sheet; manage participants and stop sharing.

## Testing Expectations
- Use MCP servers:
  - `sosumi` for documentation lookups.
  - `XCodeBuildMCP` for building/testing automation.
- Manual test passes must include multi-account CloudKit sharing, offline edits, revocation behaviour.
- Automated validation should run through `Testing/Automation.md` via `XCodeBuildMCP`.

## Immediate Deliverables
- Create the Core Data model (`Auralyst.xcdatamodeld`) matching the schema above.
- Build the persistence stack with CloudKit mirroring and history tracking hooks.
- Scaffold the SwiftUI App entry point and initial navigation shell.
- Provide developer-facing `PreviewSeed` helpers to seed a local store for SwiftUI previews.

## Coding Standards
- Swift 6, strict concurrency, no legacy Combine-based observation.
- Keep comments minimal and purposeful—only for non-obvious logic or gotchas.
- Ensure all new files adhere to iOS 18 deployment target and enable CloudKit capability.

## Future Hooks (Roadmap)
- Trigger tagging (sleep, hydration, etc.).
- HealthKit integration for relevant metrics.
- Explainable insights and optional Apple Intelligence summaries once confident.

