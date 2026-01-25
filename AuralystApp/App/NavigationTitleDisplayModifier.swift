import SwiftUI

extension View {
    @ViewBuilder
    func inlineNavigationTitleDisplay() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func largeNavigationTitleDisplay() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}
