import Foundation
import GRDB
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("App feature", .serialized)
struct AppFeatureTests {
    @MainActor
    @Test("createJournalTapped creates journal via effect")
    func createJournalViaEffect() async throws {
        try prepareTestDependencies()

        @Dependency(\.defaultDatabase) var database

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: true
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.createJournalTapped)
        await testStore.receive(\.createJournalResponse.success)

        let journalCount = try await database.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM sqLiteJournal"
            ) ?? 0
        }
        #expect(journalCount >= 1)
    }

    @MainActor
    @Test("createJournalTapped failure surfaces errorMessage")
    func createJournalFailure() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: true
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.databaseClient.createJournal = {
                throw NSError(domain: "test", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Create failed"
                ])
            }
        }
        testStore.exhaustivity = .off

        await testStore.send(.createJournalTapped)
        await testStore.receive(\.createJournalResponse.failure) {
            #expect($0.errorMessage != nil)
        }
    }

    @MainActor
    @Test("clearError resets errorMessage")
    func clearErrorResetsMessage() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: true
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.clearError) {
            $0.errorMessage = nil
        }
    }
}
