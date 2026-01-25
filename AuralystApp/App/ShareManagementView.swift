import CloudKit
import ComposableArchitecture
@preconcurrency import SQLiteData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ShareManagementView: View {
    let store: StoreOf<ShareManagementFeature>

    var body: some View {
        WithViewStore(store, observe: { $0 }) { viewStore in
            NavigationStack {
                ZStack {
                    LinearGradient(
                        colors: [Color.platformBackground, Color.blue.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    List {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.blue.opacity(0.25), .blue.opacity(0.6)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "person.2.wave.2.fill")
                                            .foregroundStyle(.white)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Journal Sharing")
                                            .font(.headline)
                                        Text("Share this journal with family, friends, or healthcare providers for collaborative tracking.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            if viewStore.isLoading {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Checking sharing status…")
                                        .foregroundStyle(.secondary)
                                }
                            } else if viewStore.isShared {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Shared")
                                            .font(.headline.weight(.semibold))
                                            .foregroundStyle(.green)
                                        Text("Others can collaborate on this journal.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }

                        Section("Actions") {
                            if viewStore.isShared {
                                Button {
                                    viewStore.send(.shareTapped)
                                    triggerImpactFeedback(style: .light)
                                } label: {
                                    HStack {
                                        Image(systemName: "person.crop.circle.badge.checkmark")
                                        Text("Manage Sharing")
                                            .font(.body.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .tint(.blue)
                            } else {
                                Button {
                                    viewStore.send(.shareTapped)
                                    triggerImpactFeedback(style: .medium)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up.on.square.fill")
                                        Text("Start Sharing")
                                            .font(.body.weight(.semibold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .tint(.blue)
                            }
                        }

                        if let errorMessage = viewStore.errorMessage {
                            Section {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.yellow)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Something went wrong")
                                            .font(.headline)
                                        Text(errorMessage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        viewStore.send(.refresh)
                    }
                    .task {
                        viewStore.send(.task)
                    }
                    #if os(iOS)
                    .sheet(
                        item: viewStore.binding(
                            get: \.sharedRecord,
                            send: ShareManagementFeature.Action.setSharedRecord
                        )
                    ) { sharedRecord in
                        CloudSharingView(sharedRecord: sharedRecord)
                    }
                    #endif
                }
                .navigationTitle("Share Journal")
                .inlineNavigationTitleDisplay()
            }
        }
    }

    private enum ImpactStyle {
        case light
        case medium
    }

    #if os(iOS)
    private func triggerImpactFeedback(style: ImpactStyle) {
        let generatorStyle: UIImpactFeedbackGenerator.FeedbackStyle = {
            switch style {
            case .light: return .light
            case .medium: return .medium
            }
        }()
        UIImpactFeedbackGenerator(style: generatorStyle).impactOccurred()
    }
    #else
    private func triggerImpactFeedback(style: ImpactStyle) {}
    #endif
}

#Preview {
    ShareManagementView(
        store: Store(initialState: ShareManagementFeature.State(journal: SQLiteJournal())) {
            ShareManagementFeature()
        }
    )
}
