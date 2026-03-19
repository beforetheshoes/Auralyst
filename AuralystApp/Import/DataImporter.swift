import Foundation
@preconcurrency import SQLiteData
import Dependencies

struct DataImporter {
    static func importFile(
        at url: URL, replaceExisting: Bool
    ) throws -> ImportResult {
        try importFile(
            at: url,
            replaceExisting: replaceExisting,
            resolution: .strict
        )
    }

    static func analyzeFile(at url: URL) throws -> ImportAnalysis {
        let payload = try parsePayload(at: url)
        return analyze(payload)
    }

    static func importFile(
        at url: URL,
        replaceExisting: Bool,
        resolution: ImportResolution
    ) throws -> ImportResult {
        let payload = try parsePayload(at: url)
        let analysis = analyze(payload)
        if analysis.hasBlockingIssues {
            throw ImportError.invalidPayload(
                blockingMessage(for: analysis.blockingIssues)
            )
        }
        if resolution == .strict, analysis.hasIssues {
            let message = blockingMessage(
                for: analysis.fixableIssues
            )
            throw ImportError.invalidPayload(message)
        }

        let sanitizedPayload = sanitize(
            payload, resolution: resolution
        )
        try validate(sanitizedPayload)
        return try importPayload(
            sanitizedPayload, replaceExisting: replaceExisting
        )
    }

    private static func parsePayload(
        at url: URL
    ) throws -> ImportPayload {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.missingFile
        }

        let data = try Data(contentsOf: url)
        switch try format(for: url) {
        case .json:
            return try parseJSON(data: data)
        case .csv:
            return try parseCSV(data: data)
        }
    }
}

// MARK: - Sanitize & Format

extension DataImporter {
    static func sanitize(
        _ payload: ImportPayload,
        resolution: ImportResolution
    ) -> ImportPayload {
        let scheduleIDs = Set(payload.schedules.map { $0.id })
        let entryIDs = Set(payload.entries.map { $0.id })

        let sanitizedIntakes = sanitizeIntakes(
            payload.intakes,
            scheduleIDs: scheduleIDs,
            entryIDs: entryIDs,
            resolution: resolution
        )

        let sanitizedNotes = sanitizeNotes(
            payload.collaboratorNotes,
            entryIDs: entryIDs,
            resolution: resolution
        )

        return ImportPayload(
            journal: payload.journal,
            entries: payload.entries,
            collaboratorNotes: sanitizedNotes,
            medications: payload.medications,
            intakes: sanitizedIntakes,
            schedules: payload.schedules
        )
    }

    private static func sanitizeIntakes(
        _ intakes: [ImportIntake],
        scheduleIDs: Set<UUID>,
        entryIDs: Set<UUID>,
        resolution: ImportResolution
    ) -> [ImportIntake] {
        intakes.map { intake in
            var scheduleID = intake.scheduleID
            var entryID = intake.entryID

            if let ref = scheduleID, !scheduleIDs.contains(ref) {
                if ref == intake.medicationID
                    || resolution == .autoFix {
                    scheduleID = nil
                }
            }

            if let ref = entryID, !entryIDs.contains(ref),
               resolution == .autoFix {
                entryID = nil
            }

            guard scheduleID != intake.scheduleID
                || entryID != intake.entryID else {
                return intake
            }

            return ImportIntake(
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
    }

    private static func sanitizeNotes(
        _ notes: [ImportCollaboratorNote],
        entryIDs: Set<UUID>,
        resolution: ImportResolution
    ) -> [ImportCollaboratorNote] {
        if resolution == .autoFix {
            return notes.map { note in
                guard let eID = note.entryID,
                      !entryIDs.contains(eID)
                else { return note }
                return ImportCollaboratorNote(
                    id: note.id,
                    journalID: note.journalID,
                    entryID: nil,
                    authorName: note.authorName,
                    text: note.text,
                    timestamp: note.timestamp
                )
            }
        }
        return notes
    }

    static func format(for url: URL) throws -> ImportFormat {
        switch url.pathExtension.lowercased() {
        case "json": return .json
        case "csv": return .csv
        default: throw ImportError.unsupportedFormat
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
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(value)"
            )
        }
        return try decoder.decode(ImportPayload.self, from: data)
    }

    static func blockingMessage(
        for issues: [ImportIssue]
    ) -> String {
        guard let issue = issues.first else {
            return "Unknown import issue."
        }
        switch issue.kind {
        case .missingScheduleReferences:
            return "One or more intakes reference missing schedules."
        case .missingIntakeEntryReferences:
            return "One or more intakes reference missing symptom entries."
        case .missingNoteEntryReferences:
            return "One or more collaborator notes reference missing symptom entries."
        case .missingMedicationReferences:
            return "One or more records reference missing medications."
        case .journalMismatch:
            return "One or more records reference a different journal."
        }
    }
}
