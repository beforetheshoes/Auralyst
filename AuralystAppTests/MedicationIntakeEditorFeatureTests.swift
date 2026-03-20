import Foundation
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication intake editor feature", .serialized)
struct MedicationIntakeEditorFeatureTests {
    @MainActor
    @Test("saveTapped posts medicationIntakesDidChange to injected center")
    func saveTappedPostsNotification() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D",
            defaultAmount: 1, defaultUnit: "pill"
        )
        let intake = try dataStore.createMedicationIntake(
            for: medication, amount: 1, unit: "pill"
        )

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationIntakesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: MedicationIntakeEditorFeature.State(intakeID: intake.id)
        ) {
            MedicationIntakeEditorFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task)
        await testStore.receive(\.loadResponse)

        await testStore.send(.saveTapped)
        await testStore.receive(\.saveResponse.success)

        #expect(posted.value == true)
    }

    @MainActor
    @Test("deleteConfirmed posts medicationIntakesDidChange to injected center")
    func deleteConfirmedPostsNotification() async throws {
        try prepareTestDependencies()

        let dataStore = DataStore()
        let journal = try dataStore.createJournal()
        let medication = dataStore.createMedication(
            for: journal, name: "Vitamin D",
            defaultAmount: 1, defaultUnit: "pill"
        )
        let intake = try dataStore.createMedicationIntake(
            for: medication, amount: 1, unit: "pill"
        )

        let notificationCenter = NotificationCenter()
        let posted = LockIsolated(false)
        let token = notificationCenter.addObserver(
            forName: .medicationIntakesDidChange, object: nil, queue: nil
        ) { _ in posted.withValue { $0 = true } }
        defer { notificationCenter.removeObserver(token) }

        let testStore = TestStore(
            initialState: MedicationIntakeEditorFeature.State(intakeID: intake.id)
        ) {
            MedicationIntakeEditorFeature()
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
}
