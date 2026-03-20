import Dependencies
import Foundation
import Observation
@preconcurrency import SQLiteData

@MainActor
@Observable final class AppSceneModel {
    var primaryJournalID: UUID?
    var sharedJournalIDs: [UUID] = []

    @ObservationIgnored
    @Dependency(\.databaseClient) private var databaseClient

    func fetchOrCreateJournal() throws -> SQLiteJournal {
        if let primaryJournalID {
            if let existing = databaseClient.fetchJournal(primaryJournalID) {
                return existing
            }
        }

        let journals = databaseClient.fetchJournals()
        if let journal = journals.first {
            primaryJournalID = journal.id
            return journal
        }

        let journal = try databaseClient.createJournal()
        primaryJournalID = journal.id
        return journal
    }

    func refreshJournals() {
        let journals = databaseClient.fetchJournals()
        updatePrimaryAndShared(from: journals)
    }

    private func updatePrimaryAndShared(from journals: [SQLiteJournal]) {
        let shareResolver = DependencyValues._current.journalShareResolver
        let ids = journals.map(\.id)
        let sharedSet: Set<UUID>
        do {
            sharedSet = try shareResolver.sharedJournalIDs(ids)
        } catch {
            sharedSet = []
        }

        sharedJournalIDs = journals
            .filter { sharedSet.contains($0.id) }
            .map(\.id)

        if let currentID = primaryJournalID,
           journals.contains(where: { $0.id == currentID }) {
            return
        }

        if let nonShared = journals.first(where: { !sharedSet.contains($0.id) }) {
            primaryJournalID = nonShared.id
        } else if let fallback = journals.first {
            primaryJournalID = fallback.id
        }
    }
}
