import ComposableArchitecture
import Dependencies
import Foundation

@Reducer
struct MedicationIntakeEditorFeature {
    @ObservableState
    struct State: Equatable {
        var intakeID: UUID
        var intake: SQLiteMedicationIntake?
        var amountValue: Double?
        var unit: String = ""
        var notes: String = ""
        var timestamp: Date = .now
        var didLoad = false
        var showDeleteConfirmation = false
        var errorMessage: String?
        var didFinish = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case loadResponse(SQLiteMedicationIntake?)
        case saveTapped
        case saveResponse(TaskResult<SQLiteMedicationIntake>)
        case deleteTapped
        case deleteConfirmed
        case deleteResponse(TaskResult<Void>)
        case clearError
        case clearDidFinish
    }

    @Dependency(\.databaseClient) private var databaseClient

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                guard !state.didLoad else { return .none }
                state.didLoad = true
                let intakeID = state.intakeID
                return .run { send in
                    let intake = databaseClient.fetchMedicationIntake(intakeID)
                    await send(.loadResponse(intake))
                }

            case .loadResponse(let intake):
                state.intake = intake
                if let intake {
                    state.amountValue = intake.amount
                    state.unit = intake.unit ?? ""
                    state.notes = intake.notes ?? ""
                    state.timestamp = intake.timestamp
                } else {
                    state.errorMessage = "Unable to load dose."
                }
                return .none

            case .saveTapped:
                guard let intake = state.intake else { return .none }
                let amount = state.amountValue
                let unit = state.unit
                let notes = state.notes
                let timestamp = state.timestamp
                return .run { send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                let updatedIntake = intake.mergingEditableFields(
                                    amount: amount,
                                    unit: unit.isEmpty ? nil : unit,
                                    timestamp: timestamp,
                                    notes: notes.isEmpty ? nil : notes
                                )
                                try databaseClient.updateMedicationIntake(updatedIntake)
                                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
                                return updatedIntake
                            }
                        )
                    )
                }

            case .saveResponse(.success(let updatedIntake)):
                state.intake = updatedIntake
                state.didFinish = true
                return .none

            case .saveResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none

            case .deleteTapped:
                state.showDeleteConfirmation = true
                return .none

            case .deleteConfirmed:
                guard let intake = state.intake else { return .none }
                return .run { send in
                    await send(
                        .deleteResponse(
                            TaskResult {
                                try databaseClient.deleteMedicationIntake(intake)
                                NotificationCenter.default.post(name: .medicationIntakesDidChange, object: nil)
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
