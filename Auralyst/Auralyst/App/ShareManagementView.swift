import SwiftUI
import CloudKit
import Dependencies
import SQLiteData

struct ShareManagementView: View {
    let journal: SQLiteJournal
    
    @Dependency(\.defaultSyncEngine) private var syncEngine
    @Dependency(\.defaultDatabase) private var database
    
    @State private var sharedRecord: SharedRecord?
    @State private var isShared = false
    @State private var isLoading = false
    @State private var error: Error?
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient background
                LinearGradient(colors: [Color(.systemBackground), Color.blue.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()

                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue.opacity(0.25), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "person.2.wave.2.fill")
                                        .foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Journal Sharing")
                                        .font(.headline)
                                    Text("Share this journal with family, friends, or healthcare providers for collaborative tracking.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(.ultraThinMaterial)
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }

                    Section("Current Status") {
                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking sharing status…")
                                    .foregroundColor(.secondary)
                            }
                        } else if isShared {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Shared")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                    Text("Others can collaborate on this journal.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Not Shared")
                                        .font(.headline)
                                    Text("Only you can access this journal.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    Section("Actions") {
                        if isShared {
                            Button {
                                Task { await startOrManageSharing() }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.checkmark")
                                    Text("Manage Sharing")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tint(.blue)
                        } else {
                            Button {
                                Task { await startOrManageSharing() }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up.on.square.fill")
                                    Text("Start Sharing")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .tint(.blue)
                        }
                    }

                    if let error = error {
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Something went wrong")
                                        .font(.headline)
                                    Text(error.localizedDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.yellow.opacity(0.12))
                            )
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("About Sharing")
                                .font(.headline)
                            Text("Sharing uses iCloud and CloudKit to securely collaborate across devices and with trusted people. You can change access or stop sharing at any time.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .scrollContentBackground(.hidden)
                .refreshable {
                    await refreshSharedRecord()
                }
                .task {
                    await refreshSharedRecord()
                }
                .sheet(item: $sharedRecord) { sharedRecord in
                    CloudSharingView(sharedRecord: sharedRecord)
                }
            }
            .navigationTitle("Share Journal")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func refreshSharedRecord() async {
        isLoading = true
        error = nil

        do {
            // Query SyncMetadata to determine if this journal has an existing CKShare
            let shared = try await database.read { db in
                try SQLiteJournal
                    .metadata(for: journal.id)
                    .select(\.isShared)
                    .fetchOne(db)
            } ?? false
            isShared = shared
        } catch {
            self.error = error
            isShared = false
        }

        isLoading = false
    }
    
    private func startOrManageSharing() async {
        isLoading = true
        error = nil
        
        do {
            sharedRecord = try await syncEngine.share(record: journal) { share in
                share[CKShare.SystemFieldKey.title] = "Auralyst Journal"
            }
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}

#Preview {
    ShareManagementView(journal: SQLiteJournal())
}
