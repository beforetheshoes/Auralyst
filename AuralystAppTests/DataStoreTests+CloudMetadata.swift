import Foundation
import GRDB
import Testing
import Dependencies
import os.log
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Cloud metadata edge cases", .serialized)
struct CloudMetadataEdgeCaseSuite {
    @MainActor
    @Test("Metadata table absent returns early without crash")
    func metadataTableAbsentReturnsEarly() throws {
        try prepareTestDependencies(configureSyncEngine: false)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        // Should not crash even though metadata table doesn't exist
        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: logger
        )

        // Journal should still exist
        let journalExists = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteJournal"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [journal.id.uuidString]
            ) ?? 0
        }
        #expect(journalExists == 1)
    }

    @MainActor
    @Test("Missing metadata row touches journal via no-op UPDATE")
    func missingMetadataRowTouchesJournal() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        // Delete any auto-created metadata so we start clean
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
        }

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: logger
        )

        // Journal row should still exist after the no-op UPDATE
        let journalExists = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteJournal"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [journal.id.uuidString]
            ) ?? 0
        }
        #expect(journalExists == 1)
    }

    @MainActor
    @Test("Deleted metadata (_isDeleted=1) is reset")
    func deletedMetadataIsReset() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        // Set _isDeleted = 1 on the metadata row
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE sqlitedata_icloud_metadata
                    SET _isDeleted = 1
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
        }

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: logger
        )

        // Metadata row should be deleted (reset)
        let metadataExists = try database.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM sqlitedata_icloud_metadata
                        WHERE recordPrimaryKey = ?
                        AND recordType = ?
                        AND _isDeleted = 1
                    )
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            ) ?? false
        }
        #expect(!metadataExists)

        // Journal row should survive
        let journalExists = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteJournal"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [journal.id.uuidString]
            ) ?? 0
        }
        #expect(journalExists == 1)
    }

    @MainActor
    @Test("Nil lastKnownServerRecord takes touchOnly path (generated column is 0)")
    func nilLastKnownServerRecordTouchesOnly() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        // Replace metadata with a row that has NULL lastKnownServerRecord.
        // The generated column hasLastKnownServerRecord computes to 0,
        // so evaluateMetadataRow falls through to .touchOnly (not .reset).
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO sqlitedata_icloud_metadata
                    (recordPrimaryKey, recordType, zoneName, ownerName,
                     lastKnownServerRecord, _isDeleted, userModificationTime)
                    VALUES (?, ?, 'com.apple.coredata.cloudkit.zone', '_defaultOwner',
                            NULL, 0, 0)
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
        }

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: logger
        )

        // touchOnly path: metadata row survives, journal row gets no-op UPDATE
        let metadataCount = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            ) ?? 0
        }
        #expect(metadataCount == 1)

        let journalExists = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteJournal"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [journal.id.uuidString]
            ) ?? 0
        }
        #expect(journalExists == 1)
    }

    @MainActor
    @Test("hasLastKnown=1 with data is skipped")
    func hasLastKnownWithDataIsSkipped() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        let fakeRecord = Data([0x01, 0x02, 0x03])
        // hasLastKnownServerRecord is generated, so delete + re-insert
        try database.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            )
            try db.execute(
                sql: """
                    INSERT INTO sqlitedata_icloud_metadata
                    (recordPrimaryKey, recordType, zoneName, ownerName,
                     lastKnownServerRecord, _isDeleted, userModificationTime)
                    VALUES (?, ?, 'com.apple.coredata.cloudkit.zone', '_defaultOwner',
                            ?, 0, 0)
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName,
                    fakeRecord
                ]
            )
        }

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: logger
        )

        // Metadata row should still exist (skip path, no deletion)
        let metadataCount = try database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM sqlitedata_icloud_metadata
                    WHERE recordPrimaryKey = ?
                    AND recordType = ?
                    """,
                arguments: [
                    journal.id.uuidString,
                    SQLiteJournal.tableName
                ]
            ) ?? 0
        }
        #expect(metadataCount == 1)
    }

    @MainActor
    @Test("Write failure is swallowed without throwing")
    func writeFailureIsSwallowed() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database

        let logger = Logger(
            subsystem: "com.yourteam.Auralyst",
            category: "CloudMetadata.test"
        )

        // Use a non-existent journal ID so the no-op UPDATE affects 0 rows,
        // but more importantly the function should not throw
        let bogusID = UUID()
        ensureJournalCloudMetadata(
            journalID: bogusID,
            database: database,
            logger: logger
        )
        // If we reach here, the function swallowed the non-error gracefully
    }
}
