import Foundation

struct ErrorLogEntry: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case error, exception, signal, message }
    let id: UUID
    let date: Date
    let kind: Kind
    let title: String
    let details: String?
}

final class ErrorLogger {
    static let shared = ErrorLogger()
    private let defaults = UserDefaults.standard
    private let key = "error_logs_v1"
    private let maxEntries = 200

    private init() {}

    func logs() -> [ErrorLogEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ErrorLogEntry].self, from: data)) ?? []
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    func append(_ entry: ErrorLogEntry) {
        var arr = logs()
        arr.append(entry)
        if arr.count > maxEntries { arr.removeFirst(arr.count - maxEntries) }
        if let data = try? JSONEncoder().encode(arr) { defaults.set(data, forKey: key) }
    }

    func log(error: Error, context: String? = nil) {
        let entry = ErrorLogEntry(id: UUID(), date: Date(), kind: .error, title: String(describing: error), details: context)
        append(entry)
    }

    func log(message: String) {
        let entry = ErrorLogEntry(id: UUID(), date: Date(), kind: .message, title: message, details: nil)
        append(entry)
    }

    func log(exception: NSException) {
        let title = "NSException: \(exception.name.rawValue) — \(exception.reason ?? "")"
        let details = exception.callStackSymbols.joined(separator: "\n")
        let entry = ErrorLogEntry(id: UUID(), date: Date(), kind: .exception, title: title, details: details)
        append(entry)
    }

    func log(signal: Int32) {
        let entry = ErrorLogEntry(id: UUID(), date: Date(), kind: .signal, title: "Signal: \(signal)", details: Thread.callStackSymbols.joined(separator: "\n"))
        append(entry)
    }
}

