import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Data Importer", .serialized)
struct DataImporterSuite {
    @MainActor
    @Test("JSON import restores exported data")
    func jsonImportRestoresData() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
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
        let medication = store.createMedication(for: journal, name: "Ibuprofen", defaultAmount: 200, defaultUnit: "mg")
        _ = try store.createMedicationIntake(for: medication, amount: 1, unit: "tablet")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "tablet",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: [.monday, .wednesday]),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let jsonData = try DataExporter.exportJSON(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-test.json")
        try jsonData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(at: url, replaceExisting: true)
        #expect(result.summary.importedEntries == 1)
        #expect(result.summary.importedMedications == 1)
        #expect(result.summary.importedSchedules == 1)
        #expect(result.summary.importedIntakes == 1)
        #expect(result.summary.importedCollaboratorNotes == 1)

        let counts = try database.read { db -> (Int, Int, Int, Int, Int) in
            let entries = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteSymptomEntry") ?? 0
            let medications = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedication") ?? 0
            let schedules = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule") ?? 0
            let intakes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationIntake") ?? 0
            let notes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteCollaboratorNote") ?? 0
            return (entries, medications, schedules, intakes, notes)
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 1)
        #expect(counts.3 == 1)
        #expect(counts.4 == 1)
    }

    @MainActor
    @Test("CSV import restores exported data")
    func csvImportRestoresData() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
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
        let medication = store.createMedication(for: journal, name: "Vitamin D", defaultAmount: 1, defaultUnit: "capsule")
        _ = try store.createMedicationIntake(for: medication, amount: 1, unit: "capsule")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Evening",
            amount: 1,
            unit: "capsule",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 20,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)

        let csvData = try DataExporter.exportCSV(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-test.csv")
        try csvData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(at: url, replaceExisting: true)
        #expect(result.summary.importedEntries == 1)
        #expect(result.summary.importedMedications == 1)
        #expect(result.summary.importedSchedules == 1)
        #expect(result.summary.importedIntakes == 1)
        #expect(result.summary.importedCollaboratorNotes == 1)

        let counts = try database.read { db -> (Int, Int, Int, Int, Int) in
            let entries = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteSymptomEntry") ?? 0
            let medications = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedication") ?? 0
            let schedules = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule") ?? 0
            let intakes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationIntake") ?? 0
            let notes = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteCollaboratorNote") ?? 0
            return (entries, medications, schedules, intakes, notes)
        }

        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 1)
        #expect(counts.3 == 1)
        #expect(counts.4 == 1)
    }
}
