import Foundation
import SQLiteData
import GRDB
import Dependencies
import os.log

func appDatabase() throws -> any DatabaseWriter {
    @Dependency(\.context) var context
    var configuration = Configuration()

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

    var migrator = DatabaseMigrator()
    #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("Create tables v2") { db in
        // Create journals table
        try #sql("""
            CREATE TABLE "sqLiteJournal"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "createdAt" TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now'))
            ) STRICT
        """).execute(db)

        // Create symptom entries table
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

        // Create medications table
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

        // Create medication intakes table
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

        // Create collaborator notes table
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

        // Create medication schedules table
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

    try migrator.migrate(database)
    return database
}

// Avoid MainActor logger in nonisolated contexts; use print for now.
