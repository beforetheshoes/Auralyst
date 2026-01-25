import Foundation
import Dependencies

struct FileExportClient {
    var export: @Sendable (_ journal: SQLiteJournal, _ format: ExportFormat) async throws -> URL
    var cleanup: @Sendable (_ url: URL) async -> Void
}

extension FileExportClient {
    static let live = FileExportClient(
        export: { journal, format in
            let data: Data
            let fileExtension: String

            switch format {
            case .csv:
                data = try DataExporter.exportCSV(for: journal)
                fileExtension = "csv"
            case .json:
                data = try DataExporter.exportJSON(for: journal)
                fileExtension = "json"
            }

            let filename = "Auralyst-\(journal.id.uuidString).\(fileExtension)"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: [.atomic])
            return url
        },
        cleanup: { url async in
            try? FileManager.default.removeItem(at: url)
        }
    )
}

private enum FileExportClientKey: DependencyKey {
    static let liveValue = FileExportClient.live
    static let testValue = FileExportClient(
        export: { _, _ in
            fatalError("FileExportClient.export unimplemented")
        },
        cleanup: { _ async in }
    )
}

extension DependencyValues {
    var fileExportClient: FileExportClient {
        get { self[FileExportClientKey.self] }
        set { self[FileExportClientKey.self] = newValue }
    }
}
