import Foundation

struct ToolUsage: Identifiable {
    enum Tool: String, CaseIterable {
        case claude = "Claude"
        case claudeB = "Fable B"
        case claudeC = "Fable C"
        case codex = "Codex"
        case gemini = "Gemini"

        /// All three Anthropic accounts share the Claude brand mark and the
        /// live-usage engine; only their tokens differ.
        var isClaudeAccount: Bool {
            switch self {
            case .claude, .claudeB, .claudeC: return true
            case .codex, .gemini: return false
            }
        }

        /// Tiny caption used where three otherwise-identical Claude rings sit
        /// side by side (the floating pill); nil for tools whose mark is
        /// already unambiguous.
        var accountBadge: String? {
            switch self {
            case .claude: return "Main"
            case .claudeB: return "B"
            case .claudeC: return "C"
            case .codex, .gemini: return nil
            }
        }
    }

    var id: String { tool.rawValue }
    let tool: Tool
    /// 0...1, nil when unavailable
    let sessionPercent: Double?
    let sessionResetsLabel: String?
    var sessionCost: Double? = nil
    let weeklyPercent: Double?
    let weeklyResetsLabel: String?
    var weeklyCost: Double? = nil
    let available: Bool
    let note: String?
}
