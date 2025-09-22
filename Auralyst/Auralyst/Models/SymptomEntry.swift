import Foundation
import SQLiteData

@Table("sqLiteSymptomEntry")
struct SQLiteSymptomEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let journalID: UUID

    // Severity metrics
    let severity: Int16
    let headache: Int16?
    let nausea: Int16?
    let anxiety: Int16?

    // Additional data
    let isMenstruating: Bool?
    let note: String?
    let sentimentLabel: String?
    let sentimentScore: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        journalID: UUID,
        severity: Int16 = 0,
        headache: Int16? = nil,
        nausea: Int16? = nil,
        anxiety: Int16? = nil,
        isMenstruating: Bool? = nil,
        note: String? = nil,
        sentimentLabel: String? = nil,
        sentimentScore: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.journalID = journalID
        self.severity = severity
        self.headache = headache
        self.nausea = nausea
        self.anxiety = anxiety
        self.isMenstruating = isMenstruating
        self.note = note
        self.sentimentLabel = sentimentLabel
        self.sentimentScore = sentimentScore
    }
}

extension SQLiteSymptomEntry {
    // Query helpers will be implemented once SQLiteData dependency is available
    // These would use SQLiteData's query building API
}