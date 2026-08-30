import XCTest
@testable import Throttle

final class UsagePresentationTests: XCTestCase {
    func testHeadlinePrefersActiveSessionOverHigherScopedWeeklyLimit() {
        let usage = ToolUsage(
            tool: .claude,
            sessionPercent: 0.34,
            sessionResetsLabel: "in 1h",
            weeklyPercent: 0.32,
            weeklyResetsLabel: "in 4d",
            fableWeeklyPercent: 0.43,
            available: true,
            note: nil
        )

        XCTAssertEqual(usage.headlinePercent ?? -1, 0.34, accuracy: 0.001)
    }

    func testHeadlineFallsBackToWeeklyWhenSessionIsZero() {
        let usage = ToolUsage(
            tool: .codex,
            sessionPercent: 0,
            sessionResetsLabel: "unknown",
            weeklyPercent: 0.12,
            weeklyResetsLabel: "in 7d",
            available: true,
            note: nil
        )

        XCTAssertEqual(usage.headlinePercent ?? -1, 0.12, accuracy: 0.001)
    }
}
