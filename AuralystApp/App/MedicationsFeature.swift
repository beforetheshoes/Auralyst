import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct MedicationsFeature {
    @ObservableState
    struct State: Equatable {
        var journal: SQLiteJournal
        var editorMode: EditorMode?
        var errorMessage: String?
    }

    enum Action {
        case addTapped
        case editTapped(UUID)
        case deleteMedication(UUID)
        case deleteResponse(TaskResult<Void>)
        case setEditorMode(EditorMode?)
        case clearError
    }

    @Dependency(\.databaseClient) private var databaseClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .addTapped:
                state.editorMode = .create
                return .none
            case .editTapped(let id):
                state.editorMode = .edit(id)
                return .none
            case .deleteMedication(let id):
                return .run { [databaseClient] send in
                    await send(
                        .deleteResponse(
                            TaskResult {
                                try databaseClient.deleteMedication(id)
                                NotificationCenter.default.post(
                                    name: .medicationsDidChange,
                                    object: nil
                                )
                            }
                        )
                    )
                }
            case .deleteResponse(.success):
                state.errorMessage = nil
                return .none
            case .deleteResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none
            case .setEditorMode(let mode):
                state.editorMode = mode
                return .none
            case .clearError:
                state.errorMessage = nil
                return .none
            }
        }
    }
}
