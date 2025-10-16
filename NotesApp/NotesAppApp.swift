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

        // Optional self-test at launch. Enable by setting env var PY_SELFTEST_AT_LAUNCH=1 in scheme if you want it.
        if ProcessInfo.processInfo.environment["PY_SELFTEST_AT_LAUNCH"] == "1" {
            runSelfTest()
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

@MainActor
private func runSelfTest() {
    guard let res = Bundle.main.resourceURL else {
        AppLogger.log("SelfTest: no resourceURL")
        return
    }
    var errbuf = Array<CChar>(repeating: 0, count: 256)
    let rcInit = res.path.withCString { cstr in
        pybridge_initialize(cstr, &errbuf, errbuf.count)
    }
    if rcInit != 0 {
        AppLogger.log("SelfTest: init failed rc=\(rcInit) msg=\(String(cString: errbuf))")
        return
    }
    let selftestPath = res.appendingPathComponent("selftest.py").path
    var outPtr: UnsafeMutablePointer<CChar>? = nil
    var errPtr: UnsafeMutablePointer<CChar>? = nil
    var status: Int32 = 0
    let rcRun: Int32 = selftestPath.withCString { cpath in
        pybridge_run_file(cpath, &outPtr, &errPtr, &status)
    }
    let out = outPtr.map { String(cString: $0) } ?? ""
    let err = errPtr.map { String(cString: $0) } ?? ""
    if let p = outPtr { pybridge_free(p) }
    if let p = errPtr { pybridge_free(p) }
    AppLogger.log("SelfTest rc=\(rcRun) status=\(status) out='\(out.trimmingCharacters(in: .whitespacesAndNewlines))' err='\(err.trimmingCharacters(in: .whitespacesAndNewlines))'")
}
