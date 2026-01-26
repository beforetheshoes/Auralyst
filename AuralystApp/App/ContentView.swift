#if os(iOS)
import UIKit
#endif
@preconcurrency import SQLiteData
import SwiftUI
import ComposableArchitecture

struct ContentView: View {
    let store: StoreOf<AppFeature>
    @FetchAll var journals: [SQLiteJournal]
    @FetchOne var primaryJournal: SQLiteJournal?
    @FetchAll var entries: [SQLiteSymptomEntry]

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                ZStack {
                    content(viewStore: viewStore)
                    if let overlay = overlayState(viewStore: viewStore) {
                        overlayView(for: overlay, viewStore: viewStore)
                            .transition(.opacity)
                            .accessibilityIdentifier("sync-status-content-unavailable")
                            .padding(.horizontal, 24)
                    }
                }
                .toolbar { titleToolbar(viewStore: viewStore) }
            }
            .onAppear {
                viewStore.send(.journalsChanged(isEmpty: journals.isEmpty))
                viewStore.send(.entriesCountChanged(entries.count))
                viewStore.send(.syncPhaseChanged(viewStore.syncStatus.status.phase))
            }
            .onChange(of: journals.isEmpty) { _, _ in viewStore.send(.journalsChanged(isEmpty: journals.isEmpty)) }
            .onChange(of: entries.count) { _, _ in viewStore.send(.entriesCountChanged(entries.count)) }
            .onChange(of: viewStore.syncStatus.status.phase) { _, phase in
                viewStore.send(.syncPhaseChanged(phase))
            }
            .sheet(
                isPresented: viewStore.binding(
                    get: \.showingAddEntry,
                    send: AppFeature.Action.setShowingAddEntry
                )
            ) {
                if let journal = primaryJournal {
                    AddEntryView(
                        store: Store(initialState: AddEntryFeature.State(journalID: journal.id)) {
                            AddEntryFeature()
                        }
                    )
                }
            }
            .sheet(
                item: viewStore.binding(
                    get: \.shareManagementJournal,
                    send: AppFeature.Action.setShareManagementJournal
                )
            ) { journal in
                ShareManagementView(
                    store: Store(initialState: ShareManagementFeature.State(journal: journal)) {
                        ShareManagementFeature()
                    }
                )
            }
            .sheet(
                isPresented: viewStore.binding(
                    get: \.showingExport,
                    send: AppFeature.Action.setShowingExport
                )
            ) {
                if let journal = primaryJournal {
                    ExportView(
                        store: Store(initialState: ExportFeature.State(journal: journal)) {
                            ExportFeature()
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    withPreviewDataStore {
        ContentView(
            store: Store(
                initialState: AppFeature.State(
                    isRunningTests: false,
                    shouldStartSync: false,
                    overridePhaseRaw: nil,
                    bypassInitialOverlay: true
                )
            ) {
                AppFeature()
            }
        )
            .environment(AppSceneModel())
    }
}

private extension ContentView {
    func overlayState(viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> InitialOverlayState? {
        initialOverlayState(state: viewStore.state)
    }

    @ToolbarContentBuilder
    func titleToolbar(viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text("Auralyst")
                    .font(.headline.weight(.semibold))
                if let presentation = indicatorPresentation(viewStore: viewStore) {
                    SyncStatusDot(presentation: presentation)
                }
            }
        }
    }

    @ViewBuilder
    func content(viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> some View {
        Group {
            if let journal = primaryJournal {
                JournalEntriesView(
                    journal: journal,
                    onAddEntry: { viewStore.send(.addEntryTapped) },
                    onShare: { viewStore.send(.shareManagementTapped(journal)) },
                    onExport: { viewStore.send(.exportTapped) }
                )
            } else {
                VStack(spacing: 20) {
                    Text("Welcome to Auralyst")
                        .font(.largeTitle.weight(.bold))

                    Text("Track your symptoms and medications")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button("Create Journal") {
                        viewStore.send(.createJournalTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(false)
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    func overlayView(for state: InitialOverlayState, viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> some View {
        switch state {
        case .syncing:
            ContentUnavailableView {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Syncing your journal…")
                        .font(.headline)
                    Text("You can start adding entries once iCloud finishes syncing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        case .error(let message):
            ContentUnavailableView {
                Label("Sync unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
            } description: {
                Text(message)
                    .foregroundStyle(.secondary)
            } actions: {
                Button("Retry") {
                    viewStore.send(.syncStatus(.retryTapped))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    var journalHasEntries: Bool {
        guard let journal = primaryJournal else { return false }
        return entries.contains(where: { $0.journalID == journal.id })
    }

    func indicatorPresentation(viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> SyncIndicatorPresentation? {
        guard overlayState(viewStore: viewStore) == nil else { return nil }
        switch viewStore.syncStatus.status.phase {
        case .syncing:
            return SyncIndicatorPresentation(
                color: .yellow,
                identifier: "sync-status-dot-syncing",
                accessibilityLabel: "Sync in progress",
                helpText: "Cloud sync is running in the background."
            )
        case .upToDate:
            return SyncIndicatorPresentation(
                color: .green,
                identifier: "sync-status-dot-success",
                accessibilityLabel: "Sync complete",
                helpText: successHelpText(viewStore: viewStore)
            )
        case .error(let issue):
            return SyncIndicatorPresentation(
                color: .red,
                identifier: "sync-status-dot-error",
                accessibilityLabel: "Sync failed",
                helpText: "Cloud sync failed: \(issue.message)"
            )
        default:
            return nil
        }
    }

    func successHelpText(viewStore: ViewStore<AppFeature.State, AppFeature.Action>) -> String {
        guard let last = viewStore.syncStatus.status.lastSuccessfulSync else {
            return "Cloud sync has completed."
        }
        let relative = SyncIndicatorPresentation.relativeFormatter.localizedString(for: last, relativeTo: Date())
        return "Last synced \(relative)"
    }
}

private struct SyncIndicatorPresentation {
    let color: Color
    let identifier: String
    let accessibilityLabel: String
    let helpText: String

    static var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }
}

private struct SyncStatusDot: View {
    let presentation: SyncIndicatorPresentation
    @State private var isPresented = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: showTooltipTemporarily) {
            Circle()
                .fill(presentation.color)
                .frame(width: 10, height: 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(presentation.identifier)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityHint(presentation.helpText)
        .help(presentation.helpText)
            #if os(macOS)
            .onHover { hovering in
                setTooltipVisible(hovering)
            }
            #elseif os(iOS)
            .onHover { hovering in
                if UIDevice.current.userInterfaceIdiom == .pad {
                    setTooltipVisible(hovering)
                }
            }
            #endif
#if os(iOS)
            .popover(isPresented: $isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                Text(presentation.helpText)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
#endif
        .onDisappear { dismissTask?.cancel() }
    }

    private func showTooltipTemporarily() {
        setTooltipVisible(true)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                setTooltipVisible(false)
            }
        }
    }

    @MainActor
    private func setTooltipVisible(_ visible: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isPresented = visible
        }
        if !visible {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }
}

private struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(radius: 3, y: 2)
            )
    }
}
