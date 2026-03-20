import Foundation
import GRDB
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medications feature", .serialized)
struct MedicationsFeatureTests {
    @MainActor
    @Test("deleteMedication sends deleteResponse success and removes row")
    func deleteMedicationSuccess() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "Melatonin",
            defaultAmount: 5, defaultUnit: "mg"
        )

        @Dependency(\.defaultDatabase) var database
        try await seedScheduleAndIntake(medicationID: medication.id, database: database)

        let testStore = TestStore(
            initialState: MedicationsFeature.State(journal: journal)
        ) {
            MedicationsFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.deleteMedication(medication.id))
        await testStore.receive(\.deleteResponse.success)

        let remaining = store.fetchMedications(for: journal)
        #expect(remaining.isEmpty)

        let scheduleCount = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule WHERE lower(medicationID) = lower(?)",
                arguments: [medication.id.uuidString]
            ) ?? 0
        }
        #expect(scheduleCount == 0)
    }

    @MainActor
    @Test("deleteMedication failure surfaces errorMessage")
    func deleteMedicationFailure() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()

        let testStore = TestStore(
            initialState: MedicationsFeature.State(journal: journal)
        ) {
            MedicationsFeature()
        } withDependencies: {
            $0.databaseClient.deleteMedication = { _ in
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Delete failed"
                ])
            }
        }
        testStore.exhaustivity = .off

        await testStore.send(.deleteMedication(UUID()))
        await testStore.receive(\.deleteResponse.failure) {
            #expect($0.errorMessage != nil)
        }
    }

    @MainActor
    @Test("clearError resets errorMessage")
    func clearErrorResetsMessage() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()

        let testStore = TestStore(
            initialState: MedicationsFeature.State(journal: journal)
        ) {
            MedicationsFeature()
        }
        testStore.exhaustivity = .off

        // Manually set error state via a failing delete
        testStore.dependencies.databaseClient.deleteMedication = { _ in
            throw NSError(domain: "test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fake error"
            ])
        }
        await testStore.send(.deleteMedication(UUID()))
        await testStore.receive(\.deleteResponse.failure) {
            #expect($0.errorMessage != nil)
        }

        await testStore.send(.clearError) {
            $0.errorMessage = nil
        }
    }

    private func seedScheduleAndIntake(
        medicationID: UUID,
        database: any DatabaseWriter
    ) async throws {
        let schedule = SQLiteMedicationSchedule(
            medicationID: medicationID,
            label: "Bedtime",
            amount: 1, unit: "tablet",
            cadence: "daily", interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 22, minute: 30,
            isActive: true, sortOrder: 0
        )
        try await database.write { db in
            try insertSchedule(schedule, in: db)
            try insertIntake(
                SQLiteMedicationIntake(
                    medicationID: medicationID,
                    scheduleID: schedule.id,
                    amount: 1, unit: "tablet",
                    timestamp: .now
                ),
                in: db
            )
        }
    }
}
