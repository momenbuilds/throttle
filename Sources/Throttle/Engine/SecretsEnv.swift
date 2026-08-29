import Foundation

/// Resolves OAuth tokens for the extra Claude accounts. The process
/// environment is checked first so terminal dev runs (`swift build` +
/// `.build/debug/Throttle`) can just export the variable — but a GUI app
/// launched from /Applications never inherits the shell environment, so the
/// reliable source is `~/.config/dabo/secrets.env`, a shell-style env file
/// (`KEY=value`, `export KEY=value`, quoted values, `#` comments).
///
/// Token values only ever live in that file / the environment — never in
/// code, never written anywhere by this app.
enum SecretsEnv {
    static func value(for key: String) -> String? {
        if let fromEnv = ProcessInfo.processInfo.environment[key], !fromEnv.isEmpty {
            return fromEnv
        }
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let path = home + "/.config/dabo/secrets.env"
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return parse(text)[key]
    }

    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            values[key] = value
        }
        return values
    }
}
