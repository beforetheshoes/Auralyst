import Foundation

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

enum ImportResolution: Equatable {
    case strict
    case autoFix
}

enum ImportIssueKind: Equatable {
    case missingScheduleReferences
    case missingIntakeEntryReferences
    case missingNoteEntryReferences
    case missingMedicationReferences
    case journalMismatch
}

struct ImportIssue: Equatable {
    let kind: ImportIssueKind
    let count: Int
    let examples: [String]
    let isFixable: Bool
}

struct ImportAnalysis: Equatable {
    let fixableIssues: [ImportIssue]
    let blockingIssues: [ImportIssue]

    var hasIssues: Bool {
        !fixableIssues.isEmpty || !blockingIssues.isEmpty
    }
    var hasBlockingIssues: Bool { !blockingIssues.isEmpty }
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

// MARK: - Import Payload Types (file-scope to avoid nesting)

struct ImportPayload: Decodable {
    let journal: ImportJournal
    let entries: [ImportSymptomEntry]
    let collaboratorNotes: [ImportCollaboratorNote]
    let medications: [ImportMedication]
    let intakes: [ImportIntake]
    let schedules: [ImportSchedule]

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

struct ImportJournal: Decodable {
    let id: UUID
    let createdAt: Date
}

struct ImportSymptomEntry: Decodable {
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

struct ImportCollaboratorNote: Decodable {
    let id: UUID
    let journalID: UUID
    let entryID: UUID?
    let authorName: String?
    let text: String?
    let timestamp: Date
}

struct ImportMedication: Decodable {
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

struct ImportIntake: Decodable {
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

struct ImportSchedule: Decodable {
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
