import Foundation

public struct TerminalAutomationError: LocalizedError, Sendable {
    public let code: Int
    public init(code: Int) { self.code = code }
    public var errorDescription: String? {
        switch code {
        case -1743, -1744:
            return "macOS has not allowed Terminal automation. In SSH Island Settings → Terminal, click Request Terminal access. If SSH Island appears in System Settings → Privacy & Security → Automation, enable Terminal there. If no entry appears, quit and reopen the .app through Finder; launching its executable from an IDE can attribute permission to the IDE."
        case -1712:
            return "Terminal did not respond in time. Check the macOS Automation prompt and Terminal, then retry."
        default:
            return "Terminal could not start SSH (Apple Events error \(code)). Open Terminal once, then retry."
        }
    }
}
