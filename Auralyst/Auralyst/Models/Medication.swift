import Foundation
import SQLiteData

@Table("sqLiteMedication")
struct SQLiteMedication: Identifiable {
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

    init(
        id: UUID = UUID(),
        journalID: UUID,
        name: String,
        defaultAmount: Double? = nil,
        defaultUnit: String? = nil,
        isAsNeeded: Bool? = nil,
        useCase: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.journalID = journalID
        self.name = name
        self.defaultAmount = defaultAmount
        self.defaultUnit = defaultUnit
        self.isAsNeeded = isAsNeeded
        self.useCase = useCase
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension SQLiteMedication {
    // Query helpers will be implemented once SQLiteData dependency is available
}