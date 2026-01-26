import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct MedicationQuickLogFeature {
    @Dependency(\.continuousClock) var clock

    @ObservableState
    struct State: Equatable {
        var journalID: UUID
        var selectedDate: Date
        var snapshot: MedicationQuickLogSnapshot = .empty
        var isLoading = false
        var errorMessage: String?

        init(journalID: UUID, selectedDate: Date = Date()) {
            self.journalID = journalID
            self.selectedDate = Calendar.current.startOfDay(for: selectedDate)
        }
    }

    enum Action {
        case task
        case refresh
        case refreshRequested
        case selectedDateChanged(Date)
        case loadResponse(TaskResult<MedicationQuickLogSnapshot>)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                state.isLoading = true
                state.errorMessage = nil
                let journalID = state.journalID
                let date = state.selectedDate
                return .run { send in
                    await send(
                        .loadResponse(
                            TaskResult {
                                let loader = MedicationQuickLogLoader()
                                return try loader.load(journalID: journalID, on: date)
                            }
                        )
                    )
                }

            case .refreshRequested:
                return .run { [clock] send in
                    try? await clock.sleep(for: .milliseconds(250))
                    await send(.refresh)
                }
                .cancellable(id: RefreshDebounceID.refresh, cancelInFlight: true)

            case .selectedDateChanged(let date):
                state.selectedDate = Calendar.current.startOfDay(for: date)
                return .send(.refresh)

            case .loadResponse(.success(let snapshot)):
                state.isLoading = false
                state.snapshot = snapshot
                return .none

            case .loadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none
            }
        }
    }
}

private enum RefreshDebounceID: Hashable {
    case refresh
}
