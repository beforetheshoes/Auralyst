import Dependencies
import GRDB
import os.log
@preconcurrency import SQLiteData
import XCTest
@testable import AuralystApp

@MainActor
final class TestDependencyBootstrapTests: XCTestCase {
    func testBootstrapConfiguresPreviewSyncEngine() async throws {
        let wasConfigured = LockIsolated(false)
        let startCount = LockIsolated(0)

        try prepareTestDependencies(configureSyncEngine: true) { dependencies in
            wasConfigured.withValue { $0 = true }
            dependencies.syncEngine = SyncEngineClient(
                start: {
                    startCount.withValue { $0 += 1 }
                },
                stop: {},
                shareJournal: { _, _ in throw SyncEngineClientError.previewUnavailable }
            )
        }

        let store = DataStore()
        let journal = try store.createJournal()

        try await DependencyValues._current.syncEngine.start()

        do {
            _ = try await DependencyValues._current.syncEngine.shareJournal(journal) { _ in }
            XCTFail("Expected preview sync engine to throw previewUnavailable")
        } catch let error as SyncEngineClientError {
            XCTAssertEqual(error, .previewUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertTrue(wasConfigured.value)
        XCTAssertEqual(startCount.value, 1)
    }

    func testAllExpectedTablesAreRegisteredForSync() throws {
        try prepareTestDependencies(configureSyncEngine: true)

        @Dependency(\.defaultDatabase) var database

        let registeredTables = try database.read { db in
            try SQLiteDataRecordTypeRow.fetchAll(db).map(\.tableName)
        }

        let expectedTables: Set<String> = [
            SQLiteJournal.tableName,
            SQLiteSymptomEntry.tableName,
            SQLiteMedication.tableName,
            SQLiteMedicationIntake.tableName,
            SQLiteCollaboratorNote.tableName,
            SQLiteMedicationSchedule.tableName
        ]

        XCTAssertEqual(Set(registeredTables), expectedTables)
    }
}

private struct SQLiteDataRecordTypeRow: FetchableRecord, TableRecord {
    static let databaseTableName = "sqlitedata_icloud_recordTypes"

    let tableName: String

    init(row: Row) {
        tableName = row["tableName"]
    }
}

@MainActor
func prepareTestDependencies(
    configureSyncEngine: Bool = false,
    _ configure: (inout DependencyValues) throws -> Void = { _ in }
) throws {
    try prepareDependencies {
        try $0.bootstrapDatabase(configureSyncEngine: configureSyncEngine)
        $0.databaseClient = buildTestDatabaseClient(
            database: $0.defaultDatabase
        )
        $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        $0.continuousClock = ContinuousClock()
        $0.syncEngine = SyncEngineClient(
            start: {},
            stop: {},
            shareJournal: { _, _ in throw SyncEngineClientError.previewUnavailable }
        )
        try configure(&$0)
    }
}

func buildTestDatabaseClient(
    database: any DatabaseWriter
) -> DatabaseClient {
    let logger = Logger(
        subsystem: "com.yourteam.Auralyst",
        category: "DatabaseClient.test"
    )
    var client = DatabaseClient.stub
    assignJournalOps(to: &client, database: database, logger: logger)
    assignEntryCreateOps(to: &client, database: database, logger: logger)
    assignEntryMutateOps(to: &client, database: database, logger: logger)
    assignNoteOps(to: &client, database: database, logger: logger)
    assignMedOps(to: &client, database: database, logger: logger)
    assignIntakeCreateOps(to: &client, database: database, logger: logger)
    assignIntakeMutateOps(to: &client, database: database, logger: logger)

    return client
}
