import Foundation
import SQLiteData
import os.log
import Dependencies
import Observation

// Data access layer providing convenient methods for database operations
@Observable
@MainActor
final class DataStore {
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    private let logger = Logger(subsystem: "com.yourteam.Auralyst", category: "DataStore")

    // Dependencies provide the database; no manual injection needed.

    // MARK: - Journal Operations

    func createJournal() -> SQLiteJournal {
        do {
            let journal = SQLiteJournal()
            try database.write { db in
                try SQLiteJournal.insert { journal }.execute(db)
            }
            if let fetched = try database.read({ db in try SQLiteJournal.find(journal.id).fetchOne(db) }) {
                logger.info("Created journal with ID: \(journal.id)")
                return fetched
            } else {
                logger.error("Failed to fetch created journal with ID: \(journal.id)")
                return journal
            }
        } catch {
            logger.error("Error creating journal: \(error.localizedDescription)")
            return SQLiteJournal()
        }
    }

    func fetchJournals() -> [SQLiteJournal] {
        do {
            let journals = try database.read { db in try SQLiteJournal.all.fetchAll(db) }
            logger.info("Fetched \(journals.count) journals")
            return journals
        } catch {
            logger.error("Error fetching journals: \(error.localizedDescription)")
            return []
        }
    }

    func fetchJournal(id: UUID) -> SQLiteJournal? {
        do {
            let journal = try database.read { db in try SQLiteJournal.find(id).fetchOne(db) }
            logger.info("Fetched journal: \(id)")
            return journal
        } catch {
            logger.error("Error fetching journal \(id): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Symptom Entry Operations

    func createSymptomEntry(for journal: SQLiteJournal, severity: Int16, note: String? = nil, timestamp: Date = .now, isMenstruating: Bool = false) throws -> SQLiteSymptomEntry {
        let entry = SQLiteSymptomEntry(
            timestamp: timestamp,
            journalID: journal.id,
            severity: severity,
            isMenstruating: isMenstruating,
            note: note
        )
        do {
            try database.write { db in
                try SQLiteSymptomEntry.insert { entry }.execute(db)
            }
            logger.info("Created symptom entry for journal: \(journal.id)")
            return entry
        } catch {
            logger.error("Error creating symptom entry: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchSymptomEntry(id: UUID) -> SQLiteSymptomEntry? {
        do {
            let entry = try database.read { db in try SQLiteSymptomEntry.find(id).fetchOne(db) }
            logger.info("Fetched symptom entry: \(id)")
            return entry
        } catch {
            logger.error("Error fetching symptom entry \(id): \(error.localizedDescription)")
            return nil
        }
    }

    func fetchSymptomEntries(for journal: SQLiteJournal) throws -> [SQLiteSymptomEntry] {
        do {
            let entries = try database.read { db in
                try SQLiteSymptomEntry
                    .where { $0.journalID == journal.id }
                    .order { $0.timestamp.desc() }
                    .fetchAll(db)
            }
            logger.info("Fetched \(entries.count) symptom entries for journal: \(journal.id)")
            return entries
        } catch {
            logger.error("Error fetching symptom entries for journal \(journal.id): \(error.localizedDescription)")
            throw error
        }
    }

    func updateSymptomEntry(_ entry: SQLiteSymptomEntry) throws {
        do {
            try database.write { db in
                try SQLiteSymptomEntry.update(entry).execute(db)
            }
            logger.info("Updated symptom entry: \(entry.id)")
        } catch {
            logger.error("Error updating symptom entry \(entry.id): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Collaborator Note Operations

    func createCollaboratorNote(for journal: SQLiteJournal, entry: SQLiteSymptomEntry? = nil, authorName: String? = nil, text: String) throws -> SQLiteCollaboratorNote {
        let note = SQLiteCollaboratorNote(
            journalID: journal.id,
            entryID: entry?.id,
            authorName: authorName,
            text: text
        )
        do {
            try database.write { db in
                try SQLiteCollaboratorNote.insert { note }.execute(db)
            }
            logger.info("Created collaborator note for journal: \(journal.id)")
            return note
        } catch {
            logger.error("Error creating collaborator note: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Medication Operations

    func createMedication(for journal: SQLiteJournal, name: String, defaultAmount: Double? = nil, defaultUnit: String? = nil) -> SQLiteMedication {
        let medication = SQLiteMedication(
            journalID: journal.id,
            name: name,
            defaultAmount: defaultAmount,
            defaultUnit: defaultUnit
        )
        do {
            try database.write { db in
                try SQLiteMedication.insert { medication }.execute(db)
            }
            logger.info("Created medication: \(name) for journal: \(journal.id)")
            return medication
        } catch {
            logger.error("Error creating medication \(name): \(error.localizedDescription)")
            return medication
        }
    }

    func fetchMedications(for journal: SQLiteJournal) -> [SQLiteMedication] {
        do {
            let meds = try database.read { db in
                try SQLiteMedication
                    .where { $0.journalID == journal.id }
                    .order { $0.name.asc() }
                    .fetchAll(db)
            }
            logger.info("Fetched \(meds.count) medications for journal: \(journal.id)")
            return meds
        } catch {
            logger.error("Error fetching medications for journal \(journal.id): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Medication Intake Operations

    func createMedicationIntake(for medication: SQLiteMedication, amount: Double? = nil, unit: String? = nil) throws -> SQLiteMedicationIntake {
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: amount,
            unit: unit
        )
        do {
            try database.write { db in
                try SQLiteMedicationIntake.insert { intake }.execute(db)
            }
            logger.info("Created medication intake for medication: \(medication.id)")
            return intake
        } catch {
            logger.error("Error creating medication intake: \(error.localizedDescription)")
            throw error
        }
    }

    func fetchMedicationIntake(id: UUID) -> SQLiteMedicationIntake? {
        do {
            let intake = try database.read { db in try SQLiteMedicationIntake.find(id).fetchOne(db) }
            logger.info("Fetched medication intake: \(id)")
            return intake
        } catch {
            logger.error("Error fetching medication intake \(id): \(error.localizedDescription)")
            return nil
        }
    }

    func updateMedicationIntake(_ intake: SQLiteMedicationIntake) throws {
        do {
            try database.write { db in
                try SQLiteMedicationIntake.update(intake).execute(db)
            }
            logger.info("Updated medication intake: \(intake.id)")
        } catch {
            logger.error("Error updating medication intake \(intake.id): \(error.localizedDescription)")
            throw error
        }
    }

    func deleteMedicationIntake(_ intake: SQLiteMedicationIntake) throws {
        do {
            try database.write { db in
                try SQLiteMedicationIntake.find(intake.id).delete().execute(db)
            }
            logger.info("Deleted medication intake: \(intake.id)")
        } catch {
            logger.error("Error deleting medication intake \(intake.id): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - CloudKit Sync

    @ObservationIgnored
    @Dependency(\.defaultSyncEngine) private var syncEngine

    func startSync() async throws {
        try await syncEngine.start()
    }

    func stopSync() {
        syncEngine.stop()
    }
}
