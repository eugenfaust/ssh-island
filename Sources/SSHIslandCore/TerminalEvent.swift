import Foundation
import Carbon

public enum TerminalEvent {
    /// Terminal.sdef: do script = coredosc, direct parameter text; omit `in` for a new session.
    public static func make(command: String) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: 0x646F7363,
                                          targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.Terminal"),
                                          returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: command), forKeyword: AEKeyword(keyDirectObject))
        return event
    }
}
