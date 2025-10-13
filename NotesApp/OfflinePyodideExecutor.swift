import Foundation
import WebKit

final class OfflinePyodideExecutor: NSObject, PythonExecutor {
    private let webView: WKWebView
    private var isLoaded = false
    private var isReady = false
    private var lastError: String? = nil
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
        // Allow generous time for Pyodide to initialize on simulator/devices
        try await ensureReady(timeout: 60.0)
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
        // Load a small inline host page and set baseURL to the bundle root so relative
        // paths like "PyodideAssets/pyodide.js" resolve correctly regardless of where
        // resources ended up in the app bundle.
        let html = """
        <!doctype html>
        <html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"></head>
        <body>
        <script>
        (async function() {
          const candidates = [new URL('PyodideAssets/', location.href), new URL('../PyodideAssets/', location.href)];
          async function tryLoad(base) {
            return new Promise((resolve, reject) => {
              const s = document.createElement('script');
              s.src = new URL('pyodide.js', base).toString();
              s.onload = async () => { try { window.pyodide = await loadPyodide({indexURL: base.toString()}); resolve(); } catch(e){ reject(e); } };
              s.onerror = () => reject(new Error('Failed to load ' + s.src));
              document.body.appendChild(s);
            });
          }
          let ok = false, lastErr = null;
          for (const b of candidates) { try { await tryLoad(b); ok = true; break; } catch(e){ lastErr = e; } }
          if (ok) {
            window.__pydeckReady = true;
            window.webkit?.messageHandlers?.pyDeck?.postMessage({type:'ready'});
          } else {
            window.__pydeckError = String(lastErr);
            window.webkit?.messageHandlers?.pyDeck?.postMessage({type:'error', message:String(lastErr)});
          }
          window.pydeckRun = async function(code, id) {
            if (!window.pyodide) {
              window.webkit?.messageHandlers?.pyDeck?.postMessage({ type: 'error', id, message: 'Pyodide not initialized' });
              return;
            }
            let stdout = '', stderr = '';
            const undoOut = window.pyodide.setStdout({ batched: s => { stdout += s; } });
            const undoErr = window.pyodide.setStderr({ batched: s => { stderr += s; } });
            let codeNum = 0;
            try { await window.pyodide.runPythonAsync(code); } catch(e){ stderr += String(e) + '\n'; codeNum = 1; }
            try { undoOut(); } catch(_){ }
            try { undoErr(); } catch(_){ }
            window.webkit?.messageHandlers?.pyDeck?.postMessage({ type: 'result', id, stdout, stderr, code: codeNum });
          }
        })();
        </script>
        </body></html>
        """
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
    }

    private func ensureReady(timeout: TimeInterval = 12.0) async throws {
        if isReady { return }
        let start = Date()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            func fail(_ message: String) {
                cont.resume(throwing: NSError(domain: "OfflinePyodideExecutor", code: -2, userInfo: [NSLocalizedDescriptionKey: message]))
            }
            func tick() {
                if let err = self.lastError {
                    fail("Pyodide load failed: \(err)")
                    return
                }
                if self.isReady {
                    cont.resume()
                    return
                }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > timeout {
                    fail("Timed out waiting for Python runtime. Ensure Pyodide assets are bundled in NotesApp/PyodideAssets/")
                    return
                }
                self.webView.evaluateJavaScript("(window.__pydeckReady===true)?'ready':(window.__pydeckError||'')") { result, _ in
                    if let s = result as? String, s == "ready" {
                        self.isReady = true
                        cont.resume()
                    } else if let s = result as? String, !s.isEmpty {
                        self.lastError = s
                        fail("Pyodide error: \(s)")
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tick() }
                    }
                }
            }
            tick()
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
            self.lastError = msg
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
