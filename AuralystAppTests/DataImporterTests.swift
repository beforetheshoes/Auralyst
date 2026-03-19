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

        let counts = try database.read { db -> DatabaseRecordCounts in
            DatabaseRecordCounts(
                entries: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteSymptomEntry") ?? 0,
                medications: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedication") ?? 0,
                schedules: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule") ?? 0,
                intakes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationIntake") ?? 0,
                notes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteCollaboratorNote") ?? 0
            )
        }

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

        let counts = try database.read { db -> DatabaseRecordCounts in
            DatabaseRecordCounts(
                entries: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteSymptomEntry") ?? 0,
                medications: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedication") ?? 0,
                schedules: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule") ?? 0,
                intakes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteMedicationIntake") ?? 0,
                notes: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteCollaboratorNote") ?? 0
            )
        }

        #expect(counts.entries == 1)
        #expect(counts.medications == 1)
        #expect(counts.schedules == 1)
        #expect(counts.intakes == 1)
        #expect(counts.notes == 1)
    }

    @MainActor
    @Test("JSON import drops references to missing schedules")
    func jsonImportDropsMissingScheduleReferences() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(for: journal, name: "Schedule Ref", defaultAmount: 1, defaultUnit: "pill")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            origin: "scheduled"
        )
        try insertIntake(intake, database: database)

        let jsonData = try DataExporter.exportJSON(for: journal)
        var object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        object?["schedules"] = []
        if var intakes = object?["intakes"] as? [[String: Any]] {
            intakes = intakes.map { intake in
                var intake = intake
                // Historical exports can persist a synthetic scheduleID == medicationID.
                if let medicationID = intake["medicationID"] as? String {
                    intake["scheduleID"] = medicationID
                }
                return intake
            }
            object?["intakes"] = intakes
        }
        let mutatedData = try JSONSerialization.data(withJSONObject: object ?? [:], options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Auralyst-import-missing-schedule.json")
        try mutatedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try DataImporter.importFile(at: url, replaceExisting: true)

        let importedScheduleID = try database.read { db -> String? in
            try String.fetchOne(
                db,
                sql: "SELECT scheduleID FROM sqLiteMedicationIntake WHERE medicationID = ? LIMIT 1",
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
        let journal = store.createJournal()
        let medication = store.createMedication(for: journal, name: "Strict Ref", defaultAmount: 1, defaultUnit: "pill")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
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
        try insertSchedule(schedule, database: database)
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            origin: "scheduled"
        )
        try insertIntake(intake, database: database)

        let jsonData = try DataExporter.exportJSON(for: journal)
        var object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        object?["schedules"] = []
        let mutatedData = try JSONSerialization.data(withJSONObject: object ?? [:], options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Auralyst-import-missing-nonsynthetic.json")
        try mutatedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ImportError.self) {
            _ = try DataImporter.importFile(at: url, replaceExisting: true)
        }
    }

    @MainActor
    @Test("Import analysis detects fixable missing references")
    func importAnalysisDetectsFixableIssues() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(for: journal, severity: 4)
        let medication = store.createMedication(for: journal, name: "Analyze", defaultAmount: 1, defaultUnit: "pill")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            entryID: entry.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            origin: "scheduled"
        )
        try insertIntake(intake, database: database)
        let note = try store.createCollaboratorNote(
            for: journal,
            entry: entry,
            authorName: "Alex",
            text: "Analyze note"
        )

        let jsonData = try DataExporter.exportJSON(for: journal)
        var object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        object?["schedules"] = []
        object?["entries"] = []
        let mutatedData = try JSONSerialization.data(withJSONObject: object ?? [:], options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Auralyst-import-analysis.json")
        try mutatedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try DataImporter.analyzeFile(at: url)
        #expect(!analysis.hasBlockingIssues)
        #expect(analysis.fixableIssues.contains(where: { $0.kind == .missingScheduleReferences }))
        #expect(analysis.fixableIssues.contains(where: { $0.kind == .missingIntakeEntryReferences }))
        #expect(analysis.fixableIssues.contains(where: { $0.kind == .missingNoteEntryReferences }))
        // Silence unused warnings in case analysis skips some issues.
        #expect(note.id != UUID())
    }

    @MainActor
    @Test("Auto-fix import clears invalid references")
    func autoFixImportClearsInvalidReferences() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let entry = try store.createSymptomEntry(for: journal, severity: 4)
        let medication = store.createMedication(for: journal, name: "AutoFix", defaultAmount: 1, defaultUnit: "pill")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            entryID: entry.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            origin: "scheduled"
        )
        try insertIntake(intake, database: database)
        let note = try store.createCollaboratorNote(
            for: journal,
            entry: entry,
            authorName: "Alex",
            text: "Auto-fix note"
        )

        let jsonData = try DataExporter.exportJSON(for: journal)
        var object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        object?["schedules"] = []
        object?["entries"] = []
        let mutatedData = try JSONSerialization.data(withJSONObject: object ?? [:], options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Auralyst-import-autofix.json")
        try mutatedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try DataImporter.importFile(at: url, replaceExisting: true, resolution: .autoFix)

        let refs = try database.read { db -> (String?, String?, String?) in
            let scheduleID = try String.fetchOne(
                db,
                sql: "SELECT scheduleID FROM sqLiteMedicationIntake WHERE medicationID = ? LIMIT 1",
                arguments: [medication.id.uuidString]
            )
            let entryID = try String.fetchOne(
                db,
                sql: "SELECT entryID FROM sqLiteMedicationIntake WHERE medicationID = ? LIMIT 1",
                arguments: [medication.id.uuidString]
            )
            let noteEntryID = try String.fetchOne(
                db,
                sql: "SELECT entryID FROM sqLiteCollaboratorNote WHERE id = ? LIMIT 1",
                arguments: [note.id.uuidString]
            )
            return (scheduleID, entryID, noteEntryID)
        }

        #expect(refs.0 == nil)
        #expect(refs.1 == nil)
        #expect(refs.2 == nil)
        #expect(intake.id != UUID())
    }

}

