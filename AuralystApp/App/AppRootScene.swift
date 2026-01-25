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
        WithViewStore(store, observe: { $0 }) { viewStore in
            Group {
                if viewStore.isRunningTests {
                    Text("Running Tests")
                } else {
                    ContentView(store: store)
                }
            }
            .task {
                guard viewStore.shouldStartSync else { return }
                viewStore.send(.task)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard viewStore.shouldStartSync else { return }
                viewStore.send(.scenePhaseChanged(newPhase))
            }
        }
    }
}
