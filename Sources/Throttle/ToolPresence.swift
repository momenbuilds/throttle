import Foundation

/// Which tools have a local footprint on this machine — drives "show what's
/// installed": a tool appears automatically when detected, and Settings can
/// activate the rest (Gemini currently has no local usage source at all, so
/// it only ever appears by choice).
enum ToolPresence {
    static func isPresent(_ tool: ToolUsage.Tool) -> Bool {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let fm = FileManager.default
        switch tool {
        case .claude:
            return fm.fileExists(atPath: home + "/.claude/.credentials.json")
                || fm.fileExists(atPath: home + "/.claude/projects")
        case .codex:
            return fm.fileExists(atPath: home + "/.codex/sessions")
        case .zcode:
            return fm.fileExists(atPath: home + "/.zcode/cli/config.json")
        case .gemini:
            return false
        }
    }
}
