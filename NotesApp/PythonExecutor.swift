import Foundation

struct ExecutionResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int?
}

protocol PythonExecutor {
    func execute(code: String) async throws -> ExecutionResult
}
