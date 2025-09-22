import Foundation
import SQLiteData

@Table("sqLiteJournal")
struct SQLiteJournal: Identifiable {
    let id: UUID
    let createdAt: Date

    init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
    }
}

extension SQLiteJournal {
    static let privateTables: [String] = []
    static let shareableTables: [String] = ["SQLiteJournal", "SQLiteSymptomEntry", "SQLiteCollaboratorNote", "SQLiteMedication", "SQLiteMedicationIntake", "SQLiteMedicationSchedule"]
}