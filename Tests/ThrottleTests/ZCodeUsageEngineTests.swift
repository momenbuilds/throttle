import XCTest
@testable import Throttle

/// ZCodeUsageEngine's contract with Z.ai's quota/limit monitor API — the same
/// endpoint the ZCode app's own usage meter polls. Fixtures are recorded
/// response shapes; the network fetch itself stays thin and untested, mirroring
/// the repo's other engines.
final class ZCodeUsageEngineTests: XCTestCase {
    /// Recorded live response (Pro plan): a 5-hour window and a weekly window.
    /// "usage" is the tier's credit limit, "percentage" is server-computed.
    private func quotaJSON(sessionPct: Int, weeklyPct: Int) -> [String: Any] {
        [
            "code": 200, "msg": "ok", "success": true,
            "data": [
                "level": "pro",
                "limits": [
                    [
                        "type": "CREDIT_LIMIT", "unit": 3, "number": 5,
                        "usage": 12000, "currentValue": 12000 * sessionPct / 100,
                        "remaining": 12000 - 12000 * sessionPct / 100,
                        "percentage": sessionPct,
                        "nextResetTime": 1_788_043_855_598,
                    ],
                    [
                        "type": "CREDIT_LIMIT", "unit": 6, "number": 1,
                        "usage": 60000, "currentValue": 60000 * weeklyPct / 100,
                        "remaining": 60000 - 60000 * weeklyPct / 100,
                        "percentage": weeklyPct,
                        "nextResetTime": 1_788_042_012_994,
                    ],
                ] as [[String: Any]],
            ] as [String: Any],
        ] as [String: Any]
    }

    func testTwoWindowsMapToSessionAndWeeklyWithPlanLevel() {
        let snapshot = ZCodeUsageEngine.parseQuotaResponse(quotaJSON(sessionPct: 31, weeklyPct: 74))

        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.sessionPercent ?? 0, 0.31, accuracy: 0.001)
        XCTAssertEqual(snapshot?.weeklyPercent ?? 0, 0.74, accuracy: 0.001)
        XCTAssertEqual(snapshot?.planLevel, "pro")
        // nextResetTime values are in the past relative to the test run's
        // clock, so the rolling-window labels clamp to "now".
        XCTAssertEqual(snapshot?.sessionResetsLabel, "now")
        XCTAssertEqual(snapshot?.weeklyResetsLabel, "now")
    }

    func testSingleWindowMapsToSessionOnly() {
        var json = quotaJSON(sessionPct: 50, weeklyPct: 50)
        var data = json["data"] as! [String: Any]
        let limits = data["limits"] as! [[String: Any]]
        data["limits"] = [limits[0]]
        json["data"] = data

        let snapshot = ZCodeUsageEngine.parseQuotaResponse(json)

        XCTAssertEqual(snapshot?.sessionPercent ?? 0, 0.5, accuracy: 0.001)
        XCTAssertNil(snapshot?.weeklyPercent)
    }

    func testMalformedInputYieldsNil() {
        XCTAssertNil(ZCodeUsageEngine.parseQuotaResponse(["unexpected": true]))
        XCTAssertNil(ZCodeUsageEngine.parseQuotaResponse(["data": ["limits": []]] as [String: Any]))
        // No coding-plan provider configured -> no key -> engine stays nil.
        XCTAssertNil(ZCodeUsageEngine.apiKey(fromConfig: Data("{}".utf8)))
        let otherProviderOnly = Data(#"{"provider":{"builtin:zai-start-plan":{"options":{"apiKey":"sk-x"}}}}"#.utf8)
        XCTAssertNil(ZCodeUsageEngine.apiKey(fromConfig: otherProviderOnly))
    }
}
