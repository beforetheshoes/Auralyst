import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct ImportFeature {
    @ObservableState
    struct State: Equatable {
        var hasExistingJournal: Bool
        var selectedFileURL: URL?
        var isImporting = false
        var errorMessage: String?
        var showFilePicker = false
        var showReplaceConfirmation = false
        var lastResult: ImportResult?
    }

    enum Action {
        case chooseFileTapped
        case filePicked(URL)
        case filePickerDismissed
        case importTapped
        case confirmReplaceTapped
        case setReplaceConfirmation(Bool)
        case importResponse(TaskResult<ImportResult>)
        case clearError
        case clearResult
    }

    @Dependency(\.importClient) private var importClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .chooseFileTapped:
                state.showFilePicker = true
                return .none

            case .filePicked(let url):
                state.selectedFileURL = url
                state.showFilePicker = false
                return .none

            case .filePickerDismissed:
                state.showFilePicker = false
                return .none

            case .importTapped:
                guard !state.isImporting else { return .none }
                guard state.selectedFileURL != nil else { return .none }
                if state.hasExistingJournal {
                    state.showReplaceConfirmation = true
                    return .none
                }
                return startImport(state: &state, replaceExisting: false)

            case .confirmReplaceTapped:
                state.showReplaceConfirmation = false
                return startImport(state: &state, replaceExisting: true)

            case .setReplaceConfirmation(let isPresented):
                state.showReplaceConfirmation = isPresented
                return .none

            case .importResponse(.success(let result)):
                state.isImporting = false
                state.lastResult = result
                return .none

            case .importResponse(.failure(let error)):
                state.isImporting = false
                state.errorMessage = error.localizedDescription
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none

            case .clearResult:
                state.lastResult = nil
                return .none
            }
        }
    }

    private func startImport(state: inout State, replaceExisting: Bool) -> Effect<Action> {
        guard let url = state.selectedFileURL else { return .none }
        state.isImporting = true
        state.errorMessage = nil
        state.lastResult = nil
        return .run { send in
            await send(
                .importResponse(
                    TaskResult {
                        try await importClient.importJournal(url, replaceExisting)
                    }
                )
            )
        }
    }
}
