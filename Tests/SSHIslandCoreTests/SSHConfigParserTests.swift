import Foundation
import CoreGraphics
import Darwin
import SSHIslandCore

final class SSHConfigParserTests: XCTestCase {
    private func parse(_ text: String) -> Discovery {
        SSHConfigParser(home: "/test", read: { _ in text }).discover()
    }
    func testAliasesOrderCommentsWildcardsAndDuplicates() {
        let result = parse("""
        # Nothing to execute
        hOsT production prod # comments
          HostName ignored.example
        Host *.internal * !excluded foo?bar
        Host prod staging
        Host=equal
        Host "with spaces" "double\\\"quote" 'apostrophe' "back\\\\slash" 日本語
        Match exec "touch /tmp/never-run"
        Host after-match
        """)
        XCTAssertEqual(result.hosts.map(\.alias), ["production", "prod", "staging", "equal", "with spaces", "double\"quote", "apostrophe", "back\\slash", "日本語", "after-match"])
    }
    func testMissingAndUnreadable() {
        let parser = SSHConfigParser(home: "/nonexistent", read: { _ in throw CocoaError(.fileReadNoPermission) })
        XCTAssertTrue(parser.discover().hosts.isEmpty)
        XCTAssertTrue(parser.discover().rootError != nil)
        let missing = SSHConfigParser(home: "/nonexistent", read: { _ in throw CocoaError(.fileReadNoSuchFile) }).discover()
        XCTAssertNil(missing.rootError)
        XCTAssertTrue(missing.warnings.isEmpty)
        let result = SSHConfigParser(home: "/test", read: { path in
            if path == "/test/.ssh/config" { return "Include /etc/hosts" }
            throw CocoaError(.fileReadNoPermission)
        }).discover()
        XCTAssertFalse(result.warnings.isEmpty)
    }
    func testNestedIncludesGlobsCyclesAndRelativeBase() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: ssh.appendingPathComponent("parts"), withIntermediateDirectories: true)
        func write(_ path: String, _ text: String) throws { try text.write(to: ssh.appendingPathComponent(path), atomically: true, encoding: .utf8) }
        try write("config", "Host first\nInclude parts/*.conf \"space file\"\nHost last")
        try write("parts/b.conf", "Host b duplicate\nInclude nested")
        try write("parts/a.conf", "Host a duplicate\nInclude ../.ssh/config")
        try write("nested", "Host nested\nInclude parts/a.conf")
        try write("space file", "Host spaced")
        let result = SSHConfigParser(home: home.path).discover()
        XCTAssertEqual(result.hosts.map(\.alias), ["first", "a", "duplicate", "b", "nested", "spaced", "last"])
        XCTAssertTrue(result.warnings.contains { $0.contains("cycle") })
        XCTAssertTrue(result.files.contains(ssh.appendingPathComponent("nested").path))
        XCTAssertTrue(result.watchDirectories.contains(ssh.appendingPathComponent("parts").path))
    }
    func testTildeIncludesAndMalformedQuotes() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".ssh"), withIntermediateDirectories: true)
        try "Host included".write(to: home.appendingPathComponent("extra"), atomically: true, encoding: .utf8)
        let result = SSHConfigParser(home: home.path, read: { path in
            if path.hasSuffix("/config") { return "Include ~/extra\nHost \"unclosed\nHost good" }
            return try String(contentsOfFile: path, encoding: .utf8)
        }).discover()
        XCTAssertEqual(result.hosts.map(\.alias), ["included", "good"])
        XCTAssertEqual(result.warnings.count, 1)
    }
    func testConnectionSpecificIncludesAreDiagnosed() {
        let result = parse("Include ${HOME}/config %h\nHost safe")
        XCTAssertEqual(result.hosts.map(\.alias), ["safe"])
        XCTAssertEqual(result.warnings.count, 2)
    }
    func testRecursionLimit() {
        let result = SSHConfigParser(home: "/test", read: { path in
            let n = Int(URL(fileURLWithPath: path).lastPathComponent) ?? 0
            return "Host h\(n)\nInclude /test/\(n + 1)"
        }, globPaths: { [$0] }).discover(path: "/test/0")
        XCTAssertEqual(result.hosts.count, 32)
        XCTAssertTrue(result.warnings.contains { $0.contains("limit") })
    }
    func testParsingNeverExecutesAndRejectsSpecialFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let marker = home.appendingPathComponent("SHOULD_NOT_EXIST").path
        let config = home.appendingPathComponent("config")
        try "Match exec \"touch \(marker)\"\nInclude \"$(touch \(marker))\" /dev/null\nHost safe".write(to: config, atomically: true, encoding: .utf8)
        let result = SSHConfigParser(home: home.path).discover(path: config.path)
        XCTAssertEqual(result.hosts.map(\.alias), ["safe"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker))
        XCTAssertTrue(result.warnings.contains { $0.contains("Cannot read") })
    }

    func testDescriptorReaderRegularSymlinkAndSpecialFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = directory.appendingPathComponent("config")
        let link = directory.appendingPathComponent("linked-config")
        try "Host regular\n".write(to: config, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
        XCTAssertEqual(try SSHConfigParser.readConfiguration(config.path), "Host regular\n")
        XCTAssertEqual(SSHConfigParser().discover(path: link.path).hosts.map(\.alias), ["regular"])
        let fifo = directory.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try SSHConfigParser.readConfiguration(fifo.path))
        XCTAssertThrowsError(try SSHConfigParser.readConfiguration(directory.path))
        try Data(repeating: 65, count: 2_097_153).write(to: config)
        XCTAssertThrowsError(try SSHConfigParser.readConfiguration(config.path))
        try Data([0xff]).write(to: config)
        XCTAssertThrowsError(try SSHConfigParser.readConfiguration(config.path))
    }

}
