import Foundation
import Testing
import Dependencies
import ComposableArchitecture
@testable import AuralystApp

extension AppFeatureTests {
    @MainActor
    @Test("journalsChanged resolves initial data when not empty")
    func journalsChangedResolvesInitialData() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: false
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        #expect(testStore.state.hasDeterminedInitialData == false)

        await testStore.send(.journalsChanged(isEmpty: false)) {
            $0.journalsEmpty = false
            $0.hasDeterminedInitialData = true
        }
    }

    @MainActor
    @Test("syncPhaseChanged to upToDate resolves initial data")
    func syncPhaseUpToDateResolvesInitialData() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: false
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        #expect(testStore.state.hasDeterminedInitialData == false)

        await testStore.send(.syncPhaseChanged(.upToDate)) {
            $0.syncPhase = .upToDate
            $0.hasDeterminedInitialData = true
        }
    }

    @MainActor
    @Test("syncPhaseChanged to error resolves initial data")
    func syncPhaseErrorResolvesInitialData() async throws {
        try prepareTestDependencies()

        let issue = SyncIssue(kind: .network, message: "Offline")
        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: false
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.syncPhaseChanged(.error(issue))) {
            $0.syncPhase = .error(issue)
            $0.hasDeterminedInitialData = true
        }
    }

    @MainActor
    @Test("syncPhaseChanged to syncing does not resolve initial data")
    func syncPhaseSyncingDoesNotResolve() async throws {
        try prepareTestDependencies()

        let testStore = TestStore(
            initialState: AppFeature.State(
                isRunningTests: true,
                shouldStartSync: false,
                overridePhaseRaw: nil,
                bypassInitialOverlay: false
            )
        ) {
            AppFeature()
        }
        testStore.exhaustivity = .off

        await testStore.send(.syncPhaseChanged(.syncing)) {
            $0.syncPhase = .syncing
        }

        #expect(testStore.state.hasDeterminedInitialData == false)
    }
}
