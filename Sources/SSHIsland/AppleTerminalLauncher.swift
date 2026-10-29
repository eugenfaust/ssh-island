import AppKit
import Carbon
import SSHIslandCore

@MainActor protocol TerminalLaunching {
    func connect(alias: String) async throws
}

struct TerminalFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor final class AppleTerminalLauncher: TerminalLaunching {
    func connect(alias: String) async throws {
        try await execute(command: TerminalCommand.command(alias: alias))
    }
    // Internal entry point also permits a controlled localhost integration test, without user config.
    func execute(command: String) async throws {
        try await requestAutomationAccess()
        let status: Int = await Task.detached {
            let event = TerminalEvent.make(command: command)
            let code: Int
            do {
                let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 30)
                code = Int(reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value ?? 0)
            } catch { code = (error as NSError).code }
            return code
        }.value
        if status != 0 { throw TerminalAutomationError(code: status) }
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first?.activate()
    }
    /// Explicitly requests consent without running a shell command. Never blocks the UI actor.
    func requestAutomationAccess() async throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") != nil else {
            throw TerminalFailure(message: "Terminal.app was not found. Restore it to Applications → Utilities, then retry.")
        }
        // A normal LaunchServices open sends open/reopen and can create a blank window
        // before `do script` creates the SSH window. `launch` skips that startup action
        // and is a no-op for an already running Terminal, even with no windows.
        // This script is constant: aliases and commands only enter TerminalEvent.make.
        let launchStatus = await Task.detached {
            guard let script = NSAppleScript(source: "tell application id \"com.apple.Terminal\" to launch") else { return -2700 }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            return (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? (error == nil ? 0 : -2700)
        }.value
        guard launchStatus == 0 else {
            throw TerminalAutomationError(code: launchStatus)
        }
        NSApp.activate(ignoringOtherApps: true)
        let status = await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Terminal")
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(0x646F7363), true)
        }.value
        guard status == noErr else { throw TerminalAutomationError(code: Int(status)) }
    }

}
