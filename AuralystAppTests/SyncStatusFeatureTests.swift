import ConcurrencyExtras
import Dependencies
import SwiftUI
import Testing
import ComposableArchitecture
@testable import AuralystApp

@Suite("Sync status feature", .serialized)
struct SyncStatusFeatureTests {
    @MainActor
    @Test("Start sync honors engine state transitions")
    func startSyncHonorsEngineState() async throws {
        try prepareTestDependencies()

        let startState = StartCallState()
        let stateStream = SyncEngineStateStream(
            initialState: .syncing
        )
        let client = makeSyncClient(
            startState: startState,
            stateStream: stateStream
        )

        let fixedDate = Date(
            timeIntervalSince1970: 1_704_000_000
        )

        let store = makeSyncStore(
            client: client, fixedDate: fixedDate
        )
        store.exhaustivity = .off(
            showSkippedAssertions: false
        )

        await store.send(.task) {
            $0.isStarting = true
            $0.status.phase = .syncing
            $0.isObserving = true
        }

        await store.receive(\.syncEngineStateUpdated) {
            $0.latestState = .syncing
            $0.syncingSince = fixedDate
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
            $0.syncingSince = nil
            $0.status.phase = .upToDate
            $0.status.lastSuccessfulSync = fixedDate
        }

        stateStream.finish()
        await store.finish()
    }

    @MainActor
    @Test("Stall timeout promotes syncing to up to date")
    func stallTimeoutPromotesToUpToDate() async throws {
        try prepareTestDependencies()

        let startState = StartCallState()
        let stalledState = SyncEngineClient.State(
            isRunning: true,
            isSynchronizing: true,
            isSendingChanges: false,
            isFetchingChanges: false
        )
        let stateStream = SyncEngineStateStream(
            initialState: stalledState
        )
        let client = makeSyncClient(
            startState: startState,
            stateStream: stateStream
        )

        let fixedDate = Date(
            timeIntervalSince1970: 1_704_000_100
        )

        let store = makeSyncStore(
            client: client, fixedDate: fixedDate
        )

        await store.send(.task) {
            $0.isStarting = true
            $0.status.phase = .syncing
            $0.isObserving = true
        }

        await store.receive(\.syncEngineStateUpdated) {
            $0.latestState = stalledState
            $0.syncingSince = fixedDate
            $0.status.phase = .syncing
        }

        await startState.waitForStartCall()
        await startState.resumeStartSuccessfully()

        await store.receive(\.startSyncResponse) {
            $0.isStarting = false
        }

        try? await Task.sleep(nanoseconds: 80_000_000)

        await store.receive(\.syncStallTimeoutFired) {
            $0.status.phase = .upToDate
            $0.status.lastSuccessfulSync = fixedDate
        }

        stateStream.finish()
        await store.finish()
    }
}

// MARK: - Additional Sync Tests

extension SyncStatusFeatureTests {
    @MainActor
    @Test("Stall timeout promotes long-running sync")
    func stallTimeoutPromotesLongRunningSync() async throws {
        try prepareTestDependencies()

        let busyState = SyncEngineClient.State(
            isRunning: true,
            isSynchronizing: true,
            isSendingChanges: true,
            isFetchingChanges: true
        )
        let syncingSince = Date(
            timeIntervalSince1970: 1_704_000_200
        )
        let now = syncingSince.addingTimeInterval(60)

        let store = TestStore(
            initialState: SyncStatusFeature.State(
                status: SyncStatus(
                    phase: .syncing,
                    lastSuccessfulSync: nil
                ),
                latestState: busyState,
                syncingSince: syncingSince,
                shouldStartSync: true,
                overridePhaseRaw: nil
            )
        ) {
            SyncStatusFeature()
        } withDependencies: {
            $0.date.now = now
            $0.syncStallTimeoutDuration = .milliseconds(20)
        }

        await store.send(.syncStallTimeoutFired) {
            $0.status.phase = .upToDate
            $0.status.lastSuccessfulSync = now
        }
        await store.finish()
    }

    @MainActor
    @Test("Failed start surfaces error phase")
    func startSyncFailureSurfacesError() async throws {
        try prepareTestDependencies()

        let startState = StartCallState(
            throws: SyncTestError()
        )
        let client = SyncEngineClient(
            start: {
                try await withCheckedThrowingContinuation { cont in
                    Task { await startState.capture(cont) }
                }
            },
            stop: {
                Task { await startState.incrementStop() }
            },
            observeState: {
                AsyncStream { $0.finish() }
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
            $0.status.phase = .error(
                SyncIssue(error: SyncTestError())
            )
        }

        await store.finish()
    }

    @MainActor
    @Test("Repeated activation does not start sync twice")
    func repeatedActivePhaseDoesNotStartTwice() async throws {
        try prepareTestDependencies()

        let startState = StartCallState()
        let client = SyncEngineClient(
            start: {
                try await withCheckedThrowingContinuation { cont in
                    Task { await startState.capture(cont) }
                }
            },
            stop: {},
            observeState: {
                AsyncStream { $0.finish() }
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

        await startState.waitForStartCall()
        await store.send(.scenePhaseChanged(.active))

        let startCount = await startState.getStartCount()
        #expect(startCount == 1)

        await startState.resumeStartSuccessfully()

        await store.receive(\.startSyncResponse) {
            $0.isStarting = false
        }

        await store.finish()
    }

    @MainActor
    @Test("Stall timeout fires at exact boundary (>= not >)")
    func stallTimeoutAtExactBoundaryFires() async throws {
        try prepareTestDependencies()

        let timeoutDuration: Duration = .milliseconds(500)
        let syncingSince = Date(timeIntervalSince1970: 1_704_000_000)
        // now - syncingSince == exactly timeoutDuration (0.5s)
        let now = syncingSince.addingTimeInterval(0.5)

        let busyState = SyncEngineClient.State(
            isRunning: true,
            isSynchronizing: true,
            isSendingChanges: true,
            isFetchingChanges: true
        )

        let store = TestStore(
            initialState: SyncStatusFeature.State(
                status: SyncStatus(
                    phase: .syncing,
                    lastSuccessfulSync: nil
                ),
                latestState: busyState,
                syncingSince: syncingSince,
                shouldStartSync: true,
                overridePhaseRaw: nil
            )
        ) {
            SyncStatusFeature()
        } withDependencies: {
            $0.date.now = now
            $0.syncStallTimeoutDuration = timeoutDuration
        }

        // With >=, 0.5 >= 0.5 is true, so phase should promote to upToDate
        await store.send(.syncStallTimeoutFired) {
            $0.status.phase = .upToDate
            $0.status.lastSuccessfulSync = now
        }
        await store.finish()
    }

    @MainActor
    @Test("Background phase does not stop sync engine")
    func backgroundDoesNotStopSyncEngine() async throws {
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
