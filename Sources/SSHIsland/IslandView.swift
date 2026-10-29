import SwiftUI
import SSHIslandCore

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var preferences: PreferencesStore
    var notchDepth: CGFloat = 0
    var fallback = false
    @FocusState private var searchFocused: Bool
    @State private var selection: String?
    private var expanded: Bool { fallback || model.state == .expanded }
    private var rows: [SSHHost] { expanded ? model.filtered : model.preview }
    var body: some View {
        VStack(spacing: 0) {
            // The black surface grows across the menu bar; controls stay below the camera.
            if notchDepth > 0 && !fallback {
                Color.clear.frame(height: notchDepth).contentShape(Rectangle())
                    .onTapGesture { model.state = .expanded }
            }
            if model.state == .collapsed && !fallback {
                Capsule().fill(.white.opacity(0.65)).frame(width: 26, height: 3).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle()).onTapGesture { model.state = .expanded }
                    .accessibilityLabel("Open SSH Island").accessibilityAddTraits(.isButton)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "terminal.fill").foregroundStyle(.mint)
                        Text("SSH Island").font(.system(.headline, design: .rounded))
                            .onTapGesture { model.state = .expanded }
                        Spacer()
                        if !expanded {
                            Button { model.state = .expanded } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                                .help("Show all hosts").accessibilityLabel("Show all hosts")
                        }
                        Menu {
                            Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                            Button("Settings…", systemImage: "gearshape") { model.settings?() }
                            Button("Quit SSH Island", systemImage: "power") { NSApp.terminate(nil) }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }
                    if expanded {
                        TextField("Search SSH aliases", text: $model.query)
                            .textFieldStyle(.plain).padding(9).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                            .focused($searchFocused).accessibilityLabel("Search SSH aliases")
                            .onSubmit { if let alias = selection ?? rows.first?.alias { model.connect(alias) } }
                    }
                    if let reason = model.fallbackReason, fallback {
                        Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                        Button("Dismiss error") { model.error = nil }
                    }
                    if model.loading && model.hosts.isEmpty {
                        ProgressView("Reading SSH configuration…").controlSize(.small)
                    } else if let failure = model.configurationError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Couldn’t read SSH configuration").font(.headline)
                            Text(failure).font(.caption).foregroundStyle(.orange)
                            Text(NSHomeDirectory() + "/.ssh/config").font(.caption2).textSelection(.enabled)
                            Button("Retry reading configuration") { model.refresh() }
                        }
                    } else if rows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(model.hosts.isEmpty ? "No SSH aliases yet" : "No matching aliases").font(.headline)
                            Text(model.hosts.isEmpty ? "Add a literal Host alias to ~/.ssh/config, then Refresh." : "Try another search.")
                                .font(.caption).foregroundStyle(.secondary)
                            if model.hosts.isEmpty { Button("Open SSH folder") { NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.ssh")) } }
                        }.padding(.vertical, 10)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 4) {
                                    ForEach(rows) { host in
                                        HostRowView(host: host, favorite: preferences.favorites.contains(host.alias),
                                                    selected: selection == host.alias, disabled: model.connecting,
                                                    connect: { model.connect(host.alias) }, favoriteAction: { preferences.favorite(host.alias) })
                                            .id(host.alias)
                                    }
                                }
                            }.frame(maxHeight: .infinity)
                                .onChange(of: selection) { _, value in if let value { proxy.scrollTo(value) } }
                        }
                    }
                    if let warning = model.warnings.first {
                        Text(warning + (model.warnings.count > 1 ? " (+\(model.warnings.count - 1) more)" : ""))
                            .font(.caption2).foregroundStyle(.orange).lineLimit(2).help(model.warnings.joined(separator: "\n"))
                    }
                    if !expanded && model.hosts.count > 0 {
                        Button { model.state = .expanded } label: {
                            HStack {
                                Text("All \(model.hosts.count) hosts")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }.font(.caption).foregroundStyle(.mint).contentShape(Rectangle())
                        }.accessibilityLabel("Show all \(model.hosts.count) SSH hosts")
                    }
                    if expanded {
                        HStack {
                            Text("\(rows.count) aliases").foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") { model.refresh() }
                            Button("Close") { model.dismiss() }
                        }.font(.caption)
                    }
                }.padding(16)
            }
        }
        // Empty/error content must fill the same externally managed viewport as the list.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white).colorScheme(.dark)
        .buttonStyle(.plain)
        .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
        .clipped()
        .ignoresSafeArea()
        .onChange(of: model.state) { _, state in
            if state == .expanded { searchFocused = true; selection = nil }
        }
        .onChange(of: model.query) { _, _ in selection = nil }
        .onAppear { if expanded { searchFocused = true } }
        .onExitCommand { model.dismiss() }
        .onKeyPress(.downArrow) { moveSelection(down: true); return .handled }
        .onKeyPress(.upArrow) { moveSelection(down: false); return .handled }
    }
    private func moveSelection(down: Bool) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.alias == selection } ?? -1
        selection = rows[down ? min(index + 1, rows.count - 1) : max(index - 1, 0)].alias

    }
}

struct HostRowView: View {
    let host: SSHHost
    let favorite: Bool
    let selected: Bool
    let disabled: Bool
    let connect: () -> Void
    let favoriteAction: () -> Void
    @State private var hovered = false
    var body: some View {
        HStack(spacing: 8) {
            Button(action: connect) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption).foregroundStyle(.mint)
                    Text(host.alias).font(.system(.body, design: .monospaced)).lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.caption2).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.disabled(disabled).accessibilityLabel("Connect to \(host.alias)").help(host.alias)
            Button(action: favoriteAction) { Image(systemName: favorite ? "star.fill" : "star").foregroundStyle(favorite ? .yellow : .gray) }
                .accessibilityLabel(favorite ? "Remove \(host.alias) from favorites" : "Favorite \(host.alias)")
        }.padding(10).background(.white.opacity(hovered || selected ? 0.13 : 0.045), in: RoundedRectangle(cornerRadius: 9))
            .onHover { hovered = $0 }
    }
}
