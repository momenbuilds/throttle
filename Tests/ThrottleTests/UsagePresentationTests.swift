import AppKit
import SwiftUI
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

    func testStatusColorsUseFourUrgencyBands() {
        assertColor(StatusColor.forPercent(0.49), equals: (0.30, 0.85, 0.45))
        assertColor(StatusColor.forPercent(0.50), equals: (0.98, 0.80, 0.20))
        assertColor(StatusColor.forPercent(0.75), equals: (0.98, 0.48, 0.16))
        assertColor(StatusColor.forPercent(0.90), equals: (0.95, 0.20, 0.24))
    }

    private func assertColor(
        _ color: Color,
        equals expected: (red: CGFloat, green: CGFloat, blue: CGFloat),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let resolved = NSColor(color).usingColorSpace(.sRGB) else {
            XCTFail("Color did not resolve in sRGB", file: file, line: line)
            return
        }
        XCTAssertEqual(resolved.redComponent, expected.red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolved.greenComponent, expected.green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(resolved.blueComponent, expected.blue, accuracy: 0.01, file: file, line: line)
    }
}
