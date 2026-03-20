import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

extension MedicationQuickLogLoaderSuite {
    @MainActor
    @Test("Intake at exact start of day is included (>= start)")
    func intakeAtStartOfDayIsIncluded() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "BoundaryMed", defaultAmount: 1, defaultUnit: "pill"
        )

        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let dayStart = Calendar.current.startOfDay(for: baseDate)

        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: 1,
            unit: "pill",
            timestamp: dayStart,
            origin: "asNeeded"
        )
        try insertIntake(intake, database: database)

        let loader = MedicationQuickLogLoader(database: database)
        let snapshot = try loader.load(journalID: journal.id, on: baseDate)

        #expect(snapshot.takenByScheduleID[medication.id] != nil)
    }

    @MainActor
    @Test("Intake one second before start of day is excluded (>= start)")
    func intakeJustBeforeStartIsExcluded() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "BoundaryMed", defaultAmount: 1, defaultUnit: "pill"
        )

        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let dayStart = Calendar.current.startOfDay(for: baseDate)
        let justBefore = dayStart.addingTimeInterval(-1)

        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: 1,
            unit: "pill",
            timestamp: justBefore,
            origin: "asNeeded"
        )
        try insertIntake(intake, database: database)

        let loader = MedicationQuickLogLoader(database: database)
        let snapshot = try loader.load(journalID: journal.id, on: baseDate)

        #expect(snapshot.takenByScheduleID[medication.id] == nil)
    }

    @MainActor
    @Test("Intake at exact start of next day is excluded (< end)")
    func intakeAtEndOfDayIsExcluded() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "BoundaryMed", defaultAmount: 1, defaultUnit: "pill"
        )

        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let dayStart = Calendar.current.startOfDay(for: baseDate)
        let nextDayStart = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: 1,
            unit: "pill",
            timestamp: nextDayStart,
            origin: "asNeeded"
        )
        try insertIntake(intake, database: database)

        let loader = MedicationQuickLogLoader(database: database)
        let snapshot = try loader.load(journalID: journal.id, on: baseDate)

        #expect(snapshot.takenByScheduleID[medication.id] == nil)
    }

    @MainActor
    @Test("Intake one second before end of day is included (< end)")
    func intakeJustBeforeEndIsIncluded() throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "BoundaryMed", defaultAmount: 1, defaultUnit: "pill"
        )

        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let dayStart = Calendar.current.startOfDay(for: baseDate)
        let justBeforeEnd = dayStart.addingTimeInterval(86399)

        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: 1,
            unit: "pill",
            timestamp: justBeforeEnd,
            origin: "asNeeded"
        )
        try insertIntake(intake, database: database)

        let loader = MedicationQuickLogLoader(database: database)
        let snapshot = try loader.load(journalID: journal.id, on: baseDate)

        #expect(snapshot.takenByScheduleID[medication.id] != nil)
    }
}
