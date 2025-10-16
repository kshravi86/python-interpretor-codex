import XCTest
@testable import NotesApp

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
}

