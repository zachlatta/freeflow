import AppKit

// MARK: - Add Vocabulary Button Extension

@MainActor
extension AppState {
    /// Pastes a word (or words) from the macOS pasteboard into the user's custom vocabulary.
    /// Returns the pasted text if successful, or nil otherwise.
    @discardableResult
    func pasteWordToVocabulary() -> String? {
        // Read text from pasteboard (macOS native clipboard API)
        // Check if there's any non-whitespace content to paste
        guard let pastedString = NSPasteboard.general.string(forType: .string),
              !pastedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Clean and prepare the new word(s)
        let wordsToAdd = pastedString
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        guard !wordsToAdd.isEmpty else { return nil }
        
        // Parse current vocabulary list to avoid adding exact duplicates
        let currentWordsList = self.customVocabulary
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        let currentWordsSet = Set(currentWordsList.map { $0.lowercased() })
        
        let newUniqueWords = wordsToAdd.filter { !currentWordsSet.contains($0.lowercased()) }
        
        guard !newUniqueWords.isEmpty else { return nil }
        
        let newWordsString = newUniqueWords.joined(separator: ", ")
        
        // Append unique words to existing vocabulary
        // We trim the block as a whole to safely append, but not the individual words themselves
        var currentVocab = self.customVocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentVocab.isEmpty {
            if !currentVocab.hasSuffix(",") {
                currentVocab += ","
            }
            currentVocab += "\n\(newWordsString)"
        } else {
            currentVocab = newWordsString
        }
        
        // Save back to the published state
        self.customVocabulary = currentVocab
        return newWordsString
    }
}

