import Foundation

enum TranscriptCorrectionCoreTests {
    static func run() {
        testParsingArrowsVariantsAndComments()
        testParsingIgnoresMalformedLines()
        testEmptyRulesLeaveTextUnchanged()
        testWholeWordMatching()
        testCaseInsensitiveMatchingAndCaseHandling()
        testLongestMatchWins()
        testNoCascadingReplacements()
        testFirstDuplicateRuleWins()
        testLiteralReplacementText()
        testRegexMetacharactersInHeardForm()
        testWhitespaceInsideHeardForm()
        testUnicodeBoundariesAndCombiningMarks()
        testPunctuationAndPossessiveBoundaries()
        testVocabularyHints()
    }

    private static func apply(_ text: String, _ rules: String) -> String {
        TranscriptCorrector(rulesText: rules).apply(text)
    }

    private static func testParsingArrowsVariantsAndComments() {
        let result = TranscriptCorrectionParser.parse("""
        # synthetic comment
        cloud code | clod  code -> Claude Code

        next message => nextMessage
        alpha => beta -> gamma
        """)
        TestSupport.expectEqual(result.invalidLineCount, 0)
        TestSupport.expectEqual(result.rules, [
            TranscriptCorrectionRule(heardForms: ["cloud code", "clod code"], replacement: "Claude Code"),
            TranscriptCorrectionRule(heardForms: ["next message"], replacement: "nextMessage"),
            TranscriptCorrectionRule(heardForms: ["alpha"], replacement: "beta -> gamma"),
        ])
    }

    private static func testParsingIgnoresMalformedLines() {
        let result = TranscriptCorrectionParser.parse("""
        plain vocabulary term
        -> Orphan Replacement
        heard form ->
        | | -> Empty Variants
        ... -> Punctuation Only
        valid | -> Valid
        """)
        TestSupport.expectEqual(result.invalidLineCount, 5)
        TestSupport.expectEqual(result.rules, [
            TranscriptCorrectionRule(heardForms: ["valid"], replacement: "Valid"),
        ])
        TestSupport.expectEqual(TranscriptCorrectionParser.parse("").rules, [])
        TestSupport.expectEqual(TranscriptCorrectionParser.parse(" \n\n ").invalidLineCount, 0)
    }

    private static func testEmptyRulesLeaveTextUnchanged() {
        TestSupport.expect(TranscriptCorrector(rulesText: "").isEmpty, "empty rules")
        TestSupport.expectEqual(apply("Synthetic text stays.", ""), "Synthetic text stays.")
        TestSupport.expectEqual(apply("", "foo -> bar"), "")
        TestSupport.expectEqual(apply("No match here.", "zebra -> Quokka"), "No match here.")
    }

    private static func testWholeWordMatching() {
        let rules = "cat -> Dog"
        TestSupport.expectEqual(apply("cat category concat cat.", rules), "Dog category concat Dog.")
        TestSupport.expectEqual(apply("cat2 2cat cat", rules), "cat2 2cat Dog")
        TestSupport.expectEqual(apply("(cat)", rules), "(Dog)")
    }

    private static func testCaseInsensitiveMatchingAndCaseHandling() {
        // Replacement with capitals is verbatim regardless of matched casing.
        let verbatim = "cloud code -> Claude Code"
        TestSupport.expectEqual(apply("cloud code", verbatim), "Claude Code")
        TestSupport.expectEqual(apply("CLOUD CODE", verbatim), "Claude Code")
        TestSupport.expectEqual(apply("Cloud Code", verbatim), "Claude Code")

        // Lowercase replacement follows the casing of the match.
        let adaptive = "gonna -> going to"
        TestSupport.expectEqual(apply("we gonna win", adaptive), "we going to win")
        TestSupport.expectEqual(apply("Gonna win", adaptive), "Going to win")
        TestSupport.expectEqual(apply("GONNA WIN", adaptive), "GOING TO WIN")

        // A one-letter capital is treated as capitalized, not all caps.
        TestSupport.expectEqual(apply("I said", "i -> me too"), "Me too said")

        // camelCase and mixed-case replacements stay verbatim.
        TestSupport.expectEqual(apply("Next message", "next message -> nextMessage"), "nextMessage")
    }

    private static func testLongestMatchWins() {
        let rules = """
        new -> Fresh
        new york -> New York
        new york city -> NYC
        """
        TestSupport.expectEqual(apply("new york city and new york and new", rules), "NYC and New York and Fresh")

        // Rule order does not change the outcome.
        let reversed = """
        new york city -> NYC
        new -> Fresh
        """
        TestSupport.expectEqual(apply("new york city, new", reversed), "NYC, Fresh")
    }

