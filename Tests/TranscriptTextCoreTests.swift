import Foundation

enum TranscriptTextCoreTests {
    static func run() {
        testJSONTranscriptParsing()
        testNonTranscriptJSONFallsBackToUTF8()
        testInvalidTranscriptResponses()
        testHighConfidenceHallucinationsAreSuppressed()
        testPossibleRealSpeechIsPreserved()
        testSubtitleCreditMatcherRecognizesKnownCredits()
        testSubtitleCreditMatcherRejectsLegitimateDictation()
        testSubtitleCreditHallucinationsAreSuppressed()
        testSubtitleCreditsArePreservedWithoutNoSpeechEvidence()
        testEdgeSubtitleCreditSegmentsAreStripped()
        testEdgeSubtitleCreditStrippingIsConservative()
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
        expectInvalidResponse(Data())
        expectInvalidResponse(Data(" \n\t ".utf8))
        expectInvalidResponse(Data("{malformed synthetic JSON".utf8))
        expectInvalidResponse(Data([0xFF, 0xFE]))
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

    private static func testSubtitleCreditMatcherRecognizesKnownCredits() {
        let credits = [
            "Subtitles by the Amara.org community",
            "subtitles BY the amara.org Community!",
            "  Subtitles by the Amara.org community.  ",
            "Untertitel im Auftrag des ZDF, 2017",
            "Untertitel im Auftrag des ZDF für funk, 2017",
            "UNTERTITEL IM AUFTRAG DES ZDF FUR FUNK",
            "Untertitelung des ZDF, 2020",
            "Untertitel der Amara.org-Community",
            "Sous-titres réalisés par la communauté d'Amara.org",
            "Sous-titres realises para la communaute d’Amara.org",
            "Sous-titrage Société Radio-Canada",
            "Subtítulos realizados por la comunidad de Amara.org",
            "Subtitulos por la comunidad de Amara.org",
            "Sottotitoli creati dalla comunità Amara.org",
            "Sottotitoli e revisione a cura di QTSS",
            "Legendas pela comunidade Amara.org",
            "Ondertitels ingediend door de Amara.org gemeenschap",
            "Napisy stworzone przez społeczność Amara.org",
            "Undertekster av Ai-Media",
            "Altyazı M.K.",
            "Субтитры сделал DimaTorzok",
            "Субтитры создавал DimaTorzok.",
            "字幕by索兰娅",
            "字幕由Amara.org社区提供",
            "ترجمة نانسي قنقر"
        ]
        for credit in credits {
            TestSupport.expect(
                SubtitleCreditMatcher.isSubtitleCredit(credit),
                "Expected subtitle credit to match: \(credit)"
            )
        }
    }

    private static func testSubtitleCreditMatcherRejectsLegitimateDictation() {
        let dictation = [
            "",
            "   ",
            "Subtitles",
            "Add subtitles by tomorrow",
            "Subtitles by Friday",
            "Subtitles by the Amara.org community are great",
            "Can you add subtitles by the Amara.org community deadline?",
            "I volunteer with the Amara.org community",
            "Amara.org",
            "Check the subtitles on the synthetic launch video.",
            "Untertitel bitte bis morgen hinzufügen",
            "Untertitel im Auftrag des Kunden",
            "Untertitel im Auftrag des ZDF sind fertig",
            "Sous-titres pour la vidéo de demain",
            "Subtítulos para el video sintético",
            "Sottotitoli per la riunione",
            "Legendas para o vídeo",
            "Napisy do filmu",
            "Undertekster til videoen",
            "Субтитры для видео",
            "字幕",
            "Thanks to the credits team",
            "Untertitel im Auftrag des ZDF 17",
            "Untertitel im Auftrag des ZDF 3017",
            "Subtitles by the Amara.org community 2017 edition"
        ]
        for text in dictation {
            TestSupport.expect(
                !SubtitleCreditMatcher.isSubtitleCredit(text),
                "Expected legitimate dictation not to match: \(text)"
            )
        }
    }

    private static func testSubtitleCreditHallucinationsAreSuppressed() {
        for credit in [
            "Subtitles by the Amara.org community",
            "Untertitel im Auftrag des ZDF, 2021",
            "Sous-titres réalisés para la communauté d'Amara.org",
            "Субтитры сделал DimaTorzok"
        ] {
            let data = jsonData([
                "text": credit,
                "segments": [["text": credit, "no_speech_prob": 0.6]]
            ])
            TestSupport.expectEqual(try? TranscriptionResponseParser.parse(data), "")
        }

        let atThreshold = jsonData([
            "text": "Undertekster av Ai-Media",
            "segments": [["no_speech_prob": 0.1]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(atThreshold), "")
    }

    private static func testSubtitleCreditsArePreservedWithoutNoSpeechEvidence() {
        let credit = "Subtitles by the Amara.org community"

        let lowProbability = jsonData([
            "text": credit,
            "segments": [["text": credit, "no_speech_prob": 0.099]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(lowProbability), credit)

        let missingMetadata = jsonData(["text": credit])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingMetadata), credit)

        let missingProbability = jsonData([
            "text": credit,
            "segments": [["text": credit]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(missingProbability), credit)

        let shortRequest = "Add subtitles by tomorrow."
        let shortRequestData = jsonData([
            "text": shortRequest,
            "segments": [["text": shortRequest, "no_speech_prob": 0.9]]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(shortRequestData), shortRequest)
    }

    private static func testEdgeSubtitleCreditSegmentsAreStripped() {
        let trailing = jsonData([
            "text": " Synthetic project update. Subtitles by the Amara.org community",
            "segments": [
                ["text": " Synthetic project update.", "no_speech_prob": 0.02],
                ["text": " Subtitles by the Amara.org community", "no_speech_prob": 0.7]
            ]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(trailing),
            "Synthetic project update."
        )

        let leading = jsonData([
            "text": "Untertitel im Auftrag des ZDF, 2017. Synthetischer Bericht.",
            "segments": [
                ["text": "Untertitel im Auftrag des ZDF, 2017.", "no_speech_prob": 0.5],
                ["text": " Synthetischer Bericht.", "no_speech_prob": 0.01]
            ]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(leading),
            "Synthetischer Bericht."
        )

        let bothEdges = jsonData([
            "text": "Субтитры сделал DimaTorzok Синтетический текст. Субтитры создавал DimaTorzok",
            "segments": [
                ["text": "Субтитры сделал DimaTorzok", "no_speech_prob": 0.4],
                ["text": " Синтетический текст.", "no_speech_prob": 0.03],
                ["text": " Субтитры создавал DimaTorzok", "no_speech_prob": 0.4]
            ]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(bothEdges),
            "Синтетический текст."
        )

        let onlyCredits = jsonData([
            "text": "Synthetic note. Subtitles by the Amara.org community",
            "segments": [
                ["text": "Synthetic note.", "no_speech_prob": 0.05],
                ["text": " Subtitles by the Amara.org community", "no_speech_prob": 0.05]
            ]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(onlyCredits),
            "Synthetic note. Subtitles by the Amara.org community"
        )
    }

    private static func testEdgeSubtitleCreditStrippingIsConservative() {
        let interior = "Synthetic intro. Subtitles by the Amara.org community Synthetic outro."
        let interiorData = jsonData([
            "text": interior,
            "segments": [
                ["text": "Synthetic intro.", "no_speech_prob": 0.01],
                ["text": " Subtitles by the Amara.org community", "no_speech_prob": 0.8],
                ["text": " Synthetic outro.", "no_speech_prob": 0.01]
            ]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(interiorData), interior)

        let mentionsSubtitles = "Synthetic update. Add subtitles by Friday."
        let mentionsData = jsonData([
            "text": mentionsSubtitles,
            "segments": [
                ["text": "Synthetic update.", "no_speech_prob": 0.01],
                ["text": " Add subtitles by Friday.", "no_speech_prob": 0.9]
            ]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(mentionsData), mentionsSubtitles)

        let missingSegmentProbability = "Synthetic update. Subtitles by the Amara.org community"
        let missingProbabilityData = jsonData([
            "text": missingSegmentProbability,
            "segments": [
                ["text": "Synthetic update.", "no_speech_prob": 0.01],
                ["text": " Subtitles by the Amara.org community"]
            ]
        ])
        TestSupport.expectEqual(
            try? TranscriptionResponseParser.parse(missingProbabilityData),
            missingSegmentProbability
        )

        let segmentTextMismatch = "Synthetic update, Amara edition."
        let mismatchData = jsonData([
            "text": segmentTextMismatch,
            "segments": [
                ["text": "Synthetic update.", "no_speech_prob": 0.01],
                ["text": " Subtitles by the Amara.org community", "no_speech_prob": 0.9]
            ]
        ])
        TestSupport.expectEqual(try? TranscriptionResponseParser.parse(mismatchData), segmentTextMismatch)
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

    private static func expectInvalidResponse(
        _ data: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            _ = try TranscriptionResponseParser.parse(data)
            TestSupport.expect(false, "Expected invalid response error", file: file, line: line)
        } catch let error as TranscriptionResponseParsingError {
            TestSupport.expectEqual(error, .invalidResponse, file: file, line: line)
        } catch {
            TestSupport.expect(
                false,
                "Expected TranscriptionResponseParsingError, got \(error)",
                file: file,
                line: line
            )
        }
    }
}
