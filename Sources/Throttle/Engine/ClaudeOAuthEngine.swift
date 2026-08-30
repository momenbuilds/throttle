import Foundation
import Security

/// Reads real usage straight from Anthropic's own account API — the same
/// endpoint Claude Code's `/usage` and `/status` use internally — instead of
/// estimating from local logs. Credentials are the ones Claude Code already
/// wrote to disk when you ran `claude login`; nothing is sent anywhere except
/// straight to api.anthropic.com with your own token.
enum ClaudeOAuthEngine {
    struct Snapshot {
        let sessionPercent: Double
        let sessionResetsLabel: String
        let weeklyPercent: Double
        let weeklyResetsLabel: String
        /// Weekly limit scoped to Claude Fable 5, from the `limits` array
        /// (`kind == "weekly_scoped"`, `scope.model.display_name == "Fable"`).
        /// nil when the account has no Fable-specific window.
        let fableWeeklyPercent: Double?
        let fableWeeklyResetsLabel: String?
        /// The model name Anthropic reports for that window (e.g. "Fable"), so
        /// the UI follows the API instead of hardcoding a version number.
        let fableWeeklyLabel: String?
        let planLabel: String?
    }

    /// Why computeOutcome() landed where it did. `noCredentials` is the only
    /// state that legitimately falls back to the local-log estimate (the user
    /// is signed out); `failed` means credentials exist but the API didn't
    /// answer (expired token, rate limit, network) — showing a guessed cost
    /// there would present a wrong number as fact, so the store shows an
    /// explanatory note instead.
    enum Outcome {
        case snapshot(Snapshot)
        case noCredentials
        case failed
    }

    struct Credentials {
        let accessToken: String
        let rateLimitTier: String?
        let subscriptionType: String?
        /// Access-token expiry in ms since epoch, when the payload says.
        let expiresAt: Double?
    }

    /// Keeps the last successful snapshot so the usage endpoint's aggressive
    /// rate limiting (observed retry-after from seconds to ~37 minutes)
    /// doesn't blank the tab after a single 429. Served stale-but-real beats
    /// an empty reading; the panel's "Updated" line shows its age.
    private static let cacheLifetime: TimeInterval = 6 * 3600
    private static var lastGood: (snapshot: Snapshot, at: Date)?
    /// When Anthropic's rate limiter last told us to come back. While due, we
    /// don't burn another request — the cache (or an honest failed note on a
    /// truly cold start) carries the tab until the window expires.
    private static var retryAfterUntil: Date?
    private static let cacheLock = NSLock()

    static func computeOutcome() -> Outcome {
        guard let creds = loadCredentials() else { return .noCredentials }

        let checkedAt = Date()
        cacheLock.lock()
        let backingOff = retryAfterUntil.map { checkedAt < $0 } ?? false
        let cached = lastGood
        cacheLock.unlock()
        if backingOff {
            if let cached, checkedAt.timeIntervalSince(cached.at) < cacheLifetime {
                return .snapshot(cached.snapshot)
            }
            return .failed
        }

        guard let json = fetchUsageJSON(accessToken: creds.accessToken) else {
            if let cached, checkedAt.timeIntervalSince(cached.at) < cacheLifetime {
                return .snapshot(cached.snapshot)
            }
            return .failed
        }
        guard let session = window(json, keys: ["five_hour"]) else { return .failed }
        let weekly = window(json, keys: ["seven_day"])
        let fable = scopedWeeklyLimit(json, modelDisplayName: "fable")

        let now = Date()
        let snapshot = Snapshot(
            sessionPercent: session.utilization,
            sessionResetsLabel: relativeLabel(until: session.resetsAt, now: now),
            weeklyPercent: weekly?.utilization ?? 0,
            weeklyResetsLabel: weekly.map { relativeLabel(until: $0.resetsAt, now: now) } ?? "unknown",
            fableWeeklyPercent: fable?.utilization,
            fableWeeklyResetsLabel: fable.map { relativeLabel(until: $0.resetsAt, now: now) },
            fableWeeklyLabel: fable?.label,
            planLabel: planLabel(rateLimitTier: creds.rateLimitTier, subscriptionType: creds.subscriptionType)
        )
        cacheLock.lock()
        lastGood = (snapshot, now)
        cacheLock.unlock()
        return .snapshot(snapshot)
    }

    /// Kept for call sites that only care about the value.
    static func computeSnapshot() -> Snapshot? {
        if case let .snapshot(snap) = computeOutcome() { return snap }
        return nil
    }

    /// Claude Code can leave several credential payloads around at once — the
    /// plaintext file plus a keychain item per account (multiple items share
    /// the "Claude Code-credentials" service name), and any of them can be a
    /// stale leftover from a previous login. Whichever token expires latest
    /// is the one the running CLI is actually using.
    private static func loadCredentials() -> Credentials? {
        var candidates: [Credentials] = []
        if let fromFile = loadCredentialsFromFile() { candidates.append(fromFile) }
        candidates.append(contentsOf: loadAllKeychainCredentials())
        return candidates.max { $0.expiresAt ?? 0 < $1.expiresAt ?? 0 }
    }

