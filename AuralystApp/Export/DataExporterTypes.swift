import Foundation
@preconcurrency import SQLiteData

struct DataExportSummary {
    let exportedEntries: Int
    let exportedMedications: Int
    let exportedSchedules: Int
    let exportedIntakes: Int
    let exportedCollaboratorNotes: Int
}

struct ExportDataset {
    let entries: [SQLiteSymptomEntry]
    let collaboratorNotes: [SQLiteCollaboratorNote]
    let medications: [SQLiteMedication]
    let intakes: [SQLiteMedicationIntake]
    let schedules: [SQLiteMedicationSchedule]

    var summary: DataExportSummary {
        DataExportSummary(
            exportedEntries: entries.count,
            exportedMedications: medications.count,
            exportedSchedules: schedules.count,
            exportedIntakes: intakes.count,
            exportedCollaboratorNotes: collaboratorNotes.count
        )
    }
}

// MARK: - JSON Export Payload

struct ExportPayload: Encodable {
    let journal: ExportJournal
    let summary: ExportSummary
    let entries: [ExportSymptomEntry]
    let collaboratorNotes: [ExportCollaboratorNote]
    let medications: [ExportMedication]
    let intakes: [ExportIntake]
    let schedules: [ExportSchedule]
}

struct ExportJournal: Encodable {
    let id: UUID
    let createdAt: Date
}

struct ExportSummary: Encodable {
    let exportedEntries: Int
    let exportedMedications: Int
    let exportedSchedules: Int
    let exportedIntakes: Int
    let exportedCollaboratorNotes: Int
}

struct ExportSymptomEntry: Encodable {
    let id: UUID
    let timestamp: Date
    let journalID: UUID
    let severity: Int
    let headache: Int?
    let nausea: Int?
    let anxiety: Int?
    let isMenstruating: Bool?
    let note: String?
    let sentimentLabel: String?
    let sentimentScore: Double?
}

struct ExportCollaboratorNote: Encodable {
    let id: UUID
    let journalID: UUID
    let entryID: UUID?
    let authorName: String?
    let text: String?
    let timestamp: Date
}

struct ExportMedication: Encodable {
    let id: UUID
    let journalID: UUID
    let name: String
    let defaultAmount: Double?
    let defaultUnit: String?
    let isAsNeeded: Bool?
    let useCase: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ExportIntake: Encodable {
    let id: UUID
    let medicationID: UUID
    let entryID: UUID?
    let scheduleID: UUID?
    let amount: Double?
    let unit: String?
    let timestamp: Date
    let scheduledDate: Date?
    let origin: String?
    let notes: String?
}

struct ExportSchedule: Encodable {
    let id: UUID
    let medicationID: UUID
    let label: String?
    let amount: Double?
    let unit: String?
    let cadence: String?
    let interval: Int
    let daysOfWeekMask: Int
    let hour: Int?
    let minute: Int?
    let timeZoneIdentifier: String?
    let startDate: Date?
    let isActive: Bool?
    let sortOrder: Int
}

// MARK: - Payload Construction

extension ExportPayload {
    init(journal: SQLiteJournal, dataset: ExportDataset) {
        self.journal = ExportJournal(
            id: journal.id, createdAt: journal.createdAt
        )
        self.summary = ExportSummary(
            exportedEntries: dataset.summary.exportedEntries,
            exportedMedications: dataset.summary.exportedMedications,
            exportedSchedules: dataset.summary.exportedSchedules,
            exportedIntakes: dataset.summary.exportedIntakes,
            exportedCollaboratorNotes: dataset.summary.exportedCollaboratorNotes
        )
        self.entries = dataset.entries.map { Self.mapEntry($0) }
        self.collaboratorNotes = dataset.collaboratorNotes.map {
            Self.mapNote($0)
        }
        self.medications = dataset.medications.map {
            Self.mapMedication($0)
        }
        self.intakes = dataset.intakes.map { Self.mapIntake($0) }
        self.schedules = dataset.schedules.map {
            Self.mapSchedule($0)
        }
    }

    private static func mapEntry(
        _ entry: SQLiteSymptomEntry
    ) -> ExportSymptomEntry {
        ExportSymptomEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            journalID: entry.journalID,
            severity: Int(entry.severity),
            headache: entry.headache.map(Int.init),
            nausea: entry.nausea.map(Int.init),
            anxiety: entry.anxiety.map(Int.init),
            isMenstruating: entry.isMenstruating,
            note: entry.note,
            sentimentLabel: entry.sentimentLabel,
            sentimentScore: entry.sentimentScore
        )
    }

    private static func mapNote(
        _ note: SQLiteCollaboratorNote
    ) -> ExportCollaboratorNote {
        ExportCollaboratorNote(
            id: note.id,
            journalID: note.journalID,
            entryID: note.entryID,
            authorName: note.authorName,
            text: note.text,
            timestamp: note.timestamp
        )
    }

    private static func mapMedication(
        _ medication: SQLiteMedication
    ) -> ExportMedication {
        ExportMedication(
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
    }

    private static func mapIntake(
        _ intake: SQLiteMedicationIntake
    ) -> ExportIntake {
        ExportIntake(
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
    }

    private static func mapSchedule(
        _ schedule: SQLiteMedicationSchedule
    ) -> ExportSchedule {
        ExportSchedule(
            id: schedule.id,
            medicationID: schedule.medicationID,
            label: schedule.label,
            amount: schedule.amount,
            unit: schedule.unit,
            cadence: schedule.cadence,
            interval: Int(schedule.interval),
            daysOfWeekMask: Int(schedule.daysOfWeekMask),
            hour: schedule.hour.map(Int.init),
            minute: schedule.minute.map(Int.init),
            timeZoneIdentifier: schedule.timeZoneIdentifier,
            startDate: schedule.startDate,
            isActive: schedule.isActive,
            sortOrder: Int(schedule.sortOrder)
        )
    }
}
