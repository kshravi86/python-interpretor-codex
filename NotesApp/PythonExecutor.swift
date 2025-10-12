import Foundation

struct ExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int?
}

protocol PythonExecutor {
    func execute(code: String) async throws -> ExecutionResult
}

/// Remote executor that calls a Piston-compatible API to run Python code.
/// Default endpoint targets the public Piston API schema. You may replace the
/// endpoint with your own service if needed.
final class RemotePythonExecutor: PythonExecutor {
    /// Replace with your own backend if desired.
    var endpoint: URL = URL(string: "https://emkc.org/api/v2/piston/execute")!

    /// Piston requires a language and version. Version may be omitted by some deployments.
    var language: String = "python"
    var version: String? = nil // e.g., "3.10.0"

    func execute(code: String) async throws -> ExecutionResult {
        var payload: [String: Any] = [
            "language": language,
            "files": [["name": "main.py", "content": code]]
        ]
        if let version { payload["version"] = version }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "RemotePythonExecutor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        // Piston 2.x response shape: { run: { stdout, stderr, code }, compile?: {...} }
        // Some deployments return top-level stdout/stderr; handle both.
        let json = try JSONSerialization.jsonObject(with: respData, options: [])
        if let dict = json as? [String: Any], let run = dict["run"] as? [String: Any] {
            let stdout = (run["stdout"] as? String) ?? ""
            let stderr = (run["stderr"] as? String) ?? ""
            let code = run["code"] as? Int
            return ExecutionResult(stdout: stdout, stderr: stderr, exitCode: code)
        } else if let dict = json as? [String: Any] {
            let stdout = (dict["stdout"] as? String) ?? ""
            let stderr = (dict["stderr"] as? String) ?? ""
            let code = dict["code"] as? Int
            return ExecutionResult(stdout: stdout, stderr: stderr, exitCode: code)
        } else {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw NSError(domain: "RemotePythonExecutor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected response: \(body)"])
        }
    }
}

