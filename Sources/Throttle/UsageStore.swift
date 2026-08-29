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

    private enum Keys {
        static let sessionBudget = "throttle.sessionBudget"
        static let weeklyBudget = "throttle.weeklyBudget"
        static let notificationsEnabled = "throttle.notificationsEnabled"
    }

    private var timer: Timer?

    init() {
        let defaults = UserDefaults.standard
        // Defaults assume a Max-tier plan; tune in Settings against your own /usage numbers.
        self.sessionBudget = defaults.object(forKey: Keys.sessionBudget) as? Double ?? 40
        self.weeklyBudget = defaults.object(forKey: Keys.weeklyBudget) as? Double ?? 400
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
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

    /// The Claude accounts shown, in display order. The primary account uses
    /// the credentials Claude Code stored itself (Keychain / credentials
    /// file); the extra accounts each read a bare OAuth token from the
    /// environment or ~/.config/dabo/secrets.env (see SecretsEnv). Raw tokens
    /// carry no plan metadata, so extra accounts get a fixed plan label.
    private struct ClaudeAccount {
        let tool: ToolUsage.Tool
        let tokenVariable: String?
        let planLabel: String?
    }

    private static let claudeAccounts: [ClaudeAccount] = [
        ClaudeAccount(tool: .claude, tokenVariable: nil, planLabel: nil),
        ClaudeAccount(tool: .claudeB, tokenVariable: "CLAUDE_DELEGATE_OAUTH_TOKEN", planLabel: "Max 20x"),
        ClaudeAccount(tool: .claudeC, tokenVariable: "CLAUDE_C_OAUTH_TOKEN", planLabel: "Max 20x"),
    ]

    private func computeAndPublish(sessionBudget: Double, weeklyBudget: Double) {
        var result: [ToolUsage] = []

        // Each account is an independent network fetch with its own timeout;
        // run them concurrently so one slow/dead token never delays the rest.
        var claudeRows: [ToolUsage.Tool: ToolUsage] = [:]
        let lock = NSLock()
        let group = DispatchGroup()
        for account in Self.claudeAccounts {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let row = Self.claudeRow(for: account, sessionBudget: sessionBudget, weeklyBudget: weeklyBudget)
                lock.lock()
                claudeRows[account.tool] = row
                lock.unlock()
                group.leave()
            }
        }
        group.wait()
        for account in Self.claudeAccounts {
            if let row = claudeRows[account.tool] { result.append(row) }
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

    private static func claudeRow(for account: ClaudeAccount, sessionBudget: Double, weeklyBudget: Double) -> ToolUsage {
        guard let tokenVariable = account.tokenVariable else {
            return primaryClaudeRow(sessionBudget: sessionBudget, weeklyBudget: weeklyBudget)
        }

        guard let token = SecretsEnv.value(for: tokenVariable) else {
            return ToolUsage(
                tool: account.tool,
                sessionPercent: nil, sessionResetsLabel: nil,
                weeklyPercent: nil, weeklyResetsLabel: nil,
                available: false,
                note: "No token found — set \(tokenVariable) in ~/.config/dabo/secrets.env"
            )
        }

        if let snap = ClaudeOAuthEngine.computeSnapshot(accessToken: token, planLabel: account.planLabel) {
            return ToolUsage(
                tool: account.tool,
                sessionPercent: snap.sessionPercent,
                sessionResetsLabel: snap.sessionResetsLabel,
                weeklyPercent: snap.weeklyPercent,
                weeklyResetsLabel: snap.weeklyResetsLabel,
                available: true,
                note: snap.planLabel.map { "Plan: \($0) — live from Anthropic" } ?? "Live from Anthropic"
            )
        }

        return ToolUsage(
            tool: account.tool,
            sessionPercent: nil, sessionResetsLabel: nil,
            weeklyPercent: nil, weeklyResetsLabel: nil,
            available: false,
            note: "Couldn't fetch usage from Anthropic — token may be expired or the network is down"
        )
    }

    private static func primaryClaudeRow(sessionBudget: Double, weeklyBudget: Double) -> ToolUsage {
        if let oauth = ClaudeOAuthEngine.computeSnapshot() {
            return ToolUsage(
                tool: .claude,
                sessionPercent: oauth.sessionPercent,
                sessionResetsLabel: oauth.sessionResetsLabel,
                weeklyPercent: oauth.weeklyPercent,
                weeklyResetsLabel: oauth.weeklyResetsLabel,
                available: true,
                note: oauth.planLabel.map { "Plan: \($0) — live from Anthropic" } ?? "Live from Anthropic"
            )
        }
        if let snap = ClaudeUsageEngine.computeSnapshot(sessionBudget: sessionBudget, weeklyBudget: weeklyBudget) {
            return ToolUsage(
                tool: .claude,
                sessionPercent: snap.sessionPercent,
                sessionResetsLabel: snap.sessionResetsLabel,
                sessionCost: snap.sessionCost,
                weeklyPercent: snap.weeklyPercent,
                weeklyResetsLabel: snap.weeklyResetsLabel,
                weeklyCost: snap.weeklyCost,
                available: true,
                note: "Sign in with `claude login` for exact numbers — estimated cost from local logs for now"
            )
        }
        return ToolUsage(tool: .claude, sessionPercent: nil, sessionResetsLabel: nil, weeklyPercent: nil, weeklyResetsLabel: nil, available: false, note: "No local Claude Code logs found")
    }
}
