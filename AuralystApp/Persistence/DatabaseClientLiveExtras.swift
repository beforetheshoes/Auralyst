import Dependencies
import Foundation
import GRDB
import os.log
@preconcurrency import SQLiteData

// MARK: - Collaborator Note Operations

func assignNoteOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.createCollaboratorNote = { journal, entry, authorName, text in
        ensureJournalCloudMetadata(
            journalID: journal.id,
            database: database, logger: logger
        )
        let note = SQLiteCollaboratorNote(
            journalID: journal.id,
            entryID: entry?.id,
            authorName: authorName,
            text: text
        )
        do {
            try database.write { db in
                try SQLiteCollaboratorNote
                    .insert { note }.execute(db)
            }
            logger.info(
                "Created note for journal: \(journal.id)"
            )
            return note
        } catch {
            logger.error(
                "Error creating note: \(error.localizedDescription)"
            )
            throw error
        }
    }
}

// MARK: - Medication Operations

func assignMedOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.deleteMedication = { medicationID in
        try deleteMedicationImpl(
            medicationID, database: database, logger: logger
        )
    }

    client.createMedication = { journal, name, defaultAmount, defaultUnit in
        createMedicationImpl(
            journal: journal, name: name,
            defaultAmount: defaultAmount, defaultUnit: defaultUnit,
            database: database, logger: logger
        )
    }

    client.loadMedicationForEditor = { medicationID in
        do {
            let result = try database.read { db in
                try loadMedication(medicationID, from: db)
            }
            logger.info(
                "Loaded medication for editor: \(medicationID)"
            )
            return result
        } catch {
            logger.error(
                "Error loading medication for editor \(medicationID): \(error.localizedDescription)"
            )
            throw error
        }
    }

    client.saveMedicationFromEditor = { snapshot in
        try saveMedicationFromEditorImpl(
            snapshot: snapshot, database: database, logger: logger
        )
    }

    client.fetchMedications = { journal in
        do {
            let meds = try database.read { db in
                try SQLiteMedication
                    .where { $0.journalID.eq(journal.id) }
                    .order { $0.name.asc() }
                    .fetchAll(db)
            }
            logger.info("Fetched \(meds.count) medications")
            return meds
        } catch {
            logger.error(
                "Error fetching medications: \(error.localizedDescription)"
            )
            return []
        }
    }
}

// swiftlint:disable:next function_parameter_count
private func createMedicationImpl(
    journal: SQLiteJournal,
    name: String,
    defaultAmount: Double?,
    defaultUnit: String?,
    database: any DatabaseWriter,
    logger: Logger
) -> SQLiteMedication {
    ensureJournalCloudMetadata(
        journalID: journal.id,
        database: database, logger: logger
    )
    let medication = SQLiteMedication(
        journalID: journal.id,
        name: name,
        defaultAmount: defaultAmount,
        defaultUnit: defaultUnit
    )
    do {
        try database.write { db in
            try SQLiteMedication
                .insert { medication }.execute(db)
        }
        logger.info("Created medication: \(name)")
        return medication
    } catch {
        logger.error(
            "Error creating medication: \(error.localizedDescription)"
        )
        return medication
    }
}

private func saveMedicationFromEditorImpl(
    snapshot: MedicationEditorSnapshot,
    database: any DatabaseWriter,
    logger: Logger
) throws {
    do {
        try database.write { db in
            let amountValue = Double(snapshot.defaultAmount)
            let unitValue = snapshot.defaultUnit.isEmpty ? nil : snapshot.defaultUnit
            let notesValue = snapshot.notes.isEmpty ? nil : snapshot.notes
            let useCaseValue = snapshot.useCase.isEmpty ? nil : snapshot.useCase
            let now = Date()

            let medicationID = try upsertMedication(
                in: db,
                params: MedicationUpsertParams(
                    journalID: snapshot.journalID,
                    medicationID: snapshot.medicationID,
                    name: snapshot.name,
                    amount: amountValue,
                    unit: unitValue,
                    isAsNeeded: snapshot.isAsNeeded,
                    useCase: useCaseValue,
                    notes: notesValue,
                    timestamp: now
                )
            )

            var drafts = snapshot.scheduleDrafts
            try syncSchedules(
                in: db, medicationID: medicationID,
                drafts: &drafts
            )
        }
        logger.info("Saved medication from editor")
    } catch {
        logger.error(
            "Error saving medication from editor: \(error.localizedDescription)"
        )
        throw error
    }
}

