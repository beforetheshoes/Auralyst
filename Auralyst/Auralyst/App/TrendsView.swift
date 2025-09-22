import Charts
import SQLiteData
import SwiftUI

struct TrendsView: View {
    let journalID: UUID
    let journalIdentifier: UUID

    @Environment(DataStore.self) private var dataStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Trends")
                    .font(.largeTitle)
                    .bold()

                Text("Trend analysis will be implemented when SQLiteData queries are available.")
                    .font(.headline)
                    .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
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
                                .foregroundColor(.secondary)
                        )
                }
            }
            .padding()
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview("Trends") {
    withPreviewDataStore { dataStore in
        let journal = dataStore.createJournal()

        NavigationStack {
            TrendsView(journalID: journal.id, journalIdentifier: journal.id)
        }
    }
}
