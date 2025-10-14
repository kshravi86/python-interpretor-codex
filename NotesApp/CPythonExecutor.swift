import Foundation

import UIKit

final class CPythonExecutor: PythonExecutor {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "CPython runtime not configured in this build." }
    }

    private static var didInit = false

    func execute(code: String) async throws -> ExecutionResult {
        AppLogger.log("CPythonExecutor.execute begin len=\(code.count)")
        
        // Safety check: ensure we don't crash on empty/invalid code
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            AppLogger.log("CPythonExecutor.execute: empty code provided")
            return ExecutionResult(stdout: "", stderr: "Error: No code provided", exitCode: 1)
        }
        
        do {
            try ensureInitialized()
        } catch {
            AppLogger.log("CPythonExecutor.execute: initialization failed - \(error)")
            return ExecutionResult(stdout: "", stderr: "Python runtime initialization failed: \(error.localizedDescription)", exitCode: 1)
        }
        
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExecutionResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var outPtr: UnsafeMutablePointer<CChar>? = nil
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                var status: Int32 = 0
                
                AppLogger.log("CPythonExecutor.execute: calling pybridge_run")
                let rc = code.withCString { cstr in
                    pybridge_run(cstr, &outPtr, &errPtr, &status)
                }
                AppLogger.log("CPythonExecutor.execute: pybridge_run returned rc=\(rc)")
                
                let stdoutStr = outPtr.flatMap { String(cString: $0) } ?? ""
                let stderrStr = errPtr.flatMap { String(cString: $0) } ?? ""
                
                AppLogger.log("CPythonExecutor.execute: stdout=\(stdoutStr.count)B stderr=\(stderrStr.count)B")
                
                // Clean up memory
                if let p = outPtr { pybridge_free(p) }
                if let p = errPtr { pybridge_free(p) }
                
                if rc == 0 {
                    AppLogger.log("CPythonExecutor.execute SUCCESS status=\(status)")
                    cont.resume(returning: ExecutionResult(stdout: stdoutStr, stderr: stderrStr, exitCode: Int(status)))
                } else {
                    AppLogger.log("CPythonExecutor.execute FAILED rc=\(rc)")
                    // Don't throw error, return error result instead to prevent crashes
                    let errorMsg = stderrStr.isEmpty ? "Python execution failed (code: \(rc))" : stderrStr
                    cont.resume(returning: ExecutionResult(stdout: stdoutStr, stderr: errorMsg, exitCode: Int(rc)))
                }
            }
        }
    }

    private func ensureInitialized() throws {
        if Self.didInit { 
            AppLogger.log("CPythonExecutor already initialized, skipping")
            return 
        }
        guard let resURL = Bundle.main.resourceURL else { 
            AppLogger.log("CPythonExecutor.init FAIL: Bundle.main.resourceURL is nil")
            throw NotConfigured() 
        }
        AppLogger.log("CPythonExecutor.init begin res=\(resURL.path)")
        
        // Check if python-stdlib.zip exists
        let stdlibPath = resURL.appendingPathComponent("python-stdlib.zip")
        let stdlibExists = FileManager.default.fileExists(atPath: stdlibPath.path)
        AppLogger.log("python-stdlib.zip exists: \(stdlibExists) at \(stdlibPath.path)")
        
        // If stdlib is missing, throw a more descriptive error instead of crashing
        if !stdlibExists {
            AppLogger.log("CRITICAL: python-stdlib.zip missing - CPython cannot initialize")
            
            // List available files in the bundle for debugging
            do {
                let files = try FileManager.default.contentsOfDirectory(atPath: resURL.path)
                AppLogger.log("Available files in app bundle: \(files.joined(separator: ", "))")
                
                // Look for any Python-related files
                let pythonFiles = files.filter { $0.lowercased().contains("python") || $0.lowercased().contains("stdlib") }
                if !pythonFiles.isEmpty {
                    AppLogger.log("Python-related files found: \(pythonFiles.joined(separator: ", "))")
                }
            } catch {
                AppLogger.log("Failed to list bundle contents: \(error)")
            }
            
            throw NSError(domain: "CPythonExecutor", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Python runtime not available. Missing python-stdlib.zip in app bundle."
            ])
        }
        
        var buf = Array<CChar>(repeating: 0, count: 256)
        let rc: Int32 = resURL.path.withCString { path in
            pybridge_initialize(path, &buf, buf.count)
        }
        if rc != 0 {
            let msg = String(cString: buf)
            AppLogger.log("CPythonExecutor.init FAIL rc=\(rc) msg=\(msg)")
            throw NSError(domain: "CPythonExecutor", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: msg])
        }
        AppLogger.log("CPythonExecutor.init SUCCESS")
        Self.didInit = true
    }
}