private func deleteMedicationImpl(
    _ medicationID: UUID,
    database: any DatabaseWriter,
    logger: Logger
) throws {
    do {
        // Belt-and-suspenders: ON DELETE CASCADE handles this at
        // the schema level; manual cleanup retained for defense
        // in depth.
        try database.write { db in
            try SQLiteMedicationSchedule
                .where { $0.medicationID.eq(medicationID) }
                .delete()
                .execute(db)
            try SQLiteMedicationIntake
                .where { $0.medicationID.eq(medicationID) }
                .delete()
                .execute(db)
            try SQLiteMedication
                .find(medicationID).delete().execute(db)
        }
        logger.info("Deleted medication: \(medicationID)")
    } catch {
        logger.error(
            "Error deleting medication \(medicationID): \(error.localizedDescription)"
        )
        throw error
    }
}

// MARK: - Medication Intake Create & Read

func assignIntakeCreateOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.createMedicationIntake = { medication, amount, unit in
        ensureJournalCloudMetadata(
            journalID: medication.journalID,
            database: database, logger: logger
        )
        let intake = SQLiteMedicationIntake(
            medicationID: medication.id,
            amount: amount,
            unit: unit
        )
        do {
            try database.write { db in
                try SQLiteMedicationIntake
                    .insert { intake }.execute(db)
            }
            logger.info(
                "Created intake for: \(medication.id)"
            )
            return intake
        } catch {
            logger.error(
                "Error creating intake: \(error.localizedDescription)"
            )
            throw error
        }
    }

    client.createAsNeededIntake = { intake in
        try createAsNeededIntakeImpl(
            intake, database: database, logger: logger
        )
    }

    client.fetchMedicationIntake = { id in
        do {
            let intake = try database.read { db in
                try SQLiteMedicationIntake
                    .find(id).fetchOne(db)
            }
            logger.info("Fetched intake: \(id)")
            return intake
        } catch {
            logger.error(
                "Error fetching intake \(id): \(error.localizedDescription)"
            )
            return nil
        }
    }
}

private func createAsNeededIntakeImpl(
    _ intake: SQLiteMedicationIntake,
    database: any DatabaseWriter,
    logger: Logger
) throws {
    do {
        try database.write { db in
            try SQLiteMedicationIntake
                .insert { intake }.execute(db)
        }
        logger.info(
            "Created as-needed intake for: \(intake.medicationID)"
        )
    } catch {
        logger.error(
            "Error creating as-needed intake: \(error.localizedDescription)"
        )
        throw error
    }
}

// MARK: - Medication Intake Update & Delete

func assignIntakeMutateOps(
    to client: inout DatabaseClient,
    database: any DatabaseWriter,
    logger: Logger
) {
    client.updateMedicationIntake = { intake in
        do {
            try database.write { db in
                let record: SQLiteMedicationIntake
                if let existing = try SQLiteMedicationIntake
                    .find(intake.id).fetchOne(db) {
                    record = existing.mergingEditableFields(
                        amount: intake.amount,
                        unit: intake.unit,
                        timestamp: intake.timestamp,
                        notes: intake.notes
                    )
                } else {
                    record = intake
                }
                try SQLiteMedicationIntake
                    .update(record).execute(db)
            }
            logger.info("Updated intake: \(intake.id)")
        } catch {
            logger.error(
                "Error updating intake \(intake.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    client.deleteMedicationIntake = { intake in
        do {
            try database.write { db in
                try SQLiteMedicationIntake
                    .find(intake.id).delete().execute(db)
            }
            logger.info("Deleted intake: \(intake.id)")
        } catch {
            logger.error(
                "Error deleting intake \(intake.id): \(error.localizedDescription)"
            )
            throw error
        }
    }
}
