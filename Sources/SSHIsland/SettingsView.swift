import SSHIslandCore
import SwiftUI
import ServiceManagement
import Carbon

struct SettingsView: View {
    @ObservedObject var preferences: PreferencesStore
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var requestingAutomation = false
    @State private var automationMessage: String?
    @State private var message: String?
    let shortcutStatus: () -> String?
    var body: some View {
        Form {
            Section("Island") {
                Toggle("Show overlay on built-in notched display", isOn: $preferences.overlayEnabled)
                Toggle("Show icon in menu bar", isOn: $preferences.showMenuBarIcon)
                Toggle("Reduce animation", isOn: $preferences.reduceMotion)
                Text("When the icon is hidden, use the island’s ellipsis menu for Settings and Quit. The icon returns automatically if the notch overlay is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Terminal") {
                Picker("Open SSH in", selection: $preferences.terminal) {
                    Text("Terminal.app").tag("com.apple.Terminal")
                }
                Button(requestingAutomation ? "Waiting for macOS…" : "Request Terminal access") {
                    requestingAutomation = true
                    Task {
                        defer { requestingAutomation = false }
                        do {
                            try await AppleTerminalLauncher().requestAutomationAccess()
                            automationMessage = "Terminal access is allowed. You can now connect to an alias."
                        } catch { automationMessage = error.localizedDescription }
                    }
                }.disabled(requestingAutomation)
                if let automationMessage {
                    Text(automationMessage).font(.caption).textSelection(.enabled)
                }
                Text("macOS may ask to allow SSH Island to control Terminal. Commands run in a new Terminal window. No keys or passwords are read by SSH Island.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Global shortcut") {
                Toggle("Enable keyboard shortcut", isOn: $preferences.hotkeyEnabled)
                HStack {
                    Picker("Modifiers", selection: $preferences.hotkeyModifiers) {
                        Text("⌃⌥⌘").tag(6400)
                        Text("⌃⌥").tag(6144)
                        Text("⇧⌥⌘").tag(2816)
                    }
                    Picker("Key", selection: $preferences.hotkeyKey) {
                        Text("Space").tag(49)
                        Text("S").tag(1)
                        Text("Return").tag(36)
                    }
                }.disabled(!preferences.hotkeyEnabled)
                Text(preferences.hotkeyEnabled ? (shortcutStatus() ?? "Shortcut registered. Changes apply immediately.") : "Shortcut disabled.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $loginEnabled)
                    .onChange(of: loginEnabled) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            if SMAppService.mainApp.status == .requiresApproval {
                                message = "Approve SSH Island in System Settings → General → Login Items."
                            } else { message = nil }
                        } catch { message = error.localizedDescription; loginEnabled = SMAppService.mainApp.status == .enabled }
                    }
                Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Section {
                Button("Clear recent hosts") { preferences.recents = [] }
                Button("Quit SSH Island") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped).frame(width: 530, height: 720)
            .onAppear { loginEnabled = SMAppService.mainApp.status == .enabled }
    }
}
