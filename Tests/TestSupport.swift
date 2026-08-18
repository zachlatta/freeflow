import Foundation

enum TestSupport {
    static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError("\(file):\(line): \(message)")
        }
    }

    static func expectEqual<T: Equatable>(
        _ actual: @autoclosure () -> T,
        _ expected: @autoclosure () -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualValue = actual()
        let expectedValue = expected()
        expect(
            actualValue == expectedValue,
            "Expected \(String(describing: expectedValue)), got \(String(describing: actualValue))",
            file: file,
            line: line
        )
    }

    static func expectApproximatelyEqual(
        _ actual: Double,
        _ expected: Double,
        accuracy: Double = 0.000_001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        expect(
            abs(actual - expected) <= accuracy,
            "Expected \(expected) ± \(accuracy), got \(actual)",
            file: file,
            line: line
        )
    }
}
