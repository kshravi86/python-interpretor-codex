import Foundation

enum AppLogger {
    private static let queue = DispatchQueue(label: "codesnake.logger")

    private static func logURL() -> URL? {
        do {
            let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("log.txt")
            return url
        } catch {
            return nil
        }
    }

    static func log(_ message: String) {
        let line = "[\(timestamp())] \(message)\n"
        queue.async {
            guard let url = logURL() else { return }
            if FileManager.default.fileExists(atPath: url.path) == false {
                try? line.data(using: .utf8)?.write(to: url, options: .atomic)
                return
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do { try handle.seekToEnd() } catch {}
                if let data = line.data(using: .utf8) { try? handle.write(contentsOf: data) }
            }
        }
    }

    static func log(error: Error) {
        log("ERROR: \(error.localizedDescription)")
    }

    private static func timestamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df.string(from: Date())
    }
}

