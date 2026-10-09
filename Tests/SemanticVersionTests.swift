import Foundation

enum SemanticVersionTests {
    static func run() {
        testParsingAndBuildMetadata()
        testCoreVersionOrdering()
        testOfficialPrereleaseOrdering()
        testInvalidVersionsAreRejected()
    }

    private static func testCoreVersionOrdering() {
        TestSupport.expect(version("1.2.3") < version("1.2.4"), "Patch versions should order numerically")
        TestSupport.expect(version("1.2.9") < version("1.3.0"), "Minor versions should order numerically")
        TestSupport.expect(version("1.9.9") < version("2.0.0"), "Major versions should order numerically")
    }

    private static func testParsingAndBuildMetadata() {
        TestSupport.expectEqual(version(" v1.2.3 "), version("V1.2.3"))
        TestSupport.expectEqual(version("1.2.3+build.1"), version("1.2.3+build.2"))
        TestSupport.expect(version("1.2.3-alpha") < version("1.2.3"), "Prereleases must sort before stable releases")
        TestSupport.expect(version("1.2.3-1") < version("1.2.3-alpha"), "Numeric identifiers must sort before alphanumeric identifiers")
        TestSupport.expect(version("1.2.3-alpha") < version("1.2.3-alpha.1"), "A shorter matching prerelease must sort first")
    }

    private static func testOfficialPrereleaseOrdering() {
        let ordered = [
            "1.0.0-alpha",
            "1.0.0-alpha.1",
            "1.0.0-alpha.beta",
            "1.0.0-beta",
            "1.0.0-beta.2",
            "1.0.0-beta.11",
            "1.0.0-rc.1",
            "1.0.0"
        ].map(version)

        for index in 0..<(ordered.count - 1) {
            TestSupport.expect(
                ordered[index] < ordered[index + 1],
                "Expected semantic version at index \(index) to sort before the next version"
            )
        }
    }

    private static func testInvalidVersionsAreRejected() {
        let invalid = ["", "1.2", "1.2.3.4", "one.2.3", "1.2.3-", "1.2.3-alpha..1"]
        for value in invalid {
            TestSupport.expectEqual(SemanticVersion(value), nil)
        }
    }

    private static func version(_ value: String) -> SemanticVersion {
        guard let parsed = SemanticVersion(value) else {
            fatalError("Expected valid semantic version: \(value)")
        }
        return parsed
    }
}
