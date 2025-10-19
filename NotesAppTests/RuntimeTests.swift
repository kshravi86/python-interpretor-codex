import XCTest
@testable import CodeSnake

final class RuntimeTests: XCTestCase {
    func testStdlibZipExistsInAppBundle() {
        let bundle = Bundle.main
        guard let resURL = bundle.resourceURL else {
            XCTFail("Bundle.main.resourceURL is nil; bundlePath=\(bundle.bundlePath)")
            return
        }
        let stdlibURL = resURL.appendingPathComponent("python-stdlib.zip")
        let exists = FileManager.default.fileExists(atPath: stdlibURL.path)
        XCTAssertTrue(exists, "python-stdlib.zip not found at \(stdlibURL.path)")
    }

    func testCPythonExecutesSimpleCode() async throws {
        // Verifies that the embedded interpreter initializes and runs code.
        let exec = CPythonExecutor()
        let result = try await exec.execute(code: "print('PYTEST', 2+2)")
        XCTAssertEqual(result.exitCode, 0, "CPython execution failed: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("PYTEST 4"), "Unexpected output: \(result.stdout)")
    }
}

