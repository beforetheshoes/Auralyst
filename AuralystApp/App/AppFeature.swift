import ComposableArchitecture
import SwiftUI
import Dependencies

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var isRunningTests: Bool
        var shouldStartSync: Bool
        var syncStatus: SyncStatusFeature.State
        var showingAddEntry = false
        var showingExport = false
        var showingImport = false
        var shareManagementJournal: SQLiteJournal?
        var hasDeterminedInitialData = false
        var bypassInitialOverlay: Bool
        var journalsEmpty = true
        var entriesCount = 0
        var syncPhase: SyncPhase = .idle

        init(isRunningTests: Bool, shouldStartSync: Bool, overridePhaseRaw: String?, bypassInitialOverlay: Bool) {
            self.isRunningTests = isRunningTests
            self.shouldStartSync = shouldStartSync
            self.syncStatus = SyncStatusFeature.State(
                shouldStartSync: shouldStartSync,
                overridePhaseRaw: overridePhaseRaw
            )
            self.bypassInitialOverlay = bypassInitialOverlay
        }
    }

    enum Action {
        case scenePhaseChanged(ScenePhase)
        case task
        case syncStatus(SyncStatusFeature.Action)
        case addEntryTapped
        case setShowingAddEntry(Bool)
        case shareManagementTapped(SQLiteJournal)
        case setShareManagementJournal(SQLiteJournal?)
        case exportTapped
        case setShowingExport(Bool)
        case importTapped
        case setShowingImport(Bool)
        case createJournalTapped
        case journalsChanged(isEmpty: Bool)
        case entriesCountChanged(Int)
        case syncPhaseChanged(SyncPhase)
    }

    @Dependency(\.databaseClient) private var databaseClient

    var body: some Reducer<State, Action> {
        Scope(state: \.syncStatus, action: \.syncStatus) {
            SyncStatusFeature()
        }
        Reduce { state, action in
            switch action {
            case .task:
                return .send(.syncStatus(.task))
            case .scenePhaseChanged(let phase):
                return .send(.syncStatus(.scenePhaseChanged(phase)))
            case .syncStatus:
                return .none
            case .addEntryTapped:
                state.showingAddEntry = true
                return .none
            case .setShowingAddEntry(let isPresented):
                state.showingAddEntry = isPresented
                return .none
            case .shareManagementTapped(let journal):
                state.shareManagementJournal = journal
                return .none
            case .setShareManagementJournal(let journal):
                state.shareManagementJournal = journal
                return .none
            case .exportTapped:
                state.showingExport = true
                return .none
            case .setShowingExport(let isPresented):
                state.showingExport = isPresented
                return .none
            case .importTapped:
                state.showingImport = true
                return .none
            case .setShowingImport(let isPresented):
                state.showingImport = isPresented
                return .none
            case .createJournalTapped:
                _ = databaseClient.createJournal()
                return .none
            case .journalsChanged(let isEmpty):
                state.journalsEmpty = isEmpty
                resolveInitialDataState(state: &state)
                return .none
            case .entriesCountChanged(let count):
                state.entriesCount = count
                resolveInitialDataState(state: &state)
                return .none
            case .syncPhaseChanged(let phase):
                state.syncPhase = phase
                resolveInitialDataState(state: &state)
                return .none
            }
        }
    }
}

private extension AppFeature {
    func resolveInitialDataState(state: inout State) {
        if state.bypassInitialOverlay {
            state.hasDeterminedInitialData = true
            return
        }
        if state.hasDeterminedInitialData { return }
        if !state.journalsEmpty {
            state.hasDeterminedInitialData = true
            return
        }
        switch state.syncPhase {
        case .upToDate, .error:
            state.hasDeterminedInitialData = true
        default:
            break
        }
    }
}
