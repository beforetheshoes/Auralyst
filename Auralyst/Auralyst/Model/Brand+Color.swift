import SwiftUI

extension Color {
    static let ink = Color(hex: 0x0F172A)
    static let primary = Color(hex: 0x2563EB)
    static let brandPrimary = Color(hex: 0x2563EB)
    static let primaryDark = Color(hex: 0x60A5FA)
    static let brandAccent = Color(hex: 0xF59E0B)
    static let brandAccentDark = Color(hex: 0xFBBF24)
    static let surfaceLight = Color(hex: 0xF8FAFC)
    static let surfaceDark = Color(hex: 0x0B1220)
}

private extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let red = Double((hex & 0xFF0000) >> 16) / 255.0
        let green = Double((hex & 0x00FF00) >> 8) / 255.0
        let blue = Double(hex & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}
