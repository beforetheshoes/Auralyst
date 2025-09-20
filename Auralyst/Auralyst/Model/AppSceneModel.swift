import CoreData
import Observation

@Observable final class AppSceneModel {
    var primaryJournalID: NSManagedObjectID?
    var sharedJournalIDs: [NSManagedObjectID] = []

    func fetchOrCreateJournal(in context: NSManagedObjectContext) -> Journal {
        if let primaryJournalID,
           let existing = try? context.existingObject(with: primaryJournalID) as? Journal {
            return existing
        }

        let request = Journal.fetchRequest()
        request.fetchLimit = 1
        if let journal = try? context.fetch(request).first {
            primaryJournalID = journal.objectID
            return journal
        }

        let journal = Journal(context: context)
        journal.id = UUID()
        journal.createdAt = Date()
        try? context.save()
        primaryJournalID = journal.objectID
        return journal
    }

    func refreshJournals(in context: NSManagedObjectContext) {
        let request = Journal.fetchRequest()
        if let journals = try? context.fetch(request) {
            updatePrimaryAndShared(from: journals, context: context)
        }
    }

    private func updatePrimaryAndShared(from journals: [Journal], context: NSManagedObjectContext) {
        var candidatePrimary: Journal?
        var sharedIDs: [NSManagedObjectID] = []

        for journal in journals {
            guard let store = journal.objectID.persistentStore else { continue }
            if store.configurationName == "Shared" {
                sharedIDs.append(journal.objectID)
            } else if candidatePrimary == nil {
                candidatePrimary = journal
            }
        }

        sharedJournalIDs = sharedIDs
        if let currentID = primaryJournalID,
           let existing = try? context.existingObject(with: currentID) as? Journal {
            primaryJournalID = existing.objectID
            return
        }

        if let candidatePrimary {
            primaryJournalID = candidatePrimary.objectID
        } else if let anyJournal = journals.first {
            primaryJournalID = anyJournal.objectID
        }
    }
}
