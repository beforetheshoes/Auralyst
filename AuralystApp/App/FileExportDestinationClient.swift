import Foundation
import Dependencies

enum FileExportPresentation: Equatable {
    case documentPicker(URL)
    case saved(URL)
    case cancelled
}

struct FileExportDestinationClient {
    var present: @Sendable (_ url: URL, _ format: ExportFormat) async throws -> FileExportPresentation
}

extension FileExportDestinationClient {
    static let iOS = FileExportDestinationClient { url, _ in
        .documentPicker(url)
    }
}

private enum FileExportDestinationClientKey: DependencyKey {
    static let liveValue: FileExportDestinationClient = {
        #if os(macOS)
        return .mac
        #else
        return .iOS
        #endif
    }()

    static let testValue = FileExportDestinationClient(
        present: { _, _ in
            fatalError("FileExportDestinationClient.present unimplemented")
        }
    )
}

extension DependencyValues {
    var fileExportDestinationClient: FileExportDestinationClient {
        get { self[FileExportDestinationClientKey.self] }
        set { self[FileExportDestinationClientKey.self] = newValue }
    }
}

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

extension FileExportDestinationClient {
    static let mac = FileExportDestinationClient { url, _ in
        try await MacExportDestinationChooser().chooseDestination(for: url)
    }
}

@MainActor
private struct MacExportDestinationChooser {
    func chooseDestination(for url: URL) async throws -> FileExportPresentation {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        if let contentType = UTType(filenameExtension: url.pathExtension) {
            panel.allowedContentTypes = [contentType]
        }

        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
        }

        guard response == .OK, let destination = panel.url else {
            return .cancelled
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: url, to: destination)
        return .saved(destination)
    }
}
#endif
