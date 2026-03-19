import Dependencies
import Foundation
@preconcurrency import SQLiteData

extension DataImporter {
    static func importPayload(
        _ payload: ImportPayload,
        replaceExisting: Bool
    ) throws -> ImportResult {
        @Dependency(\.defaultDatabase) var database
        try database.write { db in
            if replaceExisting {
                try deleteAllRecords(in: db)
            }

            let journal = SQLiteJournal(
                id: payload.journal.id,
                createdAt: payload.journal.createdAt
            )
            try SQLiteJournal.insert { journal }.execute(db)

            try insertEntries(payload.entries, in: db)
            try insertMedications(payload.medications, in: db)
            try insertSchedules(payload.schedules, in: db)
            try insertIntakes(payload.intakes, in: db)
            try insertNotes(payload.collaboratorNotes, in: db)
        }

        return ImportResult(
            journalID: payload.journal.id,
            summary: payload.summary
        )
    }

    private static func deleteAllRecords(
        in db: GRDB.Database
    ) throws {
        try SQLiteMedicationSchedule.delete().execute(db)
        try SQLiteMedicationIntake.delete().execute(db)
        try SQLiteCollaboratorNote.delete().execute(db)
        try SQLiteSymptomEntry.delete().execute(db)
        try SQLiteMedication.delete().execute(db)
        try SQLiteJournal.delete().execute(db)
    }

    private static func insertEntries(
        _ entries: [ImportSymptomEntry],
        in db: GRDB.Database
    ) throws {
        for entry in entries {
            let record = SQLiteSymptomEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                journalID: entry.journalID,
                severity: Int16(entry.severity),
                headache: entry.headache.map(Int16.init),
                nausea: entry.nausea.map(Int16.init),
                anxiety: entry.anxiety.map(Int16.init),
                isMenstruating: entry.isMenstruating,
                note: entry.note,
                sentimentLabel: entry.sentimentLabel,
                sentimentScore: entry.sentimentScore
            )
            try SQLiteSymptomEntry.insert { record }.execute(db)
        }
    }

    private static func insertMedications(
        _ medications: [ImportMedication],
        in db: GRDB.Database
    ) throws {
        for medication in medications {
            let record = SQLiteMedication(
                id: medication.id,
                journalID: medication.journalID,
                name: medication.name,
                defaultAmount: medication.defaultAmount,
                defaultUnit: medication.defaultUnit,
                isAsNeeded: medication.isAsNeeded,
                useCase: medication.useCase,
                notes: medication.notes,
                createdAt: medication.createdAt,
                updatedAt: medication.updatedAt
            )
            try SQLiteMedication.insert { record }.execute(db)
        }
    }

    private static func insertSchedules(
        _ schedules: [ImportSchedule],
        in db: GRDB.Database
    ) throws {
        for schedule in schedules {
            let record = SQLiteMedicationSchedule(
                id: schedule.id,
                medicationID: schedule.medicationID,
                label: schedule.label,
                amount: schedule.amount,
                unit: schedule.unit,
                cadence: schedule.cadence,
                interval: Int16(schedule.interval),
                daysOfWeekMask: Int16(schedule.daysOfWeekMask),
                hour: schedule.hour.map(Int16.init),
                minute: schedule.minute.map(Int16.init),
                timeZoneIdentifier: schedule.timeZoneIdentifier,
                startDate: schedule.startDate,
                isActive: schedule.isActive,
                sortOrder: Int16(schedule.sortOrder)
            )
            try SQLiteMedicationSchedule
                .insert { record }.execute(db)
        }
    }

    private static func insertIntakes(
        _ intakes: [ImportIntake],
        in db: GRDB.Database
    ) throws {
        for intake in intakes {
            let record = SQLiteMedicationIntake(
                id: intake.id,
                medicationID: intake.medicationID,
                entryID: intake.entryID,
                scheduleID: intake.scheduleID,
                amount: intake.amount,
                unit: intake.unit,
                timestamp: intake.timestamp,
                scheduledDate: intake.scheduledDate,
                origin: intake.origin,
                notes: intake.notes
            )
            try SQLiteMedicationIntake
                .insert { record }.execute(db)
        }
    }

    private static func insertNotes(
        _ notes: [ImportCollaboratorNote],
        in db: GRDB.Database
    ) throws {
        for note in notes {
            let record = SQLiteCollaboratorNote(
                id: note.id,
                journalID: note.journalID,
                entryID: note.entryID,
                authorName: note.authorName,
                text: note.text,
                timestamp: note.timestamp
            )
            try SQLiteCollaboratorNote
                .insert { record }.execute(db)
        }
    }
}
