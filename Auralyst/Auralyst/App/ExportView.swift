import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ExportView: View {
    let journal: SQLiteJournal

    @Environment(\.dismiss) private var dismiss
    @State private var exportedFileURL: URL?
    @State private var showingDocumentPicker = false
    @State private var isGenerating = false
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Data")
                    .font(.largeTitle)
                    .bold()

                Text("Generate a CSV or JSON snapshot of this journal. Files are saved to a temporary location and shared via the system share sheet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("CSV Export") {
                    export(.csv)
                }
                .disabled(isGenerating)
                .buttonStyle(.borderedProminent)

                Button("JSON Export") {
                    export(.json)
                }
                .disabled(isGenerating)
                .buttonStyle(.bordered)

                if isGenerating {
                    ProgressView("Preparing export…")
                        .progressViewStyle(.circular)
                }

                if let exportError {
                    Text(exportError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingDocumentPicker, onDismiss: removeTemporaryFile) {
                if let url = exportedFileURL {
                    DocumentExporter(url: url, onFinish: removeTemporaryFile)
                } else {
                    EmptyView()
                }
            }
        }
    }
}

private extension ExportView {
    enum Format {
        case csv
        case json
    }

    func export(_ format: Format) {
        isGenerating = true
        exportError = nil

        Task {
            do {
                let data: Data
                let fileExtension: String

                switch format {
                case .csv:
                    data = try DataExporter.exportCSV(for: journal)
                    fileExtension = "csv"
                case .json:
                    data = try DataExporter.exportJSON(for: journal)
                    fileExtension = "json"
                }

                let filename = "Auralyst-\(journal.id.uuidString).\(fileExtension)"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: url, options: [.atomic])
                await MainActor.run {
                    isGenerating = false
                    exportedFileURL = url
                    showingDocumentPicker = true
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    func removeTemporaryFile() {
        guard let url = exportedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        exportedFileURL = nil
        showingDocumentPicker = false
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
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()

        ExportView(journal: journal)
    }
}
