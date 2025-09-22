import SwiftUI
import SQLiteData

@main
struct AuralystApp: App {
    @State private var sceneModel = AppSceneModel()
    @State private var dataStore = DataStore()

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        configureAppearance()
        prepareDependencies { try! $0.bootstrapDatabase() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isRunningTests {
                    Text("Running Tests")
                } else {
                    ContentView()
                        .environment(sceneModel)
                }
            }
            .environment(dataStore)
        }
    }
}

private extension AuralystApp {
    func configureAppearance() {
        UINavigationBar.appearance().tintColor = UIColor(Color.brandAccent)
    }
}
