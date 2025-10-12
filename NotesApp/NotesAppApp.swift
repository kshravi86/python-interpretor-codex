import SwiftUI

@main
struct CodeSnakeApp: App {
    init() {
        CrashHandler.shared.install()
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PythonInterpreterView()
            }
        }
    }
}
