import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication quick log loader", .serialized)
struct MedicationQuickLogLoaderSuite {
    @MainActor
    @Test("Loads schedules for medications on refresh")
    func loaderReturnsPersistedSchedules() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Ibuprofen",
            defaultAmount: 200,
            defaultUnit: "mg"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(
                for: MedicationWeekday.allCases
            ),
            hour: 8,
            minute: 0,
            timeZoneIdentifier: TimeZone.current.identifier,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(
            journalID: journal.id, on: Date()
        )

        let loadedSchedules =
            snapshot.schedulesByMedication[medication.id]
        #expect(loadedSchedules?.count == 1)
        #expect(loadedSchedules?.first?.label == "Morning")
    }

    @Test("Loads snapshot from a detached task")
    func loaderRunsOffMainActor() async throws {
        let result = try await Task.detached {
            try withDependencies {
                $0.context = .test
                try $0.bootstrapDatabase(
                    configureSyncEngine: false
                )
                $0.databaseClient = buildTestDatabaseClient(
                    database: $0.defaultDatabase
                )
            } operation: {
                @Dependency(\.databaseClient) var client
                let journal = client.createJournal()
                let medication = client.createMedication(
                    journal, "Melatonin", 3, "mg"
                )
                let loader = MedicationQuickLogLoader()
                let snapshot = try loader.load(
                    journalID: journal.id, on: Date()
                )
                return (snapshot, medication.id)
            }
        }.value

        #expect(result.0.medications.contains(where: {
            $0.id == result.1
        }))
    }

    @MainActor
    @Test("Loads medications even if journal row is missing")
    func loaderDoesNotRequireJournalRow() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()

        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Orphan Med",
            defaultAmount: 1,
            defaultUnit: "pill"
        )
        let now = Date()

        // PRAGMA foreign_keys is a no-op inside a transaction, so
        // use writeWithoutTransaction to toggle it around the delete.
        try database.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(
                sql: """
                    DELETE FROM sqLiteJournal
                    WHERE id = ?
                    """,
                arguments: [journal.id.uuidString]
            )
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(
            journalID: journal.id, on: now
        )

        #expect(snapshot.medications.contains(where: {
            $0.id == medication.id
        }))
    }

    @MainActor
    @Test("Returns empty snapshot for unknown journal ID")
    func loaderReturnsEmptyForUnknownJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        _ = store.createMedication(
            for: journal, name: "Known Med",
            defaultAmount: 1, defaultUnit: "pill"
        )

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(
            journalID: UUID(), on: Date()
        )

        #expect(snapshot.medications.isEmpty)
        #expect(snapshot.schedulesByMedication.isEmpty)
        #expect(snapshot.takenByScheduleID.isEmpty)
    }

    @MainActor
    @Test("Maps taken intakes by schedule and medication ID")
    func loaderMapsTakenIntakes() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let fx = try createTakenIntakesFixture(
            database: database
        )

        let baseDate = Date(
            timeIntervalSince1970: 1_726_601_200
        )
        let dayStart = Calendar.current.startOfDay(
            for: baseDate
        )

        try insertTakenIntakes(
            database: database,
            scheduledMed: fx.scheduledMed,
            asNeededMed: fx.asNeededMed,
            schedule: fx.schedule,
            dayStart: dayStart
        )

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(
            journalID: fx.journal.id, on: baseDate
        )

        #expect(
            snapshot.takenByScheduleID[fx.schedule.id]?
                .medicationID == fx.scheduledMed.id
        )
        #expect(
            snapshot.takenByScheduleID[fx.asNeededMed.id]?
                .medicationID == fx.asNeededMed.id
        )
    }

    @MainActor
    @Test("Schedule persistence drops missing schedule refs")
    func schedulePersistenceDropsMissingRefs() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Fallback",
            defaultAmount: 1,
            defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let persistedID = try database.read { db in
            try MedicationQuickLogSection
                .scheduleIDToPersist(
                    scheduleID: medication.id, db: db
                )
        }

        #expect(persistedID == nil)
    }

    @MainActor
    @Test("Schedule persistence keeps real schedule refs")
    func schedulePersistenceKeepsRealRefs() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Real",
            defaultAmount: 1,
            defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(
                for: MedicationWeekday.allCases
            ),
            hour: 8,
            minute: 0,
            timeZoneIdentifier: TimeZone.current.identifier,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let persistedID = try database.read { db in
            try MedicationQuickLogSection
                .scheduleIDToPersist(
                    scheduleID: schedule.id, db: db
                )
        }

        #expect(persistedID == schedule.id)
    }
}

// MARK: - Taken Intakes Helpers

private struct TakenIntakesFixture {
    let journal: SQLiteJournal
    let scheduledMed: SQLiteMedication
    let asNeededMed: SQLiteMedication
    let schedule: SQLiteMedicationSchedule
}

@MainActor
private func createTakenIntakesFixture(
    database: any DatabaseWriter
) throws -> TakenIntakesFixture {
    let store = DataStore()
    let journal = store.createJournal()

    let scheduledMedication = store.createMedication(
        for: journal,
        name: "Scheduled Med",
        defaultAmount: 1,
        defaultUnit: "pill"
    )
    let asNeededMedication = store.createMedication(
        for: journal,
        name: "As Needed Med",
        defaultAmount: 2,
        defaultUnit: "pill"
    )

    let schedule = SQLiteMedicationSchedule(
        medicationID: scheduledMedication.id,
        label: "Morning",
        amount: 1,
        unit: "pill",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: 8,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
    try insertSchedule(schedule, database: database)

    return TakenIntakesFixture(
        journal: journal,
        scheduledMed: scheduledMedication,
        asNeededMed: asNeededMedication,
        schedule: schedule
    )
}

private func insertTakenIntakes(
    database: any DatabaseWriter,
    scheduledMed: SQLiteMedication,
    asNeededMed: SQLiteMedication,
    schedule: SQLiteMedicationSchedule,
    dayStart: Date
) throws {
    let scheduledTimestamp =
        dayStart.addingTimeInterval(8 * 60 * 60)
    let asNeededTimestamp =
        dayStart.addingTimeInterval(10 * 60 * 60)

    let scheduledIntake = SQLiteMedicationIntake(
        medicationID: scheduledMed.id,
        scheduleID: schedule.id,
        amount: 1,
        unit: "pill",
        timestamp: scheduledTimestamp,
        origin: "scheduled"
    )
    let asNeededIntake = SQLiteMedicationIntake(
        medicationID: asNeededMed.id,
        amount: 2,
        unit: "pill",
        timestamp: asNeededTimestamp,
        origin: "asNeeded"
    )
    try insertIntake(scheduledIntake, database: database)
    try insertIntake(asNeededIntake, database: database)
}
