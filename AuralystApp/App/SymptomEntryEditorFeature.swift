import ComposableArchitecture
import Dependencies
import Foundation
@preconcurrency import SQLiteData

@Reducer
struct SymptomEntryEditorFeature {
    @ObservableState
    struct State: Equatable {
        var entryID: UUID
        var entry: SQLiteSymptomEntry?
        var severity: Int = 0
        var isMenstruating: Bool = false
        var note: String = ""
        var timestamp: Date = .now
        var didLoad = false
        var showDeleteConfirmation = false
        var errorMessage: String?
        var didFinish = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case loadResponse(SQLiteSymptomEntry?)
        case saveTapped
        case saveResponse(TaskResult<Void>)
        case deleteTapped
        case deleteConfirmed
        case deleteResponse(TaskResult<Void>)
        case clearError
        case clearDidFinish
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.notificationCenter) private var notificationCenter

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                guard !state.didLoad else { return .none }
                state.didLoad = true
                let entryID = state.entryID
                return .run { send in
                    let entry = databaseClient.fetchSymptomEntry(entryID)
                    await send(.loadResponse(entry))
                }

            case .loadResponse(let entry):
                state.entry = entry
                if let entry {
                    state.severity = Int(entry.severity)
                    state.isMenstruating = entry.isMenstruating ?? false
                    state.note = entry.note ?? ""
                    state.timestamp = entry.timestamp
                } else {
                    state.errorMessage = "Unable to load entry."
                }
                return .none

            case .saveTapped:
                guard let entry = state.entry else { return .none }
                let updatedEntry = SQLiteSymptomEntry(
                    id: entry.id,
                    timestamp: state.timestamp,
                    journalID: entry.journalID,
                    severity: Int16(state.severity),
                    headache: entry.headache,
                    nausea: entry.nausea,
                    anxiety: entry.anxiety,
                    isMenstruating: state.isMenstruating,
                    note: state.note.isEmpty ? nil : state.note,
                    sentimentLabel: entry.sentimentLabel,
                    sentimentScore: entry.sentimentScore
                )
                return .run { [databaseClient, notificationCenter] send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                try databaseClient.updateSymptomEntry(updatedEntry)
                                notificationCenter.post(
                                    name: .symptomEntriesDidChange, object: nil
                                )
                            }
                        )
                    )
                }

            case .saveResponse(.success):
                state.didFinish = true
                return .none

            case .saveResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none

            case .deleteTapped:
                state.showDeleteConfirmation = true
                return .none

            case .deleteConfirmed:
                guard let entry = state.entry else { return .none }
                let entryID = entry.id
                return .run { [databaseClient, notificationCenter] send in
                    await send(
                        .deleteResponse(
                            TaskResult {
                                try databaseClient.deleteSymptomEntry(entryID)
                                notificationCenter.post(
                                    name: .symptomEntriesDidChange, object: nil
                                )
                            }
                        )
                    )
                }

            case .deleteResponse(.success):
                state.showDeleteConfirmation = false
                state.didFinish = true
                return .none

            case .deleteResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none

            case .clearDidFinish:
                state.didFinish = false
                return .none
            }
        }
    }
}
