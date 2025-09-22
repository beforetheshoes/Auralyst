# Auralyst — Agent Instructions

## Mission Context
Deliver the SQLiteData + CloudKit driven Auralyst app for iOS 18+, keeping the experience calm, collaborative, and privacy-conscious.

## How To Work
- **Lead with TDD**: Start each task by writing failing, intention-revealing tests (unit or UI) that encode the desired behaviour, then iterate until they pass. Keep the test names and assertions descriptive.
- **Use MCP Servers**: Reach for `sosumi` when you need Apple documentation (SwiftUI, SQLiteData, CloudKit) and `XCodeBuildMCP` for every automated build or test run. Prefer scripted automation as described in `Testing/Automation.md`.
- **Study the Local Docs**: Consult everything in `Auralyst/SQLiteDataDocs` before implementing or modifying persistence logic. Mirror those patterns when touching fetchers, mutations, or CloudKit syncing.
- **Adopt Modern Observation**: Default to `@Observable`, `@State`, and `@Bindable`-friendly patterns. Avoid legacy `ObservableObject`, `@StateObject`, and Combine unless a dependency forces it.
- **Lean on SQLiteData**: All persistence must go through the SQLiteData/GRDB stack already in place. When modelling new entities or migrations, extend the existing GRDB migrations rather than introducing Core Data.
- **Design for Sync**: Any change that affects data flow must consider CloudKit sharing, conflict resolution, and offline durability. Validate these flows manually after automated tests succeed.

## Quality Bar
- Tests accompany every feature or bug fix and are run via `XCodeBuildMCP` (simulator destination iOS 18). Include offline and multi-account scenarios when relevant.
- SwiftUI code follows Apple’s latest guidance (navigation stacks, observation, scene phases) and respects the brand system (`Color.brand*`, typography helpers).
- Keep documentation current: update `COMPREHENSIVE_TECHNICAL_DOCUMENTATION.md` and inline comments when behaviour changes.

## Daily Checklist
1. Define the desired behaviour in tests (failing first).
2. Implement the minimum code to make tests pass, consulting SQLiteData docs for correctness.
3. Run the full automation script or targeted `XCodeBuildMCP` commands.
4. Perform manual verification for sync/sharing flows.
5. Document anything notable for future agents.

## Reference Material
- `Auralyst/SQLiteDataDocs` — usage patterns, CloudKit sharing, query APIs.
- `COMPREHENSIVE_TECHNICAL_DOCUMENTATION.md` — system architecture overview; update when gaps are discovered.
- `Testing/Automation.md` — canonical automation commands and scenarios.
