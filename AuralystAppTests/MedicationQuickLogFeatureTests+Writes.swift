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
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeDailySchedule(medicationID: medication.id)
        try await database.write { db in try insertSchedule(schedule, in: db) }

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationIntakesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

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
        #expect(posted.value == true)
        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("unlogScheduledDose removes intake and refreshes")
    func unlogScheduledDoseRemovesIntake() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
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
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationIntakesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

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
        #expect(posted.value == true)
        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("logScheduledDose failure surfaces error in state")
    func logScheduledDoseErrorSurfaced() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
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
    @MainActor
    @Test("unlogScheduledDose failure surfaces error in state")
    func unlogScheduledDoseErrorSurfaced() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "pill"
        )
        let schedule = makeDailySchedule(medicationID: medication.id)

        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        } withDependencies: {
            $0.databaseClient.unlogScheduledDose = { _ in
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Unlog failed"
                ])
            }
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = NotificationCenter()

        let selectedDate = testStore.state.selectedDate
        await testStore.send(.unlogScheduledDose(schedule, selectedDate))
        await testStore.receive(\.unlogResponse.failure) {
            #expect($0.errorMessage != nil)
        }
        await testStore.send(.cancelNotifications)
    }

}

// MARK: - As-needed dose tests

extension MedicationQuickLogWriteTests {
    @MainActor
    @Test("logScheduledDose for as-needed med creates intake with nil scheduleID")
    func logAsNeededDoseCreatesIntakeWithNilScheduleID() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Ibuprofen", defaultAmount: 200, defaultUnit: "mg"
        )

        let notificationCenter = NotificationCenter()
        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        let selectedDate = testStore.state.selectedDate
        let schedule = makeAsNeededSchedule(medicationID: medication.id)
        await testStore.send(.logScheduledDose(schedule, medication, selectedDate))
        await testStore.receive(\.logResponse.success)

        @Dependency(\.defaultDatabase) var database
        let nullScheduleCount = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteMedicationIntake"
                    WHERE lower("medicationID") = lower(?)
                    AND "scheduleID" IS NULL
                    """,
                arguments: [medication.id.uuidString]
            ) ?? 0
        }
        #expect(nullScheduleCount == 1)
        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("unlogScheduledDose for as-needed med deletes by timestamp range")
    func unlogAsNeededDoseDeletesByTimestampRange() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Ibuprofen", defaultAmount: 200, defaultUnit: "mg"
        )

        @Dependency(\.defaultDatabase) var database
        let selectedDate = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!

        let (todayIntakeID, tomorrowIntakeID) = try await insertAsNeededIntakes(
            medicationID: medication.id,
            today: selectedDate,
            tomorrow: tomorrow,
            database: database
        )

        let notificationCenter = NotificationCenter()
        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        // The snapshot must NOT have the as-needed intake in takenByScheduleID
        // so the unlog falls through to the timestamp-range branch
        let schedule = makeAsNeededSchedule(medicationID: medication.id)
        await testStore.send(.unlogScheduledDose(schedule, selectedDate))
        await testStore.receive(\.unlogResponse.success)

        let todayRemaining = try await intakeCount(id: todayIntakeID, database: database)
        #expect(todayRemaining == 0)

        let tomorrowRemaining = try await intakeCount(id: tomorrowIntakeID, database: database)
        #expect(tomorrowRemaining == 1)
        await testStore.send(.cancelNotifications)
    }
}

// MARK: - Private helpers

private func makeAsNeededSchedule(
    medicationID: UUID
) -> SQLiteMedicationSchedule {
    // As-needed convention: schedule.id == medication.id, not in schedule table
    SQLiteMedicationSchedule(
        id: medicationID,
        medicationID: medicationID,
        label: "As Needed",
        amount: 200,
        unit: "mg",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
        hour: 9,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
}

private func insertAsNeededIntakes(
    medicationID: UUID,
    today: Date,
    tomorrow: Date,
    database: any DatabaseWriter
) async throws -> (todayID: UUID, tomorrowID: UUID) {
    let todayID = UUID()
    let tomorrowID = UUID()
    try await database.write { db in
        try insertMedicationIntake(
            in: db, id: todayID,
            medicationID: medicationID, scheduleID: nil,
            amount: 200, unit: "mg",
            timestamp: today.addingTimeInterval(3600),
            origin: "asNeeded"
        )
        try insertMedicationIntake(
            in: db, id: tomorrowID,
            medicationID: medicationID, scheduleID: nil,
            amount: 200, unit: "mg",
            timestamp: tomorrow.addingTimeInterval(3600),
            origin: "asNeeded"
        )
    }
    return (todayID, tomorrowID)
}

private func intakeCount(
    id: UUID,
    database: any DatabaseWriter
) async throws -> Int {
    try await database.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM "sqLiteMedicationIntake"
                WHERE lower("id") = lower(?)
                """,
            arguments: [id.uuidString]
        ) ?? 0
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
