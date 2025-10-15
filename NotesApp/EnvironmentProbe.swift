import Foundation

struct EnvironmentReport {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let present: Bool
    }

    let items: [Item]
    let notes: [String]
}

enum EnvironmentProbe {
    private static var cachedCPythonStatus: (available: Bool, detail: String)?

    static func collect() -> EnvironmentReport {
        let cpython = cpythonStatus()
        let pyodide = pyodideStatus()

        var items: [EnvironmentReport.Item] = []
        var notes: [String] = []

        items.append(EnvironmentReport.Item(
            title: "CPython Runtime",
            detail: cpython.detail,
            present: cpython.available
        ))

        items.append(EnvironmentReport.Item(
            title: "Pyodide Assets",
            detail: pyodide.detail,
            present: pyodide.present
        ))

        if !cpython.available {
            notes.append("Embedded CPython runtime not detected. The app will fall back to Pyodide.")
        }
        if !pyodide.present {
            notes.append("Pyodide assets missing from the bundle. Runtime will rely on CDN download at first launch.")
        }

        let activeDetail: String
        let activePresent = cpython.available || pyodide.present
        if cpython.available {
            activeDetail = "Using embedded CPython runtime"
        } else if pyodide.present {
            activeDetail = "Using bundled Pyodide runtime"
        } else {
            activeDetail = "Pyodide via CDN fallback"
        }

        items.append(EnvironmentReport.Item(
            title: "Active Runtime",
            detail: activeDetail,
            present: activePresent
        ))

        return EnvironmentReport(items: items, notes: notes)
    }

    static func isCPythonAvailable() -> Bool {
        return cpythonStatus().available
    }

    // MARK: - Private helpers

    private static func cpythonStatus() -> (available: Bool, detail: String) {
        if let cached = cachedCPythonStatus {
            return cached
        }

        guard let resourcePath = Bundle.main.resourcePath else {
            let status = (available: false, detail: "Bundle resources unavailable")
            cachedCPythonStatus = status
            return status
        }

        var buffer = Array<CChar>(repeating: 0, count: 256)
        let rc = resourcePath.withCString { path in
            pybridge_initialize(path, &buffer, buffer.count)
        }

        let message = buffer.withUnsafeBufferPointer { ptr -> String in
            guard let base = ptr.baseAddress, base.pointee != 0 else {
                return rc == 0 ? "Embedded CPython runtime ready" : "Unavailable (code \(rc))"
            }
            return String(cString: base)
        }

        let detail = rc == 0 ? "Embedded CPython runtime ready" : message
        let status = (available: rc == 0, detail: detail)
        cachedCPythonStatus = status
        return status
    }

    private static func pyodideStatus() -> (present: Bool, detail: String) {
        let fm = FileManager.default
        var haveIndex = false
        var haveJS = false

        if let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Pyodide") {
            haveIndex = fm.fileExists(atPath: indexURL.path)
        }
        if let jsURL = Bundle.main.url(forResource: "pyodide", withExtension: "js", subdirectory: "PyodideAssets") {
            haveJS = fm.fileExists(atPath: jsURL.path)
        }

        if haveIndex && haveJS {
            return (true, "Bundle contains Pyodide index.html and pyodide.js")
        } else if haveIndex {
            return (false, "pyodide.js missing from PyodideAssets")
        } else if haveJS {
            return (false, "Pyodide/index.html missing from bundle")
        } else {
            return (false, "Pyodide assets not found in bundle")
        }
    }
}
