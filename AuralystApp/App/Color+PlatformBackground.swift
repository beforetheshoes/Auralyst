import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    static var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
}
