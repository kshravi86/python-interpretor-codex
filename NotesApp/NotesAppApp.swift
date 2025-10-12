import SwiftUI

@main
struct SnakePyApp: App {
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
