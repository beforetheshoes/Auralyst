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

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: makeTestLogger()
        )

        #expect(try journalCount(id: journal.id, database: database) == 1)
    }

    @MainActor
    @Test("Missing metadata row touches journal via no-op UPDATE")
    func missingMetadataRowTouchesJournal() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        try deleteMetadata(for: journal.id, database: database)

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: makeTestLogger()
        )

        #expect(try journalCount(id: journal.id, database: database) == 1)
    }

    @MainActor
    @Test("Deleted metadata (_isDeleted=1) is reset")
    func deletedMetadataIsReset() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        try setMetadataDeleted(for: journal.id, database: database)

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: makeTestLogger()
        )

        #expect(try deletedMetadataCount(for: journal.id, database: database) == 0)
        #expect(try journalCount(id: journal.id, database: database) == 1)
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
        try replaceMetadata(for: journal.id, lastKnownServerRecord: nil, database: database)

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: makeTestLogger()
        )

        #expect(try metadataCount(for: journal.id, database: database) == 1)
        #expect(try journalCount(id: journal.id, database: database) == 1)
    }

    @MainActor
    @Test("hasLastKnown=1 with data is skipped")
    func hasLastKnownWithDataIsSkipped() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database
        let store = DataStore()
        let journal = try store.createJournal()

        let fakeRecord = Data([0x01, 0x02, 0x03])
        try replaceMetadata(
            for: journal.id,
            lastKnownServerRecord: fakeRecord,
            database: database
        )

        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database,
            logger: makeTestLogger()
        )

        #expect(try metadataCount(for: journal.id, database: database) == 1)
    }

    @MainActor
    @Test("Write failure is swallowed without throwing")
    func writeFailureIsSwallowed() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database

        ensureJournalCloudMetadata(
            journalID: UUID(),
            database: database,
            logger: makeTestLogger()
        )
    }
}

// MARK: - Helpers

private func makeTestLogger() -> Logger {
    Logger(subsystem: "com.yourteam.Auralyst", category: "CloudMetadata.test")
}

private func journalCount(
    id: UUID,
    database: any DatabaseWriter
) throws -> Int {
    try database.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM "sqLiteJournal"
                WHERE lower("id") = lower(?)
                """,
            arguments: [id.uuidString]
        ) ?? 0
    }
}

private func metadataCount(
    for journalID: UUID,
    database: any DatabaseWriter
) throws -> Int {
    try database.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM sqlitedata_icloud_metadata
                WHERE recordPrimaryKey = ? AND recordType = ?
                """,
            arguments: [journalID.uuidString, SQLiteJournal.tableName]
        ) ?? 0
    }
}

private func deletedMetadataCount(
    for journalID: UUID,
    database: any DatabaseWriter
) throws -> Int {
    try database.read { db in
        try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM sqlitedata_icloud_metadata
                WHERE recordPrimaryKey = ? AND recordType = ? AND _isDeleted = 1
                """,
            arguments: [journalID.uuidString, SQLiteJournal.tableName]
        ) ?? 0
    }
}

private func deleteMetadata(
    for journalID: UUID,
    database: any DatabaseWriter
) throws {
    try database.write { db in
        try db.execute(
            sql: """
                DELETE FROM sqlitedata_icloud_metadata
                WHERE recordPrimaryKey = ? AND recordType = ?
                """,
            arguments: [journalID.uuidString, SQLiteJournal.tableName]
        )
    }
}

private func setMetadataDeleted(
    for journalID: UUID,
    database: any DatabaseWriter
) throws {
    try database.write { db in
        try db.execute(
            sql: """
                UPDATE sqlitedata_icloud_metadata
                SET _isDeleted = 1
                WHERE recordPrimaryKey = ? AND recordType = ?
                """,
            arguments: [journalID.uuidString, SQLiteJournal.tableName]
        )
    }
}

private func replaceMetadata(
    for journalID: UUID,
    lastKnownServerRecord: Data?,
    database: any DatabaseWriter
) throws {
    // hasLastKnownServerRecord is a generated column, so delete + re-insert
    try database.write { db in
        try db.execute(
            sql: """
                DELETE FROM sqlitedata_icloud_metadata
                WHERE recordPrimaryKey = ? AND recordType = ?
                """,
            arguments: [journalID.uuidString, SQLiteJournal.tableName]
        )
        try db.execute(
            sql: """
                INSERT INTO sqlitedata_icloud_metadata
                (recordPrimaryKey, recordType, zoneName, ownerName,
                 lastKnownServerRecord, _isDeleted, userModificationTime)
                VALUES (?, ?, 'com.apple.coredata.cloudkit.zone', '_defaultOwner', ?, 0, 0)
                """,
            arguments: [
                journalID.uuidString,
                SQLiteJournal.tableName,
                lastKnownServerRecord
            ]
        )
    }
}
