import Foundation
import Dependencies
import GRDB
import os.log
@preconcurrency import SQLiteData

struct DatabaseClient: Sendable {
    var createJournal: @Sendable () -> SQLiteJournal
    var fetchJournals: @Sendable () -> [SQLiteJournal]
    var fetchJournal: @Sendable (_ id: UUID) -> SQLiteJournal?
    var createSymptomEntry: @Sendable (_ journal: SQLiteJournal, _ severity: Int16, _ note: String?, _ timestamp: Date, _ isMenstruating: Bool) throws -> SQLiteSymptomEntry
    var fetchSymptomEntry: @Sendable (_ id: UUID) -> SQLiteSymptomEntry?
    var fetchSymptomEntries: @Sendable (_ journal: SQLiteJournal) throws -> [SQLiteSymptomEntry]
    var updateSymptomEntry: @Sendable (_ entry: SQLiteSymptomEntry) throws -> Void
    var createCollaboratorNote: @Sendable (_ journal: SQLiteJournal, _ entry: SQLiteSymptomEntry?, _ authorName: String?, _ text: String) throws -> SQLiteCollaboratorNote
    var deleteMedication: @Sendable (_ medicationID: UUID) throws -> Void
    var createMedication: @Sendable (_ journal: SQLiteJournal, _ name: String, _ defaultAmount: Double?, _ defaultUnit: String?) -> SQLiteMedication
    var fetchMedications: @Sendable (_ journal: SQLiteJournal) -> [SQLiteMedication]
    var createMedicationIntake: @Sendable (_ medication: SQLiteMedication, _ amount: Double?, _ unit: String?) throws -> SQLiteMedicationIntake
    var fetchMedicationIntake: @Sendable (_ id: UUID) -> SQLiteMedicationIntake?
    var updateMedicationIntake: @Sendable (_ intake: SQLiteMedicationIntake) throws -> Void
    var deleteMedicationIntake: @Sendable (_ intake: SQLiteMedicationIntake) throws -> Void
}

private enum DatabaseClientKey: DependencyKey {
    static let liveValue: DatabaseClient = {
        @Dependency(\.defaultDatabase) var database
        let logger = Logger(subsystem: "com.yourteam.Auralyst", category: "DatabaseClient")

        return DatabaseClient(
            createJournal: {
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
            },
            fetchJournals: {
                do {
                    let journals = try database.read { db in try SQLiteJournal.all.fetchAll(db) }
                    logger.info("Fetched \(journals.count) journals")
                    return journals
                } catch {
                    logger.error("Error fetching journals: \(error.localizedDescription)")
                    return []
                }
            },
            fetchJournal: { id in
                do {
                    let journal = try database.read { db in try SQLiteJournal.find(id).fetchOne(db) }
                    logger.info("Fetched journal: \(id)")
                    return journal
                } catch {
                    logger.error("Error fetching journal \(id): \(error.localizedDescription)")
                    return nil
                }
            },
            createSymptomEntry: { journal, severity, note, timestamp, isMenstruating in
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
            },
            fetchSymptomEntry: { id in
                do {
                    let entry = try database.read { db in try SQLiteSymptomEntry.find(id).fetchOne(db) }
                    logger.info("Fetched symptom entry: \(id)")
                    return entry
                } catch {
                    logger.error("Error fetching symptom entry \(id): \(error.localizedDescription)")
                    return nil
                }
            },
            fetchSymptomEntries: { journal in
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
            },
            updateSymptomEntry: { entry in
                do {
                    try database.write { db in
                        try SQLiteSymptomEntry.update(entry).execute(db)
                    }
                    logger.info("Updated symptom entry: \(entry.id)")
                } catch {
                    logger.error("Error updating symptom entry \(entry.id): \(error.localizedDescription)")
                    throw error
                }
            },
            createCollaboratorNote: { journal, entry, authorName, text in
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
            },
            deleteMedication: { medicationID in
                do {
                    try database.write { db in
                        try SQLiteMedicationSchedule
                            .where { $0.medicationID == medicationID }
                            .delete()
                            .execute(db)
                        try SQLiteMedicationIntake
                            .where { $0.medicationID == medicationID }
                            .delete()
                            .execute(db)
                        try SQLiteMedication.find(medicationID).delete().execute(db)
                    }
                    logger.info("Deleted medication: \(medicationID)")
                } catch {
                    logger.error("Error deleting medication \(medicationID): \(error.localizedDescription)")
                    throw error
                }
            },
            createMedication: { journal, name, defaultAmount, defaultUnit in
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
            },
            fetchMedications: { journal in
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
            },
            createMedicationIntake: { medication, amount, unit in
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
            },
            fetchMedicationIntake: { id in
                do {
                    let intake = try database.read { db in try SQLiteMedicationIntake.find(id).fetchOne(db) }
                    logger.info("Fetched medication intake: \(id)")
                    return intake
                } catch {
                    logger.error("Error fetching medication intake \(id): \(error.localizedDescription)")
                    return nil
                }
            },
            updateMedicationIntake: { intake in
                do {
                    try database.write { db in
                        let recordToPersist: SQLiteMedicationIntake
                        if let existing = try SQLiteMedicationIntake.find(intake.id).fetchOne(db) {
                            recordToPersist = existing.mergingEditableFields(
                                amount: intake.amount,
                                unit: intake.unit,
                                timestamp: intake.timestamp,
                                notes: intake.notes
                            )
                        } else {
                            recordToPersist = intake
                        }

                        try SQLiteMedicationIntake.update(recordToPersist).execute(db)
                    }
                    logger.info("Updated medication intake: \(intake.id)")
                } catch {
                    logger.error("Error updating medication intake \(intake.id): \(error.localizedDescription)")
                    throw error
                }
            },
            deleteMedicationIntake: { intake in
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
        )
    }()
    static let testValue: DatabaseClient = {
        @Dependency(\.defaultDatabase) var database
        let logger = Logger(subsystem: "com.yourteam.Auralyst", category: "DatabaseClient")
        var client = liveValue

        client.fetchMedicationIntake = { id in
            do {
                let intake = try database.read { db in try SQLiteMedicationIntake.find(id).fetchOne(db) }
                logger.info("Fetched medication intake (test): \(id)")
                return intake
            } catch {
                logger.error("Error fetching medication intake (test) \(id): \(error.localizedDescription)")
                return nil
            }
        }

        client.updateMedicationIntake = { intake in
            do {
                try database.write { db in
                    if let existing = try SQLiteMedicationIntake.find(intake.id).fetchOne(db) {
                        let recordToPersist = existing.mergingEditableFields(
                            amount: intake.amount,
                            unit: intake.unit,
                            timestamp: intake.timestamp,
                            notes: intake.notes
                        )
                        try SQLiteMedicationIntake.update(recordToPersist).execute(db)
                    } else {
                        try SQLiteMedicationIntake.insert { intake }.execute(db)
                    }
                }
                logger.info("Updated medication intake (test): \(intake.id)")
            } catch {
                logger.error("Error updating medication intake (test) \(intake.id): \(error.localizedDescription)")
                throw error
            }
        }

        return client
    }()
    static let previewValue: DatabaseClient = liveValue
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClientKey.self] }
        set { self[DatabaseClientKey.self] = newValue }
    }
}
