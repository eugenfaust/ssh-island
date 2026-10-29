import AppKit
import SwiftUI
import Combine
import SSHIslandCore

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // AppKit otherwise moves borderless panels below the menu-bar visibleFrame.
    // The user-requested silhouette spans the menu bar within the current island width.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
final class TrackingHostingView: NSHostingView<IslandView> {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
}

final class NotchTriggerView: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    var clicked: (() -> Void)?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.black.setFill(); bounds.fill() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
    override func mouseDown(with event: NSEvent) { clicked?() }
}

@MainActor final class IslandPanelController {
    let panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let notchTrigger = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let model: IslandModel
    var isLauncherWindow: ((NSWindow?) -> Bool)?
    private var geometry: NotchGeometry?
    private var subscriptions = Set<AnyCancellable>()
    private var collapse: Task<Void, Never>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    init(model: IslandModel) {
        self.model = model
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        // Equal levels can put the menu bar in front after activation/Space changes.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        notchTrigger.isOpaque = true; notchTrigger.backgroundColor = .black; notchTrigger.hasShadow = false
        notchTrigger.level = panel.level; notchTrigger.collectionBehavior = panel.collectionBehavior
        notchTrigger.hidesOnDeactivate = false; notchTrigger.isReleasedWhenClosed = false
        let triggerView = NotchTriggerView()
        triggerView.setAccessibilityLabel("Open SSH Island")
        triggerView.entered = { [weak self] in self?.preview() }
        triggerView.exited = { [weak self] in self?.scheduleCollapse() }
        triggerView.clicked = { [weak self] in self?.expand() }
        notchTrigger.contentView = triggerView
        model.$state.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.layout(animated: true) }
        }.store(in: &subscriptions)
        model.preferences.$overlayEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.updateScreen() }
        }.store(in: &subscriptions)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown, event.keyCode == 53 { self?.model.dismiss() }
                else if event.type != .keyDown, let self, self.panel.isVisible,
                        self.isLauncherWindow?(event.window) != true,
                        (event.window?.level.rawValue ?? 0) < NSWindow.Level.popUpMenu.rawValue,
                        !self.panel.frame.contains(NSEvent.mouseLocation), !self.notchTrigger.frame.contains(NSEvent.mouseLocation) {
                    self.model.dismiss()
                }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.model.dismiss() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screenChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        updateScreen()
    }
    @objc private func screenChanged() { updateScreen() }
    func updateScreen() {
        geometry = nil
        if model.preferences.overlayEnabled {
            for screen in NSScreen.screens {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
                if let found = NotchGeometry.detect(frame: screen.frame, builtIn: CGDisplayIsBuiltin(number.uint32Value) != 0,
                                                    topInset: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea) {
                    geometry = found; break
                }
            }
        }
        guard let geometry else {
            model.fallbackReason = model.preferences.overlayEnabled
                ? "A built-in notched display could not be identified safely. SSH Island is available here in the menu bar."
                : "The notch overlay is disabled in Settings."
            panel.orderOut(nil); notchTrigger.orderOut(nil); return
        }
        model.fallbackReason = nil
        notchTrigger.setFrame(NSRect(x: geometry.centerX - geometry.width / 2, y: geometry.top - geometry.depth,
                                     width: geometry.width, height: geometry.depth), display: true)
        notchTrigger.orderFrontRegardless()
        let hosting = TrackingHostingView(rootView: IslandView(model: model, preferences: model.preferences, notchDepth: geometry.depth))
        // Panel geometry is owned here, not by SwiftUI's changing intrinsic content size.
        hosting.sizingOptions = []
        hosting.entered = { [weak self] in
            self?.preview()
        }
        hosting.exited = { [weak self] in self?.scheduleCollapse() }
        panel.contentView = hosting
        layout(animated: false); panel.orderFrontRegardless()
    }
    func expand() {
        model.state = .expanded
        guard geometry != nil else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func preview() {
        collapse?.cancel()
        if model.state == .collapsed { model.state = .preview }
    }
    private func scheduleCollapse() {
        collapse?.cancel()
        collapse = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, model.state == .preview, !panel.frame.contains(NSEvent.mouseLocation), !notchTrigger.frame.contains(NSEvent.mouseLocation) else { return }
            model.dismiss()
        }
    }
    private func layout(animated: Bool) {
        guard let geometry else { return }
        let width: CGFloat
        let height: CGFloat
        switch model.state {
        case .collapsed: width = geometry.width + 12; height = 8
        case .preview: width = max(320, geometry.width + 12); height = 290
        case .expanded: width = 420; height = 460
        }
        let frame = geometry.panelFrame(width: width, contentHeight: height)
        let motion = !model.preferences.reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && motion ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
        if model.state == .expanded { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else if panel.isKeyWindow { panel.resignKey() }
        // Keep the camera hit region clickable when the collapsed drawing extends behind it.
        notchTrigger.orderFrontRegardless()
    }
}
