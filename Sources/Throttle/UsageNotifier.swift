import Foundation
import UserNotifications

/// Fires a local notification the first time a session/weekly window crosses
/// 90% used, so you find out before you actually hit the rate limit instead
/// of after. Each window only notifies once per crossing — it resets once
/// usage drops back under the threshold (e.g. a session/weekly reset).
enum UsageNotifier {
    private static let threshold = 0.9
    private static var armed: [String: Bool] = [:]

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func checkThresholds(items: [ToolUsage], enabled: Bool) {
        guard enabled else { return }
        for item in items {
            guard item.available else { continue }
            check(tool: item.tool, window: "session", label: "Current session", percent: item.sessionPercent)
            check(tool: item.tool, window: "weekly", label: "Weekly", percent: item.weeklyPercent)
            check(tool: item.tool, window: "fable-weekly", label: "Fable 5 weekly", percent: item.fableWeeklyPercent)
        }
    }

    private static func check(tool: ToolUsage.Tool, window: String, label: String, percent: Double?) {
        let key = "\(tool.rawValue)-\(window)"
        guard let percent else { return }

        guard percent >= threshold else {
            armed[key] = true // usage dropped (reset) — ready to notify again next time it climbs
            return
        }

        guard armed[key] != false else { return }
        armed[key] = false

        let content = UNMutableNotificationContent()
        content.title = "\(tool.rawValue) usage is high"
        content.body = "\(label) at \(Int(percent * 100))% used"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(key)-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
