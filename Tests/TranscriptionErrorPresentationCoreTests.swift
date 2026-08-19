import Foundation

enum TranscriptionErrorPresentationCoreTests {
    static func run() {
        testConnectionLostOffersRetryAndNetworkGuidance()
        testOfflineFailuresRemainClassifiedAsNoInternet()
    }

    private static func testConnectionLostOffersRetryAndNetworkGuidance() {
        TestSupport.expectEqual(
            TranscriptionErrorPresentationCore.message(
                for: URLError(.networkConnectionLost),
                isOnline: true
            ),
            "Connection lost — retry or try another network"
        )
    }

    private static func testOfflineFailuresRemainClassifiedAsNoInternet() {
        let offlineCodes: [URLError.Code] = [
            .notConnectedToInternet,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed
        ]

        for code in offlineCodes {
            TestSupport.expectEqual(
                TranscriptionErrorPresentationCore.message(
                    for: URLError(code),
                    isOnline: true
                ),
                "No internet — check connection"
            )
        }
    }
}
