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

    /// Keep the compact strip consistent across providers: show the ordinary
    /// session window while it is active, otherwise fall back to the ordinary
    /// weekly window. Model-specific constraints remain visible in details
    /// instead of silently taking over the unlabeled headline number.
    var headlinePercent: Double? {
        if let sessionPercent, sessionPercent > 0 { return sessionPercent }
        return weeklyPercent ?? sessionPercent
    }
}
