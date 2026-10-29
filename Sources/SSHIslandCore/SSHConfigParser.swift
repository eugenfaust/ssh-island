import Foundation
import Darwin

public struct SSHHost: Identifiable, Equatable, Sendable {
    public var id: String { alias }
    public let alias: String
    public init(alias: String) { self.alias = alias }
}

public struct Discovery: Sendable {
    public var hosts: [SSHHost] = []
    public var files: Set<String> = []
    public var watchDirectories: Set<String> = []
    public var warnings: [String] = []
    public var rootError: String?
    public init() {}
}

/// An alias index, never an evaluator: Match/Host conditions do not execute.
public struct SSHConfigParser: Sendable {
    public let home: String
    public var read: @Sendable (String) throws -> String
    public var globPaths: @Sendable (String) -> [String]
    public init(home: String = NSHomeDirectory(),
                read: @escaping @Sendable (String) throws -> String = { try Self.readConfiguration($0) },
                globPaths: @escaping @Sendable (String) -> [String] = { Self.expandGlob($0) }) {
        self.home = home; self.read = read; self.globPaths = globPaths
    }
    /// Inspect the opened descriptor: Foundation's Any-valued attribute dictionary
    /// can expose file types as strings rather than FileAttributeType wrappers.
    /// Opening nonblocking also prevents an Include pointing to a FIFO from hanging.
    public static func readConfiguration(_ path: String) throws -> String {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileReadUnsupportedScheme) }
        let limit = 2_097_152
        guard info.st_size <= limit else { throw CocoaError(.fileReadTooLarge) }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        }
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }
    public func discover(path: String? = nil) -> Discovery {
        var result = Discovery()
        var seen = Set<String>()
        var visits = 0
        func visit(_ path: String, stack: Set<String>, depth: Int) {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let canonical = url.resolvingSymlinksInPath().path
            result.files.insert(url.path)
            result.files.insert(canonical)
            result.watchDirectories.insert(url.deletingLastPathComponent().path)
            guard depth < 32, visits < 1024 else {
                result.warnings.append("Include limit reached; part of the configuration was skipped."); return
            }
            guard !stack.contains(canonical) else {
                result.warnings.append("Include cycle skipped: \(url.lastPathComponent)"); return
            }
            visits += 1
            let contents: String
            do { contents = try read(url.path) }
            catch {
                let ns = error as NSError
                let missing = (ns.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(ns.code))
                    || (ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT))
                // Report actual failures even if stat/fileExists is also denied.
                if depth > 0 || !missing {
                    let permissionDenied = (ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError)
                        || (ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code))
                    let reason = permissionDenied
                        ? "Access was denied. Retry reading the configuration."
                        : "Read failed (\(ns.domain):\(ns.code))."
                    let message = "Cannot read configuration: \(url.lastPathComponent). " + reason
                    result.warnings.append(message)
                    if depth == 0 { result.rootError = message }
                }
                return
            }
            var next = stack; next.insert(canonical)
            for (number, line) in contents.components(separatedBy: .newlines).enumerated() {
                let words: [String]
                do { words = try Self.tokens(line) }
                catch { result.warnings.append("Invalid quoting in \(url.lastPathComponent):\(number + 1)"); continue }
                guard let directive = words.first?.lowercased() else { continue }
                if directive == "host" {
                    for alias in words.dropFirst() where !alias.isEmpty && !alias.contains(where: { "*?!".contains($0) }) {
                        if seen.insert(alias).inserted { result.hosts.append(SSHHost(alias: alias)) }
                    }
                } else if directive == "include" {
                    for raw in words.dropFirst() {
                        // Connection-specific tokens/environment expansion cannot be evaluated by an alias index.
                        guard !raw.contains("%"), !raw.contains("${") else {
                            result.warnings.append("Include with tokens/environment variables skipped."); continue
                        }
                        let expanded: String
                        if raw == "~" { expanded = home }
                        else if raw.hasPrefix("~/") { expanded = home + raw.dropFirst() }
                        else if raw.hasPrefix("~") { expanded = (raw as NSString).expandingTildeInPath }
                        else if raw.hasPrefix("/") { expanded = raw }
                        else { expanded = home + "/.ssh/" + raw }
                        // Watch directory glob prefixes even when no final file matches yet.
                        let components = expanded.split(separator: "/").map(String.init)
                        var prefixPattern = ""
                        for (index, component) in components.dropLast().enumerated() {
                            prefixPattern += "/" + component
                            guard index == components.count - 2 || component.contains(where: { "*?[".contains($0) }) else { continue }
                            for directory in globPaths(prefixPattern).prefix(1024) {
                                var isDirectory: ObjCBool = false
                                if FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue {
                                    result.watchDirectories.insert(directory)
                                }
                            }
                        }
                        // Missing paths need their nearest existing parent observed.
                        var parent = URL(fileURLWithPath: expanded).deletingLastPathComponent()
                        while parent.path != "/", !FileManager.default.fileExists(atPath: parent.path) {
                            parent.deleteLastPathComponent()
                        }
                        // Do not poll unrelated global ancestors when a more specific directory exists.
                        result.watchDirectories.insert(parent.path)
                        let matches = globPaths(expanded)
                        for match in matches { visit(match, stack: next, depth: depth + 1) }
                    }
                }
            }
        }
        visit(path ?? home + "/.ssh/config", stack: [], depth: 0)
        return result
    }
    public static func expandGlob(_ pattern: String) -> [String] {
        var buffer = glob_t()
        defer { globfree(&buffer) }
        guard glob(pattern, 0, nil, &buffer) == 0, let paths = buffer.gl_pathv else { return [] }
        return (0..<Int(buffer.gl_pathc)).compactMap { paths[$0].map { String(cString: $0) } }.sorted()
    }
    enum SyntaxError: Error { case unmatchedQuote }
    public static func tokens(_ line: String) throws -> [String] {
        var tokens: [String] = []; var token = ""; var quote: Character?; var started = false
        let chars = Array(line); var i = 0; var keywordDone = false
        func finish() {
            if started { tokens.append(token); token = ""; started = false; keywordDone = true }
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, chars[i + 1] == quote || chars[i + 1] == "\\" || chars[i + 1] == "\"" || chars[i + 1] == "'" {
                i += 1; token.append(chars[i]); started = true
            } else if let q = quote {
                if c == q { quote = nil } else { token.append(c) }; started = true
            } else if c == "\"" || c == "'" { quote = c; started = true }
            else if c == "#" { break }
            else if c == "=" && keywordDone && tokens.count == 1 && !started { /* optional separator */ }
            else if c.isWhitespace || (c == "=" && !keywordDone) { finish() }
            else { token.append(c); started = true }
            i += 1
        }
        guard quote == nil else { throw SyntaxError.unmatchedQuote }
        finish(); return tokens
    }
}
