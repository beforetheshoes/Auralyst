import CoreData
import SwiftUI

@main
struct AuralystApp: App {
    @State private var sceneModel = AppSceneModel()
    private let persistence = PersistenceController.shared

    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sceneModel)
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}

private extension AuralystApp {
    func configureAppearance() {
        UINavigationBar.appearance().tintColor = UIColor(Color.brandAccent)
    }
}
