import Foundation
@preconcurrency import SQLiteData
import Dependencies

struct ImportSummary: Equatable {
    let importedEntries: Int
    let importedMedications: Int
    let importedSchedules: Int
    let importedIntakes: Int
    let importedCollaboratorNotes: Int
}

struct ImportResult: Equatable {
    let journalID: UUID
    let summary: ImportSummary
}

enum ImportFormat {
    case json
    case csv
}

enum ImportError: Error, LocalizedError {
    case unsupportedFormat
    case missingFile
    case invalidCSV(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Unsupported import format."
        case .missingFile:
            return "The selected file could not be read."
        case .invalidCSV(let message):
            return "CSV import failed: \(message)"
        case .invalidPayload(let message):
            return "Import data is invalid: \(message)"
        }
    }
}

struct DataImporter {
    static func importFile(at url: URL, replaceExisting: Bool) throws -> ImportResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.missingFile
        }

        let data = try Data(contentsOf: url)
        let payload: ImportPayload
        switch try format(for: url) {
        case .json:
            payload = try parseJSON(data: data)
        case .csv:
            payload = try parseCSV(data: data)
        }

        try validate(payload)
        return try importPayload(payload, replaceExisting: replaceExisting)
    }
}

private extension DataImporter {
    struct ImportPayload: Decodable {
        struct Journal: Decodable {
            let id: UUID
            let createdAt: Date
        }

        struct SymptomEntry: Decodable {
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

        struct CollaboratorNote: Decodable {
            let id: UUID
            let journalID: UUID
            let entryID: UUID?
            let authorName: String?
            let text: String?
            let timestamp: Date
        }

        struct Medication: Decodable {
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

        struct Intake: Decodable {
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

        struct Schedule: Decodable {
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
        let entries: [SymptomEntry]
        let collaboratorNotes: [CollaboratorNote]
        let medications: [Medication]
        let intakes: [Intake]
        let schedules: [Schedule]

        var summary: ImportSummary {
            ImportSummary(
                importedEntries: entries.count,
                importedMedications: medications.count,
                importedSchedules: schedules.count,
                importedIntakes: intakes.count,
                importedCollaboratorNotes: collaboratorNotes.count
            )
        }
    }

    static func format(for url: URL) throws -> ImportFormat {
        switch url.pathExtension.lowercased() {
        case "json":
            return .json
        case "csv":
            return .csv
        default:
            throw ImportError.unsupportedFormat
        }
    }

    static func parseJSON(data: Data) throws -> ImportPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseISO8601Date(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return try decoder.decode(ImportPayload.self, from: data)
    }

    static func parseCSV(data: Data) throws -> ImportPayload {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidCSV("Unable to decode file as UTF-8.")
        }

        var journal: ImportPayload.Journal?
        var entries: [ImportPayload.SymptomEntry] = []
        var collaboratorNotes: [ImportPayload.CollaboratorNote] = []
        var medications: [ImportPayload.Medication] = []
        var intakes: [ImportPayload.Intake] = []
        var schedules: [ImportPayload.Schedule] = []

        let lines = splitCSVRows(csvString)
        var section: String?
        var headers: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                section = nil
                headers = []
                continue
            }

            if isSectionHeader(line) {
                section = line
                headers = []
                continue
            }

            guard let section else {
                continue
            }

            let values = try parseCSVLine(line)
            if headers.isEmpty {
                headers = values
                continue
            }

            let row = makeRow(headers: headers, values: values)
            switch section {
            case "journal":
                if journal == nil {
                    journal = try parseJournal(row)
                }
            case "summary":
                continue
            case "symptom_entries":
                entries.append(try parseSymptomEntry(row))
                if journal == nil, let journalID = uuid(from: row["journal_id"]) {
                    journal = ImportPayload.Journal(id: journalID, createdAt: Date())
                }
            case "collaborator_notes":
                collaboratorNotes.append(try parseCollaboratorNote(row))
                if journal == nil, let journalID = uuid(from: row["journal_id"]) {
                    journal = ImportPayload.Journal(id: journalID, createdAt: Date())
                }
            case "medications":
                medications.append(try parseMedication(row))
                if journal == nil, let journalID = uuid(from: row["journal_id"]) {
                    journal = ImportPayload.Journal(id: journalID, createdAt: Date())
                }
            case "medication_intakes":
                intakes.append(try parseIntake(row))
            case "medication_schedules":
                schedules.append(try parseSchedule(row))
            default:
                continue
            }
        }

        guard let journal else {
            throw ImportError.invalidCSV("No journal identifier found in CSV.")
        }

        return ImportPayload(
            journal: journal,
            entries: entries,
            collaboratorNotes: collaboratorNotes,
            medications: medications,
            intakes: intakes,
            schedules: schedules
        )
    }

    static func isSectionHeader(_ line: String) -> Bool {
        switch line {
        case "journal", "summary", "symptom_entries", "collaborator_notes", "medications", "medication_intakes", "medication_schedules":
            return true
        default:
            return false
        }
    }

