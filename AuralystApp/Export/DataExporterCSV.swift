import Foundation
@preconcurrency import SQLiteData

// MARK: - CSV Section Writers

extension DataExporter {
    static func appendJournalCSV(
        journal: SQLiteJournal,
        summary: DataExportSummary,
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("journal")
        lines.append("id,createdAt")
        lines.append(
            "\(journal.id.uuidString),\(isoFormat.format(journal.createdAt))"
        )
        lines.append("")
        lines.append("summary")
        lines.append("metric,value")
        lines.append("exportedEntries,\(summary.exportedEntries)")
        lines.append(
            "exportedMedications,\(summary.exportedMedications)"
        )
        lines.append(
            "exportedSchedules,\(summary.exportedSchedules)"
        )
        lines.append("exportedIntakes,\(summary.exportedIntakes)")
        lines.append(
            "exportedCollaboratorNotes,\(summary.exportedCollaboratorNotes)"
        )
    }

    static func appendEntriesCSV(
        _ entries: [SQLiteSymptomEntry],
        journalID: UUID,
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("symptom_entries")
        let header = [
            "id", "journal_id", "timestamp", "severity",
            "headache", "nausea", "anxiety", "isMenstruating",
            "note", "sentimentLabel", "sentimentScore"
        ].joined(separator: ",")
        lines.append(header)
        for entry in entries {
            var vals: [String] = []
            vals.append(entry.id.uuidString)
            vals.append(journalID.uuidString)
            vals.append(isoFormat.format(entry.timestamp))
            vals.append(String(entry.severity))
            vals.append(entry.headache.map { String($0) } ?? "")
            vals.append(entry.nausea.map { String($0) } ?? "")
            vals.append(entry.anxiety.map { String($0) } ?? "")
            vals.append(
                entry.isMenstruating.map { $0 ? "true" : "false" } ?? ""
            )
            vals.append(csvEscape(entry.note))
            vals.append(csvEscape(entry.sentimentLabel))
            vals.append(
                entry.sentimentScore.map { String($0) } ?? ""
            )
            lines.append(vals.joined(separator: ","))
        }
    }

    static func appendNotesCSV(
        _ notes: [SQLiteCollaboratorNote],
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("collaborator_notes")
        lines.append(
            "id,journal_id,entry_id,author_name,text,timestamp"
        )
        for note in notes {
            var vals: [String] = []
            vals.append(note.id.uuidString)
            vals.append(note.journalID.uuidString)
            vals.append(note.entryID?.uuidString ?? "")
            vals.append(csvEscape(note.authorName))
            vals.append(csvEscape(note.text))
            vals.append(isoFormat.format(note.timestamp))
            lines.append(vals.joined(separator: ","))
        }
    }

    static func appendMedicationsCSV(
        _ medications: [SQLiteMedication],
        journalID: UUID,
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("medications")
        let header = [
            "id", "journal_id", "name", "defaultAmount",
            "defaultUnit", "isAsNeeded", "useCase", "notes",
            "createdAt", "updatedAt"
        ].joined(separator: ",")
        lines.append(header)
        for med in medications {
            var vals: [String] = []
            vals.append(med.id.uuidString)
            vals.append(journalID.uuidString)
            vals.append(csvEscape(med.name))
            vals.append(med.defaultAmount.map { String($0) } ?? "")
            vals.append(csvEscape(med.defaultUnit))
            vals.append(
                med.isAsNeeded.map { $0 ? "true" : "false" } ?? ""
            )
            vals.append(csvEscape(med.useCase))
            vals.append(csvEscape(med.notes))
            vals.append(isoFormat.format(med.createdAt))
            vals.append(isoFormat.format(med.updatedAt))
            lines.append(vals.joined(separator: ","))
        }
    }

    static func appendIntakesCSV(
        _ intakes: [SQLiteMedicationIntake],
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("medication_intakes")
        let header = [
            "id", "medication_id", "entry_id", "schedule_id",
            "amount", "unit", "timestamp", "scheduledDate",
            "origin", "notes"
        ].joined(separator: ",")
        lines.append(header)
        for intake in intakes {
            var vals: [String] = []
            vals.append(intake.id.uuidString)
            vals.append(intake.medicationID.uuidString)
            vals.append(intake.entryID?.uuidString ?? "")
            vals.append(intake.scheduleID?.uuidString ?? "")
            vals.append(intake.amount.map { String($0) } ?? "")
            vals.append(csvEscape(intake.unit))
            vals.append(isoFormat.format(intake.timestamp))
            vals.append(
                intake.scheduledDate.map { isoFormat.format($0) } ?? ""
            )
            vals.append(csvEscape(intake.origin))
            vals.append(csvEscape(intake.notes))
            lines.append(vals.joined(separator: ","))
        }
    }

    static func appendSchedulesCSV(
        _ schedules: [SQLiteMedicationSchedule],
        isoFormat: Date.ISO8601FormatStyle,
        lines: inout [String]
    ) {
        lines.append("")
        lines.append("medication_schedules")
        let header = [
            "id", "medication_id", "label", "amount", "unit",
            "cadence", "interval", "daysOfWeekMask", "hour",
            "minute", "timeZoneIdentifier", "startDate",
            "isActive", "sortOrder"
        ].joined(separator: ",")
        lines.append(header)
        for sched in schedules {
            var vals: [String] = []
            vals.append(sched.id.uuidString)
            vals.append(sched.medicationID.uuidString)
            vals.append(csvEscape(sched.label))
            vals.append(sched.amount.map { String($0) } ?? "")
            vals.append(csvEscape(sched.unit))
            vals.append(csvEscape(sched.cadence))
            vals.append(String(sched.interval))
            vals.append(String(sched.daysOfWeekMask))
            vals.append(sched.hour.map { String($0) } ?? "")
            vals.append(sched.minute.map { String($0) } ?? "")
            vals.append(csvEscape(sched.timeZoneIdentifier))
            vals.append(
                sched.startDate.map { isoFormat.format($0) } ?? ""
            )
            vals.append(
                sched.isActive.map { $0 ? "true" : "false" } ?? ""
            )
            vals.append(String(sched.sortOrder))
            lines.append(vals.joined(separator: ","))
        }
    }
}
