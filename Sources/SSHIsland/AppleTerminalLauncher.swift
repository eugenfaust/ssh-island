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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw TerminalFailure(message: "Terminal.app was not found. Restore it to Applications → Utilities, then retry.")
        }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw TerminalFailure(message: "Terminal could not open. Open Terminal once from Applications → Utilities, then retry.")
        }
        NSApp.activate(ignoringOtherApps: true)
        let status = await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Terminal")
            return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(kAECoreSuite), AEEventID(0x646F7363), true)
        }.value
        guard status == noErr else { throw TerminalAutomationError(code: Int(status)) }
    }

}
