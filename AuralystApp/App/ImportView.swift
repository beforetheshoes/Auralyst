import SwiftUI
import UniformTypeIdentifiers
import ComposableArchitecture

struct ImportView: View {
    let store: StoreOf<ImportFeature>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                    store.send(.chooseFileTapped)
                }
                .buttonStyle(.bordered)

                if let url = store.selectedFileURL {
                    Text(url.lastPathComponent)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Import Journal") {
                    store.send(.importTapped)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.selectedFileURL == nil || store.isImporting || store.isAnalyzing)

                if store.isAnalyzing || store.isImporting {
                    ProgressView(store.isAnalyzing ? "Checking data…" : "Importing…")
                        .progressViewStyle(.circular)
                }

                if let error = store.errorMessage {
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
                isPresented: Binding(
                    get: { store.showFilePicker },
                    set: { _ in store.send(.filePickerDismissed) }
                ),
                allowedContentTypes: [UTType.json, UTType.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        store.send(.filePicked(url))
                    }
                case .failure(let error):
                    store.send(.importResponse(.failure(error)))
                }
            }
            .alert(
                "Replace Existing Data?",
                isPresented: Binding(
                    get: { store.showReplaceConfirmation },
                    set: { store.send(.setReplaceConfirmation($0)) }
                )
            ) {
                Button("Replace", role: .destructive) {
                    store.send(.confirmReplaceTapped)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Importing will delete your current journal data and replace it with the selected file.")
            }
            .alert(
                "Import Complete",
                isPresented: Binding(
                    get: { store.lastResult != nil },
                    set: { _ in store.send(.clearResult) }
                ),
                presenting: store.lastResult
            ) { _ in
                Button("OK") {
                    store.send(.clearResult)
                    dismiss()
                }
            } message: { result in
                Text(
                    importSummaryMessage(result.summary)
                )
            }
            .confirmationDialog(
                "Import Issues Found",
                isPresented: Binding(
                    get: { store.showIssuesDialog },
                    set: { _ in store.send(.dismissIssuesDialog) }
                ),
                presenting: store.analysis
            ) { _ in
                Button("Fix Automatically and Import") {
                    store.send(.importWithAutoFixTapped)
                }
                Button("Cancel", role: .cancel) {
                    store.send(.dismissIssuesDialog)
                }
            } message: { analysis in
                Text(issuesMessage(analysis))
            }
        }
    }
}

private extension ImportView {
    func importSummaryMessage(_ summary: ImportSummary) -> String {
        let parts = [
            "\(summary.importedEntries) entries",
            "\(summary.importedMedications) medications",
            "\(summary.importedSchedules) schedules",
            "\(summary.importedIntakes) intakes",
            "\(summary.importedCollaboratorNotes) notes"
        ]
        return "Imported \(parts.joined(separator: ", "))."
    }

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
