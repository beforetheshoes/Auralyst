import Foundation
import Dependencies

struct ImportClient {
    var analyze: @Sendable (_ url: URL) async throws -> ImportAnalysis
    var importJournal: @Sendable (
        _ url: URL, _ replaceExisting: Bool, _ resolution: ImportResolution
    ) async throws -> ImportResult
}

private enum ImportClientKey: DependencyKey {
    static let liveValue = ImportClient(
        analyze: { url in
            try await Task.detached {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try DataImporter.analyzeFile(at: url)
            }.value
        },
        importJournal: { url, replaceExisting, resolution in
            try await Task.detached {
                let accessGranted = url.startAccessingSecurityScopedResource()
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                return try DataImporter.importFile(
                    at: url,
                    replaceExisting: replaceExisting,
                    resolution: resolution
                )
            }.value
        }
    )

    static let testValue = ImportClient(
        analyze: { _ in
            throw ImportError.invalidPayload("ImportClient.analyze unimplemented")
        },
        importJournal: { _, _, _ in
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
