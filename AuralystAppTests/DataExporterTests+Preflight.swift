import Foundation
import Testing
import Dependencies
@preconcurrency import SQLiteData
@testable import AuralystApp

// MARK: - Preflight & Sanitization Tests

extension DataExporterSuite {
    @MainActor
    @Test("Export preflight detects and fixes invalid refs")
    func exportPreflightFixesInvalidReferences() throws {
        try prepareTestDependencies()

        let fx = try createPreflightFixture()

        @Dependency(\.defaultDatabase) var database
        try corruptReferences(
            database: database,
            intakeID: fx.intake.id,
            noteID: fx.note.id
        )

        let report = try ExportPreflightChecker.check(
            journal: fx.journal
        )
        assertPreflightIssues(report)

        let fixedReport = try ExportPreflightChecker.autoFix(
            journal: fx.journal
        )
        #expect(fixedReport.isClean)

        let refs = try fetchPreflightRefs(
            database: database,
            intakeID: fx.intake.id,
            noteID: fx.note.id
        )

        #expect(refs.scheduleID == nil)
        #expect(refs.entryID == nil)
        #expect(refs.noteEntryID == nil)
        // Silence unused warnings
        #expect(fx.entry.id != UUID())
        #expect(fx.schedule.id != UUID())
        #expect(fx.medication.id != UUID())
    }

    @MainActor
    @Test("Exporter sanitizes invalid references in payloads")
    func exporterSanitizesInvalidReferences() throws {
        try prepareTestDependencies()

        let fx = try createPreflightFixture()

        @Dependency(\.defaultDatabase) var database
        try corruptReferences(
            database: database,
            intakeID: fx.intake.id,
            noteID: fx.note.id
        )

        let jsonData = try DataExporter.exportJSON(
            for: fx.journal
        )
        let object = try JSONSerialization.jsonObject(
            with: jsonData
        ) as? [String: Any]
        let intakes = object?["intakes"]
            as? [[String: Any]]
        let notes = object?["collaboratorNotes"]
            as? [[String: Any]]

        let intakeRow = intakes?.first {
            ($0["id"] as? String) == fx.intake.id.uuidString
        }
        let noteRow = notes?.first {
            ($0["id"] as? String) == fx.note.id.uuidString
        }

        #expect(isNullValue(intakeRow?["scheduleID"]))
        #expect(isNullValue(intakeRow?["entryID"]))
        #expect(isNullValue(noteRow?["entryID"]))
    }

    @MainActor
    @Test("Preflight auto-fix enables strict round trip")
    func preflightAutoFixRoundTripsStrictImport() throws {
        try prepareTestDependencies()

        let fx = try createPreflightFixture()

        @Dependency(\.defaultDatabase) var database
        try corruptReferences(
            database: database,
            intakeID: fx.intake.id,
            noteID: fx.note.id
        )

        let fixedReport = try ExportPreflightChecker.autoFix(
            journal: fx.journal
        )
        #expect(fixedReport.isClean)

        let jsonData = try DataExporter.exportJSON(
            for: fx.journal
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Auralyst-preflight-roundtrip.json"
            )
        try jsonData.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataImporter.importFile(
            at: url, replaceExisting: true
        )
        #expect(result.summary.importedEntries == 1)
        #expect(result.summary.importedMedications == 1)
        #expect(result.summary.importedSchedules == 1)
        #expect(result.summary.importedIntakes == 1)
        #expect(result.summary.importedCollaboratorNotes == 1)
    }
}

// MARK: - Fixture and Helpers

private struct PreflightFixture {
    let journal: SQLiteJournal
    let entry: SQLiteSymptomEntry
    let medication: SQLiteMedication
    let schedule: SQLiteMedicationSchedule
    let intake: SQLiteMedicationIntake
    let note: SQLiteCollaboratorNote
}

