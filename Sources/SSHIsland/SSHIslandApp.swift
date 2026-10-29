import SSHIslandCore
import AppKit
import SwiftUI
import Combine

@main struct SSHIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let smokeMode = CommandLine.arguments.contains("--self-test")
    private let terminalSmokeMode = CommandLine.arguments.contains("--terminal-smoke")
    private let testSuite = "org.sshisland.selftest.\(UUID().uuidString)"
    private lazy var preferences = PreferencesStore(defaults: smokeMode || terminalSmokeMode ? UserDefaults(suiteName: testSuite)! : .standard)
    private var model: IslandModel!
    private var island: IslandPanelController!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private let hotkey = GlobalHotkey()
    private var subscriptions = Set<AnyCancellable>()
    private var shortcutError: String?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let smokeLauncher = SmokeTerminalLauncher()
        model = IslandModel(preferences: preferences, launcher: smokeMode ? smokeLauncher : AppleTerminalLauncher())
        model.settings = { [weak self] in self?.showSettings() }
        model.watcher = SSHConfigWatcher()
        model.watcher?.onChange = { [weak self] in self?.model.refresh() }
        island = IslandPanelController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "SSH Island")
            button.toolTip = "SSH Island — click to open; right-click for Settings and Quit"
            button.target = self; button.action = #selector(statusClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        preferences.$showMenuBarIcon.combineLatest(model.$fallbackReason).sink { [weak self] showIcon, fallback in
            // Never hide the only Settings/Quit route when the overlay cannot be used.
            self?.statusItem.isVisible = showIcon || fallback != nil
        }.store(in: &subscriptions)
        island.isLauncherWindow = { [weak self] window in
            guard let self else { return false }
            return window === self.statusItem.button?.window || self.popover.isShown
        }
        popover.behavior = .transient; popover.delegate = self
        let launcherController = NSHostingController(rootView: IslandView(model: model, preferences: preferences, fallback: true))
        launcherController.sizingOptions = []
        popover.contentViewController = launcherController
        // Assign after installing the controller: its initial view size must not replace this viewport.
        popover.contentSize = NSSize(width: 420, height: 490)
        hotkey.onPress = { [weak self] in self?.toggleLauncher() }
        preferences.$hotkeyEnabled.combineLatest(preferences.$hotkeyKey, preferences.$hotkeyModifiers).dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.registerShortcut() }
        }.store(in: &subscriptions)
        model.$state.sink { [weak self] state in
            if state == .collapsed { self?.popover.performClose(nil) }
        }.store(in: &subscriptions)
        if terminalSmokeMode {
            preferences.hotkeyEnabled = false
            model.loading = false
            Task {
                let directory = URL(fileURLWithPath: smokeOutputPath(defaultPath: "build/terminal-smoke"))
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let output = directory.appendingPathComponent("terminal-output.txt").path
                let result: String
                do {
                    let command = "/usr/bin/ssh -F /dev/null -o BatchMode=yes -o ConnectTimeout=2 -o IdentityFile=none -o IdentityAgent=none -p 1 127.0.0.1 > " + TerminalCommand.shellQuote(output) + " 2>&1; /usr/bin/printf '\nSSH_ISLAND_EXECUTED\n' >> " + TerminalCommand.shellQuote(output)
                    try await AppleTerminalLauncher().execute(command: command)
                    try? await Task.sleep(for: .seconds(3))
                    let text = (try? String(contentsOfFile: output, encoding: .utf8)) ?? ""
                    result = text.contains("SSH_ISLAND_EXECUTED") ? "PASS Terminal executed controlled localhost SSH command.\n" : "FAIL Terminal accepted event, but command completion was not observed.\n"
                } catch { result = "FAIL " + error.localizedDescription + "\n" }
                try? result.write(to: directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        } else if smokeMode {
            preferences.hotkeyEnabled = false
            model.hosts = ["production", "staging", "bastion", "home-lab"].map { SSHHost(alias: $0) }
            model.loading = false
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await SmokeCheck.run(model: model, island: island, launcher: smokeLauncher, statusItem: statusItem,
                                     directory: URL(fileURLWithPath: ProcessInfo.processInfo.environment["SSH_ISLAND_SMOKE_DIR"] ?? "build/smoke"),
                                     reopenSettings: {
                                         _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
                                         let visible = self.settingsWindow?.isVisible == true
                                         self.settingsWindow?.orderOut(nil)
                                         return visible
                                     })
            }
        } else {
            registerShortcut(); model.refresh()
            if CommandLine.arguments.contains("--diagnose-config") {
                Task {
                    await model.refreshTask?.value
                    let summary: [String: Any] = [
                        "home": NSHomeDirectory(), "configurationError": model.configurationError ?? "", "hostCount": model.hosts.count,
                        "filteredCount": model.filtered.count, "previewCount": model.preview.count,
                        "loading": model.loading, "warnings": model.warnings
                    ]
                    if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]) {
                        try? data.write(to: URL(fileURLWithPath: smokeOutputPath(defaultPath: "build/config-diagnostics.json")))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
    private func smokeOutputPath(defaultPath: String) -> String {
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-output"), index + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[index + 1]
        }
        return ProcessInfo.processInfo.environment["SSH_ISLAND_SMOKE_DIR"] ?? defaultPath
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Finder/open remains a recovery route when the user hides the status item.
        showSettings()
        return false
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.watcher?.stop()
        if smokeMode || terminalSmokeMode { UserDefaults.standard.removePersistentDomain(forName: testSuite) }
    }
    private func registerShortcut() {
        shortcutError = hotkey.register(enabled: preferences.hotkeyEnabled, key: preferences.hotkeyKey, modifiers: preferences.hotkeyModifiers)
        statusItem.button?.toolTip = shortcutError ?? "SSH Island — click to open; right-click for Settings and Quit"
    }
    @objc private func statusClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open SSH Island", action: #selector(openLauncher), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
            menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit SSH Island", action: #selector(quit), keyEquivalent: "q")
            for item in menu.items { item.target = self }
            statusItem.menu = menu; sender.performClick(nil); statusItem.menu = nil
        } else { toggleLauncher() }
    }
    @objc private func refresh() { model.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func openLauncher() {
        if model.fallbackReason == nil { island.expand() }
        else if let button = statusItem.button {
            model.state = .expanded
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func toggleLauncher() {
        if model.state == .expanded { model.dismiss() } else { openLauncher() }
    }
    func popoverDidClose(_ notification: Notification) { model.dismiss() }
    @objc private func showSettings() {
        model.dismiss()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 720), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "SSH Island Settings"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, shortcutStatus: { [weak self] in self?.shortcutError }))
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true); settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
