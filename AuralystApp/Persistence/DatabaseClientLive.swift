import Dependencies
import Foundation
import GRDB
import os.log
@preconcurrency import SQLiteData

// MARK: - Journal Operations

func assignJournalOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.createJournal = {
        createJournalImpl(database: database, logger: logger)
    }

    client.fetchJournals = {
        do {
            let journals = try database.read { db in
                try SQLiteJournal.all.fetchAll(db)
            }
            logger.info("Fetched \(journals.count) journals")
            return journals
        } catch {
            logger.error(
                "Error fetching journals: \(error.localizedDescription)"
            )
            return []
        }
    }

    client.fetchJournal = { id in
        do {
            let journal = try database.read { db in
                try SQLiteJournal.find(id).fetchOne(db)
            }
            logger.info("Fetched journal: \(id)")
            return journal
        } catch {
            logger.error(
                "Error fetching journal \(id): \(error.localizedDescription)"
            )
            return nil
        }
    }
}

private func createJournalImpl(
    database: any DatabaseWriter,
    logger: Logger
) -> SQLiteJournal {
    do {
        let journal = SQLiteJournal()
        try database.write { db in
            try SQLiteJournal.insert { journal }.execute(db)
        }
        if let fetched = try database.read({ db in
            try SQLiteJournal.find(journal.id).fetchOne(db)
        }) {
            logger.info(
                "Created journal with ID: \(journal.id)"
            )
            return fetched
        } else {
            logger.error(
                "Failed to fetch created journal: \(journal.id)"
            )
            return journal
        }
    } catch {
        logger.error(
            "Error creating journal: \(error.localizedDescription)"
        )
        return SQLiteJournal()
    }
}

// MARK: - Symptom Entry Operations (Create & Read)

func assignEntryCreateOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.createSymptomEntry = { journal, severity, note, timestamp, isMenstruating in
        try createSymptomEntryImpl(
            journal: journal, severity: severity,
            note: note, timestamp: timestamp,
            isMenstruating: isMenstruating,
            database: database, logger: logger
        )
    }

    client.fetchSymptomEntry = { id in
        do {
            let entry = try database.read { db in
                try SQLiteSymptomEntry.find(id).fetchOne(db)
            }
            logger.info("Fetched symptom entry: \(id)")
            return entry
        } catch {
            logger.error(
                "Error fetching entry \(id): \(error.localizedDescription)"
            )
            return nil
        }
    }

    client.fetchSymptomEntries = { journal in
        do {
            let entries = try database.read { db in
                try SQLiteSymptomEntry
                    .where { $0.journalID.eq(journal.id) }
                    .order { $0.timestamp.desc() }
                    .fetchAll(db)
            }
            logger.info(
                "Fetched \(entries.count) entries"
            )
            return entries
        } catch {
            logger.error(
                "Error fetching entries: \(error.localizedDescription)"
            )
            throw error
        }
    }
}

// swiftlint:disable:next function_parameter_count
private func createSymptomEntryImpl(
    journal: SQLiteJournal,
    severity: Int16,
    note: String?,
    timestamp: Date,
    isMenstruating: Bool,
    database: any DatabaseWriter,
    logger: Logger
) throws -> SQLiteSymptomEntry {
    ensureJournalCloudMetadata(
        journalID: journal.id,
        database: database, logger: logger
    )
    let entry = SQLiteSymptomEntry(
        timestamp: timestamp,
        journalID: journal.id,
        severity: severity,
        isMenstruating: isMenstruating,
        note: note
    )
    do {
        try database.write { db in
            try SQLiteSymptomEntry
                .insert { entry }.execute(db)
        }
        logger.info(
            "Created entry for journal: \(journal.id)"
        )
        return entry
    } catch {
        logger.error(
            "Error creating entry: \(error.localizedDescription)"
        )
        throw error
    }
}

// MARK: - Symptom Entry Operations (Update & Delete)

func assignEntryMutateOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.updateSymptomEntry = { entry in
        ensureJournalCloudMetadata(
            journalID: entry.journalID,
            database: database, logger: logger
        )
        do {
            try database.write { db in
                try SQLiteSymptomEntry.update(entry).execute(db)
            }
            logger.info("Updated symptom entry: \(entry.id)")
        } catch {
            logger.error(
                "Error updating entry \(entry.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    client.deleteSymptomEntry = { entryID in
        try deleteSymptomEntryImpl(
            entryID, database: database, logger: logger
        )
    }
}

private func deleteSymptomEntryImpl(
    _ entryID: UUID,
    database: any DatabaseWriter,
    logger: Logger
) throws {
    // Belt-and-suspenders: ON DELETE SET NULL handles this at
    // the schema level; manual cleanup retained for defense
    // in depth.
    do {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE sqLiteMedicationIntake
                    SET entryID = NULL
                    WHERE lower(entryID) = lower(?)
                """,
                arguments: [entryID.uuidString]
            )
            try db.execute(
                sql: """
                    UPDATE sqLiteCollaboratorNote
                    SET entryID = NULL
                    WHERE lower(entryID) = lower(?)
                """,
                arguments: [entryID.uuidString]
            )
            try SQLiteSymptomEntry
                .find(entryID).delete().execute(db)
        }
        logger.info("Deleted symptom entry: \(entryID)")
    } catch {
        logger.error(
            "Error deleting entry \(entryID): \(error.localizedDescription)"
        )
        throw error
    }
}
