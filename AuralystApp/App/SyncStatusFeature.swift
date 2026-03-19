import CloudKit
import ComposableArchitecture
import Dependencies
import SwiftUI

enum SyncPhase: Equatable {
    case idle
    case syncing
    case upToDate
    case error(SyncIssue)
}

struct SyncStatus: Equatable {
    var phase: SyncPhase = .idle
    var lastSuccessfulSync: Date?
}

struct SyncIssue: Equatable, Identifiable {
    enum Kind: Equatable {
        case account
        case network
        case permission
        case quota
        case unknown
    }

    var kind: Kind
    var message: String
    var code: Int?

    var id: String {
        if let code { return "\(kind)-\(code)" }
        return "\(kind)-\(message)"
    }

    init(kind: Kind, message: String, code: Int? = nil) {
        self.kind = kind
        self.message = message
        self.code = code
    }

    init(error: Error) {
        if let ckError = error as? CKError {
            let kind: Kind
            switch ckError.code {
            case .notAuthenticated, .managedAccountRestricted, .accountTemporarilyUnavailable:
                kind = .account
            case .networkUnavailable, .networkFailure, .serverResponseLost, .serviceUnavailable,
                 .zoneBusy, .requestRateLimited:
                kind = .network
            case .permissionFailure:
                kind = .permission
            case .quotaExceeded, .limitExceeded:
                kind = .quota
            default:
                kind = .unknown
            }
            self.init(kind: kind, message: ckError.localizedDescription, code: ckError.errorCode)
        } else {
            let nsError = error as NSError
            let message = nsError.localizedDescription.isEmpty
                ? String(describing: error)
                : nsError.localizedDescription
            self.init(kind: .unknown, message: message, code: nsError.code)
        }
    }
}

@Reducer
struct SyncStatusFeature {
    @ObservableState
    struct State: Equatable {
        var status = SyncStatus()
        var latestState: SyncEngineClient.State = .idle
        var syncingSince: Date?
        var shouldStartSync: Bool
        var overridePhaseRaw: String?
        var isObserving = false
        var isStarting = false
    }

    enum Action {
        case task
        case scenePhaseChanged(ScenePhase)
        case retryTapped
        case startSyncResponse(TaskResult<Void>)
        case syncEngineStateUpdated(SyncEngineClient.State)
        case syncStallTimeoutFired
    }

    @Dependency(\.syncEngine) private var syncEngine
    @Dependency(\.date) private var dateGenerator
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.syncStallTimeoutDuration) private var syncStallTimeoutDuration

    private enum CancelID {
        case syncStallTimeout
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.shouldStartSync else { return .none }
                return startSyncIfNeeded(state: &state)

            case .scenePhaseChanged(let phase):
                guard state.shouldStartSync else { return .none }
                switch phase {
                case .active:
                    return startSyncIfNeeded(state: &state)
                case .background:
                    guard state.overridePhaseRaw == nil else { return .none }
                    if case .error = state.status.phase { return .none }
                    state.status.phase = .idle
                    return .cancel(id: CancelID.syncStallTimeout)
                case .inactive:
                    return .none
                @unknown default:
                    return .none
                }

            case .retryTapped:
                guard state.shouldStartSync else { return .none }
                return startSyncIfNeeded(state: &state)

            case .startSyncResponse(.success):
                state.isStarting = false
                return startObservationIfNeeded(state: &state)

            case .startSyncResponse(.failure(let error)):
                state.isStarting = false
                state.status.phase = .error(SyncIssue(error: error))
                return .none

            case .syncEngineStateUpdated(let syncState):
                let previousState = state.latestState
                state.latestState = syncState
                guard state.overridePhaseRaw == nil else { return .none }

                if syncState.isSynchronizing {
                    if !previousState.isSynchronizing {
                        state.syncingSince = dateGenerator.now
                    }
                    if state.status.lastSuccessfulSync == nil {
                        state.status.phase = .syncing
                    } else {
                        state.status.phase = .upToDate
                    }
                    return scheduleSyncStallTimeout()
                }

                if case .error = state.status.phase { return .none }

                let cancelTimeout = Effect<Action>.cancel(id: CancelID.syncStallTimeout)
                state.syncingSince = nil
                if syncState.isRunning {
                    if previousState.isSynchronizing || state.status.lastSuccessfulSync == nil {
                        state.status.lastSuccessfulSync = dateGenerator.now
                    }
                    state.status.phase = .upToDate
                } else {
                    state.status.phase = .idle
                }
                return cancelTimeout

            case .syncStallTimeoutFired:
                guard state.overridePhaseRaw == nil else { return .none }
                guard state.latestState.isSynchronizing else { return .none }

                // Fallback: avoid a stuck yellow indicator by promoting to up-to-date
                // after the engine has reported synchronizing for long enough.
                let now = dateGenerator.now
                let syncHasStalled =
                    !state.latestState.isSendingChanges &&
                    !state.latestState.isFetchingChanges
                let syncHasTimedOut = state.syncingSince.map { now.timeIntervalSince($0) >= syncStallTimeoutDuration.timeInterval } ?? false

                if syncHasStalled || syncHasTimedOut {
                    state.status.lastSuccessfulSync = state.status.lastSuccessfulSync ?? now
                    state.status.phase = .upToDate
                }
                return .none
            }
        }
    }
}

