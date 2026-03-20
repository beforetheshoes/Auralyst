import ComposableArchitecture
import Dependencies
import Foundation
import CloudKit
@preconcurrency import SQLiteData

@Reducer
struct ShareManagementFeature {
    @ObservableState
    struct State: Equatable {
        var journal: SQLiteJournal
        var sharedRecord: SharedRecord?
        var isShared = false
        var isLoading = false
        var errorMessage: String?

        static func == (lhs: State, rhs: State) -> Bool {
            lhs.journal == rhs.journal
                && String(describing: lhs.sharedRecord) == String(describing: rhs.sharedRecord)
                && lhs.isShared == rhs.isShared
                && lhs.isLoading == rhs.isLoading
                && lhs.errorMessage == rhs.errorMessage
        }
    }

    enum Action {
        case task
        case refresh
        case refreshResponse(TaskResult<Bool>)
        case shareTapped
        case shareResponse(TaskResult<SharedRecord>)
        case setSharedRecord(SharedRecord?)
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.syncEngine) private var syncEngine

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                state.isLoading = true
                state.errorMessage = nil
                let journalID = state.journal.id
                return .run { [databaseClient] send in
                    await send(
                        .refreshResponse(
                            TaskResult {
                                try databaseClient.fetchJournalIsShared(journalID)
                            }
                        )
                    )
                }

            case .refreshResponse(.success(let isShared)):
                state.isLoading = false
                state.isShared = isShared
                return .none

            case .refreshResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                state.isShared = false
                return .none

            case .shareTapped:
                state.isLoading = true
                state.errorMessage = nil
                let journal = state.journal
                return .run { send in
                    await send(
                        .shareResponse(
                            TaskResult {
                                try await syncEngine.shareJournal(journal) { share in
                                    share[CKShare.SystemFieldKey.title] = "Auralyst Journal"
                                }
                            }
                        )
                    )
                }

            case .shareResponse(.success(let sharedRecord)):
                state.isLoading = false
                state.sharedRecord = sharedRecord
                return .none

            case .shareResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .setSharedRecord(let record):
                state.sharedRecord = record
                return .none
            }
        }
    }
}
