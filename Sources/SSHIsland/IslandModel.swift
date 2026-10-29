import AppKit
import Combine
import SSHIslandCore

enum IslandState { case collapsed, preview, expanded }
@MainActor final class IslandModel: ObservableObject {
    @Published var hosts: [SSHHost] = []
    @Published var warnings: [String] = []
    @Published var loading = true
    @Published var configurationError: String?
    @Published var error: String?
    @Published var connecting = false
    @Published var query = ""
    @Published var state: IslandState = .collapsed
    @Published var fallbackReason: String?
    let preferences: PreferencesStore
    private let launcher: any TerminalLaunching
    private let discover: @Sendable () async -> Discovery
    var watcher: SSHConfigWatcher?
    var settings: (() -> Void)?
    var refreshTask: Task<Void, Never>?
    init(preferences: PreferencesStore, launcher: any TerminalLaunching,
         discover: @escaping @Sendable () async -> Discovery = { await Task.detached { SSHConfigParser().discover() }.value }) {
        self.preferences = preferences; self.launcher = launcher; self.discover = discover
    }
    var filtered: [SSHHost] {
        hosts.filter { query.isEmpty || $0.alias.localizedCaseInsensitiveContains(query) }
    }
    var preview: [SSHHost] {
        let aliases = preferences.favorites + preferences.recents
        var seen = Set<String>()
        let ordered = aliases.compactMap { alias in hosts.first { $0.alias == alias } } + hosts
        return Array(ordered.filter { seen.insert($0.alias).inserted }.prefix(4))
    }
    func refresh() {
        refreshTask?.cancel()
        loading = true
        refreshTask = Task {
            var discovery = await discover()
            if discovery.rootError != nil {
                // A startup or atomic-replacement read failure must not become a permanent empty list.
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                discovery = await discover()
            }
            guard !Task.isCancelled else { return }
            hosts = discovery.hosts; warnings = discovery.warnings
            configurationError = discovery.rootError; loading = false
            watcher?.update(discovery: discovery)
        }
    }
    func connect(_ alias: String) {
        guard !connecting else { return }
        connecting = true; error = nil
        Task {
            defer { connecting = false }
            do { try await launcher.connect(alias: alias); preferences.record(alias); state = .collapsed }
            catch { self.error = error.localizedDescription; state = .expanded }
        }
    }
    func dismiss() { state = .collapsed; query = "" }
}
