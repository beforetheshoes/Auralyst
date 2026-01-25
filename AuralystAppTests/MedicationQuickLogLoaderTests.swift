import Foundation
import Testing
import Dependencies
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication quick log loader")
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
}
