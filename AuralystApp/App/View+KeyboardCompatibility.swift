import SwiftUI

extension View {
    @ViewBuilder
    func decimalPadKeyboard() -> some View {
        #if os(iOS)
        self.keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
