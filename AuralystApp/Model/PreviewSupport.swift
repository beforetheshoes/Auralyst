import SwiftUI
import Dependencies

@MainActor
func withPreviewDataStore(@ViewBuilder content: () -> some View) -> some View {
    prepareDependencies {
        try! $0.bootstrapDatabase()
    }
    return content()
}
