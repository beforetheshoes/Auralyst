import Foundation
import GRDB
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication quick log write actions", .serialized)
struct MedicationQuickLogWriteTests {
    @MainActor
    @Test("logScheduledDose creates intake and refreshes")
    func logScheduledDoseCreatesIntake() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeDailySchedule(medicationID: medication.id)
        try await database.write { db in try insertSchedule(schedule, in: db) }

        let notificationCenter = NotificationCenter()
        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        let selectedDate = testStore.state.selectedDate
        await testStore.send(.logScheduledDose(schedule, medication, selectedDate))
        await testStore.receive(\.logResponse.success)

        let count = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteMedicationIntake"
                    WHERE lower("medicationID") = lower(?)
                    AND lower("scheduleID") = lower(?)
                    """,
                arguments: [medication.id.uuidString, schedule.id.uuidString]
            ) ?? 0
        }
        #expect(count == 1)
        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("unlogScheduledDose removes intake and refreshes")
    func unlogScheduledDoseRemovesIntake() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeDailySchedule(medicationID: medication.id)
        let intakeID = UUID()
        let selectedDate = Calendar.current.startOfDay(for: Date())
        try await database.write { db in
            try insertSchedule(schedule, in: db)
            try insertMedicationIntake(
                in: db, id: intakeID,
                medicationID: medication.id, scheduleID: schedule.id,
                amount: 1, unit: "pill",
                timestamp: selectedDate, scheduledDate: selectedDate,
                origin: "scheduled"
            )
        }

        let notificationCenter = NotificationCenter()
        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)
        await testStore.send(.unlogScheduledDose(schedule, selectedDate))
        await testStore.receive(\.unlogResponse.success)

        let remaining = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \"sqLiteMedicationIntake\" WHERE lower(\"id\") = lower(?)",
                arguments: [intakeID.uuidString]
            ) ?? 0
        }
        #expect(remaining == 0)
        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("logScheduledDose failure surfaces error in state")
    func logScheduledDoseErrorSurfaced() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "pill"
        )
        let schedule = makeDailySchedule(medicationID: medication.id)

        // Delete the medication so the FK constraint on medicationID fails during insert
        @Dependency(\.defaultDatabase) var database
        try await database.write { db in
            try db.execute(
                sql: "DELETE FROM sqLiteMedication WHERE lower(id) = lower(?)",
                arguments: [medication.id.uuidString]
            )
        }

        let notificationCenter = NotificationCenter()
        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        let selectedDate = testStore.state.selectedDate
        await testStore.send(.logScheduledDose(schedule, medication, selectedDate))
        await testStore.receive(\.logResponse.failure) {
            #expect($0.errorMessage != nil)
        }
        await testStore.send(.cancelNotifications)
    }
}

private func makeDailySchedule(medicationID: UUID) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medicationID,
        label: "Morning",
        amount: 1,
        unit: "pill",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
        hour: 9,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
}
