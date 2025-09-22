import Foundation
import SQLiteData

@Table("sqLiteMedicationIntake")
struct SQLiteMedicationIntake: Identifiable {
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

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        entryID: UUID? = nil,
        scheduleID: UUID? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        timestamp: Date = Date(),
        scheduledDate: Date? = nil,
        origin: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.entryID = entryID
        self.scheduleID = scheduleID
        self.amount = amount
        self.unit = unit
        self.timestamp = timestamp
        self.scheduledDate = scheduledDate
        self.origin = origin
        self.notes = notes
    }
}

extension SQLiteMedicationIntake {
    /// Returns a copy that applies the editable fields while preserving linkage metadata used by scheduling and sync flows.
    func mergingEditableFields(
        amount: Double?,
        unit: String?,
        timestamp: Date,
        notes: String?
    ) -> SQLiteMedicationIntake {
        SQLiteMedicationIntake(
            id: id,
            medicationID: medicationID,
            entryID: entryID,
            scheduleID: scheduleID,
            amount: amount,
            unit: unit,
            timestamp: timestamp,
            scheduledDate: scheduledDate,
            origin: origin,
            notes: notes
        )
    }
}
