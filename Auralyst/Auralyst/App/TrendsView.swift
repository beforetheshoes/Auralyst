import Charts
import CoreData
import SwiftUI

struct TrendsView: View {
    private let journalIdentifier: UUID

    @FetchRequest private var entries: FetchedResults<SymptomEntry>
    @FetchRequest private var medicationIntakes: FetchedResults<MedicationIntake>
    @FetchRequest private var medications: FetchedResults<Medication>
    @State private var range: TrendRange = .seven

    init(journalID: NSManagedObjectID, journalIdentifier: UUID) {
        self.journalIdentifier = journalIdentifier
        _entries = FetchRequest(
            entity: SymptomEntry.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \SymptomEntry.timestamp, ascending: true)],
            predicate: NSPredicate(
                format: "(journal == %@) OR (journal.id == %@)",
                journalID,
                journalIdentifier as CVarArg
            ),
            animation: .default
        )
        _medicationIntakes = FetchRequest(
            entity: MedicationIntake.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \MedicationIntake.timestamp, ascending: true)],
            predicate: NSPredicate(
                format: "(medication.journal == %@) OR (entry.journal == %@) OR (medication.journal.id == %@) OR (entry.journal.id == %@)",
                journalID,
                journalID,
                journalIdentifier as CVarArg,
                journalIdentifier as CVarArg
            ),
            animation: .default
        )
        _medications = FetchRequest(
            entity: Medication.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Medication.createdAt, ascending: true)],
            predicate: NSPredicate(
                format: "(journal == %@) OR (journal.id == %@)",
                journalID,
                journalIdentifier as CVarArg
            ),
            animation: .default
        )
    }

    private var calculator: TrendCalculator {
        TrendCalculator(entries: Array(entries), intakes: Array(medicationIntakes), medications: Array(medications))
    }

    private var points: [DailySeverityPoint] {
        calculator.dailySeverityPoints(for: range)
    }

    private var heatmap: [HeatmapCell] {
        calculator.hourlyHeatmap(for: range)
    }

    private var medicationEffects: [MedicationEffectPoint] {
        calculator.medicationEffects(for: range)
    }

    private var insights: [TrendInsight] {
        calculator.insights(for: range)
    }

    private var menstruationAverages: [MenstruationAveragePoint] {
        calculator.menstruationAverages(for: range)
    }

    private var medicationAdherence: [MedicationAdherencePoint] {
        calculator.medicationAdherence(for: range)
    }

    private var painBreakdown: [SymptomPainPoint] {
        calculator.painBreakdown(for: range)
    }

    private var asNeededUsage: [AsNeededUsagePoint] {
        calculator.asNeededUsage(for: range)
    }

    private var sentimentSummary: SentimentOverview? {
        calculator.sentimentOverview(for: range)
    }

    private var menstruationDeltaDescription: String? {
        guard menstruationAverages.count == 2,
              let menstruating = menstruationAverages.first(where: { $0.label == "Menstruating" }),
              let notMenstruating = menstruationAverages.first(where: { $0.label == "Not Menstruating" }) else {
            return nil
        }
        let delta = menstruating.value - notMenstruating.value
        let formatted = String(format: "%.1f", abs(delta))
        if abs(delta) < 0.1 { return "Severity remains stable regardless of menstruation." }
        if delta > 0 {
            return "Severity runs ~\(formatted) points higher while menstruating."
        }
        return "Severity runs ~\(formatted) points lower while menstruating."
    }

    var body: some View {
        List {
            Section("Window") {
                Picker("Range", selection: $range) {
                    ForEach(TrendRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }

            if insights.isEmpty == false {
                Section("Insights") {
                    ForEach(insights) { insight in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(insight.title)
                                .font(.headline)
                                .foregroundStyle(Color.brandAccent)
                            if let detail = insight.detail {
                                Text(detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if menstruationAverages.isEmpty == false {
                Section("Menstruation Impact") {
                    Chart {
                        ForEach(menstruationAverages) { point in
                            BarMark(
                                x: .value("State", point.label),
                                y: .value("Avg Severity", point.value)
                            )
                            .foregroundStyle(point.label == "Menstruating" ? Color.brandAccent : Color.primary)
                        }
                    }
                    .chartYAxisLabel("Avg severity")
                    .frame(minHeight: 180)

                    if let delta = menstruationDeltaDescription {
                        Text(delta)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Average Severity") {
                if points.isEmpty {
                    EmptyChartPlaceholder(text: "Log a few days to unlock trends.")
                } else {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Severity", point.value)
                        )
                        .foregroundStyle(Color.primary)
                        AreaMark(
                            x: .value("Day", point.date, unit: .day),
                            y: .value("Severity", point.value)
                        )
                        .foregroundStyle(Color.primary.opacity(0.2))
                    }
                    .frame(minHeight: 200)
                }
            }

            Section("Hourly Heatmap") {
                if heatmap.isEmpty {
                    EmptyChartPlaceholder(text: "Need more timestamps to surface hourly patterns.")
                } else {
                    Chart {
                        ForEach(heatmap) { cell in
                            RectangleMark(
                                x: .value("Hour", cell.hourLabel),
                                y: .value("Weekday", cell.weekdayLabel),
                                z: .value("Severity", cell.value)
                            )
                        }
                    }
                    .chartForegroundStyleScale(range: Gradient(colors: [.surfaceLight, .accent]))
                    .chartLegend(.hidden)
                    .frame(minHeight: 220)
                }
            }

            Section("Medication Effect") {
                if medicationEffects.isEmpty {
                    EmptyChartPlaceholder(text: "Track medications alongside entries to see trends.")
                } else {
                    Chart {
                        ForEach(medicationEffects) { effect in
                            BarMark(
                                x: .value("Medication", effect.name),
                                y: .value("Δ severity", effect.delta)
                            )
                            .foregroundStyle(effect.delta >= 0 ? Color.brandAccent : Color.red.opacity(0.6))
                        }
                        RuleMark(y: .value("Baseline", 0))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    }
                    .chartYAxisLabel("Δ severity")
                    .frame(minHeight: 200)
                }
            }

            if medicationAdherence.isEmpty == false {
                Section("Medication Adherence") {
                    ForEach(medicationAdherence) { adherence in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(adherence.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.ink)
                                if let useCase = adherence.useCase {
                                    Text(useCase)
                                        .font(.footnote)
                                        .foregroundStyle(Color.brandAccent)
                                }
                            }
                            ProgressView(value: adherence.adherenceRate)
                                .tint(Color.brandAccent)
                            HStack {
                                if adherence.scheduledCount > 0 {
                                    Text("\(adherence.takenCount)/\(adherence.scheduledCount) taken")
                                } else {
                                    Text("\(adherence.takenCount) logged")
                                }
                                if let dose = adherence.averageDoseDescription {
                                    Text("• avg \(dose)")
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if painBreakdown.isEmpty == false {
                Section("Symptom Breakdown") {
                    Chart {
                        ForEach(painBreakdown) { point in
                            BarMark(
                                x: .value("Symptom", point.label),
                                y: .value("Avg Level", point.value)
                            )
                            .foregroundStyle(Color.primary)
                        }
                    }
                    .chartYAxisLabel("Avg level")
                    .frame(minHeight: 200)
                }
            }

            if asNeededUsage.isEmpty == false {
                Section("As-Needed Usage") {
                    Chart {
                        ForEach(asNeededUsage) { point in
                            BarMark(
                                x: .value("Use Case", point.label),
                                y: .value("Logs", point.count)
                            )
                            .foregroundStyle(Color.brandAccent)
                        }
                    }
                    .chartYAxisLabel("Logs")
                    .frame(minHeight: 200)

                    ForEach(asNeededUsage) { point in
                        if point.medicationNames.count > 1 {
                            Text("\(point.label): \(point.medicationNames.joined(separator: ", "))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let sentimentSummary {
                Section("Sentiment Preview") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sentimentSummary.description)
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                        if sentimentSummary.pendingAnalysisCount > 0 {
                            Text("\(sentimentSummary.pendingAnalysisCount) notes awaiting sentiment analysis via Foundation Models.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Trends")
    }
}

private enum TrendRange: CaseIterable, Identifiable {
    case seven
    case thirty
    case ninety

    var id: Self { self }

    var label: String {
        switch self {
        case .seven: return "7d"
        case .thirty: return "30d"
        case .ninety: return "90d"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .seven: return 7 * 24 * 60 * 60
        case .thirty: return 30 * 24 * 60 * 60
        case .ninety: return 90 * 24 * 60 * 60
        }
    }
}

private struct EmptyChartPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}

private struct DailySeverityPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

private struct HeatmapCell: Identifiable {
    let weekday: Int
    let hour: Int
    let value: Double

    var id: String { "\(weekday)-\(hour)" }

    var weekdayLabel: String {
        Calendar.current.shortWeekdaySymbols[(weekday - 1 + 7) % 7]
    }

    var hourLabel: String {
        String(format: "%02d", hour)
    }
}

private struct WeekHourKey: Hashable {
    let weekday: Int
    let hour: Int
}

private struct MedicationEffectPoint: Identifiable {
    let name: String
    let delta: Double

    var id: String { name }
}

private struct MedicationAdherencePoint: Identifiable {
    let id = UUID()
    let name: String
    let useCase: String?
    let scheduledCount: Int
    let takenCount: Int
    let averageDoseDescription: String?

    var adherenceRate: Double {
        guard scheduledCount > 0 else {
            return takenCount > 0 ? 1.0 : 0.0
        }
        return min(Double(takenCount) / Double(scheduledCount), 1.0)
    }
}

private struct TrendInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String?
}

private struct MenstruationAveragePoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let count: Int
}

private struct SymptomPainPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

private struct AsNeededUsagePoint: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let medicationNames: [String]
}

private struct SentimentOverview {
    let averageScore: Double?
    let labeledCount: Int
    let pendingAnalysisCount: Int

    var description: String {
        if let score = averageScore {
            let formatted = String(format: "%.2f", score)
            let tone = score >= 0.4 ? "positive" : score <= -0.1 ? "concerning" : "neutral"
            return "Average note sentiment sits at \(formatted) (\(tone))."
        }
        return "Sentiment analysis pending for recent notes."
    }
}

private struct TrendCalculator {
    let entries: [SymptomEntry]
    let intakes: [MedicationIntake]
    let medications: [Medication]

    private static let doseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    // MARK: Rollups

    func dailySeverityPoints(for range: TrendRange) -> [DailySeverityPoint] {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: relevant) { calendar.startOfDay(for: $0.timestampValue) }
        let points = grouped.map { day, entries in
            let values = entries.compactMap { severityValue(for: $0) }
            let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            return DailySeverityPoint(date: day, value: average)
        }
        return points.sorted { $0.date < $1.date }
    }

    func hourlyHeatmap(for range: TrendRange) -> [HeatmapCell] {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return [] }
        let calendar = Calendar.current
        let groups = Dictionary(grouping: relevant) { entry -> WeekHourKey in
            let comps = calendar.dateComponents([.weekday, .hour], from: entry.timestampValue)
            return WeekHourKey(weekday: comps.weekday ?? 1, hour: comps.hour ?? 0)
        }

        return groups.compactMap { key, entries in
            let values = entries.compactMap { severityValue(for: $0) }
            guard values.isEmpty == false else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return HeatmapCell(weekday: key.weekday, hour: key.hour, value: average)
        }
    }

    func medicationEffects(for range: TrendRange) -> [MedicationEffectPoint] {
        let severityPoints = dailySeverityPoints(for: range)
        guard severityPoints.isEmpty == false else { return [] }
        let calendar = Calendar.current
        let severityByDay = Dictionary(uniqueKeysWithValues: severityPoints.map { point in
            (calendar.startOfDay(for: point.date), point.value)
        })
        let baselineValues = severityPoints.map(\.value)
        let baselineAverage = baselineValues.reduce(0, +) / Double(baselineValues.count)

        let cutoff = Date().addingTimeInterval(-range.duration)
        let relevantIntakes = intakes.filter { $0.timestampValue >= cutoff }

        var medicationDays: [NSManagedObjectID: Set<Date>] = [:]
        var medicationNames: [NSManagedObjectID: String] = [:]

        for intake in relevantIntakes {
            guard let medication = intake.medication else { continue }
            let objectID = medication.objectID
            medicationNames[objectID] = medication.name ?? "Medication"
            medicationDays[objectID, default: []].insert(calendar.startOfDay(for: intake.timestampValue))
            if let scheduled = intake.scheduledDate {
                medicationDays[objectID, default: []].insert(calendar.startOfDay(for: scheduled))
            }
        }

        let effects = medicationDays.compactMap { objectID, days -> MedicationEffectPoint? in
            let values = days.compactMap { severityByDay[$0] }
            guard values.isEmpty == false else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            let delta = baselineAverage - average
            guard abs(delta) > 0.1 else { return nil }
            let name = medicationNames[objectID] ?? "Medication"
            return MedicationEffectPoint(name: name, delta: delta)
        }

        return effects.sorted { $0.delta > $1.delta }
    }

    func medicationAdherence(for range: TrendRange) -> [MedicationAdherencePoint] {
        guard medications.isEmpty == false else { return [] }
        let now = Date()
        let start = now.addingTimeInterval(-range.duration)
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: now)

        let relevantIntakes = intakes.filter { $0.timestampValue >= start && $0.timestampValue <= now }

        return medications.compactMap { medication -> MedicationAdherencePoint? in
            let medicationIntakes = relevantIntakes.filter { $0.medication == medication }

            var scheduledCount = 0
            var takenCount = 0

            if medication.isAsNeeded == false {
                for schedule in medication.scheduleList where schedule.isActive {
                    var day = max(startDay, calendar.startOfDay(for: schedule.startDate ?? start))
                    while day <= endDay {
                        if let occurrence = schedule.occurs(on: day, calendar: calendar), occurrence >= start && occurrence <= now {
                            scheduledCount += 1
                            if let recorded = schedule.intake(on: occurrence),
                               recorded.timestampValue >= start && recorded.timestampValue <= now {
                                takenCount += 1
                            }
                        }
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                        day = next
                    }
                }

                let unscheduled = medicationIntakes.filter { $0.originValue != .scheduled }
                takenCount += unscheduled.count
            } else {
                scheduledCount = 0
                takenCount = medicationIntakes.count
            }

            if scheduledCount == 0 && medicationIntakes.isEmpty {
                return nil
            }

            let doses = medicationIntakes.compactMap { $0.amountValue }.map { NSDecimalNumber(decimal: $0).doubleValue }
            let averageDoseDescription: String? = {
                guard doses.isEmpty == false else { return nil }
                let average = doses.reduce(0, +) / Double(doses.count)
                guard let formatted = Self.doseFormatter.string(from: NSNumber(value: average)) else { return nil }
                let representativeUnit = medicationIntakes.first?.unit ?? medication.defaultUnit
                if let unit = representativeUnit, unit.isEmpty == false {
                    return "\(formatted) \(unit)"
                }
                return formatted
            }()

            return MedicationAdherencePoint(
                name: medication.name ?? "Untitled",
                useCase: medication.useCaseLabel,
                scheduledCount: scheduledCount,
                takenCount: takenCount,
                averageDoseDescription: averageDoseDescription
            )
        }
        .sorted { lhs, rhs in
            if lhs.scheduledCount == rhs.scheduledCount {
                return lhs.name < rhs.name
            }
            return lhs.scheduledCount > rhs.scheduledCount
        }
    }

    func menstruationAverages(for range: TrendRange) -> [MenstruationAveragePoint] {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return [] }
        let grouped = Dictionary(grouping: relevant, by: { $0.isMenstruating })
        return grouped.compactMap { key, entries in
            let values = entries.compactMap { severityValue(for: $0) }
            guard values.isEmpty == false else { return nil }
            let average = values.reduce(0, +) / Double(values.count)
            return MenstruationAveragePoint(
                label: key ? "Menstruating" : "Not Menstruating",
                value: average,
                count: entries.count
            )
        }
        .sorted { $0.label < $1.label }
    }

    func painBreakdown(for range: TrendRange) -> [SymptomPainPoint] {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return [] }
        var points: [SymptomPainPoint] = []

        let overall = relevant.compactMap { severityValue(for: $0) }
        if overall.isEmpty == false {
            let avg = overall.reduce(0, +) / Double(overall.count)
            points.append(SymptomPainPoint(label: "Overall", value: avg))
        }

        let headacheValues = relevant.map { Double($0.headache) }.filter { $0 > 0 }
        if headacheValues.isEmpty == false {
            points.append(SymptomPainPoint(label: "Headache", value: headacheValues.reduce(0, +) / Double(headacheValues.count)))
        }

        let nauseaValues = relevant.map { Double($0.nausea) }.filter { $0 > 0 }
        if nauseaValues.isEmpty == false {
            points.append(SymptomPainPoint(label: "Nausea", value: nauseaValues.reduce(0, +) / Double(nauseaValues.count)))
        }

        let anxietyValues = relevant.map { Double($0.anxiety) }.filter { $0 > 0 }
        if anxietyValues.isEmpty == false {
            points.append(SymptomPainPoint(label: "Anxiety", value: anxietyValues.reduce(0, +) / Double(anxietyValues.count)))
        }

        return points
    }

    func asNeededUsage(for range: TrendRange) -> [AsNeededUsagePoint] {
        let start = Date().addingTimeInterval(-range.duration)
        let relevant = intakes.filter { $0.originValue == .asNeeded && $0.timestampValue >= start }
        guard relevant.isEmpty == false else { return [] }

        var groups: [String: (count: Int, meds: Set<String>)] = [:]
        for intake in relevant {
            let medicationName = intake.medication?.name ?? "Medication"
            let label = intake.medication?.useCaseLabel ?? medicationName
            var existing = groups[label] ?? (0, [])
            existing.count += 1
            existing.meds.insert(medicationName)
            groups[label] = existing
        }

        return groups.map { key, payload in
            AsNeededUsagePoint(label: key, count: payload.count, medicationNames: Array(payload.meds).sorted())
        }
        .sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.label < rhs.label
            }
            return lhs.count > rhs.count
        }
    }

    func sentimentOverview(for range: TrendRange) -> SentimentOverview? {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return nil }
        let scored = relevant.compactMap { $0.sentimentScoreValue }
        let average = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)
        let pending = relevant.filter { ($0.note?.isEmpty == false) && $0.sentimentScoreValue == nil }.count
        return SentimentOverview(averageScore: average, labeledCount: scored.count, pendingAnalysisCount: pending)
    }

    func insights(for range: TrendRange) -> [TrendInsight] {
        let relevant = filteredEntries(for: range)
        guard relevant.isEmpty == false else { return [] }
        var result: [TrendInsight] = []
        let calendar = Calendar.current

        let morningHighs = relevant.filter { entry in
            let hour = calendar.component(.hour, from: entry.timestampValue)
            return hour >= 5 && hour < 11 && severityValue(for: entry) ?? 0 >= 7
        }
        if range == .seven, morningHighs.count >= 3 {
            result.append(TrendInsight(title: "Noticed \(morningHighs.count) mornings this week with level ≥7.", detail: "Tag wake time or sleep quality to give context."))
        } else if morningHighs.count >= 3 {
            result.append(TrendInsight(title: "Morning severity ≥7 appears \(morningHighs.count) times in the last \(range.label).", detail: "Tag wake time or sleep quality to clarify triggers."))
        }

        if let effect = medicationEffects(for: range).first(where: { $0.delta > 1 }) {
            result.append(TrendInsight(title: "\(effect.name) correlates with lower severity (Δ\(String(format: "%.1f", effect.delta))).", detail: "Keep noting when you take it to confirm the pattern."))
        }

        if let menstruationPoint = menstruationAverages(for: range).first(where: { $0.label == "Menstruating" }),
           let nonMenstruationPoint = menstruationAverages(for: range).first(where: { $0.label == "Not Menstruating" }) {
            let delta = menstruationPoint.value - nonMenstruationPoint.value
            if abs(delta) >= 0.5 {
                let direction = delta > 0 ? "higher" : "lower"
                result.append(TrendInsight(title: "Severity runs \(String(format: "%.1f", abs(delta))) points \(direction) while menstruating.", detail: "Include cycle tags in notes to keep context clear."))
            }
        }

        return result
    }

    // MARK: Helpers

    private func filteredEntries(for range: TrendRange) -> [SymptomEntry] {
        guard entries.isEmpty == false else { return [] }
        let cutoff = Date().addingTimeInterval(-range.duration)
        return entries.filter { $0.timestampValue >= cutoff }
    }

    private func severityValue(for entry: SymptomEntry) -> Double? {
        if entry.severity > 0 {
            return Double(entry.severity)
        }
        let detailValues = [entry.headache, entry.nausea, entry.anxiety].map(Double.init).filter { $0 > 0 }
        guard detailValues.isEmpty == false else { return nil }
        return detailValues.reduce(0, +) / Double(detailValues.count)
    }
}

#Preview("Trends") {
    let controller = PersistenceController.preview
    let context = controller.container.viewContext
    PreviewSeed.populateIfNeeded(context: context)
    let journal = try? context.fetch(Journal.fetchRequest()).first
    return Group {
        if let journal {
            let identifier: UUID = {
                if let existing = journal.id { return existing }
                let newID = UUID()
                journal.id = newID
                try? context.save()
                return newID
            }()
            NavigationStack {
                TrendsView(journalID: journal.objectID, journalIdentifier: identifier)
            }
            .environment(\.managedObjectContext, context)
        }
    }
}
