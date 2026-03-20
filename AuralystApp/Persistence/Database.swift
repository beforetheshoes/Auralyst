import Foundation
@preconcurrency import SQLiteData
import GRDB
import Dependencies
import os.log

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true

    let containerID = SQLiteCloudKitConfig.containerIdentifier
    configuration.prepareDatabase { db in
        #if DEBUG
        db.trace(options: .profile) { event in
            if context == .preview {
                print("\(event.expandedDescription)")
            } else {
                print("SQL: \(event.expandedDescription)")
            }
        }
        #endif

        // Attach CloudKit metadata database
        try db.attachMetadatabase(containerIdentifier: containerID)
    }

    let database = try defaultDatabase(configuration: configuration)
    print("open '\(database.path)'")

    // In DEBUG builds, erase and recreate the database when the
    // schema changes so developers always start fresh. In production
    // (eraseDatabaseOnSchemaChange defaults to false), DatabaseMigrator
    // runs registered migrations in order and throws if a previously
    // applied migration is missing. Never remove or reorder existing
    // migrations; always append new ones.
    var migrator = makeMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif
    try migrator.migrate(database)

    return database
}

private func makeMigrator(
    eraseOnSchemaChange: Bool = false
) -> DatabaseMigrator {
    var migrator = DatabaseMigrator()
    if eraseOnSchemaChange {
        migrator.eraseDatabaseOnSchemaChange = true
    }
    migrator.registerMigration("Create tables v2") { db in
        try createTablesV2(in: db)
    }
    migrator.registerMigration("Clean orphaned records v1") { db in
        try cleanOrphanedRecords(in: db)
    }
    return migrator
}

private func createTablesV2(in db: Database) throws {
    try createCoreTables(in: db)
    try createSupportTables(in: db)
}

