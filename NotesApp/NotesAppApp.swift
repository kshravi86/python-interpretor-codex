import SwiftUI

@main
struct CodeSnakeApp: App {
    init() {
        CrashHandler.shared.install()
        AppLogger.log("App launch")
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PythonInterpreterView()
            }
        }
    }
}
