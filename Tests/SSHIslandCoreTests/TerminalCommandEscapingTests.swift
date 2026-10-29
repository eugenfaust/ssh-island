import Foundation
import CoreGraphics
import Carbon
import SSHIslandCore

final class TerminalCommandEscapingTests: XCTestCase {
    func testShellArgumentRoundTripWithoutExecutingAliases() throws {
        let aliases = ["production", "two words", "a'b", "double\"quote", "back\\slash", "日本語", "; touch /tmp/pwned", "$(touch /tmp/pwned)", "`id`", "a\"; do shell script \"id", "user@host", "a|b&c>d<e", "#hash"]
        for alias in aliases {
            // Execute printf only, with the exact command-argument quoting used by the launcher.
            let process = Process(); let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "printf '%s' " + TerminalCommand.shellQuote(alias)]
            process.standardOutput = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), alias)
            XCTAssertEqual(try TerminalCommand.command(alias: alias), "/usr/bin/ssh " + TerminalCommand.shellQuote(alias))
            let command = try TerminalCommand.command(alias: alias)
            let event = TerminalEvent.make(command: command)
            XCTAssertEqual(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, command)
            XCTAssertEqual(event.eventClass, AEEventClass(kAECoreSuite))
            XCTAssertEqual(event.eventID, AEEventID(0x646F7363))
            XCTAssertNil(event.paramDescriptor(forKeyword: 0x6b66696c)) // No existing tab/window target

        }
    }
    func testUnsafeAliasesRejected() {
        for alias in ["", "-oProxyCommand=id", "-V", "line\nbreak", "nul\0byte", "a\rb", "\u{7f}"] {
            XCTAssertThrowsError(try TerminalCommand.command(alias: alias))
        }
    }
    func testAppleEventParameter() {
        let text = "back\\slash and \"quotes\" 日本語"
        XCTAssertEqual(TerminalEvent.make(command: text).paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, text)
    }
    func testPermissionFailureDoesNotAssumeSettingsEntryExists() {
        for code in [-1743, -1744] {
            let message = TerminalAutomationError(code: code).localizedDescription
            XCTAssertTrue(message.contains("Request Terminal access"))
            XCTAssertTrue(message.contains("If no entry appears"))
        }
        XCTAssertTrue(TerminalAutomationError(code: -1712).localizedDescription.contains("time"))
        XCTAssertTrue(TerminalAutomationError(code: -600).localizedDescription.contains("-600"))
    }

}
