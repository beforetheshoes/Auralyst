import ComposableArchitecture
import Dependencies
import Foundation
@preconcurrency import SQLiteData

@Reducer
struct AsNeededIntakeFeature {
    @ObservableState
    struct State: Equatable {
        var medication: SQLiteMedication
        var defaultDate: Date
        var amount: String = ""
        var unit: String = ""
        var notes: String = ""
        var timestamp: Date = Date()
        var isSaving = false
        var errorMessage: String?
        var didSave = false
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case task
        case saveTapped
        case saveResponse(TaskResult<Void>)
        case clearError
        case clearDidSave
    }

    @Dependency(\.databaseClient) private var databaseClient
    @Dependency(\.date) private var date
    @Dependency(\.notificationCenter) private var notificationCenter

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                state.amount = state.medication.defaultAmount.map { $0.cleanAmount } ?? ""
                state.unit = state.medication.defaultUnit ?? ""
                let cal = Calendar.current
                let dayStart = cal.startOfDay(for: state.defaultDate)
                let now = date.now
                let comps = cal.dateComponents([.hour, .minute], from: now)
                var dtc = cal.dateComponents([.year, .month, .day], from: dayStart)
                dtc.hour = comps.hour
                dtc.minute = comps.minute
                state.timestamp = cal.date(from: dtc) ?? state.defaultDate
                return .none

            case .saveTapped:
                guard !state.isSaving else { return .none }
                state.isSaving = true
                let medication = state.medication
                let amount = state.amount
                let unit = state.unit
                let notes = state.notes
                let timestamp = state.timestamp
                return .run { [databaseClient, notificationCenter] send in
                    await send(
                        .saveResponse(
                            TaskResult {
                                let amt = Double(amount) ?? medication.defaultAmount
                                let unitValue = unit.isEmpty ? medication.defaultUnit : unit
                                let noteValue = notes.isEmpty ? nil : notes
                                let intake = SQLiteMedicationIntake(
                                    id: UUID(),
                                    medicationID: medication.id,
                                    amount: amt,
                                    unit: unitValue,
                                    timestamp: timestamp,
                                    origin: "asNeeded",
                                    notes: noteValue
                                )
                                try databaseClient.createAsNeededIntake(intake)
                                notificationCenter.post(name: .medicationIntakesDidChange, object: nil)
                            }
                        )
                    )
                }

            case .saveResponse(.success):
                state.isSaving = false
                state.didSave = true
                return .none

            case .saveResponse(.failure(let error)):
                state.isSaving = false
                state.errorMessage = error.localizedDescription
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none

            case .clearDidSave:
                state.didSave = false
                return .none
            }
        }
    }
}
