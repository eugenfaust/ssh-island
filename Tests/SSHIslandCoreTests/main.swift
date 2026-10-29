import Foundation
@MainActor func runTests() async {
let parser = SSHConfigParserTests()
let terminal = TerminalCommandEscapingTests()
let geometry = NotchGeometryTests()
let tests: [(String, () throws -> Void)] = [
    ("aliases, comments, wildcards, ordering", parser.testAliasesOrderCommentsWildcardsAndDuplicates),
    ("missing and unreadable config", parser.testMissingAndUnreadable),
    ("descriptor reader: regular files, symlinks, FIFO, size and encoding", parser.testDescriptorReaderRegularSymlinkAndSpecialFiles),
    ("nested Includes, globs, cycles, relative base", parser.testNestedIncludesGlobsCyclesAndRelativeBase),
    ("tilde and malformed quotes", parser.testTildeIncludesAndMalformedQuotes),
    ("unsupported Include diagnostics", parser.testConnectionSpecificIncludesAreDiagnosed),
    ("Include recursion limit", parser.testRecursionLimit),
    ("no configuration execution or special-file reads", parser.testParsingNeverExecutesAndRejectsSpecialFiles),
    ("shell arguments and structured Apple Events", terminal.testShellArgumentRoundTripWithoutExecutingAliases),
    ("unsafe alias rejection", terminal.testUnsafeAliasesRejected),
    ("Apple Event parameter round-trip", terminal.testAppleEventParameter),
    ("permission recovery with a missing Automation entry", terminal.testPermissionFailureDoesNotAssumeSettingsEntryExists),
    ("notch global coordinates and display fallback", geometry.testNotchedBuiltInWithExternalScreenOffset),
    ("unreliable geometry rejection", geometry.testRejectsUnreliableGap)
]
for (name, test) in tests {
    let before = failures.count
    do { try test() } catch { failures.append("\(name): \(error)") }
    print("\(before == failures.count ? "PASS" : "FAIL") \(name)")
}
do {
    try testPreferencesPersistence()
    print("PASS isolated preference persistence")
    let before = failures.count
    try await testWatcherReplacementAndNewGlob()
    print("\(before == failures.count ? "PASS" : "FAIL") replacement-safe watcher, glob creation and deletion")
} catch { failures.append("Persistence/watcher: \(error)") }
for failure in failures { fputs(failure + "\n", stderr) }
print("\(tests.count + 2) tests, \(failures.count) failures")
exit(failures.isEmpty ? 0 : 1)

}
await runTests()
