import Foundation

// Tiny assertion runner so the same checks work with Command Line Tools alone.
enum CheckState {
    static let lock = NSLock()
    static var failures: [String] = []
    static func fail(_ message: String, file: StaticString, line: UInt) {
        lock.lock()
        defer { lock.unlock() }
        failures.append("\(file):\(line): \(message)")
    }
}

func XCTFail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    CheckState.fail(message, file: file, line: line)
}
func XCTAssertEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    if actual != expected { XCTFail("Expected \(expected), got \(actual)", file: file, line: line) }
}
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    if value { XCTFail("Expected false", file: file, line: line) }
}
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    if value != nil { XCTFail("Expected nil", file: file, line: line) }
}
struct MissingValue: Error {}
func XCTUnwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else {
        XCTFail("Expected a value", file: file, line: line)
        throw MissingValue()
    }
    return value
}

@main
enum ChecksMain {
    static func main() async {
        let suite = LingClientTests()
        let tests: [(String, () async throws -> Void)] = [
            ("image + text wire format", suite.testImageAndQuestionWireFormatAndAnswer),
            ("text-only and custom model", suite.testTextOnlyUsesConfiguredModelWithoutImage),
            ("image-only", suite.testImageOnlyAddsDescribePrompt),
            ("empty input rejection", suite.testRejectsEmptyInputBeforeNetworking),
            ("base URL normalization", suite.testBaseURLNormalization),
            ("invalid settings rejection", suite.testRejectsInsecureAndInvalidConfigurationBeforeNetworking),
            ("401 and secret redaction", suite.testHTTP401PreservesStatusAndRedactsReflectedKey),
            ("404 model error", suite.testHTTP404IncludesPlainResponseBody),
            ("malformed and empty responses", suite.testMalformedAndEmptyResponsesFailClearly),
            ("text array response", suite.testTextContentArrayIsSupported),
            ("timeout", suite.testTimeoutIsReportedDistinctly),
            ("connection test endpoint", suite.testConnectionUsesRealCompletionPath)
        ]
        for (name, test) in tests {
            let before = CheckState.failures.count
            suite.setUp()
            do { try await test() }
            catch { XCTFail("\(name): \(error)") }
            suite.tearDown()
            print("\(CheckState.failures.count == before ? "PASS" : "FAIL") \(name)")
        }
        if !CheckState.failures.isEmpty {
            CheckState.failures.forEach { print($0) }
            exit(1)
        }
        print("All \(tests.count) checks passed. These use a local HTTP mock, not a live model.")
    }
}
