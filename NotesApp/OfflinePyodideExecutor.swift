import Foundation
import WebKit

final class OfflinePyodideExecutor: NSObject, PythonExecutor {
    private let webView: WKWebView
    private var isLoaded = false
    private var isReady = false
    private var continuations: [String: CheckedContinuation<ExecutionResult, Error>] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        userContent.add(self, name: "pyDeck")
        loadIfNeeded()
    }

    func execute(code: String) async throws -> ExecutionResult {
        try await ensureReady()
        let reqId = UUID().uuidString
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\\u{2028}", with: " ")
            .replacingOccurrences(of: "\\u{2029}", with: " ")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ExecutionResult, Error>) in
            continuations[reqId] = continuation
            let js = "window.pydeckRun(\"\(escaped)\", \"\(reqId)\")"
            webView.evaluateJavaScript(js) { _, error in
                if let error {
                    if let cont = self.continuations.removeValue(forKey: reqId) {
                        cont.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Pyodide") else {
            print("Pyodide index.html not found in bundle")
            return
        }
        let allow = htmlURL.deletingLastPathComponent().deletingLastPathComponent() // allow reading sibling PyodideAssets
        webView.navigationDelegate = self
        webView.loadFileURL(htmlURL, allowingReadAccessTo: allow)
    }

    private func ensureReady() async throws {
        if isReady { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Poll ready flag via JS in case ready already set after load
            func check() {
                webView.evaluateJavaScript("window.__pydeckReady === true") { result, _ in
                    if let ready = result as? Bool, ready {
                        self.isReady = true
                        cont.resume()
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { check() }
                    }
                }
            }
            check()
        }
    }
}

extension OfflinePyodideExecutor: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "pyDeck" else { return }
        guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
        if type == "ready" {
            isReady = true
            return
        }
        if type == "result" {
            let id = dict["id"] as? String ?? ""
            let stdout = dict["stdout"] as? String ?? ""
            let stderr = dict["stderr"] as? String ?? ""
            let code = dict["code"] as? Int
            if let cont = continuations.removeValue(forKey: id) {
                cont.resume(returning: ExecutionResult(stdout: stdout, stderr: stderr, exitCode: code))
            }
        }
        if type == "error" {
            let id = dict["id"] as? String ?? ""
            let msg = dict["message"] as? String ?? "Unknown error"
            if let cont = continuations.removeValue(forKey: id) {
                cont.resume(throwing: NSError(domain: "OfflinePyodideExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: msg]))
            }
        }
    }
}

extension OfflinePyodideExecutor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // no-op; ready is signaled by JS
    }
}

