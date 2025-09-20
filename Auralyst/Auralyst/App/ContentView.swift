import CoreData
import SwiftUI

struct ContentView: View {
    @Environment(AppSceneModel.self) private var sceneModel
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        entity: Journal.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Journal.createdAt, ascending: false)],
        animation: .default
    ) private var journals: FetchedResults<Journal>

    @State private var selectedJournalID: NSManagedObjectID?
    @State private var showingAddEntry = false
    @State private var shareSheetJournal: Journal?
    @State private var shareManagementJournal: Journal?
    @State private var showingExport = false

    var body: some View {
        NavigationStack {
            Group {
                if let journal = selectedJournal {
                    JournalEntriesView(
                        journalID: journal.objectID,
                        journalIdentifier: journalIdentifier(for: journal)
                    ) {
                        showingAddEntry = true
                    }
                    .overlay(alignment: .topLeading) {
                        if journalOptions.count > 1 {
                            JournalPicker(options: journalOptions, selectedID: $selectedJournalID)
                                .padding(.horizontal)
                                .padding(.top, 12)
                        }
                    }
                } else {
                    ProgressView("Preparing journal…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Auralyst")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let journal = selectedJournal {
                        NavigationLink {
                            TrendsView(
                                journalID: journal.objectID,
                                journalIdentifier: journalIdentifier(for: journal)
                            )
                        } label: {
                            Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                    .disabled(selectedJournal == nil)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button {
                            if let journal = ensureJournal() {
                                shareSheetJournal = journal
                            }
                        } label: {
                            Label("Invite", systemImage: "person.badge.plus")
                        }

                        Button {
                            if let journal = ensureJournal() {
                                shareManagementJournal = journal
                            }
                        } label: {
                            Label("Manage Sharing", systemImage: "slider.horizontal.3")
                        }

                        Divider()

                        Button {
                            showingExport = true
                        } label: {
                            Label("Export Data", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Label("Share", systemImage: "person.2")
                    }
                    .disabled(selectedJournal == nil)
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            if let journal = ensureJournal() {
                AddEntryView(journalID: journal.objectID)
                    .environment(\.managedObjectContext, context)
            }
        }
        .sheet(item: $shareSheetJournal) { journal in
            ShareSheet(journal: journal)
        }
        .sheet(item: $shareManagementJournal) { journal in
            ShareManagementView(journal: journal)
        }
        .sheet(isPresented: $showingExport) {
            NavigationStack {
                ExportView()
                    .environment(\.managedObjectContext, context)
            }
        }
        .task {
            sceneModel.refreshJournals(in: context)
            let journal = sceneModel.fetchOrCreateJournal(in: context)
            selectedJournalID = journal.objectID
        }
        .onChange(of: journals.count) { _, _ in
            syncSelectionIfNeeded()
        }
    }

    private var selectedJournal: Journal? {
        guard let selectedJournalID else { return nil }
        return journals.first(where: { $0.objectID == selectedJournalID })
    }

    private var journalOptions: [JournalOption] {
        journals.map { journal in
            let shared = isShared(journal)
            let createdAt = journal.createdAt ?? .distantPast
            let name = displayName(for: journal, shared: shared)
            return JournalOption(id: journal.objectID, name: name, isShared: shared, createdAt: createdAt)
        }
        .sorted { lhs, rhs in
            if lhs.isShared == rhs.isShared {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.isShared == false
        }
    }

    private func ensureJournal() -> Journal? {
        if let journal = selectedJournal {
            return journal
        }
        let journal = sceneModel.fetchOrCreateJournal(in: context)
        selectedJournalID = journal.objectID
        return journal
    }

    private func syncSelectionIfNeeded() {
        guard let currentSelection = selectedJournalID else {
            if let first = journalOptions.first {
                selectedJournalID = first.id
            }
            return
        }

        let available = journals.contains { $0.objectID == currentSelection }
        if available == false {
            selectedJournalID = journalOptions.first?.id
        }
    }

    private func isShared(_ journal: Journal) -> Bool {
        guard let store = journal.objectID.persistentStore else {
            return false
        }
        return store.configurationName == "Shared"
    }

    private func displayName(for journal: Journal, shared: Bool) -> String {
        if shared {
            let date = journal.createdAt?.formatted(.dateTime.month().day()) ?? ""
            let suffixSource = journal.id?.uuidString ?? UUID().uuidString
            let suffix = suffixSource.split(separator: "-").last.map(String.init) ?? ""
            if date.isEmpty {
                return "Shared Journal • \(suffix)"
            }
            return "Shared \(date) • \(suffix)"
        }
        return "My Journal"
    }

    private func journalIdentifier(for journal: Journal) -> UUID {
        if let existing = journal.id {
            return existing
        }

        let newIdentifier = UUID()
        journal.id = newIdentifier
        do {
            try context.save()
        } catch {
            // Persist identifier in-memory if save fails; CloudKit sync will reconcile later.
        }
        return newIdentifier
    }
}

private struct JournalOption: Identifiable {
    let id: NSManagedObjectID
    let name: String
    let isShared: Bool
    let createdAt: Date
}

private struct JournalPicker: View {
    let options: [JournalOption]
    @Binding var selectedID: NSManagedObjectID?

    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selectedID = option.id
                } label: {
                    HStack {
                        Label(option.name, systemImage: option.isShared ? "person.2" : "book.closed")
                        if option.id == selectedID {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(selectedLabel, systemImage: selectedOption?.isShared == true ? "person.2" : "book.closed")
                .labelStyle(.titleAndIcon)
                .padding(8)
                .background(Color.surfaceLight, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var selectedOption: JournalOption? {
        guard let selectedID else { return options.first }
        return options.first(where: { $0.id == selectedID }) ?? options.first
    }

    private var selectedLabel: String {
        selectedOption?.name ?? "Journals"
    }
}

#Preview("ContentView") {
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    return ContentView()
        .environment(AppSceneModel())
        .environment(\.managedObjectContext, context)
}
