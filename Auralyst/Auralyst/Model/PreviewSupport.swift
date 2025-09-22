import SwiftUI
import Dependencies

@MainActor
func withPreviewDataStore(@ViewBuilder content: (DataStore) -> some View) -> some View {
    prepareDependencies {
        try! $0.bootstrapDatabase()
    }
    let dataStore = DataStore()
    return content(dataStore)
        .environment(dataStore)
}
