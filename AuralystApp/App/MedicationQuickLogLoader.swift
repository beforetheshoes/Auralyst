import Foundation
import Dependencies
import GRDB
@preconcurrency import SQLiteData

struct MedicationQuickLogSnapshot: Equatable {
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
    @Dependency(\.databaseClient) private var databaseClient

    func load(journalID: UUID, on date: Date) throws -> MedicationQuickLogSnapshot {
        guard let journal = databaseClient.fetchJournal(journalID) else {
            return .empty
        }

        let medications = databaseClient.fetchMedications(journal)
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
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM sqLiteMedicationSchedule
                        WHERE medicationID = ?
                        ORDER BY sortOrder ASC, hour ASC, minute ASC
                        """,
                    arguments: [medication.id.uuidString]
                )
                let schedules = rows.map { row -> SQLiteMedicationSchedule in
                    let interval: Int16 = (row["interval"] as Int64?).map { Int16($0) } ?? 1
                    let daysOfWeekMask: Int16 = (row["daysOfWeekMask"] as Int64?).map { Int16($0) } ?? 0
                    let hour: Int16? = (row["hour"] as Int64?).map { Int16($0) }
                    let minute: Int16? = (row["minute"] as Int64?).map { Int16($0) }
                    let sortOrder: Int16 = (row["sortOrder"] as Int64?).map { Int16($0) } ?? 0
                    let idString: String = row["id"]
                    let medicationIDString: String = row["medicationID"]
                    let id = UUID(uuidString: idString) ?? UUID()
                    let medicationID = UUID(uuidString: medicationIDString) ?? medication.id
                    return SQLiteMedicationSchedule(
                        id: id,
                        medicationID: medicationID,
                        label: row["label"],
                        amount: row["amount"],
                        unit: row["unit"],
                        cadence: row["cadence"],
                        interval: interval,
                        daysOfWeekMask: daysOfWeekMask,
                        hour: hour,
                        minute: minute,
                        timeZoneIdentifier: row["timeZoneIdentifier"],
                        startDate: row["startDate"],
                        isActive: (row["isActive"] as Bool?) ?? (row["isActive"] as Int64?).map { $0 != 0 },
                        sortOrder: sortOrder
                    )
                }
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
