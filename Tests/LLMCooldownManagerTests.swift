import Foundation

enum LLMCooldownManagerTests {
    static func run() {
        testDailyQuotaTakesPriority()
        testRetryAndTokenDurations()
        testMalformedDurationsUseSafeFallback()
        testPersistenceKeyIsStable()
    }

    private static func testDailyQuotaTakesPriority() {
        let result = cooldown(headers: [
            "x-ratelimit-remaining-requests": "0",
            "x-ratelimit-reset-requests": "2m59.56s",
            "retry-after": "2"
        ])
        TestSupport.expectApproximatelyEqual(result.seconds, 179.56)
        TestSupport.expectEqual(result.isDaily, true)

        let nonExhausted = cooldown(headers: [
            "x-ratelimit-remaining-requests": "1",
            "x-ratelimit-reset-requests": "1h",
            "retry-after": "7.66"
        ])
        TestSupport.expectApproximatelyEqual(nonExhausted.seconds, 7.66)
        TestSupport.expectEqual(nonExhausted.isDaily, false)
    }

    private static func testRetryAndTokenDurations() {
        TestSupport.expectApproximatelyEqual(cooldown(headers: ["retry-after": "120ms"]).seconds, 0.12)
        TestSupport.expectApproximatelyEqual(cooldown(headers: ["retry-after": "1h2m3.5s"]).seconds, 3723.5)
        TestSupport.expectApproximatelyEqual(
            cooldown(headers: ["x-ratelimit-reset-tokens": "8.25s"]).seconds,
            8.25
        )
    }

    private static func testMalformedDurationsUseSafeFallback() {
        for invalid in ["-3", "nan", "inf", "1d", "1h30", ""] {
            let result = cooldown(headers: ["retry-after": invalid])
            TestSupport.expectApproximatelyEqual(result.seconds, 60)
            TestSupport.expectEqual(result.isDaily, false)
        }
    }

    private static func testPersistenceKeyIsStable() {
        TestSupport.expectEqual(
            LLMCooldownManager.udKey(for: "openai/gpt-oss-20b"),
            "llm_cooldown_expiry_openai/gpt-oss-20b"
        )
    }

    private static func cooldown(headers: [String: String]) -> (seconds: TimeInterval, isDaily: Bool) {
        guard let response = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: headers
        ) else {
            fatalError("Could not create test HTTP response")
        }
        return LLMCooldownManager.rateLimitCooldown(from: response)
    }
}
