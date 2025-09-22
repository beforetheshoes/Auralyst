import Testing
import Observation
import Dependencies
import SQLiteData
@testable import Auralyst

@Suite("DataStore SQLiteData integration")
struct DataStoreSuite {
    @MainActor
    @Test("DataStore adopts Observation")
    func dataStoreIsObservable() {
        let store = DataStore()
        #expect(store is any Observable)
    }

    @MainActor
    @Test("Creating and fetching journals persists through SQLiteData")
    func createAndFetchJournalThroughDefaultDatabase() throws {
        try prepareDependencies {
            try $0.bootstrapDatabase()
        }

        let store = DataStore()
        let created = store.createJournal()
        let fetched = store.fetchJournal(id: created.id)
        #expect(fetched?.id == created.id)
    }
}
