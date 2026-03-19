import Foundation
import GRDB
import os.log
@preconcurrency import SQLiteData

enum MetadataAction {
    case skip
    case reset
    case touchOnly
}

func ensureJournalCloudMetadata(
    journalID: UUID,
    database: any DatabaseWriter,
    logger: Logger
) {
    do {
        let metadataTableExists = try database.read { db in
            try String.fetchOne(
                db,
                sql: """
                    SELECT name FROM sqlite_master
                    WHERE type = 'table'
                    AND name = 'sqlitedata_icloud_metadata'
                """
            ) != nil
        }
        guard metadataTableExists else { return }

        let metadataRow = try database.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT hasLastKnownServerRecord,
                       lastKnownServerRecord, _isDeleted
                FROM sqlitedata_icloud_metadata
                WHERE recordPrimaryKey = ? AND recordType = ?
                LIMIT 1
                """,
                arguments: [
                    journalID.uuidString,
                    SQLiteJournal.tableName
                ]
            )
        }

        let action = evaluateMetadataRow(
            metadataRow, journalID: journalID
        )
        guard action != .skip else { return }

        if action == .reset {
            try resetCloudMetadata(
                journalID: journalID,
                database: database,
                logger: logger
            )
        }

        try touchJournalRecord(
            journalID: journalID, database: database
        )
        logger.info(
            "Ensured CloudKit metadata for journal: \(journalID)"
        )
    } catch {
        logger.error(
            "Error ensuring CloudKit metadata for journal \(journalID): \(error.localizedDescription)"
        )
    }
}

private func resetCloudMetadata(
    journalID: UUID,
    database: any DatabaseWriter,
    logger: Logger
) throws {
    try database.write { db in
        try db.execute(
            sql: """
            DELETE FROM sqlitedata_icloud_metadata
            WHERE recordPrimaryKey = ? AND recordType = ?
            """,
            arguments: [
                journalID.uuidString,
                SQLiteJournal.tableName
            ]
        )
    }
    logger.info("Reset CloudKit metadata for journal: \(journalID)")
}

private func touchJournalRecord(
    journalID: UUID,
    database: any DatabaseWriter
) throws {
    try database.write { db in
        try db.execute(
            sql: """
                UPDATE sqLiteJournal
                SET createdAt = createdAt WHERE id = ?
            """,
            arguments: [journalID.uuidString]
        )
    }
}

private func evaluateMetadataRow(
    _ metadataRow: Row?,
    journalID: UUID
) -> MetadataAction {
    guard let metadataRow else { return .touchOnly }

    let hasLastKnown =
        (metadataRow["hasLastKnownServerRecord"] as? Int) ?? 0
    let lastKnown =
        metadataRow["lastKnownServerRecord"] as? Data
    let isDeleted = (metadataRow["_isDeleted"] as? Int) ?? 0
    let isShared = (metadataRow["isShared"] as? Int) ?? 0
    let share = metadataRow["share"] as? Data
    let recordSize = lastKnown?.count ?? 0
    let shareSize = share?.count ?? 0

    print(
        "Journal metadata status id=\(journalID)"
        + " hasLastKnownServerRecord=\(hasLastKnown)"
        + " recordSize=\(recordSize) isDeleted=\(isDeleted)"
        + " isShared=\(isShared) shareSize=\(shareSize)"
    )

    if isDeleted == 1
        || (hasLastKnown == 1 && lastKnown == nil) {
        return .reset
    } else if hasLastKnown == 1 {
        return .skip
    }
    return .touchOnly
}
