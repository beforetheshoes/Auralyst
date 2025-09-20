import CoreData
import SwiftUI

struct ExportView: View {
    enum ExportFormat: String, CaseIterable, Identifiable {
        case csvArchive = "CSV Bundle (ZIP)"
        case json = "JSON"

        var id: String { rawValue }
        var fileExtension: String {
            switch self {
            case .csvArchive: return "zip"
            case .json: return "json"
            }
        }
    }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .csvArchive
    @State private var isExporting = false
    @State private var exportSummary: DataExportSummary?
    @State private var exportError: String?
    @State private var latestExportURL: URL?
    @State private var isShowingFileMover = false

    private let exporter: DataExporting

    init(exporter: DataExporting = DataExporter()) {
        self.exporter = exporter
    }

    var body: some View {
        Form {
            Section("Format") {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Export") {
                Button(action: export) {
                    HStack {
                        if isExporting { ProgressView() }
                        Text("Generate Export")
                    }
                }
                .disabled(isExporting)

                if let summary = exportSummary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Entries exported: \(summary.exportedEntries)")
                        Text("Medications exported: \(summary.exportedMedications)")
                        Text("Schedules exported: \(summary.exportedSchedules)")
                        Text("Intakes exported: \(summary.exportedIntakes)")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }

                if let error = exportError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if latestExportURL != nil {
                    Button {
                        isShowingFileMover = true
                    } label: {
                        Label("Save to Files", systemImage: "folder")
                    }
                }
            }
        }
        .navigationTitle("Export Data")
        .toolbar {
            toolbarContent
#if targetEnvironment(macCatalyst)
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
#endif
        }
        .fileMover(isPresented: $isShowingFileMover, file: latestExportURL) { result in
            switch result {
            case .success:
                break
            case let .failure(error):
                exportError = error.localizedDescription
            }
        }
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if let url = latestExportURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func export() {
        exportError = nil
        exportSummary = nil
        latestExportURL = nil
        isExporting = true

        let directory = FileManager.default.temporaryDirectory
        let baseName = "Auralyst-Export-\(Date().iso8601ExportString)"
        let destinationURL = directory.appendingPathComponent("\(baseName).\(selectedFormat.fileExtension)")

        Task {
            defer { isExporting = false }
            do {
                let summary: DataExportSummary
                switch selectedFormat {
                case .csvArchive:
                    summary = try exporter.exportCSVBundle(to: destinationURL, context: context)
                case .json:
                    summary = try exporter.exportJSON(to: destinationURL, context: context)
                }

                exportSummary = summary
                latestExportURL = destinationURL
            } catch {
                exportError = error.localizedDescription
            }
        }
    }
}
