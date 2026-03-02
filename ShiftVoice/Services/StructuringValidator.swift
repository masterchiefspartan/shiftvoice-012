import Foundation

nonisolated enum ValidationWarning: String, Sendable, Codable, Hashable {
    case sourceQuoteMismatch
    case topicCountMismatch
    case transcriptCoverageGap
    case duplicateItems
    case longItem
    case aiPartialCoverage
}

nonisolated struct ValidationResult: Sendable {
    let items: [CategorizedItem]
    let confidenceScore: Double
    let warnings: [ValidationWarning]
    let needsUserReview: Bool
}

nonisolated enum StructuringValidator {
    static func validate(
        transcript: String,
        items: [CategorizedItem],
        estimatedTopicCount: Int,
        transcriptCoverage: String?
    ) -> ValidationResult {
        let trimmedTranscript: String = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return ValidationResult(items: items, confidenceScore: 0.0, warnings: [.transcriptCoverageGap], needsUserReview: true)
        }

        var warnings: Set<ValidationWarning> = []
        var scorePenalty: Double = 0

        if hasSourceQuoteMismatch(transcript: trimmedTranscript, items: items) {
            warnings.insert(.sourceQuoteMismatch)
            scorePenalty += 0.18
        }

        if hasTopicCountMismatch(items: items, estimatedTopicCount: max(1, estimatedTopicCount)) {
            warnings.insert(.topicCountMismatch)
            scorePenalty += 0.16
        }

        if hasTranscriptCoverageGap(transcript: trimmedTranscript, items: items) {
            warnings.insert(.transcriptCoverageGap)
            scorePenalty += 0.18
        }

        if hasLikelyDuplicates(items: items) {
            warnings.insert(.duplicateItems)
            scorePenalty += 0.15
        }

        if hasLongItems(items: items) {
            warnings.insert(.longItem)
            scorePenalty += 0.12
        }

        if transcriptCoverage?.lowercased() == "partial" {
            warnings.insert(.aiPartialCoverage)
            scorePenalty += 0.18
        }

        let confidenceScore: Double = max(0.0, min(1.0, 1.0 - scorePenalty))
        let warningList: [ValidationWarning] = Array(warnings)
        let needsUserReview: Bool = confidenceScore < 0.7 || !warningList.isEmpty

        return ValidationResult(
            items: items,
            confidenceScore: confidenceScore,
            warnings: warningList,
            needsUserReview: needsUserReview
        )
    }

    private static func hasSourceQuoteMismatch(transcript: String, items: [CategorizedItem]) -> Bool {
        let normalizedTranscript: String = normalizeForFuzzyMatch(transcript)
        guard !normalizedTranscript.isEmpty else { return true }

        for item in items {
            guard let quote = item.sourceQuote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else { continue }
            let normalizedQuote: String = normalizeForFuzzyMatch(quote)
            guard !normalizedQuote.isEmpty else { continue }

            if normalizedTranscript.contains(normalizedQuote) {
                continue
            }

            let similarity: Double = tokenJaccardSimilarity(lhs: normalizedQuote, rhs: normalizedTranscript)
            if similarity < 0.45 {
                return true
            }
        }
        return false
    }

    private static func hasTopicCountMismatch(items: [CategorizedItem], estimatedTopicCount: Int) -> Bool {
        let aiCount: Int = items.count
        if estimatedTopicCount <= 1 {
            return aiCount == 0
        }
        let difference: Int = abs(aiCount - estimatedTopicCount)
        return difference >= 2 || Double(aiCount) < Double(estimatedTopicCount) * 0.6
    }

    private static func hasTranscriptCoverageGap(transcript: String, items: [CategorizedItem]) -> Bool {
        let transcriptWords: Set<String> = meaningfulWords(in: transcript)
        guard !transcriptWords.isEmpty else { return false }

        let quoteWords: Set<String> = Set(items.compactMap(\.sourceQuote).flatMap { meaningfulWords(in: $0) })
        let uncovered: Set<String> = transcriptWords.subtracting(quoteWords)
        let uncoveredRatio: Double = Double(uncovered.count) / Double(transcriptWords.count)
        return uncoveredRatio > 0.5
    }

    private static func hasLikelyDuplicates(items: [CategorizedItem]) -> Bool {
        guard items.count > 1 else { return false }
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let similarity: Double = tokenJaccardSimilarity(lhs: items[i].content, rhs: items[j].content)
                if similarity > 0.8 {
                    return true
                }
            }
        }
        return false
    }

    private static func hasLongItems(items: [CategorizedItem]) -> Bool {
        items.contains { item in
            item.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count > 30
        }
    }

    private static func tokenJaccardSimilarity(lhs: String, rhs: String) -> Double {
        let leftTokens: Set<String> = meaningfulWords(in: lhs)
        let rightTokens: Set<String> = meaningfulWords(in: rhs)
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }
        let intersection: Int = leftTokens.intersection(rightTokens).count
        let union: Int = leftTokens.union(rightTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func meaningfulWords(in text: String) -> Set<String> {
        let normalized: String = normalizeForFuzzyMatch(text)
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "at", "is", "it", "this", "that", "we", "i", "you", "they", "he", "she", "be", "was", "were", "are"
        ]

        let tokens: [String] = normalized
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        return Set(tokens)
    }

    private static func normalizeForFuzzyMatch(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
