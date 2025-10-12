import SwiftUI
import CoreData
import UIKit

struct TodayView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showAdd = false
    @State private var selectedDrink: String = "water"
    @State private var selectedSize: Int = 250
    @State private var toast: Toast? = nil
    // Flags to control UI for CI screenshots
    @State private var triggerAddOnAppear: Bool = ProcessInfo.processInfo.arguments.contains("--screenshot-addsheet")
    @State private var triggerCelebrateOnAppear: Bool = ProcessInfo.processInfo.arguments.contains("--screenshot-celebrate")

    @FetchRequest private var todayEntries: FetchedResults<HydrationEntry>
    
    init() {
        let start = Calendar.current.startOfDay(for: Date())
        _todayEntries = FetchRequest<HydrationEntry>(
            sortDescriptors: [NSSortDescriptor(keyPath: \HydrationEntry.timestamp, ascending: true)],
            predicate: NSPredicate(format: "timestamp >= %@", start as NSDate),
            animation: .default
        )
    }

    @State private var ringPulse = false
    @State private var showCelebration = false

    private var settings: UserSettings {
        SettingsProvider.fetchOrCreate(in: viewContext)
    }

    private var goalMl: Int64 {
        let level = ActivityLevel(rawValue: settings.activityLevel ?? ActivityLevel.medium.rawValue) ?? .medium
        return HydrationCalculator.goalMl(weightKg: settings.weightKg, activity: level)
    }

    private var todayMl: Int64 {
        todayEntries.reduce(0) { $0 + ($1.amountMl) }
    }

    private var progress: Double {
        guard goalMl > 0 else { return 0 }
        return min(1.0, Double(todayMl) / Double(goalMl))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 16)
                        .frame(width: 180, height: 180)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(WaterTheme.tint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 180, height: 180)
                        .animation(.easeInOut, value: progress)
                    VStack(spacing: 4) {
                        Text("\(todayMl) / \(goalMl) ml")
                            .font(.headline)
                        Text(progressLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .scaleEffect(ringPulse ? 1.06 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ringPulse)

                HStack(spacing: 12) {
                    ForEach(SettingsProvider.cupSizes(from: settings), id: \.self) { size in
                        Button("\(size) ml") {
                            addDrink(drink: "water", size: size)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button {
                    showAdd = true
                } label: {
                    Label("Add Drink", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
        }
        .overlay(
            Group {
                if showCelebration {
                    CelebrationOverlay(isVisible: $showCelebration)
                }
            }
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    settings.lastWorkout = Date()
                    try? viewContext.save()
                    NotificationManager.shared.schedulePostWorkoutReminder(after: 15)
                } label: {
                    Label("Workout", systemImage: "figure.run")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddDrinkSheet(selectedDrink: $selectedDrink, selectedSize: $selectedSize) { drink, size in
                addDrink(drink: drink, size: size)
            }
        }
        .toast($toast)
        .tint(WaterTheme.tint)
        .onAppear {
            if triggerAddOnAppear {
                DispatchQueue.main.async { showAdd = true }
            }
            if triggerCelebrateOnAppear {
                DispatchQueue.main.async { showCelebration = true }
            }
        }
    }

    private var progressLabel: String {
        let pct = Int(progress * 100)
        return "\(pct)% of goal"
    }

    private func addDrink(drink: String, size: Int) {
        let caffeine = estimatedCaffeine(for: drink, sizeMl: size)
        _ = logDrink(context: viewContext, amountMl: size, drinkType: drink, caffeineMg: caffeine)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        toast = Toast(title: "Added \(size) ml", subtitle: drink.capitalized, systemImage: "drop.fill")
        pulseRingAndCelebrateIfNeeded(added: size)
    }

    private func pulseRingAndCelebrateIfNeeded(added size: Int) {
        // Pulse animation when toast shows
        ringPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { ringPulse = false }

        // Check goal crossing without waiting for fetch refresh
        let predicted = todayMl + Int64(size)
        if predicted >= goalMl, shouldCelebrateToday() {
            showCelebration = true
            setCelebratedToday()
        }
    }

    private func shouldCelebrateToday() -> Bool {
        let key = "lastGoalDate"
        let todayKey = DateFormatter.cachedShort.string(from: Date())
        return UserDefaults.standard.string(forKey: key) != todayKey
    }

    private func setCelebratedToday() {
        let key = "lastGoalDate"
        let todayKey = DateFormatter.cachedShort.string(from: Date())
        UserDefaults.standard.set(todayKey, forKey: key)
    }
}

private extension DateFormatter {
    static let cachedShort: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

private func estimatedCaffeine(for drink: String, sizeMl: Int) -> Int {
    switch drink {
    case "coffee": return Int(Double(sizeMl) * 0.32) // ~320mg/L approximation
    case "tea": return Int(Double(sizeMl) * 0.20)
    case "soda": return Int(Double(sizeMl) * 0.10)
    default: return 0
    }
}

struct AddDrinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDrink: String
    @Binding var selectedSize: Int
    var onAdd: (String, Int) -> Void

    let drinks = ["water", "coffee", "tea", "soda"]
    let sizes = [150, 200, 250, 300, 350, 400, 500, 600]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Drink", selection: $selectedDrink) {
                    ForEach(drinks, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Picker("Size (ml)", selection: $selectedSize) {
                    ForEach(sizes, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            .navigationTitle("Add Drink")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd(selectedDrink, selectedSize)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TodayView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
