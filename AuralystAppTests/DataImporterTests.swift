import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

private struct DatabaseRecordCounts {
    let entries: Int
    let medications: Int
    let schedules: Int
    let intakes: Int
    let notes: Int
}

@Suite("Data Importer", .serialized)
struct DataImporterSuite {
    @MainActor
    @Test("JSON import restores exported data")
    func jsonImportRestoresData() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 3,
            note: "Import test"
        )
        _ = try store.createCollaboratorNote(
            for: journal,
            authorName: "Sam",
            text: "Note"
        )
        let medication = store.createMedication(
            for: journal, name: "Ibuprofen",
            defaultAmount: 200, defaultUnit: "mg"
        )
        _ = try store.createMedicationIntake(
            for: medication, amount: 1, unit: "tablet"
        )

        @Dependency(\.defaultDatabase) var database
        try insertMorningSchedule(
            for: medication, database: database,
            daysOfWeekMask: MedicationWeekday.mask(
                for: [.monday, .wednesday]
            )
        )

        let jsonData = try DataExporter.exportJSON(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-test.json")
        try jsonData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(
            at: url, replaceExisting: true
        )
        assertImportCounts(result.summary, expected: 1)

        let counts = try fetchRecordCounts(database: database)
        #expect(counts.entries == 1)
        #expect(counts.medications == 1)
        #expect(counts.schedules == 1)
        #expect(counts.intakes == 1)
        #expect(counts.notes == 1)
    }

    @MainActor
    @Test("CSV import restores exported data")
    func csvImportRestoresData() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        _ = try store.createSymptomEntry(
            for: journal,
            severity: 7,
            note: "CSV import"
        )
        _ = try store.createCollaboratorNote(
            for: journal,
            authorName: "Alex",
            text: "CSV note"
        )
        let medication = store.createMedication(
            for: journal, name: "Vitamin D",
            defaultAmount: 1, defaultUnit: "capsule"
        )
        _ = try store.createMedicationIntake(
            for: medication, amount: 1, unit: "capsule"
        )

        @Dependency(\.defaultDatabase) var database
        try insertMorningSchedule(
            for: medication, database: database,
            label: "Evening", hour: 20, unit: "capsule"
        )

        let csvData = try DataExporter.exportCSV(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-test.csv")
        try csvData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(
            at: url, replaceExisting: true
        )
        assertImportCounts(result.summary, expected: 1)

        let counts = try fetchRecordCounts(database: database)
        #expect(counts.entries == 1)
        #expect(counts.medications == 1)
        #expect(counts.schedules == 1)
        #expect(counts.intakes == 1)
        #expect(counts.notes == 1)
    }
}

// MARK: - Helpers

private func insertMorningSchedule(
    for medication: SQLiteMedication,
    database: any DatabaseWriter,
    label: String = "Morning",
    hour: Int16 = 8,
    unit: String = "tablet",
    daysOfWeekMask: Int16? = nil
) throws {
    let mask = daysOfWeekMask ?? MedicationWeekday.mask(
        for: MedicationWeekday.allCases
    )
    let schedule = SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: label,
        amount: 1,
        unit: unit,
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: mask,
        hour: hour,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
    try insertSchedule(schedule, database: database)
}

private func fetchRecordCounts(
    database: any DatabaseReader
) throws -> DatabaseRecordCounts {
    try database.read { db -> DatabaseRecordCounts in
        DatabaseRecordCounts(
            entries: try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM sqLiteSymptomEntry"
            ) ?? 0,
            medications: try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM sqLiteMedication"
            ) ?? 0,
            schedules: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule"
            ) ?? 0,
            intakes: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteMedicationIntake"
            ) ?? 0,
            notes: try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteCollaboratorNote"
            ) ?? 0
        )
    }
}

private func assertImportCounts(
    _ summary: ImportSummary,
    expected: Int
) {
    #expect(summary.importedEntries == expected)
    #expect(summary.importedMedications == expected)
    #expect(summary.importedSchedules == expected)
    #expect(summary.importedIntakes == expected)
    #expect(summary.importedCollaboratorNotes == expected)
}
