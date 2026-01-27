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
        let notificationCenter = NotificationCenter()

        let url = URL(fileURLWithPath: "/tmp/import.json")
        let analysis = ImportAnalysis(fixableIssues: [], blockingIssues: [])
        let result = ImportResult(
            journalID: UUID(),
            summary: ImportSummary(
                importedEntries: 1,
                importedMedications: 1,
                importedSchedules: 0,
                importedIntakes: 1,
                importedCollaboratorNotes: 0
            )
        )

        let store = TestStore(
            initialState: ImportFeature.State(
                hasExistingJournal: false,
                selectedFileURL: url
            )
        ) {
            ImportFeature()
        } withDependencies: {
            $0.importClient.analyze = { inputURL in
                #expect(inputURL == url)
                return analysis
            }
            $0.importClient.importJournal = { inputURL, replaceExisting, resolution in
                #expect(inputURL == url)
                #expect(replaceExisting == false)
                #expect(resolution == .strict)
                return result
            }
            $0.notificationCenter = notificationCenter
        }

        let medsTask = Task { await expectNotification(.medicationsDidChange, center: notificationCenter) }
        let intakesTask = Task { await expectNotification(.medicationIntakesDidChange, center: notificationCenter) }

        await store.send(.importTapped)

        await store.receive(\.checkExistingJournalResponse) {
            $0.hasExistingJournal = false
            $0.isAnalyzing = true
            $0.errorMessage = nil
            $0.lastResult = nil
            $0.analysis = nil
            $0.pendingReplaceExisting = false
        }

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
        let notificationCenter = NotificationCenter()

        let url = URL(fileURLWithPath: "/tmp/import-issues.json")
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
        let result = ImportResult(
            journalID: UUID(),
            summary: ImportSummary(
                importedEntries: 0,
                importedMedications: 1,
                importedSchedules: 0,
                importedIntakes: 2,
                importedCollaboratorNotes: 0
            )
        )

        let store = TestStore(
            initialState: ImportFeature.State(
                hasExistingJournal: false,
                selectedFileURL: url
            )
        ) {
            ImportFeature()
        } withDependencies: {
            $0.importClient.analyze = { inputURL in
                #expect(inputURL == url)
                return analysis
            }
            $0.importClient.importJournal = { inputURL, replaceExisting, resolution in
                #expect(inputURL == url)
                #expect(replaceExisting == false)
                #expect(resolution == .autoFix)
                return result
            }
            $0.notificationCenter = notificationCenter
        }

        await store.send(.importTapped)

        await store.receive(\.checkExistingJournalResponse) {
            $0.hasExistingJournal = false
            $0.isAnalyzing = true
            $0.errorMessage = nil
            $0.lastResult = nil
            $0.analysis = nil
            $0.pendingReplaceExisting = false
        }

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

@MainActor
private func expectNotification(_ name: Notification.Name, center: NotificationCenter) async -> Bool {
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
