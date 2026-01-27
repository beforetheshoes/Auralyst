import ComposableArchitecture
import Dependencies
import Foundation
import GRDB

@Reducer
struct ImportFeature {
    @ObservableState
    struct State: Equatable {
        var hasExistingJournal: Bool
        var selectedFileURL: URL?
        var isAnalyzing = false
        var isImporting = false
        var errorMessage: String?
        var showFilePicker = false
        var showReplaceConfirmation = false
        var analysis: ImportAnalysis?
        var showIssuesDialog = false
        var pendingReplaceExisting = false
        var lastResult: ImportResult?
    }

    enum Action {
        case chooseFileTapped
        case filePicked(URL)
        case filePickerDismissed
        case importTapped
        case confirmReplaceTapped
        case setReplaceConfirmation(Bool)
        case checkExistingJournalResponse(TaskResult<Bool>)
        case analyzeResponse(TaskResult<ImportAnalysis>, replaceExisting: Bool)
        case importWithAutoFixTapped
        case dismissIssuesDialog
        case importResponse(TaskResult<ImportResult>)
        case clearError
        case clearResult
    }

    @Dependency(\.importClient) private var importClient
    @Dependency(\.defaultDatabase) private var database
    @Dependency(\.notificationCenter) private var notificationCenter

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
                return .run { send in
                    await send(
                        .checkExistingJournalResponse(
                            TaskResult {
                                try database.read { db in
                                    (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqLiteJournal") ?? 0) > 0
                                }
                            }
                        )
                    )
                }

            case .confirmReplaceTapped:
                state.showReplaceConfirmation = false
                return startAnalysis(state: &state, replaceExisting: true)

            case .setReplaceConfirmation(let isPresented):
                state.showReplaceConfirmation = isPresented
                return .none

            case .checkExistingJournalResponse(.success(let hasJournal)):
                state.hasExistingJournal = hasJournal
                if hasJournal {
                    state.showReplaceConfirmation = true
                    return .none
                }
                return startAnalysis(state: &state, replaceExisting: false)

            case .checkExistingJournalResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none

            case .analyzeResponse(.success(let analysis), let replaceExisting):
                state.isAnalyzing = false
                state.analysis = analysis
                state.pendingReplaceExisting = replaceExisting
                if analysis.hasBlockingIssues {
                    state.errorMessage = blockingMessage(for: analysis.blockingIssues)
                    return .none
                }
                if analysis.hasIssues {
                    state.showIssuesDialog = true
                    return .none
                }
                return startImport(state: &state, replaceExisting: replaceExisting, resolution: .strict)

            case .analyzeResponse(.failure(let error), _):
                state.isAnalyzing = false
                state.errorMessage = error.localizedDescription
                return .none

            case .importWithAutoFixTapped:
                state.showIssuesDialog = false
                let replaceExisting = state.pendingReplaceExisting
                return startImport(state: &state, replaceExisting: replaceExisting, resolution: .autoFix)

            case .dismissIssuesDialog:
                state.showIssuesDialog = false
                return .none

            case .importResponse(.success(let result)):
                state.isImporting = false
                state.lastResult = result
                state.analysis = nil
                notificationCenter.post(name: .medicationsDidChange, object: nil)
                notificationCenter.post(name: .medicationIntakesDidChange, object: nil)
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

    private func startAnalysis(state: inout State, replaceExisting: Bool) -> Effect<Action> {
        guard let url = state.selectedFileURL else { return .none }
        state.isAnalyzing = true
        state.isImporting = false
        state.errorMessage = nil
        state.lastResult = nil
        state.analysis = nil
        state.pendingReplaceExisting = replaceExisting
        return .run { send in
            await send(
                .analyzeResponse(
                    TaskResult {
                        try await importClient.analyze(url)
                    },
                    replaceExisting: replaceExisting
                )
            )
        }
    }

    private func startImport(
        state: inout State,
        replaceExisting: Bool,
        resolution: ImportResolution
    ) -> Effect<Action> {
        guard let url = state.selectedFileURL else { return .none }
        state.isAnalyzing = false
        state.isImporting = true
        state.errorMessage = nil
        state.lastResult = nil
        return .run { send in
            await send(
                .importResponse(
                    TaskResult {
                        try await importClient.importJournal(url, replaceExisting, resolution)
                    }
                )
            )
        }
    }

    private func blockingMessage(for issues: [ImportIssue]) -> String {
        guard let issue = issues.first else { return "Import data is invalid." }
        switch issue.kind {
        case .missingScheduleReferences:
            return "Import data is invalid: One or more intakes reference missing schedules."
        case .missingIntakeEntryReferences:
            return "Import data is invalid: One or more intakes reference missing symptom entries."
        case .missingNoteEntryReferences:
            return "Import data is invalid: One or more collaborator notes reference missing symptom entries."
        case .missingMedicationReferences:
            return "Import data is invalid: One or more records reference missing medications."
        case .journalMismatch:
            return "Import data is invalid: One or more records reference a different journal."
        }
    }
}
