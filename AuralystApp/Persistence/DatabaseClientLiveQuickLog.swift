import Foundation
import GRDB
import os.log
@preconcurrency import SQLiteData

// MARK: - Quick Log Operations

func assignQuickLogOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.fetchQuickLogSnapshot = { journalID, date in
        let loader = MedicationQuickLogLoader(database: database)
        return try loader.load(journalID: journalID, on: date)
    }

    client.logScheduledDose = { params in
        let times = MedicationQuickLogFeature.scheduledDateTime(
            for: params.schedule, on: params.date
        )
        let amountValue = params.schedule.amount ?? params.medication.defaultAmount
        let unitValue = params.schedule.unit ?? params.medication.defaultUnit
        try database.write { db in
            let persistedScheduleID = try scheduleIDToPersist(
                scheduleID: params.schedule.id, db: db
            )
            try insertMedicationIntake(
                in: db,
                medicationID: params.schedule.medicationID,
                scheduleID: persistedScheduleID,
                amount: amountValue,
                unit: unitValue,
                timestamp: times.timestamp,
                scheduledDate: times.scheduledDate,
                origin: "scheduled"
            )
        }
    }

    client.unlogScheduledDose = { params in
        try unlogScheduledDoseImpl(params: params, database: database)
    }
}

private func unlogScheduledDoseImpl(
    params: ScheduledDoseUnlogParams,
    database: any DatabaseWriter
) throws {
    if let intake = params.snapshot.takenByScheduleID[params.schedule.id] {
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM "sqLiteMedicationIntake"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [intake.id.uuidString]
            )
        }
    } else if params.schedule.id == params.schedule.medicationID {
        let bounds = MedicationQuickLogFeature.dayBounds(for: params.date)
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM "sqLiteMedicationIntake"
                    WHERE lower("medicationID") = lower(?)
                    AND "timestamp" >= ? AND "timestamp" < ?
                    AND "scheduleID" IS NULL
                    """,
                arguments: [
                    params.schedule.medicationID.uuidString,
                    bounds.start,
                    bounds.end
                ]
            )
        }
    }
}
