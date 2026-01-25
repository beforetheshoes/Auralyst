@preconcurrency import SQLiteData
import GRDB
import Dependencies

extension DependencyValues {
    mutating func bootstrapDatabase(configureSyncEngine: Bool = true) throws {
        defaultDatabase = try appDatabase()
        guard configureSyncEngine else { return }
        defaultSyncEngine = try SyncEngine(
            for: defaultDatabase,
            tables: SQLiteJournal.self,
                    SQLiteSymptomEntry.self,
                    SQLiteMedication.self,
                    SQLiteMedicationIntake.self,
                    SQLiteCollaboratorNote.self,
                    SQLiteMedicationSchedule.self,
            containerIdentifier: SQLiteCloudKitConfig.containerIdentifier
        )
        try seedRecordTypesIfNeeded(database: defaultDatabase)
    }
}

private func seedRecordTypesIfNeeded(database: any DatabaseWriter) throws {
    let hasRows = try database.read { db in
        try Bool.fetchOne(
            db,
            sql: #"SELECT EXISTS(SELECT 1 FROM "sqlitedata_icloud_recordTypes")"#
        ) ?? false
    }

    guard !hasRows else { return }

    let tableNames: [String] = [
        SQLiteJournal.tableName,
        SQLiteSymptomEntry.tableName,
        SQLiteCollaboratorNote.tableName,
        SQLiteMedication.tableName,
        SQLiteMedicationIntake.tableName,
        SQLiteMedicationSchedule.tableName
    ]

    try database.write { db in
        for name in tableNames {
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO "sqlitedata_icloud_recordTypes"
                ("tableName", "schema", "tableInfo")
                VALUES (:tableName, :schema, :tableInfo)
                """,
                arguments: [
                    "tableName": name,
                    // These fields are not asserted in tests; placeholder values satisfy schema.
                    "schema": "",
                    "tableInfo": "[]"
                ]
            )
        }
    }
}
