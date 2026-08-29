import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published private(set) var items: [ToolUsage] = []
    @Published private(set) var lastUpdated: Date? = nil

    @Published var sessionBudget: Double {
        didSet { UserDefaults.standard.set(sessionBudget, forKey: Keys.sessionBudget) }
    }
    @Published var weeklyBudget: Double {
        didSet { UserDefaults.standard.set(weeklyBudget, forKey: Keys.weeklyBudget) }
    }
    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
            if notificationsEnabled { UsageNotifier.requestAuthorizationIfNeeded() }
        }
    }
    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.setEnabled(launchAtLogin) }
    }
    /// Show the Fable 5-scoped weekly limit as an extra bar on the Claude tab.
    /// Presentation only: the window is still fetched and still notifies at
    /// 90%, so hiding the bar never hides the limit that's about to bite.
    @Published var showFableUsage: Bool {
        didSet { UserDefaults.standard.set(showFableUsage, forKey: Keys.showFableUsage) }
    }

    private enum Keys {
        static let sessionBudget = "throttle.sessionBudget"
        static let weeklyBudget = "throttle.weeklyBudget"
        static let notificationsEnabled = "throttle.notificationsEnabled"
        static let showFableUsage = "throttle.showFableUsage"
    }

    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        // Defaults assume a Max-tier plan; tune in Settings against your own /usage numbers.
        self.sessionBudget = defaults.object(forKey: Keys.sessionBudget) as? Double ?? 40
        self.weeklyBudget = defaults.object(forKey: Keys.weeklyBudget) as? Double ?? 400
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.showFableUsage = defaults.object(forKey: Keys.showFableUsage) as? Bool ?? true
        self.launchAtLogin = LaunchAtLogin.isEnabled
        if notificationsEnabled { UsageNotifier.requestAuthorizationIfNeeded() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let sessionBudget = self.sessionBudget
        let weeklyBudget = self.weeklyBudget
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.computeAndPublish(sessionBudget: sessionBudget, weeklyBudget: weeklyBudget)
        }
    }

    private func computeAndPublish(sessionBudget: Double, weeklyBudget: Double) {
        var result: [ToolUsage] = []

        if let oauth = ClaudeOAuthEngine.computeSnapshot() {
            result.append(ToolUsage(
                tool: .claude,
                sessionPercent: oauth.sessionPercent,
                sessionResetsLabel: oauth.sessionResetsLabel,
                weeklyPercent: oauth.weeklyPercent,
                weeklyResetsLabel: oauth.weeklyResetsLabel,
                fableWeeklyPercent: oauth.fableWeeklyPercent,
                fableWeeklyResetsLabel: oauth.fableWeeklyResetsLabel,
                fableWeeklyLabel: oauth.fableWeeklyLabel,
                available: true,
                note: oauth.planLabel.map { "Plan: \($0) — live from Anthropic" } ?? "Live from Anthropic"
            ))
        } else if let snap = ClaudeUsageEngine.computeSnapshot(sessionBudget: sessionBudget, weeklyBudget: weeklyBudget) {
            result.append(ToolUsage(
                tool: .claude,
                sessionPercent: snap.sessionPercent,
                sessionResetsLabel: snap.sessionResetsLabel,
                sessionCost: snap.sessionCost,
                weeklyPercent: snap.weeklyPercent,
                weeklyResetsLabel: snap.weeklyResetsLabel,
                weeklyCost: snap.weeklyCost,
                available: true,
                note: "Sign in with `claude login` for exact numbers — estimated cost from local logs for now"
            ))
        } else {
            result.append(ToolUsage(tool: .claude, sessionPercent: nil, sessionResetsLabel: nil, weeklyPercent: nil, weeklyResetsLabel: nil, available: false, note: "No local Claude Code logs found"))
        }

        if let snap = CodexUsageEngine.computeSnapshot() {
            let note = snap.planType.map { "Plan: \($0) — live from OpenAI API" }
                ?? (snap.secondaryPercent == nil ? "Weekly window not exposed for your plan by OpenAI's API" : nil)
            result.append(ToolUsage(
                tool: .codex,
                sessionPercent: snap.primaryPercent,
                sessionResetsLabel: snap.primaryResetsLabel,
                weeklyPercent: snap.secondaryPercent,
                weeklyResetsLabel: snap.secondaryResetsLabel,
                available: true,
                note: note
            ))
        } else {
            result.append(ToolUsage(tool: .codex, sessionPercent: nil, sessionResetsLabel: nil, weeklyPercent: nil, weeklyResetsLabel: nil, available: false, note: "No local Codex CLI sessions found"))
        }

        result.append(ToolUsage(
            tool: .gemini,
            sessionPercent: nil,
            sessionResetsLabel: nil,
            weeklyPercent: nil,
            weeklyResetsLabel: nil,
            available: false,
            note: "Google stopped serving Gemini CLI's usage API to individual accounts in June 2026 (Workspace/Enterprise unaffected)"
        ))

        let notificationsEnabled = self.notificationsEnabled
        DispatchQueue.main.async {
            self.items = result
            self.lastUpdated = Date()
            UsageNotifier.checkThresholds(items: result, enabled: notificationsEnabled)
        }
    }
}
