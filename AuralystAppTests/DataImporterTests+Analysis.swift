import Foundation
import Testing
import Dependencies
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

// MARK: - Analysis & Auto-Fix Tests

extension DataImporterSuite {
    @MainActor
    @Test("Import analysis detects fixable missing references")
    func importAnalysisDetectsFixableIssues() throws {
        try prepareTestDependencies()

        let fx = try createJournalWithLinkedRecords(
            name: "Analyze", noteName: "Analyze note"
        )

        let url = try exportAndMutateJSON(
            for: fx.journal
        ) { obj in
            obj["schedules"] = []
            obj["entries"] = []
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try DataImporter.analyzeFile(at: url)
        #expect(!analysis.hasBlockingIssues)
        #expect(analysis.fixableIssues.contains(where: {
            $0.kind == .missingScheduleReferences
        }))
        #expect(analysis.fixableIssues.contains(where: {
            $0.kind == .missingIntakeEntryReferences
        }))
        #expect(analysis.fixableIssues.contains(where: {
            $0.kind == .missingNoteEntryReferences
        }))
        // Silence unused warnings
        #expect(fx.entry.id != UUID())
        #expect(fx.medication.id != UUID())
    }

    @MainActor
    @Test("Auto-fix import clears invalid references")
    func autoFixImportClearsInvalidReferences() throws {
        try prepareTestDependencies()

        let fx = try createJournalWithLinkedRecords(
            name: "AutoFix", noteName: "Auto-fix note"
        )

        let url = try exportAndMutateJSON(
            for: fx.journal
        ) { obj in
            obj["schedules"] = []
            obj["entries"] = []
        }
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try DataImporter.importFile(
            at: url, replaceExisting: true, resolution: .autoFix
        )

        @Dependency(\.defaultDatabase) var database
        let refs = try fetchImportedRefs(
            database: database,
            medicationID: fx.medication.id,
            noteID: fx.note.id
        )

        #expect(refs.scheduleID == nil)
        #expect(refs.entryID == nil)
        #expect(refs.noteEntryID == nil)
    }
}

// MARK: - Edge Case Tests

extension DataImporterSuite {
    @MainActor
    @Test("Import analysis flags missing medication refs as blocking")
    func importAnalysisFlagsMissingMedicationRefs() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let medication = store.createMedication(
            for: journal, name: "Block",
            defaultAmount: 1, defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = makeAnalysisSchedule(for: medication)
        try insertSchedule(schedule, database: database)
        let intake = makeAnalysisIntake(
            for: medication, scheduleID: schedule.id
        )
        try insertIntake(intake, database: database)

        let url = try exportAndMutateJSON(for: journal) { obj in
            obj["medications"] = []
        }
        defer { try? FileManager.default.removeItem(at: url) }

        let analysis = try DataImporter.analyzeFile(at: url)
        #expect(analysis.hasBlockingIssues)
        #expect(analysis.blockingIssues.contains(where: {
            $0.kind == .missingMedicationReferences
        }))

        #expect(throws: ImportError.self) {
            _ = try DataImporter.importFile(
                at: url, replaceExisting: true
            )
        }
    }

    @MainActor
    @Test("CSV import supports empty journal exports")
    func csvImportSupportsEmptyJournal() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()

        let csvData = try DataExporter.exportCSV(for: journal)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Auralyst-import-empty.csv")
        try csvData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(
            at: url, replaceExisting: true
        )
        #expect(result.summary.importedEntries == 0)
        #expect(result.summary.importedMedications == 0)
        #expect(result.summary.importedSchedules == 0)
        #expect(result.summary.importedIntakes == 0)
        #expect(result.summary.importedCollaboratorNotes == 0)

        @Dependency(\.defaultDatabase) var database
        let journalCount = try database.read { db -> Int in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteJournal"
            ) ?? 0
        }
        #expect(journalCount == 1)
    }
}

// MARK: - Shared Helpers

private struct ImportedRefs {
    let scheduleID: String?
    let entryID: String?
    let noteEntryID: String?
}

private struct LinkedRecordsFixture {
    let journal: SQLiteJournal
    let medication: SQLiteMedication
    let entry: SQLiteSymptomEntry
    let note: SQLiteCollaboratorNote
}

@MainActor
private func createJournalWithLinkedRecords(
    name: String,
    noteName: String
) throws -> LinkedRecordsFixture {
    let store = DataStore()
    let journal = try store.createJournal()
    let entry = try store.createSymptomEntry(
        for: journal, severity: 4
    )
    let medication = store.createMedication(
        for: journal, name: name,
        defaultAmount: 1, defaultUnit: "pill"
    )

    @Dependency(\.defaultDatabase) var database
    let schedule = makeAnalysisSchedule(for: medication)
    try insertSchedule(schedule, database: database)
    let intake = makeAnalysisIntake(
        for: medication,
        entryID: entry.id,
        scheduleID: schedule.id
    )
    try insertIntake(intake, database: database)
    let note = try store.createCollaboratorNote(
        for: journal,
        entry: entry,
        authorName: "Alex",
        text: noteName
    )

    return LinkedRecordsFixture(
        journal: journal, medication: medication,
        entry: entry, note: note
    )
}

private func makeAnalysisSchedule(
    for medication: SQLiteMedication
) -> SQLiteMedicationSchedule {
    SQLiteMedicationSchedule(
        medicationID: medication.id,
        label: "Morning",
        amount: 1,
        unit: "pill",
        cadence: "daily",
        interval: 1,
        daysOfWeekMask: MedicationWeekday.mask(
            for: MedicationWeekday.allCases
        ),
        hour: 8,
        minute: 0,
        isActive: true,
        sortOrder: 0
    )
}

private func makeAnalysisIntake(
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

private func exportAndMutateJSON(
    for journal: SQLiteJournal,
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
    let name = UUID().uuidString
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Auralyst-\(name).json")
    try mutatedData.write(to: url, options: [.atomic])
    return url
}

private func fetchImportedRefs(
    database: any DatabaseReader,
    medicationID: UUID,
    noteID: UUID
) throws -> ImportedRefs {
    try database.read { db in
        let scheduleID = try String.fetchOne(
            db,
            sql: """
                SELECT scheduleID
                FROM sqLiteMedicationIntake
                WHERE medicationID = ? LIMIT 1
                """,
            arguments: [medicationID.uuidString]
        )
        let entryID = try String.fetchOne(
            db,
            sql: """
                SELECT entryID
                FROM sqLiteMedicationIntake
                WHERE medicationID = ? LIMIT 1
                """,
            arguments: [medicationID.uuidString]
        )
        let noteEntryID = try String.fetchOne(
            db,
            sql: """
                SELECT entryID
                FROM sqLiteCollaboratorNote
                WHERE id = ? LIMIT 1
                """,
            arguments: [noteID.uuidString]
        )
        return ImportedRefs(
            scheduleID: scheduleID,
            entryID: entryID,
            noteEntryID: noteEntryID
        )
    }
}
