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
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            timeZoneIdentifier: TimeZone.current.identifier,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(journalID: journal.id, on: Date())

        let loadedSchedules = snapshot.schedulesByMedication[medication.id]
        #expect(loadedSchedules?.count == 1)
        #expect(loadedSchedules?.first?.label == "Morning")
    }

    @Test("Loads snapshot from a detached task")
    func loaderRunsOffMainActor() async throws {
        let result = try await Task.detached {
            try await withDependencies {
                $0.context = .test
                try $0.bootstrapDatabase(configureSyncEngine: false)
            } operation: {
                @Dependency(\.databaseClient) var databaseClient
                let journal = databaseClient.createJournal()
                let medication = databaseClient.createMedication(journal, "Melatonin", 3, "mg")
                let loader = MedicationQuickLogLoader()
                let snapshot = try loader.load(journalID: journal.id, on: Date())
                return (snapshot, medication.id)
            }
        }.value

        #expect(result.0.medications.contains(where: { $0.id == result.1 }))
    }

    @MainActor
    @Test("Loads medications even if the journal row is missing")
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

        try database.write { db in
            // Simulate a reset that removes the journal but leaves medications behind.
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(
                sql: "DELETE FROM sqLiteJournal WHERE id = ?",
                arguments: [journal.id.uuidString]
            )
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(journalID: journal.id, on: now)

        #expect(snapshot.medications.contains(where: { $0.id == medication.id }))
    }

    @MainActor
    @Test("Returns an empty snapshot for an unknown journal ID")
    func loaderReturnsEmptyForUnknownJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        _ = store.createMedication(for: journal, name: "Known Med", defaultAmount: 1, defaultUnit: "pill")

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(journalID: UUID(), on: Date())

        #expect(snapshot.medications.isEmpty)
        #expect(snapshot.schedulesByMedication.isEmpty)
        #expect(snapshot.takenByScheduleID.isEmpty)
    }

    @MainActor
    @Test("Maps taken intakes by schedule ID and medication ID")
    func loaderMapsTakenIntakesForScheduledAndAsNeeded() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
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
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let dayStart = Calendar.current.startOfDay(for: baseDate)
        let scheduledTimestamp = dayStart.addingTimeInterval(8 * 60 * 60)
        let asNeededTimestamp = dayStart.addingTimeInterval(10 * 60 * 60)

        let scheduledIntake = SQLiteMedicationIntake(
            medicationID: scheduledMedication.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: scheduledTimestamp,
            origin: "scheduled"
        )
        let asNeededIntake = SQLiteMedicationIntake(
            medicationID: asNeededMedication.id,
            amount: 2,
            unit: "pill",
            timestamp: asNeededTimestamp,
            origin: "asNeeded"
        )
        try insertIntake(scheduledIntake, database: database)
        try insertIntake(asNeededIntake, database: database)

        let loader = MedicationQuickLogLoader()
        let snapshot = try loader.load(journalID: journal.id, on: baseDate)

        #expect(snapshot.takenByScheduleID[schedule.id]?.medicationID == scheduledMedication.id)
        #expect(snapshot.takenByScheduleID[asNeededMedication.id]?.medicationID == asNeededMedication.id)
    }
}
