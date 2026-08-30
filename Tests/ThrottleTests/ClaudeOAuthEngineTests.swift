import XCTest
@testable import Throttle

/// Pins the stored-credential shape Claude Code writes — the boundary that
/// decides whether Throttle shows live numbers, an estimate, or an honest
/// "couldn't reach Anthropic" note instead of a guessed figure.
final class ClaudeOAuthEngineTests: XCTestCase {
    func testParsesClaudeAiOauthPayloadFromFileShape() {
        let json = """
        {"claudeAiOauth":{"accessToken":"tok-1","refreshToken":"r-1",
        "expiresAt":1787639935491,"rateLimitTier":"default_claude_max_20x",
        "subscriptionType":"claude_code_max"}}
        """
        let creds = ClaudeOAuthEngine.parseCredentials(Data(json.utf8))

        XCTAssertNotNil(creds)
        XCTAssertEqual(creds?.accessToken, "tok-1")
        XCTAssertEqual(creds?.rateLimitTier, "default_claude_max_20x")
        XCTAssertEqual(creds?.subscriptionType, "claude_code_max")
        XCTAssertEqual(creds?.expiresAt, 1_787_639_935_491)
    }

    func testRejectsForeignOrTokenlessPayloads() {
        // Keychain item shape from other versions: OAuth present but no token.
        let mcpOnly = """
        {"mcpOAuth":{"plugin:x:y":{"accessToken":"t"}}}
        """
        XCTAssertNil(ClaudeOAuthEngine.parseCredentials(Data(mcpOnly.utf8)))
        XCTAssertNil(ClaudeOAuthEngine.parseCredentials(Data("{}".utf8)))
        XCTAssertNil(ClaudeOAuthEngine.parseCredentials(Data("not json".utf8)))
        let emptyToken = """
        {"claudeAiOauth":{"accessToken":""}}
        """
        XCTAssertNil(ClaudeOAuthEngine.parseCredentials(Data(emptyToken.utf8)))
    }
}
