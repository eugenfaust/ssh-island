import AppKit
import Carbon

@MainActor final class GlobalHotkey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard identifier.signature == 0x53534849 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotkey>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(enabled: Bool, key: Int, modifiers: Int) -> String? {
        if let reference { UnregisterEventHotKey(reference); self.reference = nil }
        guard enabled else { return nil }
        let status = RegisterEventHotKey(UInt32(clamping: key), UInt32(clamping: modifiers),
                                         EventHotKeyID(signature: 0x53534849, id: 1), GetApplicationEventTarget(), 0, &reference)
        return status == noErr ? nil : "Shortcut unavailable (error \(status)). Choose another shortcut or use the menu bar."
    }
}
