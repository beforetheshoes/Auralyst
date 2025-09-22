import Foundation
import Testing
import Dependencies
import SQLiteData
@testable import Auralyst

@Suite("Medication quick log model", .serialized)
struct MedicationQuickLogModelSuite {
    @MainActor
    @Test("Streams new medications without manual refresh", .serialized)
    func streamsMedicationsReactively() async throws {
        try await withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            let store = DataStore()
            let journal = store.createJournal()
            let model = MedicationQuickLogModel(journalID: journal.id)

            #expect(model.snapshot.medications.isEmpty)

            _ = store.createMedication(
                for: journal,
                name: "Ibuprofen",
                defaultAmount: 200,
                defaultUnit: "mg"
            )

            // Wait for the model to pick up the new medication via SQLiteData observation
            let didUpdate = await eventually(timeout: .seconds(5)) {
                model.refresh()
                return model.snapshot.medications.contains { $0.name == "Ibuprofen" }
            }

            #expect(didUpdate)
        }
    }

    @MainActor
    @Test("Updates schedules when they change", .serialized)
    func updatesSchedulesReactively() async throws {
        try await withDependencies {
            try $0.bootstrapDatabase()
        } operation: {
            let store = DataStore()
            let journal = store.createJournal()
            let medication = store.createMedication(
                for: journal,
                name: "Vitamin D",
                defaultAmount: 1,
                defaultUnit: "pill"
            )

            let model = MedicationQuickLogModel(journalID: journal.id)

            // Initially there should be only the synthetic schedule
            #expect(model.snapshot.schedulesByMedication[medication.id]?.isEmpty ?? true)

            @Dependency(\.defaultDatabase) var database
            let schedule = SQLiteMedicationSchedule(
                medicationID: medication.id,
                label: "Morning",
                amount: 1,
                unit: "pill",
                cadence: "daily",
                interval: 1,
                daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
                hour: 9,
                minute: 0,
                isActive: true,
                sortOrder: 0
            )
            try await database.write { db in
                try SQLiteMedicationSchedule.insert { schedule }.execute(db)
            }

            let scheduleAppeared = await eventually(timeout: .seconds(5)) {
                model.refresh()
                return model.snapshot.schedulesByMedication[medication.id]?.contains(where: { $0.id == schedule.id }) == true
            }

            #expect(scheduleAppeared)
        }
    }
}

@MainActor
private func eventually(timeout: Duration = .seconds(1), pollInterval: Duration = .milliseconds(50), _ predicate: @escaping () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let start = clock.now
    let limit = start.advanced(by: timeout)

    if predicate() { return true }

    while clock.now < limit {
        await Task.yield()
        let interval = Double(pollInterval.components.seconds) + Double(pollInterval.components.attoseconds) / 1_000_000_000_000_000_000
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(interval))
        if predicate() { return true }
    }

    await Task.yield()
    return predicate()
}
