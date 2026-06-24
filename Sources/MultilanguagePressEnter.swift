/// A modular and robust utility for extracting customizable "press enter" voice commands.
/// It compiles dynamic, user-defined command variations into a highly optimized regex.

import Foundation
import os.log

public struct MultilanguagePressEnter: Sendable {
    
    /// A curated list of default commands across various languages.
    /// This is used purely as a set of recommendations in the Settings UI so users can easily add them.
    public static let suggestedCommands: [String] = [
        // English
        "press enter", "enter", "hit enter", "send", "press return",
        // Portuguese (BR & PT)
        "aperte enter", "dar enter", "pressione enter",
        // Spanish
        "presionar enter", "intro",
        // French
        "appuyer sur entrée", "entrée",
        // German
        "eingabetaste drücken", "enter drücken",
        // Italian
        "premi invio", "invio",
        // Dutch
        "druk op enter",
        // Russian
        "нажать enter",
        // Japanese
        "エンターを押す",
        // Chinese
        "回车",
    ]
    
    // MARK: - Regex Compilation
    
    /// Compiles a list of user-defined string commands into a single, optimized Regular Expression.
    /// - Parameter commands: An array of strings representing the active variations the user has chosen.
    /// - Returns: A case-insensitive NSRegularExpression, or nil if no valid commands were provided.
    public static func compileRegex(for commands: [String]) -> NSRegularExpression? {
        // Sanitize incoming commands: remove leading/trailing spaces and collapse multiple spaces 
        // between words into a single space. This guarantees our compiler handles clean data,
        // even if raw inputs had extra spaces added by mistake.
        let validCommands = commands.map { command -> String in
            let words = command.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            return words.joined(separator: " ")
        }.filter { !$0.isEmpty }
        
        guard !validCommands.isEmpty else { return nil }
        
        let regexParts = validCommands.map { command -> String in
            // Since the command is already normalized above, we can safely split by single spaces.
            let words = command.components(separatedBy: " ")
            
            // Protect each word so the search engine reads it as plain text.
            let escapedWords = words.map { NSRegularExpression.escapedPattern(for: $0) }
            
            // Glue the words back together, but allow the user to pause or leave multiple spaces between them.
            return escapedWords.joined(separator: "[ \\t\\r\\n]+")
        }
        
        // Combine all active user commands into one big search list using an OR (|) operator.
        let joinedCommands = regexParts.joined(separator: "|")
        
        // Creating the search rule (Regex) step-by-step:
        // 1. (?i)                 -> It doesn't matter if the letter is uppercase or lowercase.
        // 2. ^                    -> Start reading from the very beginning of the sentence.
        // 3. ([\\s\\S]*?)         -> Part 1 (The actual text): Save everything the person said. This is what we'll return clean.
        // 4. (?:\\s*)             -> Ignore any blank spaces right before the command word.
        // 5. (?:\b(?:\(joinedCommands))\b) -> Look for one of the user's active commands (e.g., "press enter") exactly as a word boundary.
        // 6. ([\\s\\p{P}]*)$      -> Part 2 (The Punctuation): Grab any leftover punctuation at the very end (like '?' or '!').
        let regexPattern = "(?i)^([\\s\\S]*?)(?:\\s*)(?:\\b(?:\(joinedCommands))\\b)([\\s\\p{P}]*)$"
        
        do {
            // Compile the pattern into a Mac native NSRegularExpression
            return try NSRegularExpression(pattern: regexPattern)
        } catch {
            // Log compilation errors instead of crashing the app
            os_log(.error, "Failed to compile MultilanguagePressEnter regex: %{public}@", error.localizedDescription)
            return nil
        }
    }
    
    // MARK: - Command Extraction
    
    /// Checks if the person ended the sentence with one of their configured custom commands.
    /// If yes, the command is deleted and the function returns only the text the person actually meant to dictate.
    /// - Parameters:
    ///   - transcript: The raw text spoken by the user.
    ///   - regex: The pre-compiled regular expression containing the user's active variations.
    public static func extractCommand(from transcript: String, withRegex regex: NSRegularExpression?) -> (strippedTranscript: String, didMatch: Bool) {
        guard let regex = regex else {
            // Failsafe: If the search rule fails or doesn't exist, return the original text without changing anything.
            return (transcript.trimmingCharacters(in: .whitespacesAndNewlines), false)
        }
        
        var currentTranscript = transcript
        var didMatchAny = false
        var savedPunctuation = ""
        
        // We start a loop to handle stuttering or repeated commands.
        // If the person says "final text. enter, enter", we will delete the commands from back to front until only the text is left.
        while true {
            let fullRange = NSRange(currentTranscript.startIndex..<currentTranscript.endIndex, in: currentTranscript)
            
            // Try to find the command hidden exactly at the end of the sentence.
            guard let match = regex.firstMatch(in: currentTranscript, range: fullRange) else {
                // If we can't find any more commands at the end, we stop the loop.
                break
            }
            
            // Here we cut out the two important parts that the search rule saved for us:
            let group1Range = match.range(at: 1) // Part 1 (The actual text)
            let group2Range = match.range(at: 2) // Part 2 (The Punctuation)
            
            if group1Range.location != NSNotFound, let range1 = Range(group1Range, in: currentTranscript) {
                // We find out what final punctuation the voice system added (if any).
                var trailingPunctuation = ""
                if group2Range.location != NSNotFound, let range2 = Range(group2Range, in: currentTranscript) {
                    trailingPunctuation = String(currentTranscript[range2])
                }
                
                // If we find a question mark or exclamation mark that was stuck to the command being deleted,
                // we save it in a "vault" to paste back onto the clean text later.
                if trailingPunctuation.contains("?") {
                    savedPunctuation = "?"
                } else if trailingPunctuation.contains("!") && savedPunctuation != "?" {
                    savedPunctuation = "!"
                }
                
                // We grab the clean text (without the command) and prepare for the next round of the loop.
                currentTranscript = String(currentTranscript[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                didMatchAny = true
            } else {
                break
            }
        }
        
        // If we found at least one enter command, we put the finishing touches on the text:
        if didMatchAny {
            if savedPunctuation == "?" || savedPunctuation == "!" {
                // Replace any existing terminal punctuation before restoring the saved punctuation.
                if let last = currentTranscript.last, ",.!?".contains(last) {
                    currentTranscript.removeLast()
                }
                currentTranscript.append(savedPunctuation)
            } else if currentTranscript.hasSuffix(",") {
                // If a comma was left at the end of the sentence because the person paused before saying "press enter",
                // we replace it with a neat period.
                currentTranscript.removeLast()
                currentTranscript.append(".")
            }
            
            return (currentTranscript, true)
        }
        
        // If the person didn't say any command at the end, we just clean up the blank spaces and return it.
        return (transcript.trimmingCharacters(in: .whitespacesAndNewlines), false)
    }
}
