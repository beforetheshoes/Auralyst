import Foundation
import GRDB
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication editor feature", .serialized)
struct MedicationEditorFeatureTests {
    @MainActor
    @Test("saveTapped posts medicationsDidChange to injected center")
    func saveTappedPostsNotification() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationsDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: MedicationEditorFeature.State(journalID: journal.id)
        ) {
            MedicationEditorFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(\.binding.name, "Aspirin")
        await testStore.send(.saveTapped)
        await testStore.receive(\.saveResponse.success)

        #expect(posted.value == true)
    }

    @MainActor
    @Test("deleteConfirmed posts medicationsDidChange to injected center")
    func deleteConfirmedPostsNotification() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Aspirin",
            defaultAmount: 1, defaultUnit: "tablet"
        )

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationsDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: MedicationEditorFeature.State(
                journalID: journal.id,
                medicationID: medication.id
            )
        ) {
            MedicationEditorFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.deleteTapped)
        await testStore.send(.deleteConfirmed)
        await testStore.receive(\.deleteResponse.success)

        #expect(posted.value == true)
    }
}
