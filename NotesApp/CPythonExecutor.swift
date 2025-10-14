import Foundation

import UIKit

final class CPythonExecutor: PythonExecutor {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "CPython runtime not configured in this build." }
    }

    private static var didInit = false

    func execute(code: String) async throws -> ExecutionResult {
        AppLogger.log("CPythonExecutor.execute begin len=\(code.count)")
        try ensureInitialized()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExecutionResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var outPtr: UnsafeMutablePointer<CChar>? = nil
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                var status: Int32 = 0
                let rc = code.withCString { cstr in
                    pybridge_run(cstr, &outPtr, &errPtr, &status)
                }
                let stdoutStr = outPtr.flatMap { String(cString: $0) } ?? ""
                let stderrStr = errPtr.flatMap { String(cString: $0) } ?? ""
                if let p = outPtr { pybridge_free(p) }
                if let p = errPtr { pybridge_free(p) }
                if rc == 0 {
                    AppLogger.log("CPythonExecutor.execute ok status=\(status) stdout=\(stdoutStr.count)B stderr=\(stderrStr.count)B")
                    cont.resume(returning: ExecutionResult(stdout: stdoutStr, stderr: stderrStr, exitCode: Int(status)))
                } else {
                    let err = NSError(domain: "CPythonExecutor", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: stderrStr.isEmpty ? "Execution failed (rc=\(rc))" : stderrStr])
                    AppLogger.log("CPythonExecutor.execute fail rc=\(rc) stderr=\(stderrStr)")
                    cont.resume(throwing: err)
                }
            }
        }
    }

    private func ensureInitialized() throws {
        if Self.didInit { return }
        guard let resURL = Bundle.main.resourceURL else { throw NotConfigured() }
        AppLogger.log("CPythonExecutor.init begin res=\(resURL.path)")
        var buf = Array<CChar>(repeating: 0, count: 256)
        let rc: Int32 = resURL.path.withCString { path in
            pybridge_initialize(path, &buf, buf.count)
        }
        if rc != 0 {
            let msg = String(cString: buf)
            AppLogger.log("CPythonExecutor.init fail rc=\(rc) msg=\(msg)")
            throw NSError(domain: "CPythonExecutor", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        AppLogger.log("CPythonExecutor.init ok")
        Self.didInit = true
    }
}
