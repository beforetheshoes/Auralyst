import Dependencies
@preconcurrency import SQLiteData
import XCTest
@testable import AuralystApp

@MainActor
final class TestDependencyBootstrapTests: XCTestCase {
    func testBootstrapConfiguresPreviewSyncEngine() async throws {
        let wasConfigured = LockIsolated(false)
        let startCount = LockIsolated(0)

        try prepareTestDependencies { dependencies in
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
        let journal = store.createJournal()

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
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database

        let registeredTables = try database.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT \"tableName\" FROM \"sqlitedata_icloud_recordTypes\""
            )
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

@MainActor
func prepareTestDependencies(_ configure: (inout DependencyValues) throws -> Void = { _ in }) throws {
    try prepareDependencies {
        try $0.bootstrapDatabase(configureSyncEngine: true)
        $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
        $0.syncEngine = SyncEngineClient(
            start: {},
            stop: {},
            shareJournal: { _, _ in throw SyncEngineClientError.previewUnavailable }
        )
        try configure(&$0)
    }
}
