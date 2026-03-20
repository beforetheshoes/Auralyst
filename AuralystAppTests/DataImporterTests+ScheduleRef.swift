import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

// MARK: - Schedule Reference Tests

extension DataImporterSuite {
    @MainActor
    @Test("JSON import drops references to missing schedules")
    func jsonImportDropsMissingScheduleReferences() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "Schedule Ref",
            defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeDefaultSchedule(for: medication)
        try insertSchedule(schedule, database: database)
        let intake = makeScheduledIntake(
            for: medication, scheduleID: schedule.id
        )
        try insertIntake(intake, database: database)

        let url = try exportJSONWithMutations(for: journal) { object in
            object["schedules"] = []
            mutateSyntheticScheduleIDs(in: &object)
        }
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try DataImporter.importFile(
            at: url, replaceExisting: true
        )

        let importedScheduleID = try database.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT scheduleID
                    FROM sqLiteMedicationIntake
                    WHERE medicationID = ? LIMIT 1
                    """,
                arguments: [medication.id.uuidString]
            )
        }
        #expect(importedScheduleID == nil)
    }

    @MainActor
    @Test("JSON import fails for non-synthetic missing schedules")
    func jsonImportFailsForNonSyntheticMissingSchedules() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "Strict Ref",
            defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeDefaultSchedule(
            for: medication, hour: 9
        )
        try insertSchedule(schedule, database: database)
        let intake = makeScheduledIntake(
            for: medication, scheduleID: schedule.id
        )
        try insertIntake(intake, database: database)

        let url = try exportJSONWithMutations(for: journal) { object in
            object["schedules"] = []
        }
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImportError.self) {
            _ = try DataImporter.importFile(
                at: url, replaceExisting: true
            )
        }
    }
}

// MARK: - Helpers

private func makeDefaultSchedule(
    for medication: SQLiteMedication,
    label: String = "Morning",
    hour: Int16 = 8
) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: label,
        amount: 1,
        unit: "pill",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: hour,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
}

private func makeScheduledIntake(
    for medication: SQLiteMedication,
    entryID: UUID? = nil,
    scheduleID: UUID
) -> SQLiteMedicationIntake {
    SQLiteMedicationIntake(
        medicationID: medication.id,
        entryID: entryID,
        scheduleID: scheduleID,
        amount: 1,
        unit: "pill",
        timestamp: Date(timeIntervalSince1970: 1_726_601_200),
        origin: "scheduled"
    )
}

private func exportJSONWithMutations(
    for journal: SQLiteJournal,
    fileName: String = UUID().uuidString,
    _ mutate: (inout [String: Any]) throws -> Void
) throws -> URL {
    let jsonData = try DataExporter.exportJSON(for: journal)
    var object = try JSONSerialization.jsonObject(
        with: jsonData
    ) as? [String: Any] ?? [:]
    try mutate(&object)
    let mutatedData = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys]
    )
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Auralyst-\(fileName).json")
    try mutatedData.write(to: url, options: [.atomic])
    return url
}

private func mutateSyntheticScheduleIDs(
    in object: inout [String: Any]
) {
    if var intakes = object["intakes"] as? [[String: Any]] {
        intakes = intakes.map { intake in
            var intake = intake
            if let medID = intake["medicationID"] as? String {
                intake["scheduleID"] = medID
            }
            return intake
        }
        object["intakes"] = intakes
    }
}
