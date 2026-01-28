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
        case "journal_only":
            seedJournalOnlyFixture(using: &dependencies)
        case "as_needed_quicklog":
            seedAsNeededFixture(using: &dependencies)
        case "quicklog_initial":
            seedQuickLogInitialFixture(using: &dependencies)
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

    static func seedJournalOnlyFixture(using dependencies: inout DependencyValues) {
        do {
            let database = dependencies.defaultDatabase
            try database.write { db in
                guard try SQLiteJournal.all.fetchAll(db).isEmpty else { return }
                let journal = SQLiteJournal()
                try SQLiteJournal.insert { journal }.execute(db)
            }
        } catch {
            // Only used for automation fixtures; ignore failures in production builds.
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

    static func seedQuickLogInitialFixture(using dependencies: inout DependencyValues) {
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
                let existingNames = Set(medications.map(\.name))

                let scheduledName = "Fixture Daily"
                let asNeededName = "Fixture Relief"

                var scheduledMedication: SQLiteMedication?
                if !existingNames.contains(scheduledName) {
                    let medication = SQLiteMedication(
                        journalID: journal.id,
                        name: scheduledName,
                        defaultAmount: 1,
                        defaultUnit: "pill",
                        isAsNeeded: false
                    )
                    try SQLiteMedication.insert { medication }.execute(db)
                    scheduledMedication = medication
                } else {
                    scheduledMedication = medications.first(where: { $0.name == scheduledName })
                }

                if !existingNames.contains(asNeededName) {
                    let medication = SQLiteMedication(
                        journalID: journal.id,
                        name: asNeededName,
                        defaultAmount: 2,
                        defaultUnit: "pill",
                        isAsNeeded: true,
                        useCase: "Pain"
                    )
                    try SQLiteMedication.insert { medication }.execute(db)
                }

                if let scheduledMedication {
                    let existingSchedules = try SQLiteMedicationSchedule
                        .where { $0.medicationID == scheduledMedication.id }
                        .fetchAll(db)
                    if existingSchedules.isEmpty {
                        let schedule = SQLiteMedicationSchedule(
                            medicationID: scheduledMedication.id,
                            label: "Morning",
                            amount: 1,
                            unit: "pill",
                            cadence: "daily",
                            interval: 1,
                            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
                            hour: 8,
                            minute: 0,
                            timeZoneIdentifier: TimeZone.current.identifier,
                            isActive: true,
                            sortOrder: 0
                        )
                        try SQLiteMedicationSchedule.insert {
                            (
                                $0.id,
                                $0.medicationID,
                                $0.label,
                                $0.amount,
                                $0.unit,
                                $0.cadence,
                                $0.interval,
                                $0.daysOfWeekMask,
                                $0.hour,
                                $0.minute,
                                $0.timeZoneIdentifier,
                                $0.startDate,
                                $0.isActive,
                                $0.sortOrder
                            )
                        } values: {
                            (
                                schedule.id,
                                schedule.medicationID,
                                schedule.label,
                                schedule.amount,
                                schedule.unit,
                                schedule.cadence,
                                schedule.interval,
                                schedule.daysOfWeekMask,
                                schedule.hour,
                                schedule.minute,
                                schedule.timeZoneIdentifier,
                                schedule.startDate,
                                schedule.isActive,
                                schedule.sortOrder
                            )
                        }
                        .execute(db)
                    }
                }
            }
        } catch {
            // Only used for automation fixtures; ignore failures in production builds.
        }
    }
}