    static func makeRow(headers: [String], values: [String]) -> [String: String] {
        var row: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            row[header] = index < values.count ? values[index] : ""
        }
        return row
    }

    static func parseCSVLine(_ line: String) throws -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let char = iterator.next() {
            if inQuotes {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else if next == "," {
                            inQuotes = false
                            results.append(current)
                            current = ""
                        } else {
                            inQuotes = false
                            current.append(next)
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(char)
                }
            } else {
                if char == "," {
                    results.append(current)
                    current = ""
                } else if char == "\"" {
                    inQuotes = true
                } else {
                    current.append(char)
                }
            }
        }

        results.append(current)
        if inQuotes {
            throw ImportError.invalidCSV("Unterminated quoted field: \(line)")
        }
        return results
    }

    static func splitCSVRows(_ content: String) -> [String] {
        var rows: [String] = []
        var current = ""
        var inQuotes = false
        let characters = Array(content)
        var index = 0

        while index < characters.count {
            let char = characters[index]
            if char == "\"" {
                if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
                    current.append("\"")
                    current.append("\"")
                    index += 2
                    continue
                } else {
                    inQuotes.toggle()
                    current.append(char)
                    index += 1
                    continue
                }
            }

            if (char == "\n" || char == "\r") && !inQuotes {
                if !current.isEmpty {
                    rows.append(current)
                    current = ""
                }
                if char == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 2
                } else {
                    index += 1
                }
                continue
            }

            current.append(char)
            index += 1
        }

        if !current.isEmpty {
            rows.append(current)
        }

        return rows
    }

    static func parseSymptomEntry(_ row: [String: String]) throws -> ImportPayload.SymptomEntry {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let timestamp = date(from: row["timestamp"]),
              let severity = int(from: row["severity"]) else {
            throw ImportError.invalidCSV("Invalid symptom entry row.")
        }

        return ImportPayload.SymptomEntry(
            id: id,
            timestamp: timestamp,
            journalID: journalID,
            severity: severity,
            headache: int(from: row["headache"]),
            nausea: int(from: row["nausea"]),
            anxiety: int(from: row["anxiety"]),
            isMenstruating: bool(from: row["isMenstruating"]),
            note: emptyToNil(row["note"]),
            sentimentLabel: emptyToNil(row["sentimentLabel"]),
            sentimentScore: double(from: row["sentimentScore"])
        )
    }

    static func parseJournal(_ row: [String: String]) throws -> ImportPayload.Journal {
        guard let id = uuid(from: row["id"]),
              let createdAt = date(from: row["createdAt"]) else {
            throw ImportError.invalidCSV("Invalid journal row.")
        }

        return ImportPayload.Journal(id: id, createdAt: createdAt)
    }

    static func parseCollaboratorNote(_ row: [String: String]) throws -> ImportPayload.CollaboratorNote {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let timestamp = date(from: row["timestamp"]) else {
            throw ImportError.invalidCSV("Invalid collaborator note row.")
        }

        return ImportPayload.CollaboratorNote(
            id: id,
            journalID: journalID,
            entryID: uuid(from: row["entry_id"]),
            authorName: emptyToNil(row["author_name"]),
            text: emptyToNil(row["text"]),
            timestamp: timestamp
        )
    }

    static func parseMedication(_ row: [String: String]) throws -> ImportPayload.Medication {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let createdAt = date(from: row["createdAt"]),
              let updatedAt = date(from: row["updatedAt"]) else {
            throw ImportError.invalidCSV("Invalid medication row.")
        }

        return ImportPayload.Medication(
            id: id,
            journalID: journalID,
            name: emptyToNil(row["name"]) ?? "",
            defaultAmount: double(from: row["defaultAmount"]),
            defaultUnit: emptyToNil(row["defaultUnit"]),
            isAsNeeded: bool(from: row["isAsNeeded"]),
            useCase: emptyToNil(row["useCase"]),
            notes: emptyToNil(row["notes"]),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func parseIntake(_ row: [String: String]) throws -> ImportPayload.Intake {
        guard let id = uuid(from: row["id"]),
              let medicationID = uuid(from: row["medication_id"]),
              let timestamp = date(from: row["timestamp"]) else {
            throw ImportError.invalidCSV("Invalid intake row.")
        }

        return ImportPayload.Intake(
            id: id,
            medicationID: medicationID,
            entryID: uuid(from: row["entry_id"]),
            scheduleID: uuid(from: row["schedule_id"]),
            amount: double(from: row["amount"]),
            unit: emptyToNil(row["unit"]),
            timestamp: timestamp,
            scheduledDate: date(from: row["scheduledDate"]),
            origin: emptyToNil(row["origin"]),
            notes: emptyToNil(row["notes"])
        )
    }

    static func parseSchedule(_ row: [String: String]) throws -> ImportPayload.Schedule {
        guard let id = uuid(from: row["id"]),
              let medicationID = uuid(from: row["medication_id"]),
              let interval = int(from: row["interval"]),
              let daysOfWeekMask = int(from: row["daysOfWeekMask"]),
              let sortOrder = int(from: row["sortOrder"]) else {
            throw ImportError.invalidCSV("Invalid schedule row.")
        }

        return ImportPayload.Schedule(
            id: id,
            medicationID: medicationID,
            label: emptyToNil(row["label"]),
            amount: double(from: row["amount"]),
            unit: emptyToNil(row["unit"]),
            cadence: emptyToNil(row["cadence"]),
            interval: interval,
            daysOfWeekMask: daysOfWeekMask,
            hour: int(from: row["hour"]),
            minute: int(from: row["minute"]),
            timeZoneIdentifier: emptyToNil(row["timeZoneIdentifier"]),
            startDate: date(from: row["startDate"]),
            isActive: bool(from: row["isActive"]),
            sortOrder: sortOrder
        )
    }

    static func validate(_ payload: ImportPayload) throws {
        let journalID = payload.journal.id
        if payload.entries.contains(where: { $0.journalID != journalID }) {
            throw ImportError.invalidPayload("One or more symptom entries reference a different journal.")
        }
        if payload.medications.contains(where: { $0.journalID != journalID }) {
            throw ImportError.invalidPayload("One or more medications reference a different journal.")
        }
        if payload.collaboratorNotes.contains(where: { $0.journalID != journalID }) {
            throw ImportError.invalidPayload("One or more collaborator notes reference a different journal.")
        }

        let medicationIDs = Set(payload.medications.map { $0.id })
        if payload.schedules.contains(where: { !medicationIDs.contains($0.medicationID) }) {
            throw ImportError.invalidPayload("One or more schedules reference missing medications.")
        }
        if payload.intakes.contains(where: { !medicationIDs.contains($0.medicationID) }) {
            throw ImportError.invalidPayload("One or more intakes reference missing medications.")
        }

        let entryIDs = Set(payload.entries.map { $0.id })
        if payload.collaboratorNotes.contains(where: { note in
            guard let entryID = note.entryID else { return false }
            return !entryIDs.contains(entryID)
        }) {
            throw ImportError.invalidPayload("One or more collaborator notes reference missing symptom entries.")
        }

        let scheduleIDs = Set(payload.schedules.map { $0.id })
        if payload.intakes.contains(where: { intake in
            guard let scheduleID = intake.scheduleID else { return false }
            return !scheduleIDs.contains(scheduleID)
        }) {
            throw ImportError.invalidPayload("One or more intakes reference missing schedules.")
        }

        if payload.intakes.contains(where: { intake in
            guard let entryID = intake.entryID else { return false }
            return !entryIDs.contains(entryID)
        }) {
            throw ImportError.invalidPayload("One or more intakes reference missing symptom entries.")
        }
    }

    static func importPayload(_ payload: ImportPayload, replaceExisting: Bool) throws -> ImportResult {
        @Dependency(\.defaultDatabase) var database
        try database.write { db in
            if replaceExisting {
                try SQLiteMedicationSchedule.delete().execute(db)
                try SQLiteMedicationIntake.delete().execute(db)
                try SQLiteCollaboratorNote.delete().execute(db)
                try SQLiteSymptomEntry.delete().execute(db)
                try SQLiteMedication.delete().execute(db)
                try SQLiteJournal.delete().execute(db)
            }

            let journal = SQLiteJournal(id: payload.journal.id, createdAt: payload.journal.createdAt)
            try SQLiteJournal.insert { journal }.execute(db)

            for entry in payload.entries {
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

            for medication in payload.medications {
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

            for schedule in payload.schedules {
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
                try SQLiteMedicationSchedule.insert { record }.execute(db)
            }

            for intake in payload.intakes {
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
                try SQLiteMedicationIntake.insert { record }.execute(db)
            }

            for note in payload.collaboratorNotes {
                let record = SQLiteCollaboratorNote(
                    id: note.id,
                    journalID: note.journalID,
                    entryID: note.entryID,
                    authorName: note.authorName,
                    text: note.text,
                    timestamp: note.timestamp
                )
                try SQLiteCollaboratorNote.insert { record }.execute(db)
            }
        }

        return ImportResult(journalID: payload.journal.id, summary: payload.summary)
    }

    static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return parseISO8601Date(value)
    }

    static func uuid(from value: String?) -> UUID? {
        guard let value, !value.isEmpty else { return nil }
        return UUID(uuidString: value)
    }

    static func int(from value: String?) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        return Int(value)
    }

    static func double(from value: String?) -> Double? {
        guard let value, !value.isEmpty else { return nil }
        return Double(value)
    }

    static func bool(from value: String?) -> Bool? {
        guard let value, !value.isEmpty else { return nil }
        switch value.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
