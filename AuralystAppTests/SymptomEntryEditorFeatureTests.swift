import Foundation
import GRDB
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Symptom entry editor feature", .serialized)
struct SymptomEntryEditorFeatureTests {
    @MainActor
    @Test("Task loads existing entry into state")
    func taskLoadsEntry() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 7, note: "Headache",
            isMenstruating: true
        )

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        #expect(testStore.state.entry != nil)
        #expect(testStore.state.severity == Int(entry.severity))
        #expect(testStore.state.isMenstruating == (entry.isMenstruating ?? false))
        #expect(testStore.state.note == (entry.note ?? ""))
    }

    @MainActor
    @Test("Task with missing entry sets error")
    func taskMissingEntrySetsError() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: UUID())
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.task)

        await testStore.receive(\.loadResponse) {
            $0.entry = nil
            $0.errorMessage = "Unable to load entry."
        }
    }

    @MainActor
    @Test("saveTapped updates entry through DatabaseClient")
    func saveTappedUpdatesEntry() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 5, note: "Original",
            isMenstruating: false
        )

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        // Modify fields via binding actions
        await testStore.send(\.binding.severity, 9)
        await testStore.send(\.binding.note, "Updated note")
        await testStore.send(\.binding.isMenstruating, true)

        await testStore.send(.saveTapped)

        await testStore.receive(\.saveResponse.success) {
            $0.didFinish = true
        }

        // Verify DB was updated
        @Dependency(\.defaultDatabase) var database
        let updatedCount = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT "severity" FROM "sqLiteSymptomEntry"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [entry.id.uuidString]
            )
        }
        #expect(updatedCount == 9)
    }

    @MainActor
    @Test("deleteTapped shows confirmation, deleteConfirmed removes entry")
    func deleteFlow() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 3, note: nil,
            isMenstruating: false
        )

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        await testStore.send(.deleteTapped) {
            $0.showDeleteConfirmation = true
        }

        await testStore.send(.deleteConfirmed)

        await testStore.receive(\.deleteResponse.success) {
            $0.showDeleteConfirmation = false
            $0.didFinish = true
        }

        // Verify entry is gone
        @Dependency(\.defaultDatabase) var database
        let remainingCount = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM "sqLiteSymptomEntry"
                    WHERE lower("id") = lower(?)
                    """,
                arguments: [entry.id.uuidString]
            ) ?? 0
        }
        #expect(remainingCount == 0)
    }

    @MainActor
    @Test("saveTapped posts symptomEntriesDidChange to injected center")
    func saveTappedPostsNotification() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 5, note: "Original",
            isMenstruating: false
        )

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .symptomEntriesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        await testStore.send(\.binding.severity, 9)
        await testStore.send(.saveTapped)
        await testStore.receive(\.saveResponse.success)

        #expect(posted.value == true)
    }

    @MainActor
    @Test("deleteConfirmed posts symptomEntriesDidChange to injected center")
    func deleteConfirmedPostsNotification() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 3, note: nil,
            isMenstruating: false
        )

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .symptomEntriesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        await testStore.send(.deleteTapped)
        await testStore.send(.deleteConfirmed)
        await testStore.receive(\.deleteResponse.success)

        #expect(posted.value == true)
    }

    @MainActor
    @Test("saveResponse failure sets errorMessage")
    func saveFailureSetsError() async throws {
        try prepareTestDependencies()

        let store = DataStore()
        let journal = try store.createJournal()
        let entry = try store.createSymptomEntry(
            for: journal, severity: 5, note: nil,
            isMenstruating: false
        )

        let testStore = TestStore(
            initialState: SymptomEntryEditorFeature.State(entryID: entry.id)
        ) {
            SymptomEntryEditorFeature()
        } withDependencies: {
            $0.databaseClient.updateSymptomEntry = { _ in
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Write failed"
                ])
            }
        }
        testStore.exhaustivity = .off

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        await testStore.send(.saveTapped)

        await testStore.receive(\.saveResponse.failure) {
            #expect($0.errorMessage != nil)
        }
    }
}
