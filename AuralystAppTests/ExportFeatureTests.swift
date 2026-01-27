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
                Issue.record("Auto-fix should not run for clean data")
                return ExportPreflightReport(issues: [])
            }
            $0.fileExportClient.export = { inputJournal, format in
                #expect(inputJournal.id == journal.id)
                #expect(format == .csv)
                return expectedURL
            }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { url, format in
                #expect(url == expectedURL)
                #expect(format == .csv)
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
            $0.exportPreflightClient.check = { _ in ExportPreflightReport(issues: []) }
            $0.exportPreflightClient.autoFix = { _ in ExportPreflightReport(issues: []) }
            $0.fileExportClient.export = { _, _ in
                throw SampleError()
            }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { _, _ in
                Issue.record("Should not request destination when export fails")
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

    @MainActor
    @Test("Cleanup removes temporary file when saved")
    func cleanupRemovesTemporaryFile() async {
        let journal = SQLiteJournal()
        let expectedURL = URL(fileURLWithPath: "/tmp/Export.json")
        let cleanupRecorder = CleanupRecorder()

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { _ in ExportPreflightReport(issues: []) }
            $0.exportPreflightClient.autoFix = { _ in ExportPreflightReport(issues: []) }
            $0.fileExportClient.export = { _, _ in expectedURL }
            $0.fileExportClient.cleanup = { url in
                await cleanupRecorder.record(url)
            }
            $0.fileExportDestinationClient.present = { url, format in
                #expect(url == expectedURL)
                #expect(format == .json)
                return .saved(url)
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
        let temporary = URL(fileURLWithPath: "/tmp/Cancelled.json")
        let cleanupRecorder = CleanupRecorder()

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { _ in ExportPreflightReport(issues: []) }
            $0.exportPreflightClient.autoFix = { _ in ExportPreflightReport(issues: []) }
            $0.fileExportClient.export = { _, _ in temporary }
            $0.fileExportClient.cleanup = { url in
                await cleanupRecorder.record(url)
            }
            $0.fileExportDestinationClient.present = { url, _ in
                #expect(url == temporary)
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
        let destination = URL(fileURLWithPath: "/tmp/Export.json")

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { _ in ExportPreflightReport(issues: []) }
            $0.exportPreflightClient.autoFix = { _ in ExportPreflightReport(issues: []) }
            $0.fileExportClient.export = { _, _ in destination }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { url, _ in
                #expect(url == destination)
                return .saved(url)
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

    @MainActor
    @Test("Preflight issues present dialog and auto-fix proceeds")
    func preflightIssuesAutoFixAndExport() async {
        let journal = SQLiteJournal()
        let expectedURL = URL(fileURLWithPath: "/tmp/Preflight.json")
        let issues = [
            ExportPreflightIssue(
                kind: .missingScheduleReferences,
                count: 2,
                examples: ["a -> b"]
            )
        ]

        let store = TestStore(
            initialState: ExportFeature.State(journal: journal)
        ) {
            ExportFeature()
        } withDependencies: {
            $0.exportPreflightClient.check = { _ in ExportPreflightReport(issues: issues) }
            $0.exportPreflightClient.autoFix = { _ in ExportPreflightReport(issues: []) }
            $0.fileExportClient.export = { _, _ in expectedURL }
            $0.fileExportClient.cleanup = { _ in }
            $0.fileExportDestinationClient.present = { url, _ in .documentPicker(url) }
        }

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
            $0.preflightReport = ExportPreflightReport(issues: issues)
            $0.pendingFormat = .json
            $0.isShowingPreflightDialog = true
        }

        await store.send(.preflightAutoFixTapped) {
            $0.isShowingPreflightDialog = false
            $0.isGenerating = true
            $0.isAutoFixing = true
        }

        await store.receive(\.preflightAutoFixResponse) {
            $0.isGenerating = false
            $0.isAutoFixing = false
            $0.preflightReport = nil
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
}

private actor CleanupRecorder {
    private(set) var value: URL?

    func record(_ url: URL) {
        value = url
    }
}
