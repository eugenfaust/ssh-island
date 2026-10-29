import Foundation

/// Metadata polling watches paths rather than inodes, so atomic replacements need no reattachment.
/// Directory metadata also detects new glob matches and creation of missing include paths.
@MainActor public final class SSHConfigWatcher {
    public init() {}
    private var paths: Set<String> = []
    private var signatures: [String: String] = [:]
    private var timer: Timer?
    private var pending: Task<Void, Never>?
    public var onChange: (() -> Void)?
    public func update(discovery: Discovery) {
        paths = discovery.files.union(discovery.watchDirectories)
        signatures = snapshot()
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.check() }
            }
        }
    }
    public func stop() { timer?.invalidate(); timer = nil; pending?.cancel() }
    private func snapshot() -> [String: String] {
        var result: [String: String] = [:]
        for path in paths {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { result[path] = "missing"; continue }
            let date = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            result[path] = "\(attrs[.systemFileNumber] ?? "")|\(date)|\(attrs[.size] ?? "")"
        }
        return result
    }
    private func check() {
        let current = snapshot()
        guard current != signatures else { return }
        signatures = current
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            onChange?()
        }
    }
}
