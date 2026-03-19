import SwiftUI
import Dependencies

@MainActor
func withPreviewDataStore(@ViewBuilder content: () -> some View) -> some View {
    prepareDependencies {
        do {
            try $0.bootstrapDatabase()
        } catch {
            fatalError("Failed to bootstrap preview database: \(error)")
        }
    }
    return content()
}

/// Wraps a throwing expression for use in preview `@ViewBuilder` closures
/// where `guard` and `do/catch` are not supported.
@MainActor
func previewValue<T>(_ block: () throws -> T) -> T {
    do {
        return try block()
    } catch {
        fatalError("Preview setup failed: \(error)")
    }
}
