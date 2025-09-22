import Foundation
import Dependencies
import SQLiteData

struct MedicationQuickLogSnapshot {
    var medications: [SQLiteMedication]
    var schedulesByMedication: [UUID: [SQLiteMedicationSchedule]]
    var takenByScheduleID: [UUID: SQLiteMedicationIntake]

    static let empty = MedicationQuickLogSnapshot(
        medications: [],
        schedulesByMedication: [:],
        takenByScheduleID: [:]
    )
}

@MainActor
struct MedicationQuickLogLoader {
    @Dependency(\.defaultDatabase) private var database

    private let dataStore: DataStore

    init(dataStore: DataStore) {
        self.dataStore = dataStore
    }

    func load(journalID: UUID, on date: Date) throws -> MedicationQuickLogSnapshot {
        guard let journal = dataStore.fetchJournal(id: journalID) else {
            return .empty
        }

        let medications = dataStore.fetchMedications(for: journal)
        let schedulesByMedication = try loadSchedules(for: medications)
        let takenByScheduleID = try loadIntakes(for: medications, on: date)

        return MedicationQuickLogSnapshot(
            medications: medications,
            schedulesByMedication: schedulesByMedication,
            takenByScheduleID: takenByScheduleID
        )
    }

    private func loadSchedules(for medications: [SQLiteMedication]) throws -> [UUID: [SQLiteMedicationSchedule]] {
        var mapping: [UUID: [SQLiteMedicationSchedule]] = [:]
        try database.read { db in
            for medication in medications {
                let schedules = try SQLiteMedicationSchedule
                    .where { $0.medicationID == medication.id }
                    .fetchAll(db)
                if !schedules.isEmpty {
                    mapping[medication.id] = schedules
                }
            }
        }
        return mapping
    }

    private func loadIntakes(for medications: [SQLiteMedication], on date: Date) throws -> [UUID: SQLiteMedicationIntake] {
        let medIDs = Set(medications.map { $0.id })
        let bounds = dayBounds(for: date)
        var taken: [UUID: SQLiteMedicationIntake] = [:]

        let intakes = try database.read { db in
            try SQLiteMedicationIntake
                .where { $0.timestamp >= bounds.start && $0.timestamp < bounds.end }
                .fetchAll(db)
        }

        for intake in intakes where medIDs.contains(intake.medicationID) {
            if let scheduleID = intake.scheduleID {
                taken[scheduleID] = intake
            } else {
                taken[intake.medicationID] = intake
            }
        }

        return taken
    }

    private func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
