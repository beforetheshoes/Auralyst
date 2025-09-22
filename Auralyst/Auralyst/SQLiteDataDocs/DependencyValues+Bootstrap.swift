import SQLiteData
import Dependencies

extension DependencyValues {
    mutating func bootstrapDatabase() throws {
        defaultDatabase = try appDatabase()
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
    }
}
