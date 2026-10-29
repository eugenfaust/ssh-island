import Foundation
import Combine

@MainActor public final class PreferencesStore: ObservableObject {
    private let defaults: UserDefaults
    @Published public var favorites: [String] { didSet { defaults.set(favorites, forKey: "favorites") } }
    @Published public var recents: [String] { didSet { defaults.set(recents, forKey: "recents") } }
    @Published public var overlayEnabled: Bool { didSet { defaults.set(overlayEnabled, forKey: "overlayEnabled") } }
    @Published public var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published public var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: "reduceMotion") } }
    @Published public var terminal: String { didSet { defaults.set(terminal, forKey: "terminal") } }
    @Published public var hotkeyEnabled: Bool { didSet { defaults.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published public var hotkeyKey: Int { didSet { defaults.set(hotkeyKey, forKey: "hotkeyKey") } }
    @Published public var hotkeyModifiers: Int { didSet { defaults.set(hotkeyModifiers, forKey: "hotkeyModifiers") } }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["overlayEnabled": true, "showMenuBarIcon": true, "terminal": "com.apple.Terminal", "hotkeyEnabled": true,
                                     "hotkeyKey": 49, "hotkeyModifiers": 6400]) // Control + Option + Command + Space
        favorites = defaults.stringArray(forKey: "favorites") ?? []
        recents = defaults.stringArray(forKey: "recents") ?? []
        overlayEnabled = defaults.bool(forKey: "overlayEnabled")
        showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        terminal = defaults.string(forKey: "terminal") ?? "com.apple.Terminal"
        hotkeyEnabled = defaults.bool(forKey: "hotkeyEnabled")
        hotkeyKey = defaults.integer(forKey: "hotkeyKey")
        hotkeyModifiers = defaults.integer(forKey: "hotkeyModifiers")
    }
    public func favorite(_ alias: String) {
        if favorites.contains(alias) { favorites.removeAll { $0 == alias } } else { favorites.append(alias) }
    }
    public func record(_ alias: String) { recents = Array(([alias] + recents.filter { $0 != alias }).prefix(12)) }
}
