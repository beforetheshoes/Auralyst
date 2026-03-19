import Dependencies
import Foundation
import GRDB
@preconcurrency import SQLiteData

enum ExportPreflightIssueKind: String, Equatable {
    case missingScheduleReferences
    case missingIntakeEntryReferences
    case missingNoteEntryReferences
}

struct ExportPreflightIssue: Equatable {
    let kind: ExportPreflightIssueKind
    let count: Int
    let examples: [String]
}

struct ExportPreflightReport: Equatable {
    let issues: [ExportPreflightIssue]

    var isClean: Bool { issues.isEmpty }
}

enum ExportPreflightChecker {
    static func check(journal: SQLiteJournal) throws -> ExportPreflightReport {
        @Dependency(\.defaultDatabase) var database
        return try database.read { db in
            try check(journal: journal, db: db)
        }
    }

    static func autoFix(journal: SQLiteJournal) throws -> ExportPreflightReport {
        @Dependency(\.defaultDatabase) var database
        return try database.write { db in
            let report = try check(journal: journal, db: db)
            guard !report.isClean else { return report }

            let medicationIDs = try medicationIDs(for: journal, db: db)
            let scheduleIDSet = try scheduleIDs(for: medicationIDs, db: db)
            let entryIDSet = try entryIDs(for: journal, db: db)

            let intakes = try intakes(for: medicationIDs, db: db)
            let invalidScheduleIntakeIDs = intakes.compactMap { intake -> String? in
                guard let scheduleID = intake.scheduleID?.uuidString.lowercased() else { return nil }
                return scheduleIDSet.contains(scheduleID) ? nil : intake.id.uuidString
            }
            let invalidIntakeEntryIDs = intakes.compactMap { intake -> String? in
                guard let entryID = intake.entryID?.uuidString.lowercased() else { return nil }
                return entryIDSet.contains(entryID) ? nil : intake.id.uuidString
            }

            let notes = try collaboratorNotes(for: journal, db: db)
            let invalidNoteEntryIDs = notes.compactMap { note -> String? in
                guard let entryID = note.entryID?.uuidString.lowercased() else { return nil }
                return entryIDSet.contains(entryID) ? nil : note.id.uuidString
            }

            try updateColumnToNull(
                table: "sqLiteMedicationIntake",
                column: "scheduleID",
                ids: invalidScheduleIntakeIDs,
                db: db
            )
            try updateColumnToNull(
                table: "sqLiteMedicationIntake",
                column: "entryID",
                ids: invalidIntakeEntryIDs,
                db: db
            )
            try updateColumnToNull(
                table: "sqLiteCollaboratorNote",
                column: "entryID",
                ids: invalidNoteEntryIDs,
                db: db
            )

            return try check(journal: journal, db: db)
        }
    }
}

private extension ExportPreflightChecker {
    static func check(
        journal: SQLiteJournal, db: Database
    ) throws -> ExportPreflightReport {
        let medicationIDs = try medicationIDs(for: journal, db: db)
        let scheduleIDSet = try scheduleIDs(for: medicationIDs, db: db)
        let entryIDSet = try entryIDs(for: journal, db: db)

        let intakes = try intakes(for: medicationIDs, db: db)
        let notes = try collaboratorNotes(for: journal, db: db)

        let issues = buildIssues(
            intakes: intakes,
            notes: notes,
            scheduleIDSet: scheduleIDSet,
            entryIDSet: entryIDSet
        )

        return ExportPreflightReport(issues: issues)
    }

    static func buildIssues(
        intakes: [SQLiteMedicationIntake],
        notes: [SQLiteCollaboratorNote],
        scheduleIDSet: Set<String>,
        entryIDSet: Set<String>
    ) -> [ExportPreflightIssue] {
        let missingScheduleRefs = intakes.filter { intake in
            guard let sid = intake.scheduleID?.uuidString.lowercased()
            else { return false }
            return !scheduleIDSet.contains(sid)
        }
        let missingIntakeEntryRefs = intakes.filter { intake in
            guard let eid = intake.entryID?.uuidString.lowercased()
            else { return false }
            return !entryIDSet.contains(eid)
        }
        let missingNoteEntryRefs = notes.filter { note in
            guard let eid = note.entryID?.uuidString.lowercased()
            else { return false }
            return !entryIDSet.contains(eid)
        }

        var issues: [ExportPreflightIssue] = []
        if !missingScheduleRefs.isEmpty {
            issues.append(ExportPreflightIssue(
                kind: .missingScheduleReferences,
                count: missingScheduleRefs.count,
                examples: missingScheduleRefs.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.scheduleID?.uuidString ?? "nil")"
                }
            ))
        }
        if !missingIntakeEntryRefs.isEmpty {
            issues.append(ExportPreflightIssue(
                kind: .missingIntakeEntryReferences,
                count: missingIntakeEntryRefs.count,
                examples: missingIntakeEntryRefs.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.entryID?.uuidString ?? "nil")"
                }
            ))
        }
        if !missingNoteEntryRefs.isEmpty {
            issues.append(ExportPreflightIssue(
                kind: .missingNoteEntryReferences,
                count: missingNoteEntryRefs.count,
                examples: missingNoteEntryRefs.prefix(3).map {
                    "\($0.id.uuidString) -> \($0.entryID?.uuidString ?? "nil")"
                }
            ))
        }
        return issues
    }

    static func medicationIDs(for journal: SQLiteJournal, db: Database) throws -> [UUID] {
        try SQLiteMedication
            .select { $0.id }
            .where { $0.journalID.eq(journal.id) }
            .fetchAll(db)
    }

    static func scheduleIDs(for medicationIDs: [UUID], db: Database) throws -> Set<String> {
        guard !medicationIDs.isEmpty else { return [] }
        let schedules = try SQLiteMedicationSchedule
            .select { $0.id }
            .where { $0.medicationID.in(medicationIDs) }
            .fetchAll(db)
        return Set(schedules.map { $0.uuidString.lowercased() })
    }

    static func entryIDs(for journal: SQLiteJournal, db: Database) throws -> Set<String> {
        let entries = try SQLiteSymptomEntry
            .select { $0.id }
            .where { $0.journalID.eq(journal.id) }
            .fetchAll(db)
        return Set(entries.map { $0.uuidString.lowercased() })
    }

    static func intakes(for medicationIDs: [UUID], db: Database) throws -> [SQLiteMedicationIntake] {
        guard !medicationIDs.isEmpty else { return [] }
        return try SQLiteMedicationIntake
            .where { $0.medicationID.in(medicationIDs) }
            .fetchAll(db)
    }

    static func collaboratorNotes(for journal: SQLiteJournal, db: Database) throws -> [SQLiteCollaboratorNote] {
        try SQLiteCollaboratorNote
            .where { $0.journalID.eq(journal.id) }
            .fetchAll(db)
    }

    static func updateColumnToNull(
        table: String,
        column: String,
        ids: [String],
        db: Database
    ) throws {
        guard !ids.isEmpty else { return }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "UPDATE \(table) SET \(column) = NULL WHERE lower(id) IN (\(placeholders))"
        let args = StatementArguments(ids.map { $0.lowercased() })
        try db.execute(sql: sql, arguments: args)
    }
}
