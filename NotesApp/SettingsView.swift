import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var weightText: String = ""
    @State private var activity: ActivityLevel = .medium
    @State private var cupSizesText: String = ""

    private var settings: UserSettings {
        SettingsProvider.fetchOrCreate(in: viewContext)
    }

    private var computedGoal: Int64 {
        HydrationCalculator.goalMl(weightKg: Double(weightText), activity: activity)
    }

    var body: some View {
        Form {
                Section(header: Text("Profile")) {
                    HStack {
                        Text("Weight (kg)")
                        Spacer()
                        TextField("70", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    Picker("Activity", selection: $activity) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(level.rawValue.capitalized).tag(level)
                        }
                    }
                }

                Section(header: Text("Daily Goal"), footer: Text("Automatically calculated from weight and activity. You can override if needed.")) {
                    HStack {
                        Text("Suggested Goal")
                        Spacer()
                        Text("\(computedGoal) ml")
                            .foregroundColor(.secondary)
                    }
                    Button("Apply Suggested Goal") {
                        settings.dailyGoalMl = computedGoal
                        try? viewContext.save()
                    }
                }

                Section(header: Text("Quick Add Cup Sizes"), footer: Text("Comma-separated list, e.g. 250,350,500")) {
                    TextField("250,350,500", text: $cupSizesText)
                }

                Section {
                    Button("Save Settings") {
                        if let w = Double(weightText) { settings.weightKg = w }
                        settings.activityLevel = activity.rawValue
                        SettingsProvider.setCupSizes(parseSizes(cupSizesText), for: settings)
                        if settings.dailyGoalMl == 0 { settings.dailyGoalMl = computedGoal }
                        try? viewContext.save()
                    }
                }

                Section(header: Text("Legal")) {
                    if let url = URL(string: "https://kshravi86.github.io/hydrateiq-privacy/") {
                        Link("Privacy Policy", destination: url)
                    }
                }

                Section(header: Text("Support")) {
                    if let url = URL(string: "https://kshravi86.github.io/hydrateiq-support/") {
                        Link("Support Website", destination: url)
                    }
                    if let mail = URL(string: "mailto:kshravi86@gmail.com") {
                        Link("Email Support", destination: mail)
                    }
                }
        }
        .onAppear(perform: loadFromStore)
    }

    private func loadFromStore() {
        weightText = settings.weightKg > 0 ? String(format: "%.0f", settings.weightKg) : "70"
        activity = ActivityLevel(rawValue: settings.activityLevel ?? ActivityLevel.medium.rawValue) ?? .medium
        cupSizesText = SettingsProvider.cupSizes(from: settings).map { String($0) }.joined(separator: ",")
    }

    private func parseSizes(_ text: String) -> [Int] {
        text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 }
    }
}

#Preview {
    SettingsView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
