import ComposableArchitecture
import Dependencies
import Foundation
@preconcurrency import SQLiteData

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
        var isAutoFixing = false
        var errorMessage: String?
        var exportedFileURL: URL?
        var savedDestinationURL: URL?
        var isShowingDocumentPicker = false
        var preflightReport: ExportPreflightReport?
        var pendingFormat: ExportFormat?
        var isShowingPreflightDialog = false
    }

    enum Action {
        case exportTapped(ExportFormat)
        case preflightResponse(TaskResult<ExportPreflightReport>, ExportFormat)
        case preflightAutoFixTapped
        case preflightAutoFixResponse(TaskResult<ExportPreflightReport>)
        case preflightCancelTapped
        case proceedExport(ExportFormat)
        case exportResponse(TaskResult<(URL, FileExportPresentation)>)
        case finishExport
        case cleanupFinished
        case clearSavedDestination
        case documentPickerDismissed
    }

    @Dependency(\.fileExportClient) private var fileExportClient
    @Dependency(\.fileExportDestinationClient) private var fileExportDestinationClient
    @Dependency(\.exportPreflightClient) private var exportPreflightClient

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
                        .preflightResponse(
                            TaskResult {
                                try await exportPreflightClient.check(journal)
                            }
                            ,
                            format
                        )
                    )
                }

            case .preflightResponse(.success(let report), let format):
                state.isGenerating = false
                if report.isClean {
                    return .send(.proceedExport(format))
                }
                state.preflightReport = report
                state.pendingFormat = format
                state.isShowingPreflightDialog = true
                return .none

            case .preflightResponse(.failure(let error), _):
                state.isGenerating = false
                state.errorMessage = error.localizedDescription
                return .none

            case .preflightAutoFixTapped:
                guard let format = state.pendingFormat else { return .none }
                state.isShowingPreflightDialog = false
                state.isGenerating = true
                state.isAutoFixing = true
                let journal = state.journal
                return .run { send in
                    do {
                        let report = try await exportPreflightClient.autoFix(journal)
                        await send(.preflightAutoFixResponse(.success(report)))
                        await send(.proceedExport(format))
                    } catch {
                        await send(.preflightAutoFixResponse(.failure(error)))
                    }
                }

            case .preflightAutoFixResponse(.success(let report)):
                state.isGenerating = false
                state.isAutoFixing = false
                state.preflightReport = report.isClean ? nil : report
                return .none

            case .preflightAutoFixResponse(.failure(let error)):
                state.isGenerating = false
                state.isAutoFixing = false
                state.errorMessage = error.localizedDescription
                return .none

            case .preflightCancelTapped:
                state.isShowingPreflightDialog = false
                state.preflightReport = nil
                state.pendingFormat = nil
                return .none

            case .proceedExport(let format):
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
                state.isAutoFixing = false
                state.preflightReport = nil
                state.pendingFormat = nil
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
                state.isAutoFixing = false
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
