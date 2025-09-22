import Foundation
import SQLiteData
import Dependencies

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

struct DataExportSummary {
    let exportedEntries: Int
    let exportedMedications: Int
    let exportedSchedules: Int
    let exportedIntakes: Int
}

struct DataExporter {
    static func exportCSV(for journal: SQLiteJournal) throws -> Data {
        let dataset = try fetchDataset(for: journal)
        let summary = dataset.summary

        var lines: [String] = []
        lines.append("summary")
        lines.append("metric,value")
        lines.append("exportedEntries,\(summary.exportedEntries)")
        lines.append("exportedMedications,\(summary.exportedMedications)")
        lines.append("exportedSchedules,\(summary.exportedSchedules)")
        lines.append("exportedIntakes,\(summary.exportedIntakes)")

        lines.append("")
        lines.append("symptom_entries")
        lines.append("id,journal_id,timestamp,severity,headache,nausea,anxiety,isMenstruating,note,sentimentLabel,sentimentScore")
        for entry in dataset.entries {
            var values: [String] = []
            values.append(entry.id.uuidString)
            values.append(journal.id.uuidString)
            values.append(isoFormatter.string(from: entry.timestamp))
            values.append(String(entry.severity))
            values.append(entry.headache.map { String($0) } ?? "")
            values.append(entry.nausea.map { String($0) } ?? "")
            values.append(entry.anxiety.map { String($0) } ?? "")
            values.append(entry.isMenstruating.map { $0 ? "true" : "false" } ?? "")
            values.append(csvEscape(entry.note))
            values.append(csvEscape(entry.sentimentLabel))
            values.append(entry.sentimentScore.map { String($0) } ?? "")
            lines.append(values.joined(separator: ","))
        }

        lines.append("")
        lines.append("medications")
        lines.append("id,journal_id,name,defaultAmount,defaultUnit,isAsNeeded,useCase,notes,createdAt,updatedAt")
        for medication in dataset.medications {
            var values: [String] = []
            values.append(medication.id.uuidString)
            values.append(journal.id.uuidString)
            values.append(csvEscape(medication.name))
            values.append(medication.defaultAmount.map { String($0) } ?? "")
            values.append(csvEscape(medication.defaultUnit))
            values.append(medication.isAsNeeded.map { $0 ? "true" : "false" } ?? "")
            values.append(csvEscape(medication.useCase))
            values.append(csvEscape(medication.notes))
            values.append(isoFormatter.string(from: medication.createdAt))
            values.append(isoFormatter.string(from: medication.updatedAt))
            lines.append(values.joined(separator: ","))
        }

        lines.append("")
        lines.append("medication_intakes")
        lines.append("id,medication_id,entry_id,schedule_id,amount,unit,timestamp,scheduledDate,origin,notes")
        for intake in dataset.intakes {
            var values: [String] = []
            values.append(intake.id.uuidString)
            values.append(intake.medicationID.uuidString)
            values.append(intake.entryID?.uuidString ?? "")
            values.append(intake.scheduleID?.uuidString ?? "")
            values.append(intake.amount.map { String($0) } ?? "")
            values.append(csvEscape(intake.unit))
            values.append(isoFormatter.string(from: intake.timestamp))
            values.append(intake.scheduledDate.map { isoFormatter.string(from: $0) } ?? "")
            values.append(csvEscape(intake.origin))
            values.append(csvEscape(intake.notes))
            lines.append(values.joined(separator: ","))
        }

        lines.append("")
        lines.append("medication_schedules")
        lines.append("id,medication_id,label,amount,unit,cadence,interval,daysOfWeekMask,hour,minute,timeZoneIdentifier,startDate,isActive,sortOrder")
        for schedule in dataset.schedules {
            var values: [String] = []
            values.append(schedule.id.uuidString)
            values.append(schedule.medicationID.uuidString)
            values.append(csvEscape(schedule.label))
            values.append(schedule.amount.map { String($0) } ?? "")
            values.append(csvEscape(schedule.unit))
            values.append(csvEscape(schedule.cadence))
            values.append(String(schedule.interval))
            values.append(String(schedule.daysOfWeekMask))
            values.append(schedule.hour.map { String($0) } ?? "")
            values.append(schedule.minute.map { String($0) } ?? "")
            values.append(csvEscape(schedule.timeZoneIdentifier))
            values.append(schedule.startDate.map { isoFormatter.string(from: $0) } ?? "")
            values.append(schedule.isActive.map { $0 ? "true" : "false" } ?? "")
            values.append(String(schedule.sortOrder))
            lines.append(values.joined(separator: ","))
        }

        let csvString = lines.joined(separator: "\n") + "\n"
        return Data(csvString.utf8)
    }

