import Foundation

enum ScreenshotMode {
    static var isOn: Bool {
        ProcessInfo.processInfo.arguments.contains("--seed-screenshots")
    }
}

