import Testing
import Dependencies
@testable import Auralyst

@Suite("App scene model share handling")
struct AppSceneModelSuite {
    @MainActor
    @Test("Refresh journals separates primary and shared IDs")
    func refreshSeparatesSharedJournals() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let primary = store.createJournal()
        let shared = store.createJournal()

        let model = withDependencies {
            $0.journalShareResolver = JournalShareResolver { ids in
                Set(ids.filter { $0 == shared.id })
            }
        } operation: { () -> AppSceneModel in
            let model = AppSceneModel()
            model.refreshJournals()
            return model
        }

        #expect(model.primaryJournalID == primary.id)
        #expect(model.sharedJournalIDs.contains(shared.id))
    }
}
