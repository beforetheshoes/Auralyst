import Foundation
@preconcurrency import SQLiteData
import Dependencies

struct DataExporter {
    static func exportCSV(
        for journal: SQLiteJournal
    ) throws -> Data {
        let dataset = try fetchDataset(for: journal)
        let isoFormat = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true,
            timeZone: .current
        )

        var lines: [String] = []
        appendJournalCSV(
            journal: journal, summary: dataset.summary,
            isoFormat: isoFormat, lines: &lines
        )
        appendEntriesCSV(
            dataset.entries, journalID: journal.id,
            isoFormat: isoFormat, lines: &lines
        )
        appendNotesCSV(
            dataset.collaboratorNotes,
            isoFormat: isoFormat, lines: &lines
        )
        appendMedicationsCSV(
            dataset.medications, journalID: journal.id,
            isoFormat: isoFormat, lines: &lines
        )
        appendIntakesCSV(
            dataset.intakes,
            isoFormat: isoFormat, lines: &lines
        )
        appendSchedulesCSV(
            dataset.schedules,
            isoFormat: isoFormat, lines: &lines
        )

        let csvString = lines.joined(separator: "\n") + "\n"
        return Data(csvString.utf8)
    }

    static func exportJSON(
        for journal: SQLiteJournal
    ) throws -> Data {
        let dataset = try fetchDataset(for: journal)
        let payload = ExportPayload(
            journal: journal, dataset: dataset
        )
        let isoFormat = Date.ISO8601FormatStyle(
            includingFractionalSeconds: true,
            timeZone: .current
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormat.format(date))
        }

        return try encoder.encode(payload)
    }

    static func exportSummary(
        for journal: SQLiteJournal
    ) throws -> DataExportSummary {
        try fetchDataset(for: journal).summary
    }
}

// MARK: - Data Fetching

extension DataExporter {
    static func fetchDataset(
        for journal: SQLiteJournal
    ) throws -> ExportDataset {
        @Dependency(\.defaultDatabase) var database
        return try database.read { db in
            let entries = try SQLiteSymptomEntry
                .where { $0.journalID.eq(journal.id) }
                .order { $0.timestamp.desc() }
                .fetchAll(db)

            let collaboratorNotes = try SQLiteCollaboratorNote
                .where { $0.journalID.eq(journal.id) }
                .order { $0.timestamp.desc() }
                .fetchAll(db)

            let medications = try SQLiteMedication
                .where { $0.journalID.eq(journal.id) }
                .order { $0.name.asc() }
                .fetchAll(db)

            let intakes = try SQLiteMedicationIntake
                .where {
                    $0.medicationID.in(
                        SQLiteMedication
                            .select { $0.id }
                            .where { $0.journalID.eq(journal.id) }
                    )
                }
                .order { $0.timestamp.desc() }
                .fetchAll(db)

            let schedules = try SQLiteMedicationSchedule
                .where {
                    $0.medicationID.in(
                        SQLiteMedication
                            .select { $0.id }
                            .where { $0.journalID.eq(journal.id) }
                    )
                }
                .order { $0.sortOrder.asc() }
                .fetchAll(db)

            let dataset = ExportDataset(
                entries: entries,
                collaboratorNotes: collaboratorNotes,
                medications: medications,
                intakes: intakes,
                schedules: schedules
            )
            return sanitize(dataset)
        }
    }

    static func sanitize(
        _ dataset: ExportDataset
    ) -> ExportDataset {
        let scheduleIDs = Set(dataset.schedules.map { $0.id })
        let entryIDs = Set(dataset.entries.map { $0.id })

        let sanitizedIntakes = dataset.intakes.map { intake in
            var scheduleID = intake.scheduleID
            var entryID = intake.entryID
            if let ref = scheduleID, !scheduleIDs.contains(ref) {
                scheduleID = nil
            }
            if let ref = entryID, !entryIDs.contains(ref) {
                entryID = nil
            }
            guard scheduleID != intake.scheduleID
                || entryID != intake.entryID else {
                return intake
            }
            return SQLiteMedicationIntake(
                id: intake.id,
                medicationID: intake.medicationID,
                entryID: entryID,
                scheduleID: scheduleID,
                amount: intake.amount,
                unit: intake.unit,
                timestamp: intake.timestamp,
                scheduledDate: intake.scheduledDate,
                origin: intake.origin,
                notes: intake.notes
            )
        }

        let sanitizedNotes = dataset.collaboratorNotes.map { note in
            guard let eID = note.entryID,
                  !entryIDs.contains(eID) else { return note }
            return SQLiteCollaboratorNote(
                id: note.id,
                journalID: note.journalID,
                entryID: nil,
                authorName: note.authorName,
                text: note.text,
                timestamp: note.timestamp
            )
        }

        return ExportDataset(
            entries: dataset.entries,
            collaboratorNotes: sanitizedNotes,
            medications: dataset.medications,
            intakes: sanitizedIntakes,
            schedules: dataset.schedules
        )
    }

    static func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let needsQuotes = value.contains(",")
            || value.contains("\n") || value.contains("\"")
        let escaped = value.replacingOccurrences(
            of: "\"", with: "\"\""
        )
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
