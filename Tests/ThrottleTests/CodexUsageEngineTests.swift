import XCTest
@testable import Throttle

final class CodexUsageEngineTests: XCTestCase {
    func testMapsWeeklyOnlyAccountLimitIntoWeeklyWindow() {
        let json = """
        {
          "id": 1,
          "result": {
            "rateLimits": {
              "limitId": "codex",
              "planType": "pro",
              "primary": {
                "usedPercent": 12,
                "windowDurationMins": 10080,
                "resetsAt": 1700604800
              },
              "secondary": null
            }
          }
        }
        """

        let snapshot = CodexUsageEngine.parseRateLimitsResponse(
            Data(json.utf8),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.primaryPercent ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(snapshot?.secondaryPercent ?? -1, 0.12, accuracy: 0.001)
        XCTAssertEqual(snapshot?.secondaryResetsLabel, "in 7d")
        XCTAssertEqual(snapshot?.planType, "pro")
    }
}
