import Foundation

// MARK: - CSV Parsing & Primitive Helpers

extension DataImporter {
    static func parseCSV(data: Data) throws -> ImportPayload {
        guard let csvString = String(data: data, encoding: .utf8)
        else {
            throw ImportError.invalidCSV(
                "Unable to decode file as UTF-8."
            )
        }

        var state = CSVParseState()
        let lines = splitCSVRows(csvString)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            try processCSVLine(line, state: &state)
        }

        guard let journal = state.journal else {
            throw ImportError.invalidCSV(
                "No journal identifier found in CSV."
            )
        }

        return ImportPayload(
            journal: journal,
            entries: state.entries,
            collaboratorNotes: state.collaboratorNotes,
            medications: state.medications,
            intakes: state.intakes,
            schedules: state.schedules
        )
    }
}

// MARK: - CSV Parse State

private struct CSVParseState {
    var journal: ImportJournal?
    var entries: [ImportSymptomEntry] = []
    var collaboratorNotes: [ImportCollaboratorNote] = []
    var medications: [ImportMedication] = []
    var intakes: [ImportIntake] = []
    var schedules: [ImportSchedule] = []
    var section: String?
    var headers: [String] = []
}

// MARK: - Line Processing

extension DataImporter {
    fileprivate static func processCSVLine(
        _ line: String,
        state: inout CSVParseState
    ) throws {
        if line.isEmpty {
            state.section = nil
            state.headers = []
            return
        }

        if isSectionHeader(line) {
            state.section = line
            state.headers = []
            return
        }

        guard let section = state.section else { return }

        let values = try parseCSVLine(line)
        if state.headers.isEmpty {
            state.headers = values
            return
        }

        let row = makeRow(headers: state.headers, values: values)
        try routeCSVRow(
            section: section, row: row, state: &state
        )
    }

    fileprivate static func routeCSVRow(
        section: String,
        row: [String: String],
        state: inout CSVParseState
    ) throws {
        switch section {
        case "journal":
            if state.journal == nil {
                state.journal = try parseJournal(row)
            }
        case "summary":
            break
        case "symptom_entries":
            state.entries.append(try parseSymptomEntry(row))
            inferJournal(from: row, state: &state)
        case "collaborator_notes":
            state.collaboratorNotes.append(
                try parseCollaboratorNote(row)
            )
            inferJournal(from: row, state: &state)
        case "medications":
            state.medications.append(try parseMedication(row))
            inferJournal(from: row, state: &state)
        case "medication_intakes":
            state.intakes.append(try parseIntake(row))
        case "medication_schedules":
            state.schedules.append(try parseSchedule(row))
        default:
            break
        }
    }

    private static func inferJournal(
        from row: [String: String],
        state: inout CSVParseState
    ) {
        if state.journal == nil,
           let journalID = uuid(from: row["journal_id"]) {
            state.journal = ImportJournal(
                id: journalID, createdAt: Date()
            )
        }
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

    static func makeRow(
        headers: [String], values: [String]
    ) -> [String: String] {
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
                parseQuotedChar(
                    char, iterator: &iterator,
                    inQuotes: &inQuotes,
                    current: &current, results: &results
                )
            } else {
                parseUnquotedChar(
                    char, inQuotes: &inQuotes,
                    current: &current, results: &results
                )
            }
        }

        results.append(current)
        if inQuotes {
            throw ImportError.invalidCSV(
                "Unterminated quoted field: \(line)"
            )
        }
        return results
    }

    private static func parseQuotedChar(
        _ char: Character,
        iterator: inout String.Iterator,
        inQuotes: inout Bool,
        current: inout String,
        results: inout [String]
    ) {
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
    }

    private static func parseUnquotedChar(
        _ char: Character,
        inQuotes: inout Bool,
        current: inout String,
        results: inout [String]
    ) {
        if char == "," {
            results.append(current)
            current = ""
        } else if char == "\"" {
            inQuotes = true
        } else {
            current.append(char)
        }
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
                if inQuotes,
                   index + 1 < characters.count,
                   characters[index + 1] == "\"" {
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
                if char == "\r",
                   index + 1 < characters.count,
                   characters[index + 1] == "\n" {
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

}
