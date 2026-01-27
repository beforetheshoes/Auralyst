import Foundation
import Dependencies

struct ImportClient {
    var importJournal: @Sendable (_ url: URL, _ replaceExisting: Bool) async throws -> ImportResult
}

private enum ImportClientKey: DependencyKey {
    static let liveValue = ImportClient(
        importJournal: { url, replaceExisting in
            try await Task.detached {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try DataImporter.importFile(at: url, replaceExisting: replaceExisting)
            }.value
        }
    )

    static let testValue = ImportClient(
        importJournal: { _, _ in
            throw ImportError.invalidPayload("ImportClient.importJournal unimplemented")
        }
    )
}

extension DependencyValues {
    var importClient: ImportClient {
        get { self[ImportClientKey.self] }
        set { self[ImportClientKey.self] = newValue }
    }
}
