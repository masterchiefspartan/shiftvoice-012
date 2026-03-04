import Foundation

nonisolated enum WhisperPromptBuilder {
    private static let maxPromptTokens: Int = 210
    private static let maxPromptCharacters: Int = 900
    private static let maxTerms: Int = 80
    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 32
        return cache
    }()

    static func build(from industryVocabulary: [String]) -> String {
        let normalizedTerms: [String] = normalizedUniqueTerms(from: industryVocabulary)
        guard !normalizedTerms.isEmpty else { return "" }

        let key: String = cacheKey(from: normalizedTerms)
        if let cachedPrompt = cache.object(forKey: key as NSString) {
            return String(cachedPrompt)
        }

        var promptTerms: [String] = []
        var usedTokenCount: Int = 0

        for term in normalizedTerms {
            let separator: String = promptTerms.isEmpty ? "" : ", "
            let separatorTokens: Int = promptTerms.isEmpty ? 0 : estimatedTokenCount(for: separator)
            let termTokens: Int = estimatedTokenCount(for: term)
            let candidateTokenCount: Int = usedTokenCount + separatorTokens + termTokens

            guard candidateTokenCount <= maxPromptTokens else { break }

            promptTerms.append(term)
            usedTokenCount = candidateTokenCount

            let candidatePrompt: String = promptTerms.joined(separator: ", ")
            guard candidatePrompt.count <= maxPromptCharacters else {
                promptTerms.removeLast()
                break
            }
        }

        let prompt: String = promptTerms.joined(separator: ", ")
        cache.setObject(prompt as NSString, forKey: key as NSString)
        return prompt
    }

    private static func estimatedTokenCount(for text: String) -> Int {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let roughByCharacters: Int = Int(ceil(Double(trimmed.count) / 4.0))
        let wordLikePieces: [Substring] = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        let roughByWords: Int = max(wordLikePieces.count, 1)
        return max(roughByCharacters, roughByWords)
    }

    private static func cacheKey(from terms: [String]) -> String {
        terms.joined(separator: "|").lowercased()
    }

    private static func normalizedUniqueTerms(from terms: [String]) -> [String] {
        var seenKeys: Set<String> = []
        var unique: [String] = []

        for term in terms {
            let trimmed: String = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key: String = trimmed.lowercased()
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            unique.append(trimmed)
            if unique.count >= maxTerms { break }
        }

        return unique
    }
}
