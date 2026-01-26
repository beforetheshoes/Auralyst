import XCTest
@testable import AuralystApp

final class InitialOverlayStateTests: XCTestCase {
    func testIdleWithNoDataReturnsNil() {
        var state = AppFeature.State(
            isRunningTests: true,
            shouldStartSync: false,
            overridePhaseRaw: nil,
            bypassInitialOverlay: false
        )
        state.hasDeterminedInitialData = false
        state.syncPhase = .idle

        XCTAssertNil(initialOverlayState(state: state))
    }

    func testIdleWithShouldStartSyncReturnsSyncing() {
        var state = AppFeature.State(
            isRunningTests: true,
            shouldStartSync: true,
            overridePhaseRaw: nil,
            bypassInitialOverlay: false
        )
        state.hasDeterminedInitialData = false
        state.syncPhase = .idle

        XCTAssertEqual(initialOverlayState(state: state), .syncing)
    }

    func testSyncingReturnsSyncing() {
        var state = AppFeature.State(
            isRunningTests: true,
            shouldStartSync: true,
            overridePhaseRaw: nil,
            bypassInitialOverlay: false
        )
        state.syncPhase = .syncing

        XCTAssertEqual(initialOverlayState(state: state), .syncing)
    }

    func testErrorReturnsError() {
        var state = AppFeature.State(
            isRunningTests: true,
            shouldStartSync: true,
            overridePhaseRaw: nil,
            bypassInitialOverlay: false
        )
        state.syncPhase = .error(SyncIssue(kind: .network, message: "Offline"))

        XCTAssertEqual(initialOverlayState(state: state), .error(message: "Offline"))
    }

    func testDeterminedDataBypassesOverlay() {
        var state = AppFeature.State(
            isRunningTests: true,
            shouldStartSync: true,
            overridePhaseRaw: nil,
            bypassInitialOverlay: false
        )
        state.hasDeterminedInitialData = true
        state.syncPhase = .syncing

        XCTAssertNil(initialOverlayState(state: state))
    }
}
