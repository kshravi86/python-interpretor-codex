import SwiftUI

@main
struct PyDeckApp: App {
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
