import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func scheduleInactivityReminder(after minutes: Int = 90) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["inactivity_reminder"]) 

        let content = UNMutableNotificationContent()
        content.title = "Time to hydrate"
        content.body = "You haven't logged water in a while. Take a sip!"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "inactivity_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func schedulePostWorkoutReminder(after minutes: Int = 15) {
        let content = UNMutableNotificationContent()
        content.title = "Rehydrate after workout"
        content.body = "Top up your fluids after exercising."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "post_workout_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

