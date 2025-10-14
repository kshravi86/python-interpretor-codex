import Foundation

enum CrashLogger {
    private static func crashLogURL() -> URL? {
        do {
            let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("crash_log.txt")
            return url
        } catch {
            return nil
        }
    }
    
    static func log(_ message: String) {
        let timestamp = DateFormatter().string(from: Date())
        let line = "[\(timestamp)] CRASH_LOG: \(message)\n"
        
        guard let url = crashLogURL() else { return }
        
        if FileManager.default.fileExists(atPath: url.path) {
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            }
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
        
        // Also try to print to console
        print("CRASH_LOG: \(message)")
    }
}