import Foundation
import Dependencies
import Testing
import ComposableArchitecture
import CasePaths
@testable import AuralystApp

@Suite("Export feature", .serialized)
struct ExportFeatureTests {
    @MainActor
    @Test("Export success requests document picker")
    func exportSuccessRequestsDocumentPicker() async {
        let journal = SQLiteJournal()
        let expectedURL = URL(fileURLWithPath: "/tmp/Export.csv")

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { inputJournal in
                #expect(inputJournal.id == journal.id)
                return ExportPreflightReport(issues: [])
            }
            $0.exportPreflightClient.autoFix = { _ in
                Issue.record("Auto-fix should not run")
                return ExportPreflightReport(issues: [])
            }
            $0.fileExportClient.export = { input, format in
                #expect(input.id == journal.id)
                #expect(format == .csv)
                return expectedURL
            }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { url, fmt in
                #expect(url == expectedURL)
                #expect(fmt == .csv)
                return .documentPicker(url)
            }
        }

        await store.send(.exportTapped(.csv)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
        }

        await store.receive(\.proceedExport) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.exportResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.preflightReport = nil
            $0.pendingFormat = nil
            $0.exportedFileURL = expectedURL
            $0.savedDestinationURL = nil
            $0.isShowingDocumentPicker = true
        }
    }

    @MainActor
    @Test("Export failure publishes error")
    func exportFailurePublishesError() async {
        struct SampleError: LocalizedError {
            var errorDescription: String? { "failed" }
        }

        let journal = SQLiteJournal()

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { _ in
                ExportPreflightReport(issues: [])
            }
            $0.exportPreflightClient.autoFix = { _ in
                ExportPreflightReport(issues: [])
            }
            $0.fileExportClient.export = { _, _ in
                throw SampleError()
            }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { _, _ in
                Issue.record("Should not request destination")
                return .cancelled
            }
        }

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
        }

        await store.receive(\.proceedExport) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.exportResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.errorMessage = "failed"
            $0.exportedFileURL = nil
            $0.savedDestinationURL = nil
            $0.isShowingDocumentPicker = false
        }
    }
}

// MARK: - Cleanup & Destination Tests

extension ExportFeatureTests {
    @MainActor
    @Test("Cleanup removes temporary file when saved")
    func cleanupRemovesTemporaryFile() async {
        let journal = SQLiteJournal()
        let expectedURL = URL(
            fileURLWithPath: "/tmp/Export.json"
        )
        let cleanupRecorder = CleanupRecorder()

        let store = makeCleanupStore(
            journal: journal,
            exportURL: expectedURL,
            cleanupRecorder: cleanupRecorder,
            destinationResult: .saved(expectedURL)
        )

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
        }

        await store.receive(\.proceedExport) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.exportResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.preflightReport = nil
            $0.pendingFormat = nil
            $0.exportedFileURL = nil
            $0.savedDestinationURL = expectedURL
            $0.isShowingDocumentPicker = false
        }

        await store.receive(\.cleanupFinished)
        let cleanedURL = await cleanupRecorder.value
        #expect(cleanedURL == expectedURL)
    }

    @MainActor
    @Test("Cancelled export cleans up temporary file")
    func cancelledExportCleansUpTemporaryFile() async {
        let journal = SQLiteJournal()
        let temporary = URL(
            fileURLWithPath: "/tmp/Cancelled.json"
        )
        let cleanupRecorder = CleanupRecorder()

        let store = makeCleanupStore(
            journal: journal,
            exportURL: temporary,
            cleanupRecorder: cleanupRecorder,
            destinationResult: .cancelled
        )

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
        }

        await store.receive(\.proceedExport) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.exportResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.preflightReport = nil
            $0.pendingFormat = nil
            $0.exportedFileURL = nil
            $0.savedDestinationURL = nil
            $0.isShowingDocumentPicker = false
        }

        await store.receive(\.cleanupFinished)
        let cleanedURL = await cleanupRecorder.value
        #expect(cleanedURL == temporary)
    }

    @MainActor
    @Test("Clearing saved destination")
    func clearingSavedDestination() async {
        let journal = SQLiteJournal()
        let destination = URL(
            fileURLWithPath: "/tmp/Export.json"
        )

        let store = makeCleanupStore(
            journal: journal,
            exportURL: destination,
            cleanupRecorder: CleanupRecorder(),
            destinationResult: .saved(destination)
        )

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
        }

        await store.receive(\.proceedExport) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.exportResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.preflightReport = nil
            $0.pendingFormat = nil
            $0.exportedFileURL = nil
            $0.savedDestinationURL = destination
            $0.isShowingDocumentPicker = false
        }

        await store.receive(\.cleanupFinished)

        await store.send(.clearSavedDestination) {
            $0.savedDestinationURL = nil
        }
    }
}

// MARK: - Test Helpers

@MainActor
private func makeCleanupStore(
    journal: SQLiteJournal,
    exportURL: URL,
    cleanupRecorder: CleanupRecorder,
    destinationResult: FileExportPresentation
) -> TestStore<
    ExportFeature.State, ExportFeature.Action
> {
    TestStore(
        initialState: ExportFeature.State(journal: journal)
    ) {
        ExportFeature()
    } withDependencies: {
        $0.exportPreflightClient.check = { _ in
            ExportPreflightReport(issues: [])
        }
        $0.exportPreflightClient.autoFix = { _ in
            ExportPreflightReport(issues: [])
        }
        $0.fileExportClient.export = { _, _ in exportURL }
        $0.fileExportClient.cleanup = { url in
            await cleanupRecorder.record(url)
        }
        $0.fileExportDestinationClient.present = { _, _ in
            destinationResult
        }
    }
}

private actor CleanupRecorder {
    private(set) var value: URL?

    func record(_ url: URL) {
        value = url
    }
}
