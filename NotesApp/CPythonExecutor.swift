import Foundation

import UIKit

final class CPythonExecutor: PythonExecutor {
    struct NotConfigured: LocalizedError {
        var errorDescription: String? { "CPython runtime not configured in this build." }
    }

    private static var didInit = false
    private static var didInstallCallbacks = false

    // Notification names for streaming output
    static let stdoutNotification = Notification.Name("PythonStdoutDidEmit")
    static let stderrNotification = Notification.Name("PythonStderrDidEmit")

    // C-callback shims are defined at global scope below

    func execute(code: String) async throws -> ExecutionResult {
        AppLogger.log("=== CPythonExecutor.execute() START ===")
        AppLogger.log("Code length: \(code.count) characters")
        AppLogger.log("Code preview (first 100 chars): \(String(code.prefix(100)))")
        
        // Safety check: ensure we don't crash on empty/invalid code
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            AppLogger.log("CPythonExecutor.execute: empty code provided after trimming")
            return ExecutionResult(stdout: "", stderr: "Error: No code provided", exitCode: 1)
        }
        
        AppLogger.log("Code after trimming: \(trimmedCode.count) characters")
        
        // Initialize CPython if needed
        AppLogger.log("Ensuring CPython is initialized...")
        do {
            try ensureInitialized()
            AppLogger.log("CPython initialization check complete")
        } catch {
            AppLogger.log("CPythonExecutor.execute: initialization FAILED - \(error)")
            AppLogger.log("Error type: \(type(of: error))")
            AppLogger.log("Error description: \(error.localizedDescription)")
            return ExecutionResult(stdout: "", stderr: "Python runtime initialization failed: \(error.localizedDescription)", exitCode: 1)
        }
        
        AppLogger.log("About to execute Python code via pybridge_run...")
        
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ExecutionResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                AppLogger.log("=== EXECUTING ON BACKGROUND THREAD ===")
                
                var outPtr: UnsafeMutablePointer<CChar>? = nil
                var errPtr: UnsafeMutablePointer<CChar>? = nil
                var status: Int32 = 0
                
                AppLogger.log("Initialized output pointers:")
                AppLogger.log("outPtr: \(outPtr == nil ? "nil" : "not nil")")
                AppLogger.log("errPtr: \(errPtr == nil ? "nil" : "not nil")")
                AppLogger.log("status: \(status)")
                
                AppLogger.log("Calling pybridge_run with code...")
                let rc = code.withCString { cstr in
                    AppLogger.log("Code converted to C string, length: \(strlen(cstr))")
                    AppLogger.log("About to call pybridge_run...")
                    let result = pybridge_run(cstr, &outPtr, &errPtr, &status)
                    AppLogger.log("pybridge_run call completed with result: \(result)")
                    return result
                }
                
                AppLogger.log("pybridge_run returned: rc=\(rc), status=\(status)")
                
                // Extract output strings
                AppLogger.log("Extracting output strings...")
                let stdoutStr = outPtr.flatMap { ptr in
                    AppLogger.log("stdout pointer is not nil, extracting string...")
                    let str = String(cString: ptr)
                    AppLogger.log("stdout string extracted, length: \(str.count)")
                    return str
                } ?? ""
                
                let stderrStr = errPtr.flatMap { ptr in
                    AppLogger.log("stderr pointer is not nil, extracting string...")
                    let str = String(cString: ptr)
                    AppLogger.log("stderr string extracted, length: \(str.count)")
                    return str
                } ?? ""
                
                AppLogger.log("Output extraction complete:")
                AppLogger.log("stdout: \(stdoutStr.count) bytes")
                AppLogger.log("stderr: \(stderrStr.count) bytes")
                
                if stdoutStr.count > 0 {
                    AppLogger.log("stdout content: '\(stdoutStr)'")
                }
                if stderrStr.count > 0 {
                    AppLogger.log("stderr content: '\(stderrStr)'")
                }
                
                // Clean up memory
                AppLogger.log("Cleaning up memory...")
                if let p = outPtr { 
                    AppLogger.log("Freeing stdout pointer")
                    pybridge_free(p) 
                }
                if let p = errPtr { 
                    AppLogger.log("Freeing stderr pointer")
                    pybridge_free(p) 
                }
                AppLogger.log("Memory cleanup complete")
                
