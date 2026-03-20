import SwiftUI
import Dependencies
#if canImport(UIKit)
import UIKit
#endif

import ComposableArchitecture

struct ExportView: View {
    let store: StoreOf<ExportFeature>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Data")
                    .font(.largeTitle)
                    .bold()

                Text(
                    "Generate a CSV or JSON snapshot of this journal."
                    + " Files are saved to a temporary location and shared via the system share sheet."
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("CSV Export") {
                    store.send(.exportTapped(.csv))
                }
                .disabled(store.isGenerating)
                .buttonStyle(.borderedProminent)

                Button("JSON Export") {
                    store.send(.exportTapped(.json))
                }
                .disabled(store.isGenerating)
                .buttonStyle(.bordered)

                if store.isGenerating {
                    ProgressView(store.isAutoFixing ? "Fixing data issues…" : "Preparing export…")
                        .progressViewStyle(.circular)
                }

                if let exportError = store.errorMessage {
                    Text(exportError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Export")
            .inlineNavigationTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
#if canImport(UIKit)
            .sheet(
                isPresented: Binding(
                    get: { store.isShowingDocumentPicker },
                    set: { _ in store.send(.documentPickerDismissed) }
                )
            ) {
                if let url = store.exportedFileURL {
                    DocumentExporter(url: url, onFinish: { store.send(.documentPickerDismissed) })
                } else {
                    EmptyView()
                }
            }
#endif
            .confirmationDialog(
                "Data Health Issues Found",
                isPresented: Binding(
                    get: { store.isShowingPreflightDialog },
                    set: { _ in store.send(.preflightCancelTapped) }
                ),
                presenting: store.preflightReport
            ) { _ in
                Button("Fix Automatically and Export") {
                    store.send(.preflightAutoFixTapped)
                }
                Button("Cancel", role: .cancel) {
                    store.send(.preflightCancelTapped)
                }
            } message: { report in
                Text(preflightMessage(report))
            }
            .alert(
                "Export Saved",
                isPresented: Binding(
                    get: { store.savedDestinationURL != nil },
                    set: { _ in store.send(.clearSavedDestination) }
                ),
                presenting: store.savedDestinationURL
            ) { _ in
                Button("OK") { store.send(.clearSavedDestination) }
            } message: { _ in
                Text(store.savedDestinationURL?.path ?? "")
            }
        }
    }
}

private extension ExportView {
    func preflightMessage(_ report: ExportPreflightReport) -> String {
        let lines = report.issues.map { issue in
            switch issue.kind {
            case .missingScheduleReferences:
                return "\(issue.count) intakes reference missing schedules."
            case .missingIntakeEntryReferences:
                return "\(issue.count) intakes reference missing symptom entries."
            case .missingNoteEntryReferences:
                return "\(issue.count) collaborator notes reference missing symptom entries."
            }
        }
        return lines.joined(separator: "\n")
    }
}

#if canImport(UIKit)
private struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        controller.delegate = context.coordinator
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }
    }
}
#endif

    #Preview {
        withPreviewDataStore {
            let journal = previewValue { try DependencyValues._current.databaseClient.createJournal() }

            ExportView(
                store: Store(initialState: ExportFeature.State(journal: journal)) {
                    ExportFeature()
                }
            )
        }
    }
