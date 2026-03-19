import ComposableArchitecture
import SwiftUI

struct AppRootScene: Scene {
    let store: StoreOf<AppFeature>

    @State private var sceneModel = AppSceneModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(
                store: store
            )
            .environment(sceneModel)
        }
    }
}

private struct AppRootView: View {
    let store: StoreOf<AppFeature>

    init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.isRunningTests {
                Text("Running Tests")
            } else {
                ContentView(store: store)
            }
        }
        .task {
            guard store.shouldStartSync else { return }
            store.send(.task)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard store.shouldStartSync else { return }
            store.send(.scenePhaseChanged(newPhase))
        }
    }
}
