import Foundation
import Darwin

final class CrashHandler {
    static let shared = CrashHandler()
    private var installed = false

    private init() {}

    func install() {
        guard !installed else { return }
        installed = true

        NSSetUncaughtExceptionHandler { exception in
            ErrorLogger.shared.log(exception: exception)
        }
        // Avoid installing POSIX signal handlers that may perform unsafe work
        // in signal context. App Store review is fine with exception logging
        // and system crash reports are available in App Store Connect.
    }
}
