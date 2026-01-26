import Foundation

enum InitialOverlayState: Equatable {
    case syncing
    case error(message: String)
}

func initialOverlayState(state: AppFeature.State) -> InitialOverlayState? {
    guard !state.bypassInitialOverlay, state.hasDeterminedInitialData == false else { return nil }
    switch state.syncPhase {
    case .syncing:
        return .syncing
    case .idle where state.shouldStartSync:
        return .syncing
    case .error(let issue):
        return .error(message: issue.message)
    default:
        return nil
    }
}
