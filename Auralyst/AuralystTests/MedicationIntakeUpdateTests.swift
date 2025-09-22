import Foundation
import Testing
@testable import Auralyst

@Suite("Medication intake editing helpers")
struct MedicationIntakeUpdateSuite {
    @Test("Editable field merge keeps linkage metadata intact")
    func mergePreservesMetadata() {
        let original = SQLiteMedicationIntake(
            id: UUID(),
            medicationID: UUID(),
            entryID: UUID(),
            scheduleID: UUID(),
            amount: 1,
            unit: "tablet",
            timestamp: Date(timeIntervalSince1970: 1_726_000_000),
            scheduledDate: Date(timeIntervalSince1970: 1_725_936_000),
            origin: "scheduled",
            notes: "before"
        )

        let merged = original.mergingEditableFields(
            amount: 2,
            unit: "capsule",
            timestamp: original.timestamp.addingTimeInterval(900),
            notes: "after"
        )

        #expect(merged.id == original.id)
        #expect(merged.medicationID == original.medicationID)
        #expect(merged.scheduleID == original.scheduleID)
        #expect(merged.entryID == original.entryID)
        #expect(merged.scheduledDate == original.scheduledDate)
        #expect(merged.origin == original.origin)
        #expect(merged.amount == 2)
        #expect(merged.unit == "capsule")
        #expect(merged.timestamp == original.timestamp.addingTimeInterval(900))
        #expect(merged.notes == "after")
    }
}
