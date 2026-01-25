import ConcurrencyExtras
import Dependencies
import SwiftUI
import Testing
import ComposableArchitecture
@testable import AuralystApp

@Suite("Sync status feature", .serialized)
struct SyncStatusFeatureTests {
    @MainActor
    @Test("Start sync remains syncing until engine finishes, then transitions to up to date")
    func startSyncHonorsEngineState() async throws {
        try prepareTestDependencies()

        let startState = StartCallState()
        let stateStream = SyncEngineStateStream(initialState: .syncing)
        let client = SyncEngineClient(
            start: {
                try await withCheckedThrowingContinuation { continuation in
                    Task { await startState.capture(continuation) }
                }
            },
            stop: {
                Task { await startState.incrementStop() }
            },
            observeState: { stateStream.stream }
        )

        let fixedDate = Date(timeIntervalSince1970: 1_704_000_000)

        let store = TestStore(
            initialState: SyncStatusFeature.State(
                shouldStartSync: true,
                overridePhaseRaw: nil
            )
        ) {
            SyncStatusFeature()
        } withDependencies: {
            $0.syncEngine = client
            $0.date.now = fixedDate
        }

        await store.send(.task) {
            $0.isStarting = true
            $0.status.phase = .syncing
            $0.isObserving = true
        }

        await store.receive(\.syncEngineStateUpdated) {
            $0.latestState = .syncing
            $0.status.phase = .syncing
        }

        await startState.waitForStartCall()
        await startState.resumeStartSuccessfully()

        await store.receive(\.startSyncResponse) {
            $0.isStarting = false
        }

        stateStream.yield(.upToDate)

        await store.receive(\.syncEngineStateUpdated) {
            $0.latestState = .upToDate
            $0.status.phase = .upToDate
            $0.status.lastSuccessfulSync = fixedDate
        }

        stateStream.finish()
        await store.finish()
    }

    @MainActor
    @Test("Failed start surfaces error phase and retains last success timestamp")
    func startSyncFailureSurfacesError() async throws {
        try prepareTestDependencies()

        let startState = StartCallState(throws: TestError())
        let client = SyncEngineClient(
            start: {
                try await withCheckedThrowingContinuation { continuation in
                    Task { await startState.capture(continuation) }
                }
            },
            stop: {
                Task { await startState.incrementStop() }
            },
            observeState: {
                AsyncStream { continuation in
                    continuation.finish()
                }
            }
        )

        let store = TestStore(
            initialState: SyncStatusFeature.State(
                shouldStartSync: true,
                overridePhaseRaw: nil
            )
        ) {
            SyncStatusFeature()
        } withDependencies: {
            $0.syncEngine = client
        }

        await store.send(.task) {
            $0.isStarting = true
            $0.status.phase = .syncing
            $0.isObserving = true
        }

        await store.receive(\.startSyncResponse) {
            $0.isStarting = false
            $0.status.phase = .error(SyncIssue(error: TestError()))
        }

        await store.finish()
    }

    @MainActor
    @Test("Background scene phase does not stop the sync engine")
    func backgroundScenePhaseDoesNotStopSyncEngine() async throws {
        try prepareTestDependencies()

        let stopCount = LockIsolated(0)
        let client = SyncEngineClient(
            start: {},
            stop: {
                stopCount.withValue { $0 += 1 }
            },
            observeState: {
                AsyncStream { continuation in
                    continuation.yield(.idle)
                    continuation.finish()
                }
            }
        )

        let store = TestStore(
            initialState: SyncStatusFeature.State(
                shouldStartSync: true,
                overridePhaseRaw: nil
            )
        ) {
            SyncStatusFeature()
        } withDependencies: {
            $0.syncEngine = client
        }

        await store.send(.scenePhaseChanged(.background))

        #expect(stopCount.value == 0)
    }
}

private actor StartCallState {
    private var continuation: CheckedContinuation<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var stopCount = 0
    private let thrownError: Error?

    init(throws error: Error? = nil) {
        self.thrownError = error
    }

    func capture(_ continuation: CheckedContinuation<Void, Error>) {
        if let thrownError {
            continuation.resume(throwing: thrownError)
            notifyWaiters()
            return
        }
        self.continuation = continuation
        notifyWaiters()
    }

    func waitForStartCall() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func resumeStartSuccessfully() {
        continuation?.resume()
        continuation = nil
    }

    func incrementStop() {
        stopCount += 1
        var remaining: [(expected: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in stopWaiters {
            if stopCount >= waiter.expected {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        stopWaiters = remaining
    }

    func waitForStopCount(_ expected: Int) async {
        guard stopCount < expected else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopWaiters.append((expected: expected, continuation: continuation))
        }
    }

    private func notifyWaiters() {
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private struct TestError: Error, CustomStringConvertible, Equatable {
    var description: String { "TestError" }
}

private final class SyncEngineStateStream: @unchecked Sendable {
    let stream: AsyncStream<SyncEngineClient.State>
    private let continuation: AsyncStream<SyncEngineClient.State>.Continuation

    init(initialState: SyncEngineClient.State) {
        var storedContinuation: AsyncStream<SyncEngineClient.State>.Continuation!
        self.stream = AsyncStream { continuation in
            storedContinuation = continuation
            continuation.yield(initialState)
        }
        self.continuation = storedContinuation
    }

    func yield(_ state: SyncEngineClient.State) {
        continuation.yield(state)
    }

    func finish() {
        continuation.finish()
    }
}

private extension SyncEngineClient.State {
    static var syncing: Self { .init(isRunning: true, isSynchronizing: true, isSendingChanges: true, isFetchingChanges: true) }
    static var upToDate: Self { .init(isRunning: true, isSynchronizing: false, isSendingChanges: false, isFetchingChanges: false) }
}