private extension SyncStatusFeature {
    func startObservationIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.isObserving else { return .none }
        state.isObserving = true
        return .run { send in
            for await state in syncEngine.observeState() {
                await send(.syncEngineStateUpdated(state))
            }
        }
    }

    func startSyncIfNeeded(state: inout State) -> Effect<Action> {
        guard !state.isStarting else { return .none }
        if applyOverrideIfNeeded(state: &state) {
            return .none
        }
        state.isStarting = true
        state.status.phase = .syncing
        let observationEffect = startObservationIfNeeded(state: &state)
        let startEffect: Effect<Action> = .run { send in
            await send(
                .startSyncResponse(
                    TaskResult {
                        try await syncEngine.start()
                    }
                )
            )
        }
        return .merge(observationEffect, startEffect)
    }

    func scheduleSyncStallTimeout() -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: syncStallTimeoutDuration)
            await send(.syncStallTimeoutFired)
        }
        .cancellable(id: CancelID.syncStallTimeout, cancelInFlight: true)
    }

    func applyOverrideIfNeeded(state: inout State) -> Bool {
        guard let overridePhaseRaw = state.overridePhaseRaw else { return false }
        let trimmed = overridePhaseRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = SyncStatusOverride(rawValue: trimmed, now: dateGenerator.now)
        switch parsed {
        case .none:
            return false
        case .some(let resolved):
            state.status.phase = resolved.phase
            state.status.lastSuccessfulSync = resolved.lastSuccessfulSync
            return true
        }
    }
}

private enum SyncStallTimeoutDurationKey: DependencyKey {
    static let liveValue: Duration = .seconds(12)
    static let testValue: Duration = .seconds(12)
    static let previewValue: Duration = .seconds(12)
}

extension DependencyValues {
    var syncStallTimeoutDuration: Duration {
        get { self[SyncStallTimeoutDurationKey.self] }
        set { self[SyncStallTimeoutDurationKey.self] = newValue }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}

private struct SyncStatusOverride {
    var phase: SyncPhase
    var lastSuccessfulSync: Date?

    init?(rawValue: String, now: Date) {
        let lowercased = rawValue.lowercased()
        switch lowercased {
        case "idle":
            phase = .idle
            lastSuccessfulSync = nil
        case "syncing":
            phase = .syncing
            lastSuccessfulSync = nil
        case "up_to_date", "up-to-date", "uptodate", "up to date":
            phase = .upToDate
            lastSuccessfulSync = now
        default:
            if lowercased.hasPrefix("error") {
                let components = rawValue.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                let message = components.count > 1 ? components[1] : "Sync unavailable"
                phase = .error(SyncIssue(kind: .unknown, message: message, code: nil))
                lastSuccessfulSync = nil
            } else {
                return nil
            }
        }
    }
}
