import Foundation
import SSHIslandCore

@MainActor func testPreferencesPersistence() throws {
    let suite = "org.sshisland.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = PreferencesStore(defaults: defaults)
    XCTAssertTrue(first.showMenuBarIcon)
    first.showMenuBarIcon = false
    first.favorite("prod"); first.favorite("staging"); first.favorite("prod")
    for number in 0..<16 { first.record("host\(number)") }
    first.record("host10")
    first.hotkeyKey = 1; first.overlayEnabled = false
    let second = PreferencesStore(defaults: defaults)
    XCTAssertEqual(second.favorites, ["staging"])
    XCTAssertEqual(second.recents.count, 12)
    XCTAssertEqual(second.recents.first, "host10")
    XCTAssertEqual(Set(second.recents).count, second.recents.count)
    XCTAssertEqual(second.hotkeyKey, 1)
    XCTAssertFalse(second.overlayEnabled)
    XCTAssertFalse(second.showMenuBarIcon)
    XCTAssertEqual(second.terminal, "com.apple.Terminal")
}

@MainActor func testWatcherReplacementAndNewGlob() async throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let ssh = home.appendingPathComponent(".ssh")
    try FileManager.default.createDirectory(at: ssh.appendingPathComponent("parts"), withIntermediateDirectories: true)
    let config = ssh.appendingPathComponent("config")
    try "Host before\nInclude parts/*.conf".write(to: config, atomically: true, encoding: .utf8)
    let parser = SSHConfigParser(home: home.path)
    let watcher = SSHConfigWatcher()
    defer { watcher.stop() }
    var events = 0
    watcher.onChange = { events += 1; watcher.update(discovery: parser.discover()) }
    watcher.update(discovery: parser.discover())
    try "Host after\nInclude parts/*.conf".write(to: config, atomically: true, encoding: .utf8)
    try await Task.sleep(for: .seconds(2.2))
    XCTAssertEqual(events, 1)
    XCTAssertEqual(parser.discover().hosts.map(\.alias), ["after"])
    try "Host added".write(to: ssh.appendingPathComponent("parts/new.conf"), atomically: true, encoding: .utf8)
    try await Task.sleep(for: .seconds(2.2))
    XCTAssertEqual(events, 2)
    XCTAssertEqual(parser.discover().hosts.map(\.alias), ["after", "added"])
    try FileManager.default.removeItem(at: config)
    try await Task.sleep(for: .seconds(2.2))
    XCTAssertEqual(events, 3)
    XCTAssertTrue(parser.discover().hosts.isEmpty)
}
