import Foundation
import SQLiteData

@Table("sqLiteMedicationSchedule")
struct SQLiteMedicationSchedule: Identifiable {
    let id: UUID
    let medicationID: UUID
    let label: String?
    let amount: Double?
    let unit: String?
    let cadence: String?
    let interval: Int16
    let daysOfWeekMask: Int16
    let hour: Int16?
    let minute: Int16?
    let timeZoneIdentifier: String?
    let startDate: Date?
    let isActive: Bool?
    let sortOrder: Int16

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        label: String? = nil,
        amount: Double? = nil,
        unit: String? = nil,
        cadence: String? = nil,
        interval: Int16 = 1,
        daysOfWeekMask: Int16 = 0,
        hour: Int16? = nil,
        minute: Int16? = nil,
        timeZoneIdentifier: String? = nil,
        startDate: Date? = nil,
        isActive: Bool? = nil,
        sortOrder: Int16 = 0
    ) {
        self.id = id
        self.medicationID = medicationID
        self.label = label
        self.amount = amount
        self.unit = unit
        self.cadence = cadence
        self.interval = interval
        self.daysOfWeekMask = daysOfWeekMask
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startDate = startDate
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

extension SQLiteMedicationSchedule {
    // Query helpers will be implemented once SQLiteData dependency is available
}