    private static func loadCredentialsFromFile() -> Credentials? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        let path = home + "/.claude/.credentials.json"
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return parseCredentials(data)
    }

    // Claude Code stores the OAuth payload in the macOS Keychain under
    // service "Claude Code-credentials" — one item per account, so ask for
    // all of them and let expiry decide below.
    private static func loadAllKeychainCredentials() -> [Credentials] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        guard status == errSecSuccess, let array = items as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            (item[kSecValueData as String] as? Data).flatMap(parseCredentials)
        }
    }

    /// Internal (not private) so tests can pin the stored-credential shape —
    /// the boundary that decides between live, estimate, and failed states.
    static func parseCredentials(_ data: Data) -> Credentials? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        return Credentials(
            accessToken: token,
            rateLimitTier: oauth["rateLimitTier"] as? String,
            subscriptionType: oauth["subscriptionType"] as? String,
            expiresAt: oauth["expiresAt"] as? Double ?? (oauth["expiresAt"] as? Int).map(Double.init)
        )
    }

    private static func window(_ json: [String: Any], keys: [String]) -> (utilization: Double, resetsAt: Date?)? {
        for key in keys {
            guard let obj = json[key] as? [String: Any] else { continue }
            let utilization = (obj["utilization"] as? Double) ?? (obj["utilization"] as? Int).map(Double.init)
            guard let utilization else { continue }
            let resetsAt = (obj["resets_at"] as? String).flatMap(parseDate)
            return (utilization / 100.0, resetsAt)
        }
        return nil
    }

    /// Newer responses carry a `limits` array alongside the legacy top-level
    /// windows. Model-scoped weekly limits (e.g. Fable 5) only appear there:
    /// `{"kind": "weekly_scoped", "percent": 75, "resets_at": ...,
    ///   "scope": {"model": {"display_name": "Fable"}}}`.
    private static func scopedWeeklyLimit(_ json: [String: Any], modelDisplayName: String) -> (utilization: Double, resetsAt: Date?, label: String?)? {
        guard let limits = json["limits"] as? [[String: Any]] else { return nil }
        for limit in limits {
            guard (limit["kind"] as? String) == "weekly_scoped",
                  let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any]
            else { continue }
            // Match on either field, but only ever label the bar with the
            // human-readable one — an id like "claude-fable-5" is not a title.
            let displayName = model["display_name"] as? String
            let name = displayName ?? (model["id"] as? String) ?? ""
            guard name.lowercased().contains(modelDisplayName.lowercased()) else { continue }
            let percent = (limit["percent"] as? Double) ?? (limit["percent"] as? Int).map(Double.init)
            guard let percent else { continue }
            let resetsAt = (limit["resets_at"] as? String).flatMap(parseDate)
            return (percent / 100.0, resetsAt, displayName)
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }

    private static func relativeLabel(until date: Date?, now: Date) -> String {
        guard let date else { return "unknown" }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "now" }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 24 { return "in \(hours / 24)d" }
        if hours >= 1 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes) min"
    }

    // Mirrors the plan-label logic used by community usage trackers: prefer
    // subscriptionType, fall back to rate_limit_tier, and surface the Max
    // usage multiplier (e.g. "default_claude_max_20x" -> "Max 20x") when present.
    private static func planLabel(rateLimitTier: String?, subscriptionType: String?) -> String? {
        let words: (String?) -> [String] = { text in
            (text ?? "").lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }

        func basePlan(_ text: String?) -> String? {
            let w = words(text)
            if w.contains("max") { return "Max" }
            if w.contains("pro") { return "Pro" }
            if w.contains("team") { return "Team" }
            if w.contains("enterprise") { return "Enterprise" }
            if w.contains("ultra") { return "Ultra" }
            return nil
        }

        guard let plan = basePlan(subscriptionType) ?? basePlan(rateLimitTier) else { return nil }

        if plan == "Max" {
            let tierWords = words(rateLimitTier)
            if let maxIndex = tierWords.firstIndex(of: "max"), tierWords.indices.contains(maxIndex + 1) {
                let multiplier = tierWords[maxIndex + 1]
                if multiplier.hasSuffix("x"), Int(multiplier.dropLast()) != nil {
                    return "Max \(multiplier)"
                }
            }
        }
        return plan
    }

    private static func fetchUsageJSON(accessToken: String) -> [String: Any]? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.233", forHTTPHeaderField: "User-Agent")

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 429,
               let retryAfter = http.value(forHTTPHeaderField: "retry-after"),
               let seconds = TimeInterval(retryAfter) {
                // Observed values range from ~200s to ~2250s; clamp sanely.
                let wait = min(max(seconds, 60), 3600)
                cacheLock.lock()
                retryAfterUntil = Date().addingTimeInterval(wait)
                cacheLock.unlock()
                return
            }
            guard http.statusCode == 200, let data else { return }
            cacheLock.lock()
            retryAfterUntil = nil
            cacheLock.unlock()
            result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result
    }
}
