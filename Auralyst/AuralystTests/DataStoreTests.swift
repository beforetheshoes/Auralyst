import Foundation
import Testing
import Observation
import Dependencies
import SQLiteData
@testable import Auralyst

@Suite("DataStore SQLiteData integration")
struct DataStoreSuite {
    @MainActor
    @Test("DataStore adopts Observation")
    func dataStoreIsObservable() {
        let store = DataStore()
        #expect(store is any Observable)
    }

    @MainActor
    @Test("Creating and fetching journals persists through SQLiteData")
    func createAndFetchJournalThroughDefaultDatabase() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let created = store.createJournal()
        let fetched = store.fetchJournal(id: created.id)
        #expect(fetched?.id == created.id)
    }

    @MainActor
    @Test("Updating a scheduled intake preserves its linkage metadata")
    func updateMedicationIntakePreservesScheduleLinkage() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        @Dependency(\.defaultDatabase) var database

        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal,
            severity: 4,
            note: "Pre-edit log"
        )
        let medication = store.createMedication(
            for: journal,
            name: "Levothyroxine",
            defaultAmount: 1,
            defaultUnit: "tablet"
        )

        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            hour: 7,
            minute: 30,
            isActive: true,
            sortOrder: 0
        )
        try database.write { db in
            try SQLiteMedicationSchedule.insert { schedule }.execute(db)
        }

        let originalIntake = SQLiteMedicationIntake(
            id: UUID(),
            medicationID: medication.id,
            entryID: entry.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "tablet",
            timestamp: Date(timeIntervalSince1970: 1_726_000_000),
            scheduledDate: Date(timeIntervalSince1970: 1_725_936_000),
            origin: "scheduled",
            notes: "Logged from quick checkmark"
        )
        try database.write { db in
            try SQLiteMedicationIntake.insert { originalIntake }.execute(db)
        }

        let editedIntake = SQLiteMedicationIntake(
            id: originalIntake.id,
            medicationID: originalIntake.medicationID,
            amount: 2,
            unit: "tablet",
            timestamp: originalIntake.timestamp.addingTimeInterval(1800),
            notes: "Adjusted amount"
        )

        try store.updateMedicationIntake(editedIntake)

        let reloaded = store.fetchMedicationIntake(id: originalIntake.id)

        #expect(reloaded?.id == originalIntake.id)
        #expect(reloaded?.scheduleID == originalIntake.scheduleID)
        #expect(reloaded?.entryID == originalIntake.entryID)
        #expect(reloaded?.scheduledDate == originalIntake.scheduledDate)
        #expect(reloaded?.origin == originalIntake.origin)
        #expect(reloaded?.amount == editedIntake.amount)
        #expect(reloaded?.timestamp == editedIntake.timestamp)
        #expect(reloaded?.notes == editedIntake.notes)
    }

    @MainActor
    @Test("Deleting a medication cascades schedules and intakes")
    func deleteMedicationRemovesRelatedRecords() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        @Dependency(\.defaultDatabase) var database

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Melatonin",
            defaultAmount: 5,
            defaultUnit: "mg"
        )

        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Bedtime",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 22,
            minute: 30,
            isActive: true,
            sortOrder: 0
        )

        try database.write { db in
            try SQLiteMedicationSchedule.insert { schedule }.execute(db)
            try SQLiteMedicationIntake.insert {
                SQLiteMedicationIntake(
                    medicationID: medication.id,
                    scheduleID: schedule.id,
                    amount: 1,
                    unit: "tablet",
                    timestamp: .now
                )
            }.execute(db)
        }

        try store.deleteMedication(medication.id)

        let remainingMedications = store.fetchMedications(for: journal)
        #expect(remainingMedications.isEmpty)

        let remainingSchedules = try database.read { db in
            try SQLiteMedicationSchedule
                .where { $0.medicationID == medication.id }
                .fetchAll(db)
        }
        #expect(remainingSchedules.isEmpty)

        let remainingIntakes = try database.read { db in
            try SQLiteMedicationIntake
                .where { $0.medicationID == medication.id }
                .fetchAll(db)
        }
        #expect(remainingIntakes.isEmpty)
    }
}
