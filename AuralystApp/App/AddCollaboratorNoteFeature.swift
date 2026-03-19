import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct AddCollaboratorNoteFeature {
    @ObservableState
    struct State: Equatable {
        var entryID: UUID
        var text: String = ""
        var authorName: String = ""
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
                let trimmed = state.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !state.isSaving else { return .none }
                state.isSaving = true
                let entryID = state.entryID
                let author = state.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
                return .run { send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                guard let entry = databaseClient.fetchSymptomEntry(entryID) else {
                                    throw NSError(
                                        domain: "AddCollaboratorNoteFeature",
                                        code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing entry"]
                                    )
                                }
                                guard let journal = databaseClient.fetchJournal(entry.journalID) else {
                                    throw NSError(
                                        domain: "AddCollaboratorNoteFeature",
                                        code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing journal"]
                                    )
                                }
                                _ = try databaseClient.createCollaboratorNote(
                                    journal,
                                    entry,
                                    author.isEmpty ? nil : author,
                                    trimmed
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
