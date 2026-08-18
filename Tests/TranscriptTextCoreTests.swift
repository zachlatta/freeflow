import Foundation

enum TranscriptTextCoreTests {
    static func run() {
        testJSONTranscriptParsing()
        testNonTranscriptJSONFallsBackToUTF8()
        testInvalidTranscriptResponses()
        testHighConfidenceHallucinationsAreSuppressed()
        testPossibleRealSpeechIsPreserved()
        testPostProcessedTranscriptSanitization()
        testModeSpecificSanitization()
        testInstructionExecutionGuard()
    }

    private static func testJSONTranscriptParsing() {
        let data = jsonData(["text": "Synthetic transcript."])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(data),
            "Synthetic transcript."
        )

        let emptyData = jsonData(["text": ""])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(emptyData), "")
    }

    private static func testNonTranscriptJSONFallsBackToUTF8() {
        let data = Data("{\n  \"synthetic\": \"fallback\"\n}".utf8)
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(data),
            "{   \"synthetic\": \"fallback\" }"
        )
    }

    private static func testInvalidTranscriptResponses() {
        expectParsingFailure(Data())
        expectParsingFailure(Data(" \n\t ".utf8))
        expectParsingFailure(Data("{malformed synthetic JSON".utf8))
        expectParsingFailure(Data([0xFF, 0xFE]))
    }

    private static func testHighConfidenceHallucinationsAreSuppressed() {
        let atThreshold = jsonData([
            "text": "Thank you.",
            "segments": [["no_speech_prob": 0.1]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(atThreshold), "")

        let normalizedPhrase = jsonData([
            "text": "  THANK YOU FOR WATCHING!!!  ",
            "segments": [["no_speech_prob": 0.9]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(normalizedPhrase), "")
    }

    private static func testPossibleRealSpeechIsPreserved() {
        let lowProbability = jsonData([
            "text": "Thank you.",
            "segments": [["no_speech_prob": 0.099]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(lowProbability), "Thank you.")

        let missingMetadata = jsonData(["text": "Thank you."])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingMetadata), "Thank you.")

        let missingProbability = jsonData([
            "text": "Thank you.",
            "segments": [["synthetic": true]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingProbability), "Thank you.")

        let unrelatedSpeech = jsonData([
            "text": "Synthetic project update.",
            "segments": [["no_speech_prob": 0.95]]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(unrelatedSpeech),
            "Synthetic project update."
        )
    }

    private static func testPostProcessedTranscriptSanitization() {
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.postProcessedTranscript("  \"Synthetic output.\" \n"),
            "Synthetic output."
        )
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("EMPTY"), "")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("\"EMPTY\""), "")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("empty"), "empty")
        TestSupport.expectEqual(TranscriptOutputSanitizer.postProcessedTranscript("  \n "), "")
    }

    private static func testModeSpecificSanitization() {
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.verbatimTranslation("  \"EMPTY\"  "),
            "EMPTY"
        )
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.verbatimTranslation(" \"Literal synthetic text.\" "),
            "Literal synthetic text."
        )
        TestSupport.expectEqual(
            TranscriptOutputSanitizer.commandModeTranscript("  \"Keep command quotes\" \n"),
            "\"Keep command quotes\""
        )
    }

    private static func testInstructionExecutionGuard() {
        TestSupport.expect(
            TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write an email asking Alex for the synthetic report.",
                cleanedTranscript: "Sure, here's a draft: Hello Alex, please send the report.",
                outputLanguage: ""
            ),
            "Assistant-style execution should be rejected"
        )
        TestSupport.expect(
            TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write a haiku about synthetic rain.",
                cleanedTranscript: "Soft drizzle taps windows.",
                outputLanguage: ""
            ),
            "Low-overlap instruction execution should be rejected"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Write an email asking Alex for the synthetic report.",
                cleanedTranscript: "Write an email asking Alex for the synthetic report.",
                outputLanguage: ""
            ),
            "Faithful cleanup should preserve instruction wording"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "The synthetic launch is Friday.",
                cleanedTranscript: "Sure, the synthetic launch is Friday.",
                outputLanguage: ""
            ),
            "Ordinary speech without an instruction marker should not trigger the guard"
        )
        TestSupport.expect(
            !TranscriptOutputSanitizer.appearsToHaveExecutedInstruction(
                rawTranscript: "Translate the synthetic update.",
                cleanedTranscript: "Aggiornamento sintetico.",
                outputLanguage: "Italian"
            ),
            "Explicit translation output should bypass the instruction guard"
        )
    }

    private static func jsonData(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            fatalError("Synthetic JSON fixture should be serializable")
        }
        return data
    }

    private static func expectParsingFailure(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try TranscriptionResponseParser.parse(data)
            TestSupport.expect(false, "Expected response parsing to fail", file: file, line: line)
        } catch {
            return
        }
    }
}
