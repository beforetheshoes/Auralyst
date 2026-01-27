import SwiftUI
import UniformTypeIdentifiers
import ComposableArchitecture

struct ImportView: View {
    let store: StoreOf<ImportFeature>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Import Data")
                        .font(.largeTitle)
                        .bold()

                    Text("Import a previously exported JSON or CSV journal file. Importing will replace any existing data.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Choose File") {
                        viewStore.send(.chooseFileTapped)
                    }
                    .buttonStyle(.bordered)

                    if let url = viewStore.selectedFileURL {
                        Text(url.lastPathComponent)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Import Journal") {
                        viewStore.send(.importTapped)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewStore.selectedFileURL == nil || viewStore.isImporting || viewStore.isAnalyzing)

                    if viewStore.isAnalyzing || viewStore.isImporting {
                        ProgressView(viewStore.isAnalyzing ? "Checking data…" : "Importing…")
                            .progressViewStyle(.circular)
                    }

                    if let error = viewStore.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .navigationTitle("Import")
                .inlineNavigationTitleDisplay()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .fileImporter(
                    isPresented: viewStore.binding(
                        get: \.showFilePicker,
                        send: { _ in .filePickerDismissed }
                    ),
                    allowedContentTypes: [UTType.json, UTType.commaSeparatedText],
                    allowsMultipleSelection: false
                ) { result in
                    switch result {
                    case .success(let urls):
                        if let url = urls.first {
                            viewStore.send(.filePicked(url))
                        }
                    case .failure(let error):
                        viewStore.send(.importResponse(.failure(error)))
                    }
                }
                .alert(
                    "Replace Existing Data?",
                    isPresented: viewStore.binding(
                        get: \.showReplaceConfirmation,
                        send: ImportFeature.Action.setReplaceConfirmation
                    )
                ) {
                    Button("Replace", role: .destructive) {
                        viewStore.send(.confirmReplaceTapped)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Importing will delete your current journal data and replace it with the selected file.")
                }
                .alert(
                    "Import Complete",
                    isPresented: viewStore.binding(
                        get: { $0.lastResult != nil },
                        send: { _ in .clearResult }
                    ),
                    presenting: viewStore.lastResult
                ) { _ in
                    Button("OK") {
                        viewStore.send(.clearResult)
                        dismiss()
                    }
                } message: { result in
                    Text(
                        "Imported \(result.summary.importedEntries) entries, \(result.summary.importedMedications) medications, \(result.summary.importedSchedules) schedules, \(result.summary.importedIntakes) intakes, and \(result.summary.importedCollaboratorNotes) notes."
                    )
                }
                .confirmationDialog(
                    "Import Issues Found",
                    isPresented: viewStore.binding(
                        get: \.showIssuesDialog,
                        send: { _ in .dismissIssuesDialog }
                    ),
                    presenting: viewStore.analysis
                ) { _ in
                    Button("Fix Automatically and Import") {
                        viewStore.send(.importWithAutoFixTapped)
                    }
                    Button("Cancel", role: .cancel) {
                        viewStore.send(.dismissIssuesDialog)
                    }
                } message: { analysis in
                    Text(issuesMessage(analysis))
                }
            }
        }
    }
}

private extension ImportView {
    func issuesMessage(_ analysis: ImportAnalysis) -> String {
        let lines = analysis.fixableIssues.map { issue in
            switch issue.kind {
            case .missingScheduleReferences:
                return "\(issue.count) intakes reference missing schedules."
            case .missingIntakeEntryReferences:
                return "\(issue.count) intakes reference missing symptom entries."
            case .missingNoteEntryReferences:
                return "\(issue.count) collaborator notes reference missing symptom entries."
            case .missingMedicationReferences:
                return "\(issue.count) records reference missing medications."
            case .journalMismatch:
                return "\(issue.count) records reference a different journal."
            }
        }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    ImportView(
        store: Store(initialState: ImportFeature.State(hasExistingJournal: true)) {
            ImportFeature()
        }
    )
}