                // Determine result
                if rc == 0 {
                    AppLogger.log("Execution SUCCESS - rc=0, status=\(status)")
                    let result = ExecutionResult(stdout: stdoutStr, stderr: stderrStr, exitCode: Int(status))
                    AppLogger.log("Created ExecutionResult with exitCode: \(result.exitCode ?? -999)")
                    cont.resume(returning: result)
                } else {
                    AppLogger.log("Execution FAILED - rc=\(rc)")
                    let errorMsg = stderrStr.isEmpty ? "Python execution failed (code: \(rc))" : stderrStr
                    AppLogger.log("Error message: '\(errorMsg)'")
                    let result = ExecutionResult(stdout: stdoutStr, stderr: errorMsg, exitCode: Int(rc))
                    AppLogger.log("Created error ExecutionResult with exitCode: \(result.exitCode ?? -999)")
                    cont.resume(returning: result)
                }
                
                AppLogger.log("=== BACKGROUND THREAD EXECUTION COMPLETE ===")
            }
        }
    }

    private func ensureInitialized() throws {
        AppLogger.log("=== CPythonExecutor.ensureInitialized() START ===")
        
        if Self.didInit { 
            AppLogger.log("CPythonExecutor already initialized, skipping")
            return 
        }
        
        AppLogger.log("CPythonExecutor not yet initialized, proceeding with setup")
        
        // Check Bundle.main.resourceURL
        AppLogger.log("Checking Bundle.main.resourceURL...")
        guard let resURL = Bundle.main.resourceURL else { 
            AppLogger.log("FATAL ERROR: Bundle.main.resourceURL is nil")
            AppLogger.log("Bundle.main.bundlePath: \(Bundle.main.bundlePath)")
            AppLogger.log("Bundle.main.resourcePath: \(Bundle.main.resourcePath ?? "nil")")
            throw NotConfigured() 
        }
        
        AppLogger.log("Bundle.main.resourceURL: \(resURL)")
        AppLogger.log("Resource URL path: \(resURL.path)")
        AppLogger.log("Resource URL absoluteString: \(resURL.absoluteString)")
        
        // Check if resource directory exists and is accessible
        let resPath = resURL.path
        let resExists = FileManager.default.fileExists(atPath: resPath)
        AppLogger.log("Resource directory exists: \(resExists) at \(resPath)")
        
        if resExists {
            var isDir: ObjCBool = false
            let accessible = FileManager.default.fileExists(atPath: resPath, isDirectory: &isDir)
            AppLogger.log("Resource directory accessible: \(accessible), isDirectory: \(isDir.boolValue)")
        }
        
        // List ALL files in the bundle root
        AppLogger.log("=== LISTING ALL FILES IN APP BUNDLE ===")
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(atPath: resPath)
            AppLogger.log("Total files in bundle: \(allFiles.count)")
            
            for (index, file) in allFiles.enumerated() {
                let filePath = resURL.appendingPathComponent(file)
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDir)
                let fileSize: Int64
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: filePath.path)
                    fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                } catch {
                    fileSize = -1
                }
                
                AppLogger.log("File \(index + 1): \(file) (exists: \(exists), isDir: \(isDir.boolValue), size: \(fileSize) bytes)")
            }
            
            // Filter for Python/stdlib related files
            let pythonFiles = allFiles.filter { file in
                let lower = file.lowercased()
                return lower.contains("python") || lower.contains("stdlib") || lower.contains(".zip") || lower.contains("framework")
            }
            
            if !pythonFiles.isEmpty {
                AppLogger.log("=== PYTHON/STDLIB RELATED FILES ===")
                for file in pythonFiles {
                    AppLogger.log("Python-related: \(file)")
                }
            } else {
                AppLogger.log("NO Python/stdlib related files found in bundle!")
            }
            
        } catch {
            AppLogger.log("FAILED to list bundle contents: \(error)")
            AppLogger.log("Error domain: \(error.localizedDescription)")
        }
        
        // Prepare Application Support mirror of site-packages/app_packages (optional copy on first run)
        do {
            let appSup = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let resSite = resURL.appendingPathComponent("site-packages")
            let resApps = resURL.appendingPathComponent("app_packages")
            let dstSite = appSup.appendingPathComponent("site-packages")
            let dstApps = appSup.appendingPathComponent("app_packages")
            func copyIfNeeded(src: URL, dst: URL, label: String) {
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: dst.path, isDirectory: &isDir)
                if !exists {
                    if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
                        AppLogger.log("Copying \(label) from Resources to Application Support...")
                        do {
                            try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                        } catch {}
                        do { try FileManager.default.copyItem(at: src, to: dst); AppLogger.log("Copied \(label) -> \(dst.path)") }
                        catch { AppLogger.log("Failed to copy \(label): \(error.localizedDescription)") }
                    }
                } else {
                    AppLogger.log("Application Support \(label) already exists; skipping copy")
                }
            }
            copyIfNeeded(src: resSite, dst: dstSite, label: "site-packages")
            copyIfNeeded(src: resApps, dst: dstApps, label: "app_packages")
        } catch {
            AppLogger.log("Could not prepare Application Support packages: \(error.localizedDescription)")
        }

        // Check specifically for python-stdlib.zip
        AppLogger.log("=== CHECKING FOR python-stdlib.zip ===")
        let stdlibPath = resURL.appendingPathComponent("python-stdlib.zip")
        AppLogger.log("Expected stdlib path: \(stdlibPath.path)")
        AppLogger.log("Expected stdlib URL: \(stdlibPath.absoluteString)")
        
        let stdlibExists = FileManager.default.fileExists(atPath: stdlibPath.path)
        AppLogger.log("python-stdlib.zip exists: \(stdlibExists)")
        
        if stdlibExists {
            // Get file info
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: stdlibPath.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let modDate = attrs[.modificationDate] as? Date
                AppLogger.log("python-stdlib.zip size: \(size) bytes")
                AppLogger.log("python-stdlib.zip modified: \(modDate?.description ?? "unknown")")
                
                // Check if readable
                let readable = FileManager.default.isReadableFile(atPath: stdlibPath.path)
                AppLogger.log("python-stdlib.zip readable: \(readable)")
            } catch {
                AppLogger.log("Failed to get stdlib file info: \(error)")
            }
        } else {
            AppLogger.log("CRITICAL: python-stdlib.zip MISSING from app bundle!")
            precondition(false, "python-stdlib.zip missing in app bundle")
            
            // Check for alternative stdlib file names (with crash protection)
            let alternativeNames = ["stdlib.zip", "python314.zip", "lib.zip"]
            AppLogger.log("Checking for alternative stdlib file names...")
            
            for altName in alternativeNames {
                do {
                    let altPath = resURL.appendingPathComponent(altName)
                    let altExists = FileManager.default.fileExists(atPath: altPath.path)
                    AppLogger.log("Alternative \(altName): exists=\(altExists)")
                    
                    if altExists {
                        do {
                            let attrs = try FileManager.default.attributesOfItem(atPath: altPath.path)
                            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                            AppLogger.log("Alternative \(altName) size: \(size) bytes")
                        } catch {
                            AppLogger.log("Failed to get size for \(altName): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    AppLogger.log("Error checking alternative file \(altName): \(error.localizedDescription)")
                }
            }
            
            // Check Frameworks directory
            let frameworksPath = resURL.appendingPathComponent("Frameworks")
            let frameworksExists = FileManager.default.fileExists(atPath: frameworksPath.path)
            AppLogger.log("Frameworks directory exists: \(frameworksExists)")
            
            var foundPythonFramework = false
            if frameworksExists {
                do {
                    let frameworks = try FileManager.default.contentsOfDirectory(atPath: frameworksPath.path)
                    AppLogger.log("Frameworks found: \(frameworks.joined(separator: ", "))")
                    
                    for fw in frameworks {
                        if fw.lowercased().contains("python") {
                            AppLogger.log("Python framework found: \(fw)")
                            foundPythonFramework = true
                            let fwPath = frameworksPath.appendingPathComponent(fw)
                            let fwFiles = try? FileManager.default.contentsOfDirectory(atPath: fwPath.path)
                            AppLogger.log("Python framework contents: \(fwFiles?.joined(separator: ", ") ?? "error reading")")
                            
                            // Deep search for Python stdlib files inside the framework (with crash protection)
                            if let files = fwFiles {
                                AppLogger.log("=== DEEP FRAMEWORK INSPECTION ===")
                                AppLogger.log("Framework files to inspect: \(files.count)")
                                
                                for (index, file) in files.enumerated() {
                                    AppLogger.log("Inspecting file \(index + 1)/\(files.count): \(file)")
                                    
                                    do {
                                        let filePath = fwPath.appendingPathComponent(file)
                                        var isDir: ObjCBool = false
                                        let exists = FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDir)
                                        
                                        if exists {
                                            if isDir.boolValue {
                                                AppLogger.log("Framework subdirectory: \(file)")
                                                
                                                // Safely list directory contents
                                                do {
                                                    let subFiles = try FileManager.default.contentsOfDirectory(atPath: filePath.path)
                                                    AppLogger.log("Contents of \(file): \(subFiles.prefix(5).joined(separator: ", "))")
                                                    
                                                    // Look for common Python stdlib locations (limited to avoid crashes)
                                                    let commonStdlibPaths = ["lib", "python3.14"]
                                                    for stdlibPath in commonStdlibPaths {
                                                        let stdlibFullPath = filePath.appendingPathComponent(stdlibPath)
                                                        if FileManager.default.fileExists(atPath: stdlibFullPath.path) {
                                                            AppLogger.log("Found potential stdlib at: \(file)/\(stdlibPath)")
                                                        }
                                                    }
                                                } catch {
                                                    AppLogger.log("Error reading directory \(file): \(error.localizedDescription)")
                                                }
                                            } else {
                                                // Check for zip files or Python-related files
                                                let fileExt = (file as NSString).pathExtension.lowercased()
                                                if fileExt == "zip" || file.lowercased().contains("python") {
                                                    do {
                                                        let attrs = try FileManager.default.attributesOfItem(atPath: filePath.path)
                                                        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                                                        AppLogger.log("Framework file: \(file) (size: \(size) bytes)")
                                                    } catch {
                                                        AppLogger.log("Framework file: \(file) (size: unknown - \(error.localizedDescription))")
                                                    }
                                                }
                                            }
                                        } else {
                                            AppLogger.log("Framework file \(file) does not exist or is not accessible")
                                        }
                                    } catch {
                                        AppLogger.log("Error inspecting framework file \(file): \(error.localizedDescription)")
                                    }
                                }
                                
                                AppLogger.log("Framework inspection completed")
                                AppLogger.log("=== END FRAMEWORK INSPECTION ===")
                            } else {
                                AppLogger.log("No framework files to inspect")
                            }
                        }
                    }
                } catch {
                    AppLogger.log("Failed to list Frameworks: \(error)")
                }
            }
            
            AppLogger.log("=== END STDLIB SEARCH ===")
            
            if foundPythonFramework {
                AppLogger.log("Python.framework found but python-stdlib.zip missing")
                AppLogger.log("Attempting to proceed with framework-only setup...")
                // Don't throw error immediately - try to proceed with just the framework
            } else {
                AppLogger.log("No Python framework found either - complete Python runtime missing")
                throw NSError(domain: "CPythonExecutor", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Python runtime not available. Missing both python-stdlib.zip and Python.framework."
                ])
            }
        }
        
        // Initialize CPython
        AppLogger.log("=== INITIALIZING CPYTHON ===")
        AppLogger.log("Calling pybridge_initialize with path: \(resURL.path)")
        
        var buf = Array<CChar>(repeating: 0, count: 256)
        let rc: Int32 = resURL.path.withCString { path in
            AppLogger.log("Path passed to pybridge_initialize (C string): \(String(cString: path))")
            return pybridge_initialize(path, &buf, buf.count)
        }
        
        AppLogger.log("pybridge_initialize returned: \(rc)")
        
        if rc != 0 {
            let msg = String(cString: buf)
            AppLogger.log("CPythonExecutor.init FAILED")
            AppLogger.log("Return code: \(rc)")
            AppLogger.log("Error message: '\(msg)'")
            AppLogger.log("Error buffer length: \(msg.count)")
            
            throw NSError(domain: "CPythonExecutor", code: Int(rc), userInfo: [
                NSLocalizedDescriptionKey: "CPython initialization failed (code \(rc)): \(msg)"
            ])
        }
        
        AppLogger.log("CPythonExecutor initialization SUCCESS!")
        AppLogger.log("Setting didInit = true")
        Self.didInit = true
        // Install streaming output callbacks once
        if !Self.didInstallCallbacks {
            typealias PyOutCB = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
            let out: PyOutCB = swift_py_stdout_cb
            let err: PyOutCB = swift_py_stderr_cb
            pybridge_set_output_handlers(out, err, nil)
            Self.didInstallCallbacks = true
            AppLogger.log("Installed CPython stdout/stderr streaming callbacks")
        }
        AppLogger.log("=== CPythonExecutor.ensureInitialized() COMPLETE ===")
    }

    // Request stop of currently-running Python code (raises KeyboardInterrupt soon)
    func requestStop() {
        _ = pybridge_request_stop()
    }
}

// Global C-callable shims that forward stdout/stderr chunks via NotificationCenter
@_cdecl("swift_py_stdout_cb")
public func swift_py_stdout_cb(_ cstr: UnsafePointer<CChar>?, _ user: UnsafeMutableRawPointer?) {
    guard let cstr = cstr else { return }
    let s = String(cString: cstr)
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: CPythonExecutor.stdoutNotification, object: s)
    }
}

@_cdecl("swift_py_stderr_cb")
public func swift_py_stderr_cb(_ cstr: UnsafePointer<CChar>?, _ user: UnsafeMutableRawPointer?) {
    guard let cstr = cstr else { return }
    let s = String(cString: cstr)
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: CPythonExecutor.stderrNotification, object: s)
    }
}
