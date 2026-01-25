import ComposableArchitecture
import Dependencies
import Foundation

enum ExportFormat {
    case csv
    case json
}

@Reducer
struct ExportFeature {
    @ObservableState
    struct State: Equatable {
        var journal: SQLiteJournal
        var isGenerating = false
        var errorMessage: String?
        var exportedFileURL: URL?
        var savedDestinationURL: URL?
        var isShowingDocumentPicker = false
    }

    enum Action {
        case exportTapped(ExportFormat)
        case exportResponse(TaskResult<(URL, FileExportPresentation)>)
        case finishExport
        case cleanupFinished
        case clearSavedDestination
        case documentPickerDismissed
    }

    @Dependency(\.fileExportClient) private var fileExportClient
    @Dependency(\.fileExportDestinationClient) private var fileExportDestinationClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .exportTapped(let format):
                guard !state.isGenerating else { return .none }
                state.isGenerating = true
                state.errorMessage = nil
                let journal = state.journal
                return .run { send in
                    await send(
                        .exportResponse(
                            TaskResult {
                                let temporaryURL = try await fileExportClient.export(journal, format)
                                let presentation = try await fileExportDestinationClient.present(temporaryURL, format)
                                return (temporaryURL, presentation)
                            }
                        )
                    )
                }

            case .exportResponse(.success(let result)):
                state.isGenerating = false
                let (temporaryURL, presentation) = result
                switch presentation {
                case .documentPicker(let url):
                    state.exportedFileURL = url
                    state.savedDestinationURL = nil
                    state.isShowingDocumentPicker = true
                    return .none
                case .saved(let destination):
                    state.exportedFileURL = nil
                    state.savedDestinationURL = destination
                    state.isShowingDocumentPicker = false
                    return .run { send in
                        await fileExportClient.cleanup(temporaryURL)
                        await send(.cleanupFinished)
                    }
                case .cancelled:
                    state.exportedFileURL = nil
                    state.savedDestinationURL = nil
                    state.isShowingDocumentPicker = false
                    return .run { send in
                        await fileExportClient.cleanup(temporaryURL)
                        await send(.cleanupFinished)
                    }
                }

            case .exportResponse(.failure(let error)):
                state.isGenerating = false
                state.errorMessage = error.localizedDescription
                state.exportedFileURL = nil
                state.savedDestinationURL = nil
                state.isShowingDocumentPicker = false
                return .none

            case .finishExport:
                guard let url = state.exportedFileURL else { return .none }
                state.exportedFileURL = nil
                state.isShowingDocumentPicker = false
                return .run { send in
                    await fileExportClient.cleanup(url)
                    await send(.cleanupFinished)
                }

            case .documentPickerDismissed:
                return .send(.finishExport)

            case .cleanupFinished:
                return .none

            case .clearSavedDestination:
                state.savedDestinationURL = nil
                return .none
            }
        }
    }
}
