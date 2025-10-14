import SwiftUI

@main
struct CodeSnakeApp: App {
    init() {
        CrashHandler.shared.install()
        AppLogger.log("App launch")
        // Extra context at startup
        let device = UIDevice.current
        let system = "\(device.systemName) \(device.systemVersion)"
        let model = device.model
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        AppLogger.log("App version: \(version) (\(build)), Device: \(model), System: \(system)")
        // Log file location to aid discovery
        if let docs = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            let logURL = docs.appendingPathComponent("log.txt")
            AppLogger.log("Log file: \(logURL.path)")
        }
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PythonInterpreterView()
            }
        }
    }
}
