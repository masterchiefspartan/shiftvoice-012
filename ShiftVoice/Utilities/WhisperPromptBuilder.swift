import Foundation

nonisolated enum WhisperPromptBuilder {
    private static let maxPromptCharacters: Int = 700
    private static let maxTerms: Int = 80

    static func build(from industryVocabulary: [String]) -> String {
        let normalizedTerms: [String] = normalizedUniqueTerms(from: industryVocabulary)
        guard !normalizedTerms.isEmpty else { return "" }

        let prefix: String = "Shift handoff transcription vocabulary: "
        var prompt: String = prefix

        for term in normalizedTerms {
            let separator: String = prompt == prefix ? "" : ", "
            let candidate: String = prompt + separator + term
            guard candidate.count <= maxPromptCharacters else { break }
            prompt = candidate
        }

        return prompt == prefix ? "" : prompt
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
