import Foundation
import GRDB
@preconcurrency import SQLiteData
@testable import AuralystApp

/// Manual insert helper to avoid hitting the StructuredQueries insert path that crashes for schedules.
func insertSchedule(_ schedule: SQLiteMedicationSchedule, database: any DatabaseWriter) throws {
    try database.write { db in
        try insertSchedule(schedule, in: db)
    }
}

func insertSchedule(_ schedule: SQLiteMedicationSchedule, in db: Database) throws {
    try db.execute(sql: "PRAGMA foreign_keys = OFF")
    defer { try? db.execute(sql: "PRAGMA foreign_keys = ON") }

    try db.execute(
        sql: """
        INSERT OR REPLACE INTO "sqLiteMedicationSchedule"
        ("id", "medicationID", "label", "amount", "unit", "cadence", "interval",
         "daysOfWeekMask", "hour", "minute", "timeZoneIdentifier", "startDate",
         "isActive", "sortOrder")
        VALUES (:id, :medicationID, :label, :amount, :unit, :cadence, :interval,
                :daysOfWeekMask, :hour, :minute, :timeZoneIdentifier, :startDate,
                :isActive, :sortOrder)
        """,
        arguments: [
            "id": schedule.id.uuidString,
            "medicationID": schedule.medicationID.uuidString,
            "label": schedule.label,
            "amount": schedule.amount,
            "unit": schedule.unit,
            "cadence": schedule.cadence,
            "interval": schedule.interval,
            "daysOfWeekMask": schedule.daysOfWeekMask,
            "hour": schedule.hour,
            "minute": schedule.minute,
            "timeZoneIdentifier": schedule.timeZoneIdentifier,
            "startDate": schedule.startDate,
            "isActive": schedule.isActive.map { $0 ? 1 : 0 },
            "sortOrder": schedule.sortOrder
        ]
    )
}

func insertIntake(_ intake: SQLiteMedicationIntake, database: any DatabaseWriter) throws {
    try database.write { db in
        try insertIntake(intake, in: db)
    }
}

func insertIntake(_ intake: SQLiteMedicationIntake, in db: Database) throws {
    try db.execute(sql: "PRAGMA foreign_keys = OFF")
    defer { try? db.execute(sql: "PRAGMA foreign_keys = ON") }

    try db.execute(
        sql: """
        INSERT OR REPLACE INTO "sqLiteMedicationIntake"
        ("id", "medicationID", "entryID", "scheduleID", "amount", "unit",
         "timestamp", "scheduledDate", "origin", "notes")
        VALUES (:id, :medicationID, :entryID, :scheduleID, :amount, :unit,
                :timestamp, :scheduledDate, :origin, :notes)
        """,
        arguments: [
            "id": intake.id.uuidString,
            "medicationID": intake.medicationID.uuidString,
            "entryID": intake.entryID?.uuidString,
            "scheduleID": intake.scheduleID?.uuidString,
            "amount": intake.amount,
            "unit": intake.unit,
            "timestamp": intake.timestamp,
            "scheduledDate": intake.scheduledDate,
            "origin": intake.origin,
            "notes": intake.notes
        ]
    )
}
