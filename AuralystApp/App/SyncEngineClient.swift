import CloudKit
import ConcurrencyExtras
import Dependencies
import Observation
@preconcurrency import SQLiteData

struct SyncEngineClient: Sendable {
    var start: @Sendable () async throws -> Void
    var stop: @Sendable () -> Void
    var shareJournal: @Sendable (_ journal: SQLiteJournal, _ configure: @Sendable (CKShare) -> Void) async throws -> SharedRecord
    var observeState: @Sendable () -> AsyncStream<State>

    init(
        start: @escaping @Sendable () async throws -> Void,
        stop: @escaping @Sendable () -> Void,
        shareJournal: @escaping @Sendable (_ journal: SQLiteJournal, _ configure: @Sendable (CKShare) -> Void) async throws -> SharedRecord = { _, _ in
            throw SyncEngineClientError.unimplemented
        },
        observeState: @escaping @Sendable () -> AsyncStream<State> = {
            AsyncStream { continuation in
                continuation.yield(.idle)
                continuation.finish()
            }
        }
    ) {
        self.start = start
        self.stop = stop
        self.shareJournal = shareJournal
        self.observeState = observeState
    }
}

extension SyncEngineClient {
    struct State: Sendable, Equatable {
        var isRunning: Bool
        var isSynchronizing: Bool
        var isSendingChanges: Bool
        var isFetchingChanges: Bool

        static let idle = State(
            isRunning: false,
            isSynchronizing: false,
            isSendingChanges: false,
            isFetchingChanges: false
        )
    }
}

private enum SyncEngineClientKey: DependencyKey {
    static let liveValue: SyncEngineClient = .live
    static let testValue: SyncEngineClient = .unimplemented
    static let previewValue: SyncEngineClient = .preview
}

extension DependencyValues {
    var syncEngine: SyncEngineClient {
        get { self[SyncEngineClientKey.self] }
        set { self[SyncEngineClientKey.self] = newValue }
    }
}

private struct SyncEngineObservationState {
    var continuation: CheckedContinuation<Void, Never>?
    var didYield = false
}

extension SyncEngineObservationState: @unchecked Sendable {}

private extension SyncEngineClient {
    static var live: SyncEngineClient {
        SyncEngineClient(
            start: {
                @Dependency(\.defaultSyncEngine) var syncEngine
                try await syncEngine.start()
            },
            stop: {
                @Dependency(\.defaultSyncEngine) var syncEngine
                syncEngine.stop()
            },
            shareJournal: { journal, configure in
                @Dependency(\.defaultSyncEngine) var syncEngine
                return try await syncEngine.share(record: journal, configure: configure)
            },
            observeState: {
                @Dependency(\.defaultSyncEngine) var syncEngine
                return makeStateStream(from: syncEngine)
            }
        )
    }

    static var preview: SyncEngineClient {
        SyncEngineClient(
            start: {},
            stop: {},
            shareJournal: { _, _ in throw SyncEngineClientError.previewUnavailable },
            observeState: {
                AsyncStream { continuation in
                    continuation.yield(.idle)
                    continuation.finish()
                }
            }
        )
    }

    static var unimplemented: SyncEngineClient {
        SyncEngineClient(
            start: { throw SyncEngineClientError.unimplemented },
            stop: { fatalError("SyncEngineClient.stop unimplemented") },
            shareJournal: { _, _ in throw SyncEngineClientError.unimplemented },
            observeState: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        )
    }
}

private extension SyncEngineClient {
    static func makeStateStream(from syncEngine: SQLiteData.SyncEngine) -> AsyncStream<State> {
        AsyncStream { continuation in
            let observationState = LockIsolated(SyncEngineObservationState())
            let task = Task { @MainActor [weak syncEngine] in
                guard let syncEngine else {
                    continuation.finish()
                    return
                }

                continuation.yield(State(syncEngine: syncEngine))

                while !Task.isCancelled {
                    observationState.withValue {
                        $0.continuation = nil
                        $0.didYield = false
                    }
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                            observationState.withValue {
                                $0.continuation = resume
                                $0.didYield = false
                            }
                            withObservationTracking {
                                _ = syncEngine.isRunning
                                _ = syncEngine.isSynchronizing
                                _ = syncEngine.isSendingChanges
                                _ = syncEngine.isFetchingChanges
                            } onChange: {
                                guard !Task.isCancelled else { return }
                                let continuationToResume: CheckedContinuation<Void, Never>? = observationState.withValue {
                                    guard !$0.didYield else { return nil }
                                    $0.didYield = true
                                    let pending = $0.continuation
                                    $0.continuation = nil
                                    return pending
                                }
                                guard let continuationToResume else { return }
                                continuation.yield(State(syncEngine: syncEngine))
                                continuationToResume.resume()
                            }
                        }
                    } onCancel: {
                        observationState.withValue { state in
                            state.continuation?.resume()
                            state.continuation = nil
                        }
                    }
                }

                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private extension SyncEngineClient.State {
    init(syncEngine: SQLiteData.SyncEngine) {
        self.init(
            isRunning: syncEngine.isRunning,
            isSynchronizing: syncEngine.isSynchronizing,
            isSendingChanges: syncEngine.isSendingChanges,
            isFetchingChanges: syncEngine.isFetchingChanges
        )
    }
}

enum SyncEngineClientError: Error {
    case unimplemented
    case previewUnavailable
}
