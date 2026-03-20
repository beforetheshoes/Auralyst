import Foundation
import Dependencies
import Observation
@preconcurrency import SQLiteData

// Data access layer providing convenient methods for database operations
@MainActor
final class DataStore: Observable {
    @ObservationIgnored
    @Dependency(\.databaseClient) private var databaseClient
    @ObservationIgnored
    private let _observationRegistrar = ObservationRegistrar()

    // MARK: - Observation

    nonisolated func access<Member>(_ keyPath: KeyPath<DataStore, Member>) {
        _observationRegistrar.access(self, keyPath: keyPath)
    }

    nonisolated func withMutation<Member, MutationResult>(
        of keyPath: KeyPath<DataStore, Member>,
        _ mutation: () throws -> MutationResult
    ) rethrows -> MutationResult {
        try _observationRegistrar.withMutation(of: self, keyPath: keyPath, mutation)
    }

    // MARK: - Journal Operations

    func createJournal() throws -> SQLiteJournal {
        try databaseClient.createJournal()
    }

    func fetchJournals() -> [SQLiteJournal] {
        databaseClient.fetchJournals()
    }

    func fetchJournal(id: UUID) -> SQLiteJournal? {
        databaseClient.fetchJournal(id)
    }

    // MARK: - Symptom Entry Operations

    func createSymptomEntry(
        for journal: SQLiteJournal,
        severity: Int16,
        note: String? = nil,
        timestamp: Date = .now,
        isMenstruating: Bool = false
    ) throws -> SQLiteSymptomEntry {
        try databaseClient.createSymptomEntry(
            journal, severity, note, timestamp, isMenstruating
        )
    }

    func fetchSymptomEntry(id: UUID) -> SQLiteSymptomEntry? {
        databaseClient.fetchSymptomEntry(id)
    }

    func fetchSymptomEntries(for journal: SQLiteJournal) throws -> [SQLiteSymptomEntry] {
        try databaseClient.fetchSymptomEntries(journal)
    }

    func updateSymptomEntry(_ entry: SQLiteSymptomEntry) throws {
        try databaseClient.updateSymptomEntry(entry)
    }

    func deleteSymptomEntry(id: UUID) throws {
        try databaseClient.deleteSymptomEntry(id)
    }

    // MARK: - Collaborator Note Operations

    func createCollaboratorNote(
        for journal: SQLiteJournal,
        entry: SQLiteSymptomEntry? = nil,
        authorName: String? = nil,
        text: String
    ) throws -> SQLiteCollaboratorNote {
        try databaseClient.createCollaboratorNote(
            journal, entry, authorName, text
        )
    }

    // MARK: - Medication Operations

    func deleteMedication(_ medicationID: UUID) throws {
        try databaseClient.deleteMedication(medicationID)
    }

    func createMedication(
        for journal: SQLiteJournal,
        name: String,
        defaultAmount: Double? = nil,
        defaultUnit: String? = nil
    ) -> SQLiteMedication {
        databaseClient.createMedication(
            journal, name, defaultAmount, defaultUnit
        )
    }

    func fetchMedications(for journal: SQLiteJournal) -> [SQLiteMedication] {
        databaseClient.fetchMedications(journal)
    }

    // MARK: - Medication Intake Operations

    func createMedicationIntake(
        for medication: SQLiteMedication,
        amount: Double? = nil,
        unit: String? = nil
    ) throws -> SQLiteMedicationIntake {
        try databaseClient.createMedicationIntake(
            medication, amount, unit
        )
    }

    func fetchMedicationIntake(id: UUID) -> SQLiteMedicationIntake? {
        databaseClient.fetchMedicationIntake(id)
    }

    func updateMedicationIntake(_ intake: SQLiteMedicationIntake) throws {
        try databaseClient.updateMedicationIntake(intake)
    }

    func deleteMedicationIntake(_ intake: SQLiteMedicationIntake) throws {
        try databaseClient.deleteMedicationIntake(intake)
    }

}
