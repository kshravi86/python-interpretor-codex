import Foundation
import Darwin

final class CrashHandler {
    static let shared = CrashHandler()
    private var installed = false

    private init() {}

    func install() {
        guard !installed else { return }
        installed = true
        AppLogger.log("CrashHandler installed")

        NSSetUncaughtExceptionHandler { exception in
            AppLogger.log("Uncaught NSException captured: \(exception.name.rawValue)")
            ErrorLogger.shared.log(exception: exception)
        }
        // Avoid installing POSIX signal handlers that may perform unsafe work
        // in signal context. App Store review is fine with exception logging
        // and system crash reports are available in App Store Connect.
    }
}
