import Foundation
import Testing
import ComposableArchitecture
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("As-needed intake feature", .serialized)
struct AsNeededIntakeFeatureSuite {
    @MainActor
    @Test("Task initializes defaults from medication")
    func taskInitializesDefaults() async throws {
        let baseDate = Date(timeIntervalSince1970: 1_726_601_200)
        let medication = SQLiteMedication(
            journalID: UUID(),
            name: "Relief",
            defaultAmount: 2,
            defaultUnit: "pill",
            isAsNeeded: true
        )
        let calendar = Calendar.current
        let now = Date(timeIntervalSince1970: 1_726_700_000)
        let dayStart = calendar.startOfDay(for: baseDate)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: dayStart)
        dateComponents.hour = nowComponents.hour
        dateComponents.minute = nowComponents.minute
        let expectedTimestamp = calendar.date(from: dateComponents) ?? baseDate

        let store = TestStore(
            initialState: AsNeededIntakeFeature.State(
                medication: medication,
                defaultDate: baseDate
            )
        ) {
            AsNeededIntakeFeature()
        } withDependencies: {
            $0.date.now = now
        }

        await store.send(.task) {
            $0.amount = "2"
            $0.unit = "pill"
            $0.timestamp = expectedTimestamp
        }

        #expect(store.state.amount == "2")
        #expect(store.state.unit == "pill")
        #expect(Calendar.current.isDate(store.state.timestamp, inSameDayAs: baseDate))
    }
}
