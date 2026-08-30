import Foundation

struct ToolUsage: Identifiable {
    enum Tool: String, CaseIterable {
        case claude = "Claude"
        case codex = "Codex"
        case gemini = "Gemini"
        case zcode = "ZCode"
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
    /// Claude only: weekly limit scoped to Fable 5, when the account has one.
    /// Always populated regardless of the "Show Fable 5 usage" setting — that
    /// setting hides the bar, it does not suppress the 90% notification. 0...1.
    var fableWeeklyPercent: Double? = nil
    var fableWeeklyResetsLabel: String? = nil
    var fableWeeklyLabel: String? = nil
    let available: Bool
    let note: String?

    /// The window closest to its limit across everything the provider
    /// reports — the number a glance should carry. The session window alone
    /// reads 0% right after a reset even when the weekly limit is the one
    /// about to bite (Codex's UI leads with weekly for exactly this reason).
    var headlinePercent: Double? {
        [sessionPercent, weeklyPercent, fableWeeklyPercent]
            .compactMap { $0 }
            .max()
    }
}
