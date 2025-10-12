import Foundation
import CoreData

enum ActivityLevel: String, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
}

struct HydrationCalculator {
    static func goalMl(weightKg: Double?, activity: ActivityLevel?) -> Int64 {
        let base = ((weightKg ?? 70) * 35).rounded()
        let activityAdj: Double
        switch activity ?? .medium {
        case .low: activityAdj = 0
        case .medium: activityAdj = 350
        case .high: activityAdj = 700
        }
        return Int64(max(1500, Int(base + activityAdj)))
    }
}

final class SettingsProvider {
    static func fetchOrCreate(in context: NSManagedObjectContext) -> UserSettings {
        let request = NSFetchRequest<UserSettings>(entityName: "UserSettings")
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first {
            return existing
        }
        let s = UserSettings(context: context)
        s.weightKg = 70
        s.activityLevel = ActivityLevel.medium.rawValue
        s.dailyGoalMl = HydrationCalculator.goalMl(weightKg: s.weightKg, activity: .medium)
        s.cupSizes = "[250,350,500]"
        try? context.save()
        return s
    }

    static func cupSizes(from settings: UserSettings) -> [Int] {
        guard let data = settings.cupSizes?.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Int] else {
            return [250,350,500]
        }
        return arr
    }

    static func setCupSizes(_ sizes: [Int], for settings: UserSettings) {
        if let data = try? JSONSerialization.data(withJSONObject: sizes, options: []) {
            settings.cupSizes = String(data: data, encoding: .utf8)
        }
    }
}

extension Calendar {
    func startOfToday() -> Date { startOfDay(for: Date()) }
}

struct HydrationStats {
    static func todayTotalMl(context: NSManagedObjectContext) -> Int64 {
        let req = NSFetchRequest<NSFetchRequestResult>(entityName: "HydrationEntry")
        let start = Calendar.current.startOfToday()
        req.predicate = NSPredicate(format: "timestamp >= %@", start as NSDate)
        req.resultType = .dictionaryResultType
        let sumExp = NSExpressionDescription()
        sumExp.name = "total"
        sumExp.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "amountMl")])
        sumExp.expressionResultType = .integer64AttributeType
        req.propertiesToFetch = [sumExp]
        if let result = try? context.fetch(req) as? [[String: Any]],
           let total = result.first?["total"] as? Int64 {
            return total
        }
        return 0
    }
}

@discardableResult
func logDrink(context: NSManagedObjectContext, amountMl: Int, drinkType: String, caffeineMg: Int = 0) -> HydrationEntry {
    let entry = HydrationEntry(context: context)
    entry.amountMl = Int64(amountMl)
    entry.timestamp = Date()
    entry.drinkType = drinkType
    entry.caffeineMg = Int64(caffeineMg)
    try? context.save()
    NotificationManager.shared.scheduleInactivityReminder(after: 90)
    return entry
}

