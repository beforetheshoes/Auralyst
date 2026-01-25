import Charts
@preconcurrency import SQLiteData
import SwiftUI
import Dependencies

struct TrendsView: View {
    let journalID: UUID
    let journalIdentifier: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Trends")
                    .font(.largeTitle)
                    .bold()

                Text("Trend analysis will be implemented when SQLiteData queries are available.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Placeholder charts
                VStack(alignment: .leading, spacing: 16) {
                    Text("Symptom Severity Over Time")
                        .font(.headline)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay(
                            Text("Chart Placeholder")
                                .foregroundStyle(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Medication Adherence")
                        .font(.headline)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay(
                            Text("Chart Placeholder")
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
        .largeNavigationTitleDisplay()
    }
}

#Preview("Trends") {
    withPreviewDataStore {
        let journal = DependencyValues._current.databaseClient.createJournal()

        NavigationStack {
            TrendsView(journalID: journal.id, journalIdentifier: journal.id)
        }
    }
}
