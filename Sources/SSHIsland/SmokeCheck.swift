import AppKit
import SwiftUI
import SSHIslandCore

@MainActor final class SmokeTerminalLauncher: TerminalLaunching {
    var received: [String] = []
    var failure: String?
    func connect(alias: String) async throws {
        if let failure { throw TerminalFailure(message: failure) }
        received.append(alias)
    }
}

private actor ConfigReadFixture {
    private(set) var attempts = 0
    let persistentFailure: Bool
    init(persistentFailure: Bool = false) { self.persistentFailure = persistentFailure }
    func read() -> Discovery {
        attempts += 1
        var result = Discovery()
        if persistentFailure || attempts == 1 {
            result.rootError = "Cannot read configuration: config. Temporary test failure."
            result.warnings = [result.rootError!]
        } else {
            result.hosts = (1...15).map { SSHHost(alias: "test-host-\($0)") }
        }
        return result
    }
}

/// Opt-in integration check. Uses synthetic hosts and an injected terminal; never reads SSH config or connects.
@MainActor enum SmokeCheck {
    static func run(model: IslandModel, island: IslandPanelController, launcher: SmokeTerminalLauncher, statusItem: NSStatusItem, directory: URL, reopenSettings: () -> Bool) async {
        var checks: [String] = []
        func check(_ condition: Bool, _ name: String) { checks.append("\(condition ? "PASS" : "FAIL") \(name)") }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            check(NSApp.activationPolicy() == .accessory, "Accessory app lifecycle")
            checks.append("INFO screens: \(NSScreen.screens.count); notch detected: \(model.fallbackReason == nil)")
            if let hosting = island.panel.contentView as? TrackingHostingView {
                if let screen = island.panel.screen {
                    check(abs(island.panel.frame.maxY - screen.frame.maxY) < 1,
                          "Collapsed outline includes the camera neck, not only the bottom strip")
                    let bitmap = try capture(hosting, to: directory.appendingPathComponent("collapsed.png"))
                    let scale = CGFloat(bitmap.pixelsHigh) / hosting.bounds.height
                    let depth = screen.safeAreaInsets.top
                    // Sample the left/right corner arcs above the seam; the old 8-point
                    // surface could not draw these pixels at all. Bitmap rows start at top.
                    let x = Int(scale)
                    let upper = Int((depth - 18) * scale)
                    let curved = Int((depth - 2) * scale)
                    if upper >= 0 && curved < bitmap.pixelsHigh {
                        let upperLeft = bitmap.colorAt(x: x, y: upper)?.alphaComponent ?? 0
                        let lowerLeft = bitmap.colorAt(x: x, y: curved)?.alphaComponent ?? 1
                        let upperRight = bitmap.colorAt(x: bitmap.pixelsWide - x - 1, y: upper)?.alphaComponent ?? 0
                        let lowerRight = bitmap.colorAt(x: bitmap.pixelsWide - x - 1, y: curved)?.alphaComponent ?? 1
                        check(upperLeft > 0.9 && lowerLeft < 0.1 && upperRight > 0.9 && lowerRight < 0.1,
                              "Rasterized collapsed corners curve on both sides above the notch seam")
                    }
                }
                let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: island.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
                (island.notchTrigger.contentView as? NotchTriggerView)?.mouseEntered(with: event)
                check(model.state == .preview, "Camera-gap tracking view hover reveals preview")
                try await Task.sleep(for: .milliseconds(250))
                let previewBitmap = try capture(hosting, to: directory.appendingPathComponent("preview.png"))
                check(topCornersAreBlack(previewBitmap), "Preview fills the menu-bar area across its full width")
                island.expand()
                try await Task.sleep(for: .milliseconds(300))
                check(island.panel.isVisible && island.panel.isKeyWindow, "Expanded panel is visible and accepts keyboard focus")
                check(abs(island.panel.frame.maxY - island.panel.screen!.frame.maxY) < 1,
                      "Expanded silhouette reaches display top across the menu bar")
                if let screen = island.panel.screen {
                    check(abs(island.notchTrigger.frame.maxY - screen.frame.maxY) < 1,
                          "Camera trigger reaches display top without AppKit menu-bar clamping")
                    check(island.panel.frame.contains(island.notchTrigger.frame),
                          "Camera trigger is contained within the expanded silhouette")
                }
                for window in [island.panel, island.notchTrigger] {
                    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
                    let layer = (info?.first?[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
                    check(layer > NSWindow.Level.statusBar.rawValue && layer < NSWindow.Level.popUpMenu.rawValue,
                          "WindowServer places overlay window above status bar and below pop-up menus")
                }
                let expandedBitmap = try capture(hosting, to: directory.appendingPathComponent("expanded.png"))
                check(topCornersAreBlack(expandedBitmap), "Expanded panel paints both shoulders black above the menu-bar seam")
                check(try await searchRestoresList(model: model, view: hosting, window: island.panel,
                                                   directory: directory, name: "island"),
                      "Search with no results then clearing restores the island list height")
                for (code, characters) in [(UInt16(125), "\u{f701}"), (125, "\u{f701}"), (36, "\r")] {
                    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                 windowNumber: island.panel.windowNumber, context: nil,
                                                 characters: characters, charactersIgnoringModifiers: characters,
                                                 isARepeat: false, keyCode: code)!
                    island.panel.sendEvent(event)
                }
                try await Task.sleep(for: .milliseconds(100))
                check(launcher.received == ["staging"], "Keyboard down/down/Return selects staging through focused search")
                island.expand()
                try await Task.sleep(for: .milliseconds(50))
                let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                              windowNumber: island.panel.windowNumber, context: nil, characters: "\u{1b}",
                                              charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
                island.panel.sendEvent(escape)
                check(model.state == .collapsed, "Escape dismisses expanded panel")
                launcher.received = []
                model.preferences.recents = []

            } else {
                checks.append("SKIP physical notch hover checks: no reliable notch geometry")
            }
            model.query = "staging"
            check(model.filtered.map(\.alias) == ["staging"], "Search filters aliases")
            model.preferences.favorite("staging")
            check(model.preview.first?.alias == "staging", "Favorites lead preview")
            model.connect("staging")
            try await Task.sleep(for: .milliseconds(100))
            check(launcher.received == ["staging"], "Selection passes original alias to injected terminal")
            check(model.preferences.recents.first == "staging", "Successful launch records recent alias")
            check(model.state == .collapsed, "Successful launch dismisses island")
            launcher.failure = "Automation permission was denied. Enable Terminal in Privacy & Security → Automation."
            model.connect("production")
            try await Task.sleep(for: .milliseconds(100))
            check(model.error != nil && model.state == .expanded, "Terminal failure keeps actionable feedback visible")
            check(model.preferences.recents == ["staging"], "Failed launch does not add a recent alias")
            model.error = nil
            model.preferences.showMenuBarIcon = false
            check(statusItem.isVisible == (model.fallbackReason != nil) && (island.panel.isVisible || statusItem.isVisible),
                  "Menu-bar icon hides while Settings and Quit remain reachable")
            check(reopenSettings(), "Reopening the app exposes Settings while the status icon is hidden")
            model.preferences.overlayEnabled = false
            island.updateScreen()
            check(!island.panel.isVisible && !island.notchTrigger.isVisible && model.fallbackReason != nil, "Overlay disable provides menu-bar fallback")
            check(statusItem.isVisible, "Fallback restores the menu-bar icon even when its preference is hidden")
            model.preferences.overlayEnabled = true
            island.updateScreen()
            check(statusItem.isVisible == (model.fallbackReason != nil) && !model.preferences.showMenuBarIcon,
                  "Restoring the overlay reapplies the saved hidden-icon preference")
            model.preferences.showMenuBarIcon = true
            check(statusItem.isVisible, "Showing the menu-bar icon again applies immediately")
            model.state = .expanded
            let demoController = NSHostingController(rootView: IslandView(model: model, preferences: model.preferences, fallback: true))
            demoController.sizingOptions = []
            let demo = demoController.view
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 490),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentViewController = demoController
            window.setContentSize(NSSize(width: 420, height: 490))
            window.orderFrontRegardless()
            model.query = ""
            try await Task.sleep(for: .milliseconds(250))
            try capture(demo, to: directory.appendingPathComponent("menu-launcher.png"))
            check(try await searchRestoresList(model: model, view: demo, window: window,
                                               directory: directory, name: "popover"),
                  "Search with no results then clearing restores the fallback list height")
            window.orderOut(nil)
        } catch { checks.append("FAIL \(error.localizedDescription)") }
        let fixture = ConfigReadFixture()
        let retryModel = IslandModel(preferences: model.preferences, launcher: launcher, discover: { await fixture.read() })
        retryModel.refresh()
        await retryModel.refreshTask?.value
        let attempts = await fixture.attempts
        check(attempts == 2 && retryModel.hosts.count == 15 && retryModel.configurationError == nil,
              "Transient root read failure retries and recovers all 15 aliases")
        check(retryModel.preview.count == 4 && retryModel.filtered.count == 15,
              "Preview is limited to four while the complete list retains every alias")
        let failedFixture = ConfigReadFixture(persistentFailure: true)
        let failedModel = IslandModel(preferences: model.preferences, launcher: launcher, discover: { await failedFixture.read() })
        failedModel.refresh()
        await failedModel.refreshTask?.value
        check(failedModel.configurationError != nil && !failedModel.loading,
              "Persistent config read failure is exposed as an error, not an empty configuration")
        checks.append("INFO Terminal automation, physical pointer movement, external monitor hot-plug and sleep/wake require interactive smoke testing.")
        try? checks.joined(separator: "\n").write(to: directory.appendingPathComponent("smoke.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
    private static func searchRestoresList(model: IslandModel, view: NSView, window: NSWindow,
                                          directory: URL, name: String) async throws -> Bool {
        let original = model.hosts
        model.hosts = (1...15).map { SSHHost(alias: "demo-host-\($0)") }
        model.query = ""
        try await Task.sleep(for: .milliseconds(200))
        let baseline = window.frame.size
        let baselineHeight = view.bounds.height
        model.query = "demo-host-15"
        try await Task.sleep(for: .milliseconds(100))
        let singleResult = model.filtered.count == 1
        model.query = "no-host-matches-this-query"
        try await Task.sleep(for: .milliseconds(200))
        try capture(view, to: directory.appendingPathComponent("\(name)-empty-search.png"))
        let emptyIsStable = model.filtered.isEmpty && abs(window.frame.height - baseline.height) < 1
        model.query = ""
        try await Task.sleep(for: .milliseconds(200))
        let bitmap = try capture(view, to: directory.appendingPathComponent("\(name)-cleared-search.png"))
        let bottomAlpha = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 4)?.alphaComponent ?? 0
        let restored = singleResult && emptyIsStable && model.filtered.count == 15 && abs(window.frame.height - baseline.height) < 1
            && abs(view.bounds.height - baselineHeight) < 1 && bottomAlpha > 0.9
        model.hosts = original
        try await Task.sleep(for: .milliseconds(100))
        return restored
    }
    private static func topCornersAreBlack(_ bitmap: NSBitmapImageRep) -> Bool {
        for x in [2, bitmap.pixelsWide - 3] {
            guard let color = bitmap.colorAt(x: x, y: 2)?.usingColorSpace(.deviceRGB),
                  color.alphaComponent > 0.99, color.redComponent < 0.02,
                  color.greenComponent < 0.02, color.blueComponent < 0.02 else { return false }
        }
        return true
    }
    @discardableResult
    private static func capture(_ view: NSView, to url: URL) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        return bitmap
    }
}
