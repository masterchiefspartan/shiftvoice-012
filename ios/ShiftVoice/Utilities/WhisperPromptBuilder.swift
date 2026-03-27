import Foundation

nonisolated enum WhisperPromptBuilder {
    private static let maxPromptTokens: Int = 210
    private static let maxPromptCharacters: Int = 900
    private static let maxTerms: Int = 80
    private static let contextPrefix: String = "Shift handoff notes. Terms: "
    private static let fallbackPrompt: String = "Shift handoff notes."
    private static let separator: String = ", "
    private static let tokenCharDivisor: Double = 4.0
    private static let minimumWordCount: Int = 1

    private static let cache: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 32
        return cache
    }()

    static func build(from industryVocabulary: [String]) -> String {
        let normalizedTerms: [String] = normalizedUniqueTerms(from: industryVocabulary)
        let key: String = cacheKey(from: normalizedTerms)

        if let cachedPrompt = cache.object(forKey: key as NSString) {
            return String(cachedPrompt)
        }

        let prefixTokenCount: Int = estimatedTokenCount(for: contextPrefix)
        let prefixCharacterCount: Int = contextPrefix.count
        let fallbackTokenCount: Int = estimatedTokenCount(for: fallbackPrompt)
        let fallbackCharacterCount: Int = fallbackPrompt.count

        guard !normalizedTerms.isEmpty,
              prefixTokenCount <= maxPromptTokens,
              prefixCharacterCount <= maxPromptCharacters else {
            let fallback: String = fallbackTokenCount <= maxPromptTokens && fallbackCharacterCount <= maxPromptCharacters ? fallbackPrompt : ""
            cache.setObject(fallback as NSString, forKey: key as NSString)
            return fallback
        }

        let remainingTokenBudget: Int = max(maxPromptTokens - prefixTokenCount, 0)
        let remainingCharacterBudget: Int = max(maxPromptCharacters - prefixCharacterCount, 0)

        var promptTerms: [String] = []
        var usedTokenCount: Int = 0
        var usedCharacterCount: Int = 0

        for term in normalizedTerms {
            let separatorTokenCount: Int = promptTerms.isEmpty ? 0 : estimatedTokenCount(for: separator)
            let separatorCharacterCount: Int = promptTerms.isEmpty ? 0 : separator.count
            let termTokenCount: Int = estimatedTokenCount(for: term)
            let candidateTokenCount: Int = usedTokenCount + separatorTokenCount + termTokenCount
            let candidateCharacterCount: Int = usedCharacterCount + separatorCharacterCount + term.count

            guard candidateTokenCount <= remainingTokenBudget,
                  candidateCharacterCount <= remainingCharacterBudget else { break }

            promptTerms.append(term)
            usedTokenCount = candidateTokenCount
            usedCharacterCount = candidateCharacterCount
        }

        let prompt: String
        if promptTerms.isEmpty {
            prompt = fallbackTokenCount <= maxPromptTokens && fallbackCharacterCount <= maxPromptCharacters ? fallbackPrompt : ""
        } else {
            prompt = contextPrefix + promptTerms.joined(separator: separator)
        }

        cache.setObject(prompt as NSString, forKey: key as NSString)
        return prompt
    }

    private static func estimatedTokenCount(for text: String) -> Int {
        let trimmed: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let roughByCharacters: Int = Int(ceil(Double(trimmed.count) / tokenCharDivisor))
        let wordLikePieces: [Substring] = trimmed.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        let roughByWords: Int = max(wordLikePieces.count, minimumWordCount)
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
