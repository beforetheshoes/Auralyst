import Foundation
@preconcurrency import Dependencies
@preconcurrency import SQLiteData

struct AppBootstrap {
    struct Configuration {
        let shouldStartSync: Bool
        let shouldConfigureAppearance: Bool
    }

    static func isRunningTests(processInfo: ProcessInfo = .processInfo) -> Bool {
        if processInfo.environment["FORCE_FULL_APP"] == "1" { return false }
        return processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeConfiguration(isRunningTests: Bool) -> Configuration {
        Configuration(
            shouldStartSync: !isRunningTests,
            shouldConfigureAppearance: !isRunningTests
        )
    }

    static func initializeEnvironment(isRunningTests: Bool) {
        prepareDependencies {
            try! $0.bootstrapDatabase(configureSyncEngine: !isRunningTests)
            resetForUITests(using: &$0)
            seedAutomationFixtures(using: &$0)
        }

        guard !isRunningTests else { return }
    }
}

private extension AppBootstrap {
    static func seedAutomationFixtures(using dependencies: inout DependencyValues) {
        guard let fixture = ProcessInfo.processInfo.environment["AURALYST_UI_FIXTURE"] else { return }
        switch fixture {
        case "as_needed_quicklog":
            seedAsNeededFixture(using: &dependencies)
        default:
            break
        }
    }

    static func resetForUITests(using dependencies: inout DependencyValues) {
        guard ProcessInfo.processInfo.environment["AURALYST_UI_RESET"] == "1" else { return }
        do {
            let database = dependencies.defaultDatabase
            try database.write { db in
                try SQLiteJournal.delete().execute(db)
            }
        } catch {
            // Best-effort cleanup for UI automation.
        }
    }

    static func seedAsNeededFixture(using dependencies: inout DependencyValues) {
        do {
            let database = dependencies.defaultDatabase
            try database.write { db in
                let journal: SQLiteJournal
                if let existing = try SQLiteJournal.all.fetchAll(db).first {
                    journal = existing
                } else {
                    let newJournal = SQLiteJournal()
                    try SQLiteJournal.insert { newJournal }.execute(db)
                    journal = newJournal
                }

                let medications = try SQLiteMedication
                    .where { $0.journalID == journal.id }
                    .fetchAll(db)
                let existingAsNeededNames = Set(
                    medications
                        .filter { $0.isAsNeeded == true }
                        .map(\.name)
                )

                let requiredNames = ["Fixture Relief", "Fixture Sleep"]
                let missingNames = requiredNames.filter { !existingAsNeededNames.contains($0) }

                for (index, name) in missingNames.enumerated() {
                    let medication = SQLiteMedication(
                        journalID: journal.id,
                        name: name,
                        defaultAmount: index == 0 ? 1 : 2,
                        defaultUnit: "pill",
                        isAsNeeded: true,
                        useCase: index == 0 ? "Pain" : "Sleep"
                    )
                    try SQLiteMedication.insert { medication }.execute(db)
                }
            }
        } catch {
            // Only used for automation fixtures; ignore failures in production builds.
        }
    }
}
