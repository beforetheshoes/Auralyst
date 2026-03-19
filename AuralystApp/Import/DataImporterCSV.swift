import Foundation

// MARK: - CSV Parsing & Primitive Helpers

extension DataImporter {
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
        case "journal", "summary", "symptom_entries",
             "collaborator_notes", "medications",
             "medication_intakes", "medication_schedules":
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

    // MARK: - Row Parsers

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

    static func parseCollaboratorNote(
        _ row: [String: String]
    ) throws -> ImportPayload.CollaboratorNote {
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

    // MARK: - Primitive Helpers

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
