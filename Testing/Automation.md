# Automated Validation Plan

Use MCP services for repeatable validation:

- **Build & UI tests:** run the `xcodebuild` workflows via the `XCodeBuildMCP` server. Suggested command once the Xcode project is configured:
  - `XCodeBuildMCP run --scheme Auralyst --destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0' --actions test`
- **Documentation lookups:** rely on the `sosumi` MCP server for Apple API references instead of web searches.
- **CloudKit collaboration tests:** script paired runs by launching `XCodeBuildMCP` on two simulator destinations to cover share invitations, acceptance, and revocation.
- **Offline regression:** add an automation step that toggles the simulator network state before executing the `XCodeBuildMCP` run to verify persistence without connectivity.

Keep these steps wired into CI once the project file lands; the MCP servers give reproducible runs without leaving the toolchain.
