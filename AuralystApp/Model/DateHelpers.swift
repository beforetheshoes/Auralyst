import Foundation

extension ISO8601DateFormatter {
    static var exportFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

extension Date {
    var iso8601ExportString: String {
        ISO8601DateFormatter.exportFormatter.string(from: self)
    }
}
