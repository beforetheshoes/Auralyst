import Foundation
import Dependencies
import GRDB
import os.log
@preconcurrency import SQLiteData

struct DatabaseClient: Sendable {
    var createJournal: @Sendable () throws -> SQLiteJournal
    var fetchJournals: @Sendable () -> [SQLiteJournal]
    var fetchJournal: @Sendable (_ id: UUID) -> SQLiteJournal?
    var createSymptomEntry: @Sendable (
        _ journal: SQLiteJournal, _ severity: Int16, _ note: String?,
        _ timestamp: Date, _ isMenstruating: Bool
    ) throws -> SQLiteSymptomEntry
    var fetchSymptomEntry: @Sendable (_ id: UUID) -> SQLiteSymptomEntry?
    var fetchSymptomEntries: @Sendable (
        _ journal: SQLiteJournal
    ) throws -> [SQLiteSymptomEntry]
    var updateSymptomEntry: @Sendable (
        _ entry: SQLiteSymptomEntry
    ) throws -> Void
    var deleteSymptomEntry: @Sendable (_ id: UUID) throws -> Void
    var createCollaboratorNote: @Sendable (
        _ journal: SQLiteJournal, _ entry: SQLiteSymptomEntry?,
        _ authorName: String?, _ text: String
    ) throws -> SQLiteCollaboratorNote
    var deleteMedication: @Sendable (_ medicationID: UUID) throws -> Void
    var createMedication: @Sendable (
        _ journal: SQLiteJournal, _ name: String,
        _ defaultAmount: Double?, _ defaultUnit: String?
    ) -> SQLiteMedication
    var fetchMedications: @Sendable (
        _ journal: SQLiteJournal
    ) -> [SQLiteMedication]
    var createMedicationIntake: @Sendable (
        _ medication: SQLiteMedication,
        _ amount: Double?, _ unit: String?
    ) throws -> SQLiteMedicationIntake
    var fetchMedicationIntake: @Sendable (
        _ id: UUID
    ) -> SQLiteMedicationIntake?
    var updateMedicationIntake: @Sendable (
        _ intake: SQLiteMedicationIntake
    ) throws -> Void
    var deleteMedicationIntake: @Sendable (
        _ intake: SQLiteMedicationIntake
    ) throws -> Void

    static let stub = DatabaseClient(
        createJournal: { SQLiteJournal() },
        fetchJournals: { [] },
        fetchJournal: { _ in nil },
        createSymptomEntry: { _, _, _, _, _ in
            throw StubError.notImplemented
        },
        fetchSymptomEntry: { _ in nil },
        fetchSymptomEntries: { _ in [] },
        updateSymptomEntry: { _ in },
        deleteSymptomEntry: { _ in },
        createCollaboratorNote: { _, _, _, _ in
            throw StubError.notImplemented
        },
        deleteMedication: { _ in },
        createMedication: { journal, name, _, _ in
            SQLiteMedication(journalID: journal.id, name: name)
        },
        fetchMedications: { _ in [] },
        createMedicationIntake: { _, _, _ in
            throw StubError.notImplemented
        },
        fetchMedicationIntake: { _ in nil },
        updateMedicationIntake: { _ in },
        deleteMedicationIntake: { _ in }
    )

    private enum StubError: Error {
        case notImplemented
    }
}

private enum DatabaseClientKey: DependencyKey {
    static let liveValue: DatabaseClient = makeLiveClient()
    static let testValue: DatabaseClient = makeTestClient()
    static let previewValue: DatabaseClient = liveValue
}

extension DependencyValues {
    var databaseClient: DatabaseClient {
        get { self[DatabaseClientKey.self] }
        set { self[DatabaseClientKey.self] = newValue }
    }
}

private func makeLiveClient() -> DatabaseClient {
    @Dependency(\.defaultDatabase) var database
    let logger = Logger(
        subsystem: "com.yourteam.Auralyst",
        category: "DatabaseClient"
    )

    var client = DatabaseClient.stub
    assignJournalOps(
        to: &client, database: database, logger: logger
    )
    assignEntryCreateOps(
        to: &client, database: database, logger: logger
    )
    assignEntryMutateOps(
        to: &client, database: database, logger: logger
    )
    assignNoteOps(
        to: &client, database: database, logger: logger
    )
    assignMedOps(
        to: &client, database: database, logger: logger
    )
    assignIntakeCreateOps(
        to: &client, database: database, logger: logger
    )
    assignIntakeMutateOps(
        to: &client, database: database, logger: logger
    )
    return client
}

private func makeTestClient() -> DatabaseClient {
    @Dependency(\.defaultDatabase) var database
    let logger = Logger(
        subsystem: "com.yourteam.Auralyst",
        category: "DatabaseClient"
    )
    var client = makeLiveClient()

    client.fetchMedicationIntake = { id in
        do {
            let intake = try database.read { db in
                try SQLiteMedicationIntake.find(id).fetchOne(db)
            }
            logger.info("Fetched medication intake (test): \(id)")
            return intake
        } catch {
            logger.error(
                "Error fetching intake (test) \(id): \(error.localizedDescription)"
            )
            return nil
        }
    }

    client.updateMedicationIntake = { intake in
        do {
            try database.write { db in
                if let existing = try SQLiteMedicationIntake
                    .find(intake.id).fetchOne(db) {
                    let merged = existing.mergingEditableFields(
                        amount: intake.amount,
                        unit: intake.unit,
                        timestamp: intake.timestamp,
                        notes: intake.notes
                    )
                    try SQLiteMedicationIntake
                        .update(merged).execute(db)
                } else {
                    try SQLiteMedicationIntake
                        .insert { intake }.execute(db)
                }
            }
            logger.info(
                "Updated medication intake (test): \(intake.id)"
            )
        } catch {
            logger.error(
                "Error updating intake (test) \(intake.id): \(error.localizedDescription)"
            )
            throw error
        }
    }

    return client
}
