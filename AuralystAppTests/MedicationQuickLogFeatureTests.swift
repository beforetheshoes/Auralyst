import Foundation
import Testing
import Dependencies
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Medication quick log feature", .serialized)
struct MedicationQuickLogFeatureTests {
    @MainActor
    @Test("Loads medications and schedules for a journal")
    func loadsSnapshot() async throws {
        try prepareTestDependencies()
        let notificationCenter = NotificationCenter()

        let store = DataStore()
        let journal = store.createJournal()
        let medication = store.createMedication(
            for: journal,
            name: "Vitamin D",
            defaultAmount: 1,
            defaultUnit: "pill"
        )

        @Dependency(\.defaultDatabase) var database
        let schedule = SQLiteMedicationSchedule(
            medicationID: medication.id,
            label: "Morning",
            amount: 1,
            unit: "pill",
            cadence: "daily",
            interval: 1,
            daysOfWeekMask: MedicationWeekday.mask(for: MedicationWeekday.allCases),
            hour: 9,
            minute: 0,
            isActive: true,
            sortOrder: 0
        )
        try await database.write { db in
            try insertSchedule(schedule, in: db)
        }

        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task) {
            $0.isLoading = true
            $0.errorMessage = nil
        }

        let loader = MedicationQuickLogLoader()
        let expectedSnapshot = try loader.load(journalID: journal.id, on: testStore.state.selectedDate)

        await testStore.receive(\.loadResponse) {
            $0.isLoading = false
            $0.snapshot = expectedSnapshot
        }

        #expect(testStore.state.snapshot.medications.contains(where: { $0.name == "Vitamin D" }))
        #expect(testStore.state.snapshot.schedulesByMedication[medication.id]?.contains(where: { $0.id == schedule.id }) == true)

        await testStore.send(.cancelNotifications)
    }

    @MainActor
    @Test("Debounces refresh requests to a single load")
    func debouncesRefreshRequests() async throws {
        try prepareTestDependencies()
        let notificationCenter = NotificationCenter()

        let store = DataStore()
        let journal = store.createJournal()
        _ = store.createMedication(
            for: journal,
            name: "Vitamin D",
            defaultAmount: 1,
            defaultUnit: "pill"
        )

        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.exhaustivity = .off
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.refreshRequested)
        await testStore.send(.refreshRequested)

        await testStore.receive(\.refresh) {
            $0.isLoading = true
            $0.errorMessage = nil
        }

        let loader = MedicationQuickLogLoader()
        let expectedSnapshot = try loader.load(journalID: journal.id, on: testStore.state.selectedDate)

        await testStore.receive(\.loadResponse) {
            $0.isLoading = false
            $0.snapshot = expectedSnapshot
        }
    }

    @MainActor
    @Test("Refreshes after medication change notifications")
    func refreshesAfterMedicationChangeNotifications() async throws {
        try prepareTestDependencies()

        let notificationCenter = NotificationCenter()

        let store = DataStore()
        let journal = store.createJournal()
        _ = store.createMedication(
            for: journal,
            name: "Vitamin D",
            defaultAmount: 1,
            defaultUnit: "pill"
        )

        let testStore = TestStore(
            initialState: MedicationQuickLogFeature.State(journalID: journal.id)
        ) {
            MedicationQuickLogFeature()
        }
        testStore.dependencies.notificationCenter = notificationCenter

        await testStore.send(.task) {
            $0.isLoading = true
            $0.errorMessage = nil
        }

        let loader = MedicationQuickLogLoader()
        let expectedSnapshot = try loader.load(journalID: journal.id, on: testStore.state.selectedDate)

        await testStore.receive(\.loadResponse) {
            $0.isLoading = false
            $0.snapshot = expectedSnapshot
        }

        notificationCenter.post(name: .medicationsDidChange, object: nil)

        await testStore.receive(\.refreshRequested)
        try? await Task.sleep(nanoseconds: 400_000_000)

        await testStore.receive(\.refresh) {
            $0.isLoading = true
            $0.errorMessage = nil
        }

        let refreshedSnapshot = try loader.load(journalID: journal.id, on: testStore.state.selectedDate)

        await testStore.receive(\.loadResponse) {
            $0.isLoading = false
            $0.snapshot = refreshedSnapshot
        }

        await testStore.send(.cancelNotifications)
    }
}
