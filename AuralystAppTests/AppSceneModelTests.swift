import Testing
import Dependencies
@testable import AuralystApp

@Suite("App scene model share handling")
struct AppSceneModelSuite {
    @MainActor
    @Test("Refresh journals separates primary and shared IDs")
    func refreshSeparatesSharedJournals() throws {
        try prepareTestDependencies()

        let store = DataStore()
        let primary = store.createJournal()
        let shared = store.createJournal()
        let primaryID = primary.id
        let sharedID = shared.id

        let model = withDependencies {
            $0.journalShareResolver = JournalShareResolver { ids in
                Set(ids.filter { $0 == sharedID })
            }
        } operation: { () -> AppSceneModel in
            let model = AppSceneModel()
            model.refreshJournals()
            return model
        }

        #expect(model.primaryJournalID == primaryID)
        #expect(model.sharedJournalIDs.contains(sharedID))
    }
}
