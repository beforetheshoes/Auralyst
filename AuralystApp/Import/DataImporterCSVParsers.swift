import Foundation

// MARK: - CSV Row Parsers

extension DataImporter {
    static func parseSymptomEntry(
        _ row: [String: String]
    ) throws -> ImportSymptomEntry {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let timestamp = date(from: row["timestamp"]),
              let severity = int(from: row["severity"]) else {
            throw ImportError.invalidCSV(
                "Invalid symptom entry row."
            )
        }

        return ImportSymptomEntry(
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

    static func parseJournal(
        _ row: [String: String]
    ) throws -> ImportJournal {
        guard let id = uuid(from: row["id"]),
              let createdAt = date(from: row["createdAt"]) else {
            throw ImportError.invalidCSV("Invalid journal row.")
        }
        return ImportJournal(id: id, createdAt: createdAt)
    }

    static func parseCollaboratorNote(
        _ row: [String: String]
    ) throws -> ImportCollaboratorNote {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let timestamp = date(from: row["timestamp"]) else {
            throw ImportError.invalidCSV(
                "Invalid collaborator note row."
            )
        }

        return ImportCollaboratorNote(
            id: id,
            journalID: journalID,
            entryID: uuid(from: row["entry_id"]),
            authorName: emptyToNil(row["author_name"]),
            text: emptyToNil(row["text"]),
            timestamp: timestamp
        )
    }

    static func parseMedication(
        _ row: [String: String]
    ) throws -> ImportMedication {
        guard let id = uuid(from: row["id"]),
              let journalID = uuid(from: row["journal_id"]),
              let createdAt = date(from: row["createdAt"]),
              let updatedAt = date(from: row["updatedAt"]) else {
            throw ImportError.invalidCSV("Invalid medication row.")
        }

        return ImportMedication(
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

    static func parseIntake(
        _ row: [String: String]
    ) throws -> ImportIntake {
        guard let id = uuid(from: row["id"]),
              let medicationID = uuid(from: row["medication_id"]),
              let timestamp = date(from: row["timestamp"]) else {
            throw ImportError.invalidCSV("Invalid intake row.")
        }

        return ImportIntake(
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

    static func parseSchedule(
        _ row: [String: String]
    ) throws -> ImportSchedule {
        guard let id = uuid(from: row["id"]),
              let medicationID = uuid(from: row["medication_id"]),
              let interval = int(from: row["interval"]),
              let mask = int(from: row["daysOfWeekMask"]),
              let sortOrder = int(from: row["sortOrder"]) else {
            throw ImportError.invalidCSV("Invalid schedule row.")
        }

        return ImportSchedule(
            id: id,
            medicationID: medicationID,
            label: emptyToNil(row["label"]),
            amount: double(from: row["amount"]),
            unit: emptyToNil(row["unit"]),
            cadence: emptyToNil(row["cadence"]),
            interval: interval,
            daysOfWeekMask: mask,
            hour: int(from: row["hour"]),
            minute: int(from: row["minute"]),
            timeZoneIdentifier: emptyToNil(
                row["timeZoneIdentifier"]
            ),
            startDate: date(from: row["startDate"]),
            isActive: bool(from: row["isActive"]),
            sortOrder: sortOrder
        )
    }

    // MARK: - Primitive Helpers

    static func parseISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds
        ]
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
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    static func emptyToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
