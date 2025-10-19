import Foundation

struct ExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int?
}

protocol PythonExecutor {
    func execute(code: String) async throws -> ExecutionResult
}

// Simple Pyodide-backed executor fallback using WKWebView
// Loads Pyodide from bundled NotesApp/PyodideAssets and executes code, capturing stdout
import WebKit

final class PyodideExecutor: NSObject, PythonExecutor, WKNavigationDelegate {
    static let shared = PyodideExecutor()
    private var webView: WKWebView?
    private var isReady = false
    private var pendingContinuations: [CheckedContinuation<Void, Error>] = []

    private func ensureReady() async throws {
        AppLogger.log("PyodideExecutor: ensureReady called, isReady=\(isReady)")
        if isReady { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                if self.webView == nil {
                    let cfg = WKWebViewConfiguration()
                    cfg.limitsNavigationsToAppBoundDomains = false
                    let wv = WKWebView(frame: .zero, configuration: cfg)
                    wv.navigationDelegate = self
                    self.webView = wv
                    let base = Bundle.main.bundleURL
                    AppLogger.log("PyodideExecutor: created WKWebView with baseURL: \(base)")
                    // Prepare minimal HTML that imports pyodide
                    let html = """
                    <!doctype html>
                    <html><head><meta charset=\"utf-8\"></head>
                    <body>
                      <script src=\"PyodideAssets/pyodide.js\"></script>
                      <script>
                        window._pyReady = false;
                        async function boot() {
                          try {
                            window.pyodide = await loadPyodide({ indexURL: 'PyodideAssets' });
                            window._pyReady = true;
                          } catch (e) { console.error('pyodide boot error', e); }
                        }
                        boot();
                      </script>
                    </body></html>
                    """
                    wv.loadHTMLString(html, baseURL: base)
                }
                self.pendingContinuations.append(cont)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        AppLogger.log("PyodideExecutor: WK didFinish; waiting for _pyReady...")
        // Poll _pyReady in the page until true
        checkPyodideReady(webView: webView)
    }
    
    private func checkPyodideReady(webView: WKWebView) {
        webView.evaluateJavaScript("window._pyReady === true") { [weak self] value, error in
            guard let self else { return }
            if (value as? Bool) == true {
                self.isReady = true
                AppLogger.log("PyodideExecutor: ready=true")
                let arr = self.pendingContinuations
                self.pendingContinuations.removeAll()
                for c in arr { c.resume() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { 
                    self.checkPyodideReady(webView: webView)
                }
            }
        }
    }

    func execute(code: String) async throws -> ExecutionResult {
        AppLogger.log("PyodideExecutor: execute called with code length: \(code.count)")
        try await ensureReady()
        guard let wv = self.webView else {
            AppLogger.log("PyodideExecutor: ERROR - webview not available")
            return ExecutionResult(stdout: "", stderr: "Pyodide webview not available", exitCode: 1)
        }
        // Escape backticks and backslashes for JS template literal
        let safe = code.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        AppLogger.log("PyodideExecutor: escaped code length: \(safe.count)")
        let js = """
        (async () => {
          const py = window.pyodide;
          try {
            await py.runPythonAsync(`import sys, io; _b=io.StringIO(); _o,_e=sys.stdout,sys.stderr; sys.stdout=_b; sys.stderr=_b;`);
            await py.runPythonAsync(`
            \(safe)
            `);
            await py.runPythonAsync(`sys.stdout=_o; sys.stderr=_e; _out=_b.getvalue()`);
            const out = py.globals.get('_out');
            return out && out.toString ? out.toString() : String(out);
          } catch (e) {
            return 'ERROR: ' + (e && e.toString ? e.toString() : 'unknown');
          }
        })();
        """
        AppLogger.log("PyodideExecutor: executing JavaScript...")
        let result: String = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            wv.evaluateJavaScript(js) { value, error in
                if let error {
                    AppLogger.log("PyodideExecutor: JavaScript execution error: \(error.localizedDescription)")
                    cont.resume(throwing: error)
                } else {
                    let resultStr = (value as? String) ?? ""
                    AppLogger.log("PyodideExecutor: JavaScript execution completed, result length: \(resultStr.count)")
                    cont.resume(returning: resultStr)
                }
            }
        }
        AppLogger.log("PyodideExecutor: returning result with stdout length: \(result.count)")
        return ExecutionResult(stdout: result, stderr: "", exitCode: 0)
    }
}
