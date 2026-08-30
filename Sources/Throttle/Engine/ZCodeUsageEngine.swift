import Foundation

/// Real usage straight from Z.ai's monitor API — the same endpoint the ZCode
/// app's own usage meter polls. Z.ai meters coding plans in credits over two
/// windows (per docs.z.ai/devpack/overview): a 5-hour rolling window and a
/// weekly window, with tier limits like Pro = 12,000/5h + 60,000/week. The API
/// returns each window already server-computed (percentage + nextResetTime),
/// so no estimation is needed. Authenticated with the coding-plan API key
/// ZCode already saved in ~/.zcode/cli/config.json; nothing is sent anywhere
/// except straight to api.z.ai with your own key.
enum ZCodeUsageEngine {
    struct Snapshot {
        let sessionPercent: Double
        let sessionResetsLabel: String
        let weeklyPercent: Double?
        let weeklyResetsLabel: String?
        let planLevel: String?
    }

    static func computeSnapshot() -> Snapshot? {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return nil }
        guard let data = FileManager.default.contents(atPath: home + "/.zcode/cli/config.json"),
              let key = apiKey(fromConfig: data) else { return nil }
        guard let json = fetchQuotaJSON(apiKey: key) else { return nil }
        return parseQuotaResponse(json)
    }

    /// The coding-plan API key from ZCode's config. The subscription provider
    /// id is fixed ("builtin:zai-coding-plan") — the free/start provider has
    /// no plan windows to meter.
    static func apiKey(fromConfig data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = root["provider"] as? [String: Any],
              let plan = provider["builtin:zai-coding-plan"] as? [String: Any],
              let options = plan["options"] as? [String: Any],
              let key = options["apiKey"] as? String, !key.isEmpty
        else { return nil }
        return key
    }

    /// Maps the quota/limit response to Throttle's windows. The API reports
    /// one entry per plan window; every tier's 5-hour limit is smaller than
    /// its weekly limit (Lite 2k/10k, Pro 12k/60k, Max 28k/140k), so the
    /// smaller-limit entry is the session window and the larger is weekly.
    static func parseQuotaResponse(_ json: [String: Any]) -> Snapshot? {
        guard let data = json["data"] as? [String: Any],
              let limits = (data["limits"] as? [[String: Any]])?.compactMap(Window.init)
        else { return nil }
        guard let session = limits.min(by: { $0.limit < $1.limit }) else { return nil }
        let weekly = limits.count > 1 ? limits.max(by: { $0.limit < $1.limit }) : nil

        let now = Date()
        return Snapshot(
            sessionPercent: session.percent,
            sessionResetsLabel: session.resetLabel(now: now),
            weeklyPercent: weekly?.percent,
            weeklyResetsLabel: weekly.map { $0.resetLabel(now: now) },
            planLevel: data["level"] as? String
        )
    }

    private struct Window {
        let limit: Double
        let percent: Double
        let resetsAt: Date?

        init?(_ obj: [String: Any]) {
            guard let limit = obj["usage"] as? Double ?? (obj["usage"] as? Int).map(Double.init),
                  let percent = obj["percentage"] as? Double ?? (obj["percentage"] as? Int).map(Double.init)
            else { return nil }
            // "usage" is the window's credit limit; "currentValue" the spent
            // amount — the server's "percentage" already encodes the ratio.
            self.limit = limit
            self.percent = percent / 100.0
            self.resetsAt = (obj["nextResetTime"] as? Double ?? (obj["nextResetTime"] as? Int).map(Double.init))
                .map { Date(timeIntervalSince1970: $0 / 1000.0) }
        }

        func resetLabel(now: Date) -> String {
            guard let resetsAt else { return "unknown" }
            let interval = resetsAt.timeIntervalSince(now)
            if interval <= 0 { return "now" }
            let hours = Int(interval / 3600)
            if hours >= 24 { return "in \(hours / 24)d" }
            if hours >= 1 {
                let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
                return "in \(hours)h \(minutes)m"
            }
            return "in \(Int(interval / 60)) min"
        }
    }

    private static func fetchQuotaJSON(apiKey: String) -> [String: Any]? {
        guard let url = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data else { return }
            result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result
    }
}
