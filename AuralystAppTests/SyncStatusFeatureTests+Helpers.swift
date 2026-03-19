import Foundation
import ConcurrencyExtras
import Dependencies
import Testing
import ComposableArchitecture
@testable import AuralystApp

// MARK: - Store Factories

@MainActor
func makeSyncStore(
    client: SyncEngineClient,
    fixedDate: Date
) -> TestStore<
    SyncStatusFeature.State, SyncStatusFeature.Action
> {
    TestStore(
        initialState: SyncStatusFeature.State(
            shouldStartSync: true,
            overridePhaseRaw: nil
        )
    ) {
        SyncStatusFeature()
    } withDependencies: {
        $0.syncEngine = client
        $0.date.now = fixedDate
        $0.syncStallTimeoutDuration = .milliseconds(20)
    }
}

func makeSyncClient(
    startState: StartCallState,
    stateStream: SyncEngineStateStream
) -> SyncEngineClient {
    SyncEngineClient(
        start: {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await startState.capture(continuation)
                }
            }
        },
        stop: {
            Task { await startState.incrementStop() }
        },
        observeState: { stateStream.stream }
    )
}

// MARK: - Test Doubles

actor StartCallState {
    private var continuation: CheckedContinuation<Void, Error>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [
        (expected: Int,
         continuation: CheckedContinuation<Void, Never>)
    ] = []
    private(set) var stopCount = 0
    private var startCount = 0
    private let thrownError: Error?

    init(throws error: Error? = nil) {
        self.thrownError = error
    }

    func capture(
        _ continuation: CheckedContinuation<Void, Error>
    ) {
        startCount += 1
        if let thrownError {
            continuation.resume(throwing: thrownError)
            notifyWaiters()
            return
        }
        self.continuation = continuation
        notifyWaiters()
    }

    func getStartCount() -> Int {
        startCount
    }

    func waitForStartCall() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    func resumeStartSuccessfully() {
        continuation?.resume()
        continuation = nil
    }

    func incrementStop() {
        stopCount += 1
        var remaining: [
            (expected: Int,
             continuation: CheckedContinuation<Void, Never>)
        ] = []
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
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            stopWaiters.append((expected: expected, continuation: cont))
        }
    }

    private func notifyWaiters() {
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

struct SyncTestError: Error, CustomStringConvertible, Equatable {
    var description: String { "TestError" }
}

final class SyncEngineStateStream: @unchecked Sendable {
    let stream: AsyncStream<SyncEngineClient.State>
    private let continuation:
        AsyncStream<SyncEngineClient.State>.Continuation

    init(initialState: SyncEngineClient.State) {
        var stored:
            AsyncStream<SyncEngineClient.State>.Continuation!
        self.stream = AsyncStream { continuation in
            stored = continuation
            continuation.yield(initialState)
        }
        self.continuation = stored
    }

    func yield(_ state: SyncEngineClient.State) {
        continuation.yield(state)
    }

    func finish() {
        continuation.finish()
    }
}

extension SyncEngineClient.State {
    static var syncing: Self {
        .init(
            isRunning: true,
            isSynchronizing: true,
            isSendingChanges: true,
            isFetchingChanges: true
        )
    }
    static var upToDate: Self {
        .init(
            isRunning: true,
            isSynchronizing: false,
            isSendingChanges: false,
            isFetchingChanges: false
        )
    }
}
