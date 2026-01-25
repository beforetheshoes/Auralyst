import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct MedicationsFeature {
    @ObservableState
    struct State: Equatable {
        var journal: SQLiteJournal
        var editorMode: EditorMode?
    }

    enum Action: Equatable {
        case addTapped
        case editTapped(UUID)
        case deleteMedication(UUID)
        case setEditorMode(EditorMode?)
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
                do {
                    try databaseClient.deleteMedication(id)
                    NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
                } catch {
                    assertionFailure("Failed to delete medication: \(error)")
                }
                return .none
            case .setEditorMode(let mode):
                state.editorMode = mode
                return .none
            }
        }
    }
}
