import SQLiteData
import SwiftUI
import Dependencies

struct ContentView: View {
    @FetchAll var journals: [SQLiteJournal]
    @FetchOne var primaryJournal: SQLiteJournal?

    @Environment(DataStore.self) private var dataStore
    @State private var showingAddEntry = false
    @State private var shareManagementJournal: SQLiteJournal?
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            Group {
                if let journal = primaryJournal {
                    JournalEntriesView(
                        journal: journal,
                        onAddEntry: { showingAddEntry = true },
                        onShare: { shareManagementJournal = journal },
                        onExport: { showingExport = true }
                    )
                } else {
                    VStack(spacing: 20) {
                        Text("Welcome to Auralyst")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Track your symptoms and medications")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Button("Create Journal") {
                            print("🔴 Button clicked!")
                            createJournal()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(false)
                    }
                    .padding()
                }
            }
            .navigationTitle("Auralyst")
        }
        .onAppear {
            loadJournal()
        }
        .sheet(isPresented: $showingAddEntry) {
            if let journal = primaryJournal {
                AddEntryView(journalID: journal.id)
            }
        }
        .sheet(item: $shareManagementJournal) { journal in
            ShareManagementView(journal: journal)
        }
        .sheet(isPresented: $showingExport) {
            if let journal = primaryJournal {
                ExportView(journal: journal)
            }
        }
    }


    private func createJournal() {
        _ = dataStore.createJournal()
    }

    private func loadJournal() {
        // @FetchAll automatically handles loading and observing changes
        // No need for manual loading
    }
}

#Preview {
    withPreviewDataStore { dataStore in
        ContentView()
            .environment(AppSceneModel())
    }
}
