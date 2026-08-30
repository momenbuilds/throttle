import Foundation
import Combine

final class UsageStore: ObservableObject {
    @Published private(set) var items: [ToolUsage] = []
    @Published private(set) var lastUpdated: Date? = nil
    /// Tools visible in the pill and panel: detected as installed locally, or
    /// explicitly activated in Settings (Gemini is the "activate manually" case).
    @Published private(set) var visibleTools: [ToolUsage.Tool] = ToolUsage.Tool.allCases.filter(ToolPresence.isPresent)

    /// Tools the user turned on in Settings despite no local footprint.
    @Published private(set) var activatedTools: Set<ToolUsage.Tool> = [] {
        didSet {
            UserDefaults.standard.set(activatedTools.map(\.rawValue).sorted(), forKey: Keys.activatedTools)
            recomputeVisibleTools()
        }
    }

    /// Tools the user turned off in Settings, even though they're installed.
    @Published private(set) var hiddenTools: Set<ToolUsage.Tool> = [] {
        didSet {
            UserDefaults.standard.set(hiddenTools.map(\.rawValue).sorted(), forKey: Keys.hiddenTools)
            recomputeVisibleTools()
        }
    }

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
    /// Which screen edge the floating pill parks on (.top parks it as a
    /// horizontal strip under the menu bar, by the notch).
    @Published var pillEdge: PillEdge {
        didSet { UserDefaults.standard.set(pillEdge.rawValue, forKey: Keys.pillEdge) }
    }
    /// Low-profile pill: only a sliver shows until the pointer hovers over it.
    @Published var pillPeek: Bool {
        didSet { UserDefaults.standard.set(pillPeek, forKey: Keys.pillPeek) }
    }

    private enum Keys {
        static let sessionBudget = "throttle.sessionBudget"
        static let weeklyBudget = "throttle.weeklyBudget"
        static let notificationsEnabled = "throttle.notificationsEnabled"
        static let showFableUsage = "throttle.showFableUsage"
        static let activatedTools = "throttle.activatedTools"
        static let hiddenTools = "throttle.hiddenTools"
        static let pillEdge = "throttle.pillEdge"
        static let pillPeek = "throttle.pillPeek"
    }

    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        // Defaults assume a Max-tier plan; tune in Settings against your own /usage numbers.
        self.sessionBudget = defaults.object(forKey: Keys.sessionBudget) as? Double ?? 40
        self.weeklyBudget = defaults.object(forKey: Keys.weeklyBudget) as? Double ?? 400
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        self.showFableUsage = defaults.object(forKey: Keys.showFableUsage) as? Bool ?? true
        self.pillEdge = (defaults.string(forKey: Keys.pillEdge)).flatMap(PillEdge.init(rawValue:)) ?? .right
        self.pillPeek = defaults.object(forKey: Keys.pillPeek) as? Bool ?? false
        self.activatedTools = Set((defaults.stringArray(forKey: Keys.activatedTools) ?? []).compactMap(ToolUsage.Tool.init(rawValue:)))
        self.hiddenTools = Set((defaults.stringArray(forKey: Keys.hiddenTools) ?? []).compactMap(ToolUsage.Tool.init(rawValue:)))
        self.launchAtLogin = LaunchAtLogin.isEnabled
        recomputeVisibleTools()
        if notificationsEnabled { UsageNotifier.requestAuthorizationIfNeeded() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    /// The Settings toggle: on = show the tool (and remember it if nothing
    /// local detects it), off = keep it out of the pill, panel, and checks.
    func setToolVisible(_ tool: ToolUsage.Tool, _ visible: Bool) {
        if visible {
            hiddenTools.remove(tool)
            if !ToolPresence.isPresent(tool) { activatedTools.insert(tool) }
        } else {
            hiddenTools.insert(tool)
            activatedTools.remove(tool)
        }
    }

    private func recomputeVisibleTools() {
        // Re-run on every toggle: presence is cheap (file stats) and installs
        // can happen while the app runs.
        visibleTools = ToolUsage.Tool.allCases.filter {
            !hiddenTools.contains($0) && (activatedTools.contains($0) || ToolPresence.isPresent($0))
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

        switch ClaudeOAuthEngine.computeOutcome() {
        case .snapshot(let oauth):
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
        case .failed:
            // Credentials exist but the API didn't answer (expired token,
            // rate limit, network). A guessed cost here would present a wrong
            // number as fact — say what happened instead.
            result.append(ToolUsage(
                tool: .claude,
                sessionPercent: nil, sessionResetsLabel: nil,
                weeklyPercent: nil, weeklyResetsLabel: nil,
                available: false,
                note: "Signed in, but Anthropic's usage API didn't respond — the stored token may be expired. Running any `claude` command refreshes it."
            ))
        case .noCredentials:
            if let snap = ClaudeUsageEngine.computeSnapshot(sessionBudget: sessionBudget, weeklyBudget: weeklyBudget) {
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

        if let snap = ZCodeUsageEngine.computeSnapshot() {
            let note = snap.planLevel.map { "Plan: \($0.capitalized) — live from Z.ai" } ?? "Live from Z.ai"
            result.append(ToolUsage(
                tool: .zcode,
                sessionPercent: snap.sessionPercent,
                sessionResetsLabel: snap.sessionResetsLabel,
                weeklyPercent: snap.weeklyPercent,
                weeklyResetsLabel: snap.weeklyResetsLabel,
                available: true,
                note: note
            ))
        } else {
            result.append(ToolUsage(tool: .zcode, sessionPercent: nil, sessionResetsLabel: nil, weeklyPercent: nil, weeklyResetsLabel: nil, available: false, note: "No coding-plan ZCode config found (~/.zcode/cli/config.json)"))
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

        // Hidden tools are excluded here — not measured, not notified about.
        let visible = visibleTools
        let shown = result.filter { visible.contains($0.tool) }
        let notificationsEnabled = self.notificationsEnabled
        DispatchQueue.main.async {
            self.items = shown
            self.lastUpdated = Date()
            UsageNotifier.checkThresholds(items: shown, enabled: notificationsEnabled)
        }
    }
}