private func createCoreTables(in db: Database) throws {
    try #sql("""
        CREATE TABLE "sqLiteJournal"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "createdAt" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now'))
        ) STRICT
    """).execute(db)

    try #sql("""
        CREATE TABLE "sqLiteSymptomEntry"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "timestamp" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
            "journalID" TEXT NOT NULL,
            "severity" INTEGER NOT NULL DEFAULT 0,
            "headache" INTEGER,
            "nausea" INTEGER,
            "anxiety" INTEGER,
            "isMenstruating" INTEGER,
            "note" TEXT,
            "sentimentLabel" TEXT,
            "sentimentScore" REAL,
            FOREIGN KEY ("journalID") REFERENCES "sqLiteJournal"("id") ON DELETE CASCADE
        ) STRICT
    """).execute(db)

    try #sql("""
        CREATE TABLE "sqLiteMedication"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "journalID" TEXT NOT NULL,
            "name" TEXT NOT NULL DEFAULT '',
            "defaultAmount" REAL,
            "defaultUnit" TEXT,
            "isAsNeeded" INTEGER,
            "useCase" TEXT,
            "notes" TEXT,
            "createdAt" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
            "updatedAt" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
            FOREIGN KEY ("journalID") REFERENCES "sqLiteJournal"("id") ON DELETE CASCADE
        ) STRICT
    """).execute(db)
}

private func createSupportTables(in db: Database) throws {
    try #sql("""
        CREATE TABLE "sqLiteMedicationIntake"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "medicationID" TEXT NOT NULL,
            "entryID" TEXT,
            "scheduleID" TEXT,
            "amount" REAL,
            "unit" TEXT,
            "timestamp" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
            "scheduledDate" TEXT,
            "origin" TEXT,
            "notes" TEXT,
            FOREIGN KEY ("medicationID") REFERENCES "sqLiteMedication"("id") ON DELETE CASCADE,
            FOREIGN KEY ("entryID") REFERENCES "sqLiteSymptomEntry"("id") ON DELETE SET NULL
        ) STRICT
    """).execute(db)

    try #sql("""
        CREATE TABLE "sqLiteCollaboratorNote"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "journalID" TEXT NOT NULL,
            "entryID" TEXT,
            "authorName" TEXT,
            "text" TEXT,
            "timestamp" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')),
            FOREIGN KEY ("journalID") REFERENCES "sqLiteJournal"("id") ON DELETE CASCADE,
            FOREIGN KEY ("entryID") REFERENCES "sqLiteSymptomEntry"("id") ON DELETE SET NULL
        ) STRICT
    """).execute(db)

    try #sql("""
        CREATE TABLE "sqLiteMedicationSchedule"(
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "medicationID" TEXT NOT NULL,
            "label" TEXT,
            "amount" REAL,
            "unit" TEXT,
            "cadence" TEXT,
            "interval" INTEGER NOT NULL DEFAULT 1,
            "daysOfWeekMask" INTEGER NOT NULL DEFAULT 0,
            "hour" INTEGER,
            "minute" INTEGER,
            "timeZoneIdentifier" TEXT,
            "startDate" TEXT,
            "isActive" INTEGER,
            "sortOrder" INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY ("medicationID") REFERENCES "sqLiteMedication"("id") ON DELETE CASCADE
        ) STRICT
    """).execute(db)
}

private func cleanOrphanedRecords(in db: Database) throws {
    // Clean orphans bottom-up (leaf tables first) so deletes
    // cannot themselves violate FK constraints.
    try db.execute(sql: """
        DELETE FROM sqLiteMedicationIntake
        WHERE medicationID NOT IN (SELECT id FROM sqLiteMedication)
    """)
    try db.execute(sql: """
        UPDATE sqLiteMedicationIntake SET entryID = NULL
        WHERE entryID IS NOT NULL
        AND entryID NOT IN (SELECT id FROM sqLiteSymptomEntry)
    """)
    try db.execute(sql: """
        DELETE FROM sqLiteMedicationSchedule
        WHERE medicationID NOT IN (SELECT id FROM sqLiteMedication)
    """)
    try db.execute(sql: """
        DELETE FROM sqLiteCollaboratorNote
        WHERE journalID NOT IN (SELECT id FROM sqLiteJournal)
    """)
    try db.execute(sql: """
        UPDATE sqLiteCollaboratorNote SET entryID = NULL
        WHERE entryID IS NOT NULL
        AND entryID NOT IN (SELECT id FROM sqLiteSymptomEntry)
    """)
    try db.execute(sql: """
        DELETE FROM sqLiteSymptomEntry
        WHERE journalID NOT IN (SELECT id FROM sqLiteJournal)
    """)
    try db.execute(sql: """
        DELETE FROM sqLiteMedication
        WHERE journalID NOT IN (SELECT id FROM sqLiteJournal)
    """)
}

// Avoid MainActor logger in nonisolated contexts; use print for now.

#if DEBUG
/// Insert helpers that go through SQLiteData so sync metadata is updated in tests.
func insertSchedule(_ schedule: SQLiteMedicationSchedule, database: any DatabaseWriter) throws {
    try database.write { db in
        try insertSchedule(schedule, in: db)
    }
}

func insertSchedule(_ schedule: SQLiteMedicationSchedule, in db: Database) throws {
    try SQLiteMedicationSchedule.insert {
        (
            $0.id,
            $0.medicationID,
            $0.label,
            $0.amount,
            $0.unit,
            $0.cadence,
            $0.interval,
            $0.daysOfWeekMask,
            $0.hour,
            $0.minute,
            $0.timeZoneIdentifier,
            $0.startDate,
            $0.isActive,
            $0.sortOrder
        )
    } values: {
        (
            schedule.id,
            schedule.medicationID,
            schedule.label,
            schedule.amount,
            schedule.unit,
            schedule.cadence,
            schedule.interval,
            schedule.daysOfWeekMask,
            schedule.hour,
            schedule.minute,
            schedule.timeZoneIdentifier,
            schedule.startDate,
            schedule.isActive,
            schedule.sortOrder
        )
    }
    .execute(db)
}

func insertIntake(_ intake: SQLiteMedicationIntake, database: any DatabaseWriter) throws {
    try database.write { db in
        try insertIntake(intake, in: db)
    }
}

func insertIntake(_ intake: SQLiteMedicationIntake, in db: Database) throws {
    try SQLiteMedicationIntake.insert {
        (
            $0.id,
            $0.medicationID,
            $0.entryID,
            $0.scheduleID,
            $0.amount,
            $0.unit,
            $0.timestamp,
            $0.scheduledDate,
            $0.origin,
            $0.notes
        )
    } values: {
        (
            intake.id,
            intake.medicationID,
            intake.entryID,
            intake.scheduleID,
            intake.amount,
            intake.unit,
            intake.timestamp,
            intake.scheduledDate,
            intake.origin,
            intake.notes
        )
    }
    .execute(db)
}
#endif