    static func exportJSON(for journal: SQLiteJournal) throws -> Data {
        let dataset = try fetchDataset(for: journal)
        let payload = ExportPayload(journal: journal, dataset: dataset)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }

        return try encoder.encode(payload)
    }

    static func exportSummary(for journal: SQLiteJournal) throws -> DataExportSummary {
        try fetchDataset(for: journal).summary
    }
}

private extension DataExporter {
    struct Dataset {
        let entries: [SQLiteSymptomEntry]
        let medications: [SQLiteMedication]
        let intakes: [SQLiteMedicationIntake]
        let schedules: [SQLiteMedicationSchedule]

        var summary: DataExportSummary {
            DataExportSummary(
                exportedEntries: entries.count,
                exportedMedications: medications.count,
                exportedSchedules: schedules.count,
                exportedIntakes: intakes.count
            )
        }
    }

    struct ExportPayload: Encodable {
        struct Journal: Encodable {
            let id: UUID
            let createdAt: Date
        }

        struct Summary: Encodable {
            let exportedEntries: Int
            let exportedMedications: Int
            let exportedSchedules: Int
            let exportedIntakes: Int
        }

        struct SymptomEntry: Encodable {
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

        struct Medication: Encodable {
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

        struct Intake: Encodable {
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

        struct Schedule: Encodable {
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

        let journal: Journal
        let summary: Summary
        let entries: [SymptomEntry]
        let medications: [Medication]
        let intakes: [Intake]
        let schedules: [Schedule]

        init(journal: SQLiteJournal, dataset: Dataset) {
            self.journal = Journal(id: journal.id, createdAt: journal.createdAt)
            self.summary = Summary(
                exportedEntries: dataset.summary.exportedEntries,
                exportedMedications: dataset.summary.exportedMedications,
                exportedSchedules: dataset.summary.exportedSchedules,
                exportedIntakes: dataset.summary.exportedIntakes
            )

            self.entries = dataset.entries.map { entry in
                SymptomEntry(
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

            self.medications = dataset.medications.map { medication in
                Medication(
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

            self.intakes = dataset.intakes.map { intake in
                Intake(
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

            self.schedules = dataset.schedules.map { schedule in
                Schedule(
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
    }

    static func fetchDataset(for journal: SQLiteJournal) throws -> Dataset {
        @Dependency(\.defaultDatabase) var database
        return try database.read { db in
            let entries = try SQLiteSymptomEntry
                .where { $0.journalID == journal.id }
                .order { $0.timestamp.desc() }
                .fetchAll(db)

            let medications = try SQLiteMedication
                .where { $0.journalID == journal.id }
                .order { $0.name.asc() }
                .fetchAll(db)

            let medicationIDs = Set(medications.map(\.id))

            let allIntakes = try SQLiteMedicationIntake
                .order { $0.timestamp.desc() }
                .fetchAll(db)
            let intakes = allIntakes.filter { medicationIDs.contains($0.medicationID) }

            let allSchedules = try SQLiteMedicationSchedule
                .order { $0.sortOrder.asc() }
                .fetchAll(db)
            let schedules = allSchedules.filter { medicationIDs.contains($0.medicationID) }

            return Dataset(entries: entries, medications: medications, intakes: intakes, schedules: schedules)
        }
    }

    static func csvEscape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let needsQuotes = value.contains(",") || value.contains("\n") || value.contains("\"")
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }
}
