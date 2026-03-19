import Foundation
import Dependencies
import Testing
import ComposableArchitecture
import CasePaths
@testable import AuralystApp

// MARK: - Preflight Tests

extension ExportFeatureTests {
    @MainActor
    @Test("Preflight issues present dialog and auto-fix")
    func preflightIssuesAutoFixAndExport() async {
        let expectedURL = URL(
            fileURLWithPath: "/tmp/Preflight.json"
        )
        let issues = [
            ExportPreflightIssue(
                kind: .missingScheduleReferences,
                count: 2,
                examples: ["a -> b"]
            )
        ]

        let store = makePreflightStore(
            issues: issues, exportURL: expectedURL
        )

        await store.send(.exportTapped(.json)) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }

        await store.receive(\.preflightResponse) {
            $0.isGenerating = false
            $0.preflightReport = ExportPreflightReport(
                issues: issues
            )
            $0.pendingFormat = .json
            $0.isShowingPreflightDialog = true
        }

        await store.send(.preflightAutoFixTapped) {
            $0.isShowingPreflightDialog = false
            $0.isGenerating = true
            $0.isAutoFixing = true
        }

        await assertPreflightCompletion(
            store: store, expectedURL: expectedURL
        )
    }
}

@MainActor
private func makePreflightStore(
    issues: [ExportPreflightIssue],
    exportURL: URL
) -> TestStore<
    ExportFeature.State, ExportFeature.Action
> {
    let journal = SQLiteJournal()
    return TestStore(
        initialState: ExportFeature.State(
            journal: journal
        )
    ) {
        ExportFeature()
    } withDependencies: {
        $0.exportPreflightClient.check = { _ in
            ExportPreflightReport(issues: issues)
        }
        $0.exportPreflightClient.autoFix = { _ in
            ExportPreflightReport(issues: [])
        }
        $0.fileExportClient.export = { _, _ in exportURL }
        $0.fileExportClient.cleanup = { _ in }
        $0.fileExportDestinationClient.present = { url, _ in
            .documentPicker(url)
        }
    }
}

@MainActor
private func assertPreflightCompletion(
    store: TestStore<
        ExportFeature.State, ExportFeature.Action
    >,
    expectedURL: URL
) async {
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
