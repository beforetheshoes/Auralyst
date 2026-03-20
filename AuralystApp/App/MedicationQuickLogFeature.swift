import ComposableArchitecture
import Dependencies
import Foundation
import GRDB
@preconcurrency import SQLiteData

@Reducer
struct MedicationQuickLogFeature {
    @Dependency(\.continuousClock) var clock
    @Dependency(\.databaseClient) var databaseClient
    @Dependency(\.notificationCenter) var notificationCenter

    @ObservableState
    struct State: Equatable {
        var journalID: UUID
        var selectedDate: Date
        var snapshot: MedicationQuickLogSnapshot = .empty
        var isLoading = false
        var errorMessage: String?

        init(journalID: UUID, selectedDate: Date = Date()) {
            self.journalID = journalID
            self.selectedDate = Calendar.current.startOfDay(for: selectedDate)
        }
    }

    enum Action {
        case task
        case refresh
        case refreshRequested
        case selectedDateChanged(Date)
        case loadResponse(TaskResult<MedicationQuickLogSnapshot>)
        case cancelNotifications
        case logScheduledDose(SQLiteMedicationSchedule, SQLiteMedication, Date)
        case logResponse(TaskResult<Void>)
        case unlogScheduledDose(SQLiteMedicationSchedule, Date)
        case unlogResponse(TaskResult<Void>)
    }

    private enum CancelID {
        case medicationChanges
        case intakeChanges
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task, .refresh:
                state.isLoading = true
                state.errorMessage = nil
                let journalID = state.journalID
                let date = state.selectedDate
                let loadEffect: Effect<Action> = .run { [databaseClient] send in
                    await send(
                        .loadResponse(
                            TaskResult {
                                try databaseClient.fetchQuickLogSnapshot(journalID, date)
                            }
                        )
                    )
                }

                let medicationChanges: Effect<Action> = .run { [notificationCenter] send in
                    for await _ in notificationCenter.notifications(named: .medicationsDidChange) {
                        await send(.refreshRequested)
                    }
                }
                .cancellable(id: CancelID.medicationChanges, cancelInFlight: true)

                let intakeChanges: Effect<Action> = .run { [notificationCenter] send in
                    for await _ in notificationCenter.notifications(named: .medicationIntakesDidChange) {
                        await send(.refreshRequested)
                    }
                }
                .cancellable(id: CancelID.intakeChanges, cancelInFlight: true)

                return .merge(loadEffect, medicationChanges, intakeChanges)

            case .refreshRequested:
                return .run { [clock] send in
                    try? await clock.sleep(for: .milliseconds(250))
                    await send(.refresh)
                }
                .cancellable(id: RefreshDebounceID.refresh, cancelInFlight: true)

            case .selectedDateChanged(let date):
                state.selectedDate = Calendar.current.startOfDay(for: date)
                return .send(.refresh)

            case .loadResponse(.success(let snapshot)):
                state.isLoading = false
                state.snapshot = snapshot
                return .none

            case .loadResponse(.failure(let error)):
                state.isLoading = false
                state.errorMessage = error.localizedDescription
                return .none

            case .cancelNotifications:
                return .merge(
                    .cancel(id: CancelID.medicationChanges),
                    .cancel(id: CancelID.intakeChanges)
                )

            case .logScheduledDose(let schedule, let medication, let date):
                return .run { [databaseClient, notificationCenter] send in
                    await send(
                        .logResponse(
                            TaskResult {
                                try databaseClient.logScheduledDose(
                                    ScheduledDoseLogParams(
                                        schedule: schedule,
                                        medication: medication,
                                        date: date
                                    )
                                )
                                notificationCenter.post(
                                    name: .medicationIntakesDidChange, object: nil
                                )
                            }
                        )
                    )
                }

            case .logResponse(.success):
                state.errorMessage = nil
                return .send(.refreshRequested)

            case .logResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none

            case .unlogScheduledDose(let schedule, let date):
                let snapshot = state.snapshot
                return .run { [databaseClient, notificationCenter] send in
                    await send(
                        .unlogResponse(
                            TaskResult {
                                try databaseClient.unlogScheduledDose(
                                    ScheduledDoseUnlogParams(
                                        schedule: schedule,
                                        date: date,
                                        snapshot: snapshot
                                    )
                                )
                                notificationCenter.post(
                                    name: .medicationIntakesDidChange, object: nil
                                )
                            }
                        )
                    )
                }

            case .unlogResponse(.success):
                state.errorMessage = nil
                return .send(.refreshRequested)

            case .unlogResponse(.failure(let error)):
                state.errorMessage = error.localizedDescription
                return .none
            }
        }
    }

    static func scheduledDateTime(
        for schedule: SQLiteMedicationSchedule,
        on date: Date
    ) -> (timestamp: Date, scheduledDate: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        var comps = cal.dateComponents([.year, .month, .day], from: start)
        comps.hour = Int(schedule.hour ?? 8)
        comps.minute = Int(schedule.minute ?? 0)
        let scheduled = cal.date(from: comps) ?? start
        return (scheduled, start)
    }

    static func dayBounds(for date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return (start, end)
    }
}

private enum RefreshDebounceID: Hashable {
    case refresh
}

// swiftlint:disable:next function_parameter_count
func insertMedicationIntake(
    in db: Database,
    id: UUID = UUID(),
    medicationID: UUID,
    scheduleID: UUID? = nil,
    amount: Double?,
    unit: String?,
    timestamp: Date,
    scheduledDate: Date? = nil,
    origin: String?
) throws {
    try db.execute(
        sql: """
            INSERT INTO "sqLiteMedicationIntake"
            ("id","medicationID","scheduleID","amount","unit",
             "timestamp","scheduledDate","origin")
            VALUES (?,?,?,?,?,?,?,?)
            """,
        arguments: [
            id.uuidString.lowercased(),
            medicationID.uuidString.lowercased(),
            scheduleID?.uuidString.lowercased(),
            amount,
            unit,
            timestamp,
            scheduledDate,
            origin
        ]
    )
}

func scheduleIDToPersist(scheduleID: UUID, db: Database) throws -> UUID? {
    let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sqLiteMedicationSchedule WHERE lower(id) = lower(?) OR id = ?",
        arguments: [scheduleID.uuidString, scheduleID]
    ) ?? 0
    return count > 0 ? scheduleID : nil
}