@MainActor
private func createPreflightFixture(
) throws -> PreflightFixture {
    let store = DataStore()
    let journal = try store.createJournal()
    let entry = try store.createSymptomEntry(
        for: journal, severity: 5
    )
    let medication = store.createMedication(
        for: journal, name: "Preflight",
        defaultAmount: 1, defaultUnit: "pill"
    )

    @Dependency(\.defaultDatabase) var database
    let schedule = SQLiteMedicationSchedule(
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
    try insertSchedule(schedule, database: database)

    let intake = SQLiteMedicationIntake(
        medicationID: medication.id,
        entryID: entry.id,
        scheduleID: schedule.id,
        amount: 1,
        unit: "pill",
        timestamp: Date(
            timeIntervalSince1970: 1_726_601_200
        ),
        origin: "scheduled"
    )
    try insertIntake(intake, database: database)
    let note = try store.createCollaboratorNote(
        for: journal,
        entry: entry,
        authorName: "Alex",
        text: "Linked note"
    )

    return PreflightFixture(
        journal: journal, entry: entry,
        medication: medication, schedule: schedule,
        intake: intake, note: note
    )
}

private func corruptReferences(
    database: any DatabaseWriter,
    intakeID: UUID,
    noteID: UUID
) throws {
    let invalidEntryID = UUID()
    let invalidScheduleID = UUID()
    // PRAGMA foreign_keys is a no-op inside a transaction, so
    // use writeWithoutTransaction to toggle it around the writes.
    try database.writeWithoutTransaction { db in
        try db.execute(sql: "PRAGMA foreign_keys = OFF")
        try db.inTransaction(.deferred) {
            try db.execute(
                sql: """
                    UPDATE sqLiteMedicationIntake
                    SET scheduleID = ?, entryID = ?
                    WHERE lower(id) = lower(?)
                    """,
                arguments: [
                    invalidScheduleID.uuidString,
                    invalidEntryID.uuidString,
                    intakeID.uuidString
                ]
            )
            try db.execute(
                sql: """
                    UPDATE sqLiteCollaboratorNote
                    SET entryID = ?
                    WHERE lower(id) = lower(?)
                    """,
                arguments: [
                    invalidEntryID.uuidString,
                    noteID.uuidString
                ]
            )
            return .commit
        }
        try db.execute(sql: "PRAGMA foreign_keys = ON")
    }
}

private struct PreflightRefs {
    let scheduleID: String?
    let entryID: String?
    let noteEntryID: String?
}

private func fetchPreflightRefs(
    database: any DatabaseReader,
    intakeID: UUID,
    noteID: UUID
) throws -> PreflightRefs {
    try database.read { db in
        let scheduleID = try String.fetchOne(
            db,
            sql: """
                SELECT scheduleID
                FROM sqLiteMedicationIntake
                WHERE lower(id) = lower(?) LIMIT 1
                """,
            arguments: [intakeID.uuidString]
        )
        let entryID = try String.fetchOne(
            db,
            sql: """
                SELECT entryID
                FROM sqLiteMedicationIntake
                WHERE lower(id) = lower(?) LIMIT 1
                """,
            arguments: [intakeID.uuidString]
        )
        let noteEntryID = try String.fetchOne(
            db,
            sql: """
                SELECT entryID
                FROM sqLiteCollaboratorNote
                WHERE lower(id) = lower(?) LIMIT 1
                """,
            arguments: [noteID.uuidString]
        )
        return PreflightRefs(
            scheduleID: scheduleID,
            entryID: entryID,
            noteEntryID: noteEntryID
        )
    }
}

private func assertPreflightIssues(
    _ report: ExportPreflightReport
) {
    #expect(report.issues.contains(where: {
        $0.kind == .missingScheduleReferences
    }))
    #expect(report.issues.contains(where: {
        $0.kind == .missingIntakeEntryReferences
    }))
    #expect(report.issues.contains(where: {
        $0.kind == .missingNoteEntryReferences
    }))
}

private func isNullValue(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}
