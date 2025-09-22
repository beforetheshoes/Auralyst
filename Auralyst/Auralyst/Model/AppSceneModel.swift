import Foundation
import SQLiteData
import Observation
import Dependencies

@Observable final class AppSceneModel {
    var primaryJournalID: UUID?
    var sharedJournalIDs: [UUID] = []

    private let dataStore = DataStore()
    @ObservationIgnored @Dependency(\.journalShareResolver) private var shareResolver

    func fetchOrCreateJournal() -> SQLiteJournal {
        if let primaryJournalID {
            if let existing = dataStore.fetchJournal(id: primaryJournalID) {
                return existing
            }
        }

        let journals = dataStore.fetchJournals()
        if let journal = journals.first {
            primaryJournalID = journal.id
            return journal
        }

        let journal = dataStore.createJournal()
        primaryJournalID = journal.id
        return journal
    }

    func refreshJournals() {
        let journals = dataStore.fetchJournals()
        updatePrimaryAndShared(from: journals)
    }

    private func updatePrimaryAndShared(from journals: [SQLiteJournal]) {
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
