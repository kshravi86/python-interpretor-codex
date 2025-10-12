import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Seed preview data
        let settings = UserSettings(context: viewContext)
        settings.weightKg = 70
        settings.activityLevel = "medium"
        settings.dailyGoalMl = 70 * 35
        settings.cupSizes = "[250,350,500]"
        settings.lastWorkout = Date().addingTimeInterval(-7200)

        let entry1 = HydrationEntry(context: viewContext)
        entry1.amountMl = 350
        entry1.timestamp = Date().addingTimeInterval(-3600)
        entry1.drinkType = "water"
        entry1.caffeineMg = 0

        let entry2 = HydrationEntry(context: viewContext)
        entry2.amountMl = 250
        entry2.timestamp = Date().addingTimeInterval(-18000)
        entry2.drinkType = "coffee"
        entry2.caffeineMg = 80
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "NotesModel")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
