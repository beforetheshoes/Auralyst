import Foundation
import Dependencies
import ComposableArchitecture
import Testing
import CasePaths
@preconcurrency import SQLiteData
@testable import AuralystApp

@Suite("Import feature", .serialized)
struct ImportFeatureTests {
    @MainActor
    @Test("Clean analysis proceeds directly to strict import")
    func cleanAnalysisProceedsToImport() async throws {
        try prepareTestDependencies()
        let center = NotificationCenter()

        let url = URL(fileURLWithPath: "/tmp/import.json")
        let analysis = ImportAnalysis(
            fixableIssues: [], blockingIssues: []
        )
        let result = makeImportResult()

        let store = makeImportStore(ImportStoreConfig(
            url: url, analysis: analysis,
            result: result, resolution: .strict,
            replaceExisting: false,
            notificationCenter: center
        ))

        let medsTask = Task {
            await expectNotification(
                .medicationsDidChange, center: center
            )
        }
        let intakesTask = Task {
            await expectNotification(
                .medicationIntakesDidChange, center: center
            )
        }

        await store.send(.importTapped)

        await assertCheckExistingJournal(store: store)

        await store.receive(\.analyzeResponse) {
            $0.isAnalyzing = false
            $0.analysis = analysis
            $0.pendingReplaceExisting = false
            $0.isImporting = true
            $0.errorMessage = nil
            $0.lastResult = nil
        }

        await store.receive(\.importResponse) {
            $0.isImporting = false
            $0.lastResult = result
            $0.analysis = nil
        }

        #expect(await medsTask.value)
        #expect(await intakesTask.value)
    }

    @MainActor
    @Test("Fixable issues show dialog and auto-fix import runs")
    func fixableIssuesShowDialogAndAutoFix() async throws {
        try prepareTestDependencies()
        let center = NotificationCenter()

        let url = URL(
            fileURLWithPath: "/tmp/import-issues.json"
        )
        let analysis = ImportAnalysis(
            fixableIssues: [
                ImportIssue(
                    kind: .missingScheduleReferences,
                    count: 2,
                    examples: ["a -> b"],
                    isFixable: true
                )
            ],
            blockingIssues: []
        )
        let result = makeAutoFixImportResult()

        let store = makeImportStore(ImportStoreConfig(
            url: url, analysis: analysis,
            result: result, resolution: .autoFix,
            replaceExisting: false,
            notificationCenter: center
        ))

        await store.send(.importTapped)

        await assertCheckExistingJournal(store: store)

        await store.receive(\.analyzeResponse) {
            $0.isAnalyzing = false
            $0.analysis = analysis
            $0.pendingReplaceExisting = false
            $0.showIssuesDialog = true
        }

        await store.send(.importWithAutoFixTapped) {
            $0.showIssuesDialog = false
            $0.isAnalyzing = false
            $0.isImporting = true
            $0.errorMessage = nil
            $0.lastResult = nil
        }

        await store.receive(\.importResponse) {
            $0.isImporting = false
            $0.lastResult = result
            $0.analysis = nil
        }
    }
}

// MARK: - Store Factory

private struct ImportStoreConfig {
    let url: URL
    let analysis: ImportAnalysis
    let result: ImportResult
    let resolution: ImportResolution
    let replaceExisting: Bool
    let notificationCenter: NotificationCenter
}

@MainActor
private func makeImportStore(
    _ config: ImportStoreConfig
) -> TestStore<ImportFeature.State, ImportFeature.Action> {
    TestStore(
        initialState: ImportFeature.State(
            hasExistingJournal: false,
            selectedFileURL: config.url
        )
    ) {
        ImportFeature()
    } withDependencies: {
        $0.importClient.analyze = { inputURL in
            #expect(inputURL == config.url)
            return config.analysis
        }
        $0.importClient.importJournal = { inputURL, replace, res in
            #expect(inputURL == config.url)
            #expect(replace == config.replaceExisting)
            #expect(res == config.resolution)
            return config.result
        }
        $0.notificationCenter = config.notificationCenter
    }
}

@MainActor
private func assertCheckExistingJournal(
    store: TestStore<
        ImportFeature.State, ImportFeature.Action
    >
) async {
    await store.receive(\.checkExistingJournalResponse) {
        $0.hasExistingJournal = false
        $0.isAnalyzing = true
        $0.errorMessage = nil
        $0.lastResult = nil
        $0.analysis = nil
        $0.pendingReplaceExisting = false
    }
}

// MARK: - Result Factories

private func makeImportResult() -> ImportResult {
    ImportResult(
        journalID: UUID(),
        summary: ImportSummary(
            importedEntries: 1,
            importedMedications: 1,
            importedSchedules: 0,
            importedIntakes: 1,
            importedCollaboratorNotes: 0
        )
    )
}

private func makeAutoFixImportResult() -> ImportResult {
    ImportResult(
        journalID: UUID(),
        summary: ImportSummary(
            importedEntries: 0,
            importedMedications: 1,
            importedSchedules: 0,
            importedIntakes: 2,
            importedCollaboratorNotes: 0
        )
    )
}

@MainActor
private func expectNotification(
    _ name: Notification.Name,
    center: NotificationCenter
) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in center.notifications(named: name) {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return false
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
    }
}
