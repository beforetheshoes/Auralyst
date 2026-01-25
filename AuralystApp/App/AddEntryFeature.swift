import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct AddEntryFeature {
    @ObservableState
    struct State: Equatable {
        var journalID: UUID
        var timestamp: Date = .now
        var overallSeverity: Int = 0
        var isMenstruating = false
        var note = ""
        var isSaving = false
        var errorMessage: String?
        var didSave = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveTapped
        case saveResponse(TaskResult<Void>)
        case clearError
        case clearDidSave
    }

    @Dependency(\.databaseClient) private var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .saveTapped:
                guard !state.isSaving else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                let journalID = state.journalID
                let severity = state.overallSeverity
                let note = state.note
                let timestamp = state.timestamp
                let isMenstruating = state.isMenstruating
                return .run { send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                guard let journal = databaseClient.fetchJournal(journalID) else {
                                    throw NSError(domain: "AddEntryFeature", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing journal for new entry"])
                                }
                                _ = try databaseClient.createSymptomEntry(
                                    journal,
                                    Int16(severity),
                                    note.isEmpty ? nil : note,
                                    timestamp,
                                    isMenstruating
                                )
                            }
                        )
                    )
                }

            case .saveResponse(.success):
                state.isSaving = false
                state.didSave = true
                return .none

            case .saveResponse(.failure(let error)):
                state.isSaving = false
                state.errorMessage = error.localizedDescription
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none

            case .clearDidSave:
                state.didSave = false
                return .none
            }
        }
    }
}
