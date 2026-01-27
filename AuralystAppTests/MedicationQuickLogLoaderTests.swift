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
}