    private static func testNoCascadingReplacements() {
        let rules = """
        alpha -> beta
        beta -> gamma
        """
        TestSupport.expectEqual(apply("alpha beta", rules), "beta gamma")

        // A replacement that contains its own heard form is not re-scanned.
        TestSupport.expectEqual(apply("echo", "echo -> echo echo"), "echo echo")
        TestSupport.expectEqual(apply("swap one two", "one -> two\ntwo -> one"), "swap two one")
    }

    private static func testFirstDuplicateRuleWins() {
        let rules = """
        widget -> Gadget
        WIDGET -> Gizmo
        """
        TestSupport.expectEqual(apply("widget", rules), "Gadget")
    }

    private static func testLiteralReplacementText() {
        TestSupport.expectEqual(apply("price tag", "price tag -> $1 \\0 \\n $"), "$1 \\0 \\n $")
        TestSupport.expectEqual(apply("pay", "pay -> $&"), "$&")
    }

    private static func testRegexMetacharactersInHeardForm() {
        TestSupport.expectEqual(apply("use c++ now", "c++ -> C plus plus"), "use C plus plus now")
        TestSupport.expectEqual(apply("a.b axb", "a.b -> Dot"), "Dot axb")
        TestSupport.expectEqual(apply("(x) (y)", "(x) -> Ex"), "Ex (y)")
        TestSupport.expectEqual(apply("v1.2 v1x2", "v1.2 -> Version Twelve"), "Version Twelve v1x2")
    }

    private static func testWhitespaceInsideHeardForm() {
        TestSupport.expectEqual(apply("next   message\nnext\tmessage", "next message -> nextMessage"), "nextMessage\nnextMessage")
        TestSupport.expectEqual(apply("nextmessage", "next message -> nextMessage"), "nextmessage")
    }

    private static func testUnicodeBoundariesAndCombiningMarks() {
        // Letters outside ASCII are word characters.
        TestSupport.expectEqual(apply("café cafés", "café -> Coffee"), "Coffee cafés")
        TestSupport.expectEqual(apply("über überall", "über -> Over"), "Over überall")
        TestSupport.expectEqual(apply("Straße", "straße -> Street"), "Street")

        // A trailing combining mark keeps the word intact.
        let decomposed = "cafe\u{0301} cafe"
        TestSupport.expectEqual(apply(decomposed, "cafe -> Shop"), "café Shop")

        // Precomposed and decomposed forms match each other.
        TestSupport.expectEqual(apply("cafe\u{0301}", "caf\u{00E9} -> Coffee"), "Coffee")
        TestSupport.expectEqual(apply("caf\u{00E9}", "cafe\u{0301} -> Coffee"), "Coffee")

        // Non-Latin scripts and digits.
        TestSupport.expectEqual(apply("привет приветствие", "привет -> Hello"), "Hello приветствие")
        TestSupport.expectEqual(apply("item٣ item", "item -> Thing"), "item٣ Thing")

        // Emoji and supplementary-plane neighbours.
        TestSupport.expectEqual(apply("🎉cat🎉", "cat -> Dog"), "🎉Dog🎉")
        TestSupport.expectEqual(apply("𐐨cat cat", "cat -> Dog"), "𐐨cat Dog")
    }

    private static func testPunctuationAndPossessiveBoundaries() {
        let rules = "cloud code -> Claude Code"
        TestSupport.expectEqual(apply("cloud code's docs", rules), "Claude Code's docs")
        TestSupport.expectEqual(apply("\"cloud code\", again", rules), "\"Claude Code\", again")
        TestSupport.expectEqual(apply("re-cloud code", rules), "re-Claude Code")
        TestSupport.expectEqual(apply("cloud_code", "cloud -> Sky"), "Sky_code")
    }

    private static func testVocabularyHints() {
        let rules = """
        cloud code -> Claude Code
        clod code -> Claude Code
        next message -> nextMessage
        bad line
        """
        TestSupport.expectEqual(
            TranscriptCorrector.vocabularyHints(for: TranscriptCorrectionParser.parse(rules).rules),
            ["Claude Code", "nextMessage"]
        )
        TestSupport.expectEqual(
            TranscriptCorrector.vocabulary("Synthetic Term", addingHintsFrom: rules),
            "Synthetic Term\nClaude Code\nnextMessage"
        )
        TestSupport.expectEqual(
            TranscriptCorrector.vocabulary("  ", addingHintsFrom: rules),
            "Claude Code\nnextMessage"
        )
        TestSupport.expectEqual(
            TranscriptCorrector.vocabulary("Synthetic Term", addingHintsFrom: ""),
            "Synthetic Term"
        )
    }
}
