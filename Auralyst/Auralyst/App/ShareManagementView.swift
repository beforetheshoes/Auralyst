import CoreData
import SwiftUI

@MainActor
struct ShareManagementView: View {
    let journal: Journal

    @State private var model = ShareStatusModel()
    @State private var isStoppingShare = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if model.isLoading {
                    Section {
                        ProgressView("Loading share info…")
                    }
                } else if let info = model.shareInfo {
                    Section("Share") {
                        LabeledContent("Title") {
                            Text(info.title)
                        }
                    }

                    Section("Participants") {
                        ForEach(info.participants) { participant in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(participant.displayName)
                                        .font(.body)
                                    Text(participant.kindLabel)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(participant.acceptanceLabel)
                                    .font(.caption)
                                    .foregroundStyle(participant.acceptance == .accepted ? .green : .secondary)
                            }
                        }
                    }

                    Section("Actions") {
                        Button(role: .destructive) {
                            Task { await stopSharing() }
                        } label: {
                            if isStoppingShare {
                                ProgressView()
                            } else {
                                Text("Stop Sharing")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Journal is not currently shared.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.errorMessage {
                    Section("Error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Share Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await model.loadShare(for: journal)
            }
            .alert("Sharing", isPresented: Binding<Bool>(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            ), actions: {}, message: {
                if let alertMessage {
                    Text(alertMessage)
                }
            })
        }
    }

    @Environment(\.dismiss) private var dismiss

    private func stopSharing() async {
        guard isStoppingShare == false else { return }
        isStoppingShare = true
        do {
            try await model.stopSharing(journal: journal)
            alertMessage = "Sharing stopped. Collaborators will lose access shortly."
        } catch {
            alertMessage = error.localizedDescription
        }
        isStoppingShare = false
    }
}

private extension ShareInfo.Participant {
    var kindLabel: String {
        switch kind {
        case .owner: return "Owner"
        case .privateUser: return "Collaborator"
        case .unknown: return "Participant"
        }
    }

    var acceptanceLabel: String {
        switch acceptance {
        case .accepted: return "Accepted"
        case .pending: return "Pending"
        case .removed: return "Removed"
        case .unknown: return "Unknown"
        }
    }
}

#Preview("Share Management") {
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    let journal = try? context.fetch(Journal.fetchRequest()).first
    return Group {
        if let journal {
            ShareManagementView(journal: journal)
                .environment(\.managedObjectContext, context)
        }
    }
}
