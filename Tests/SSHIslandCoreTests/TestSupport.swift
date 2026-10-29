import Foundation

// Dependency-free assertions: Command Line Tools does not ship XCTest/Swift Testing.
class XCTestCase {}
nonisolated(unsafe) var failures: [String] = []
func XCTAssertTrue(_ value: Bool, _ message: String = "", file: String = #filePath, line: Int = #line) {
    if !value { failures.append("\(file):\(line): expected true. \(message)") }
}
func XCTAssertFalse(_ value: Bool, file: String = #filePath, line: Int = #line) { XCTAssertTrue(!value, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: String = #filePath, line: Int = #line) {
    if a != b { failures.append("\(file):\(line): \(a) != \(b)") }
}
func XCTAssertNil<T>(_ value: T?, file: String = #filePath, line: Int = #line) { XCTAssertTrue(value == nil, file: file, line: line) }
func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw NSError(domain: "TestUnwrap", code: 1) }; return value
}
func XCTAssertThrowsError<T>(_ operation: @autoclosure () throws -> T, file: String = #filePath, line: Int = #line) {
    do { _ = try operation(); failures.append("\(file):\(line): expected error") } catch {}
}
