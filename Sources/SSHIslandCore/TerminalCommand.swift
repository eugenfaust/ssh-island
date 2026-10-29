import Foundation
public enum TerminalCommand {
    public enum Failure: LocalizedError {
        case invalidAlias
        public var errorDescription: String? { "This alias contains control characters or starts with ‘-’. Rename it in ~/.ssh/config before connecting." }
    }
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
    public static func command(alias: String) throws -> String {
        guard !alias.isEmpty, !alias.hasPrefix("-"), !alias.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw Failure.invalidAlias
        }
        return "/usr/bin/ssh " + shellQuote(alias)
    }
}
