import Foundation
import SQLiteData

@Table("sqLiteCollaboratorNote")
struct SQLiteCollaboratorNote: Identifiable {
    let id: UUID
    let journalID: UUID
    let entryID: UUID?
    let authorName: String?
    let text: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        journalID: UUID,
        entryID: UUID? = nil,
        authorName: String? = nil,
        text: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.journalID = journalID
        self.entryID = entryID
        self.authorName = authorName
        self.text = text
        self.timestamp = timestamp
    }
}

extension SQLiteCollaboratorNote {
    // Query helpers will be implemented once SQLiteData dependency is available
}