// MARK: - Edge Case Tests

extension DataImporterSuite {
    @MainActor
    @Test("Import analysis flags missing medication references as blocking")
    func importAnalysisFlagsMissingMedicationReferences() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(for: journal, name: "Block", defaultAmount: 1, defaultUnit: "pill")

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 8,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try insertSchedule(schedule, database: database)
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            scheduleID: schedule.id,
            amount: 1,
            unit: "pill",
            timestamp: Date(timeIntervalSince1970: 1_726_601_200),
            origin: "scheduled"
        )
        try insertIntake(intake, database: database)

        let jsonData = try DataExporter.exportJSON(for: journal)
        var object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        object?["medications"] = []
        let mutatedData = try JSONSerialization.data(withJSONObject: object ?? [:], options: [.prettyPrinted, .sortedKeys])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Auralyst-import-blocking.json")
        try mutatedData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try DataImporter.analyzeFile(at: url)
        #expect(analysis.hasBlockingIssues)
        #expect(analysis.blockingIssues.contains(where: { $0.kind == .missingMedicationReferences }))

        #expect(throws: ImportError.self) {
            _ = try DataImporter.importFile(at: url, replaceExisting: true)
        }
    }

    @MainActor
    @Test("CSV import supports empty journal exports")
    func csvImportSupportsEmptyJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = store.createJournal()

        let csvData = try DataExporter.exportCSV(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-empty.csv")
        try csvData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(at: url, replaceExisting: true)
        #expect(result.summary.importedEntries == 0)
        #expect(result.summary.importedMedications == 0)
        #expect(result.summary.importedSchedules == 0)
        #expect(result.summary.importedIntakes == 0)
        #expect(result.summary.importedCollaboratorNotes == 0)

        @Dependency(\.defaultDatabase) var database
        let journalCount = try database.read { db -> Int in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteJournal") ?? 0
        }
        #expect(journalCount == 1)
    }
}
