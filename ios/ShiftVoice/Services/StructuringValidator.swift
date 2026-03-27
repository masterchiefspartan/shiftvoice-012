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
    let warningItemIDs: Set<String>
    let needsUserReview: Bool
}

nonisolated enum StructuringValidator {
    private static let sourceQuotePenalty: Double = 0.22
    private static let topicCountPenalty: Double = 0.14
    private static let transcriptCoveragePenalty: Double = 0.22
    private static let duplicatePenalty: Double = 0.15
    private static let longItemPenalty: Double = 0.10
    private static let aiPartialCoveragePenalty: Double = 0.18

    private static let quoteWindowMatchThreshold: Double = 0.60
    private static let transcriptGapWarningThreshold: Double = 0.45
    private static let transcriptGapHardThreshold: Double = 0.62
    private static let duplicateSimilarityThreshold: Double = 0.84
    private static let longItemWordThreshold: Int = 28
    private static let lowValueWords: Set<String> = [
        "thing", "stuff", "something", "someone", "somebody", "anything", "everything", "issue", "issues", "problem", "problems", "item", "items", "note", "notes"
    ]

    static func validate(
        transcript: String,
        items: [CategorizedItem],
        estimatedTopicCount: Int,
        transcriptCoverage: String?
    ) -> ValidationResult {
        let trimmedTranscript: String = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            return ValidationResult(items: items, confidenceScore: 0.0, warnings: [.transcriptCoverageGap], warningItemIDs: [], needsUserReview: true)
        }

        var warnings: Set<ValidationWarning> = []
        var warningItemIDs: Set<String> = []
        var scorePenalty: Double = 0

        let quoteMismatchItemIDs: Set<String> = sourceQuoteMismatchItemIDs(transcript: trimmedTranscript, items: items)
        if !quoteMismatchItemIDs.isEmpty {
            warnings.insert(.sourceQuoteMismatch)
            warningItemIDs.formUnion(quoteMismatchItemIDs)
            scorePenalty += sourceQuotePenalty
        }

        if hasTopicCountMismatch(items: items, estimatedTopicCount: max(1, estimatedTopicCount)) {
            warnings.insert(.topicCountMismatch)
            scorePenalty += topicCountPenalty
        }

        let uncoveredRatio: Double = uncoveredMeaningfulRatio(transcript: trimmedTranscript, items: items)
        if uncoveredRatio > transcriptGapWarningThreshold {
            warnings.insert(.transcriptCoverageGap)
            if uncoveredRatio >= transcriptGapHardThreshold {
                scorePenalty += transcriptCoveragePenalty
            } else {
                scorePenalty += transcriptCoveragePenalty * 0.65
            }
        }

        let duplicateItemIDs: Set<String> = duplicateItemIDs(in: items)
        if !duplicateItemIDs.isEmpty {
            warnings.insert(.duplicateItems)
            warningItemIDs.formUnion(duplicateItemIDs)
            scorePenalty += duplicatePenalty
        }

        let longItemIDs: Set<String> = longItemIDs(in: items)
        if !longItemIDs.isEmpty {
            warnings.insert(.longItem)
            warningItemIDs.formUnion(longItemIDs)
            scorePenalty += longItemPenalty
        }

        if transcriptCoverage?.lowercased() == "partial" {
            warnings.insert(.aiPartialCoverage)
            scorePenalty += aiPartialCoveragePenalty
        }

        let confidenceScore: Double = max(0.0, min(1.0, 1.0 - scorePenalty))
        let warningList: [ValidationWarning] = Array(warnings)
        let needsUserReview: Bool = confidenceScore < 0.7 || !warningList.isEmpty

        return ValidationResult(
            items: items,
            confidenceScore: confidenceScore,
            warnings: warningList,
            warningItemIDs: warningItemIDs,
            needsUserReview: needsUserReview
        )
    }

    private static func sourceQuoteMismatchItemIDs(transcript: String, items: [CategorizedItem]) -> Set<String> {
        let normalizedTranscript: String = normalizeForFuzzyMatch(transcript)
        guard !normalizedTranscript.isEmpty else { return Set(items.map(\.id)) }

        let transcriptTokens: [String] = meaningfulTokenList(in: normalizedTranscript)
        guard !transcriptTokens.isEmpty else { return Set(items.map(\.id)) }

        var mismatches: Set<String> = []
        for item in items {
            guard let quote = item.sourceQuote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else {
                mismatches.insert(item.id)
                continue
            }

            let normalizedQuote: String = normalizeForFuzzyMatch(quote)
            let quoteTokens: [String] = meaningfulTokenList(in: normalizedQuote)
            guard !quoteTokens.isEmpty else {
                mismatches.insert(item.id)
                continue
            }

            if normalizedTranscript.contains(normalizedQuote) {
                continue
            }

            let maxWindowScore: Double = maxWindowedJaccardSimilarity(quoteTokens: quoteTokens, transcriptTokens: transcriptTokens)
            if maxWindowScore < quoteWindowMatchThreshold {
                mismatches.insert(item.id)
            }
        }
        return mismatches
    }

    private static func hasTopicCountMismatch(items: [CategorizedItem], estimatedTopicCount: Int) -> Bool {
        let aiCount: Int = items.count
        if estimatedTopicCount <= 1 {
            return aiCount == 0
        }
        let difference: Int = abs(aiCount - estimatedTopicCount)
        return difference >= 2 || Double(aiCount) < Double(estimatedTopicCount) * 0.6
    }

    private static func uncoveredMeaningfulRatio(transcript: String, items: [CategorizedItem]) -> Double {
        let transcriptWords: Set<String> = meaningfulWords(in: transcript)
        guard !transcriptWords.isEmpty else { return 0 }

        let quoteWords: Set<String> = Set(items.compactMap(\.sourceQuote).flatMap { meaningfulWords(in: $0) })
        let uncovered: Set<String> = transcriptWords.subtracting(quoteWords)
        guard !uncovered.isEmpty else { return 0 }

        let meaningfulUncovered: [String] = uncovered.filter { !lowValueWords.contains($0) }
        let weightedUncoveredCount: Double = Double(meaningfulUncovered.count) + (Double(uncovered.count - meaningfulUncovered.count) * 0.35)
        return weightedUncoveredCount / Double(transcriptWords.count)
    }

    private static func duplicateItemIDs(in items: [CategorizedItem]) -> Set<String> {
        guard items.count > 1 else { return [] }
        var duplicates: Set<String> = []
        for i in 0..<items.count {
            for j in (i + 1)..<items.count {
                let similarity: Double = tokenJaccardSimilarity(lhs: items[i].content, rhs: items[j].content)
                if similarity >= duplicateSimilarityThreshold {
                    duplicates.insert(items[i].id)
                    duplicates.insert(items[j].id)
                }
            }
        }
        return duplicates
    }

    private static func longItemIDs(in items: [CategorizedItem]) -> Set<String> {
        Set(items.compactMap { item in
            let wordCount: Int = item.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            return wordCount > longItemWordThreshold ? item.id : nil
        })
    }

    private static func tokenJaccardSimilarity(lhs: String, rhs: String) -> Double {
        let leftTokens: Set<String> = meaningfulWords(in: lhs)
        let rightTokens: Set<String> = meaningfulWords(in: rhs)
        return tokenJaccardSimilarity(lhsTokens: leftTokens, rhsTokens: rightTokens)
    }

    private static func maxWindowedJaccardSimilarity(quoteTokens: [String], transcriptTokens: [String]) -> Double {
        guard !quoteTokens.isEmpty, !transcriptTokens.isEmpty else { return 0 }
        let quoteSet: Set<String> = Set(quoteTokens)

        let minWindowSize: Int = max(1, quoteTokens.count - 2)
        let maxWindowSize: Int = min(transcriptTokens.count, quoteTokens.count + 3)
        guard minWindowSize <= maxWindowSize else {
            return tokenJaccardSimilarity(lhsTokens: quoteSet, rhsTokens: Set(transcriptTokens))
        }

        var bestScore: Double = 0
        for windowSize in minWindowSize...maxWindowSize {
            guard transcriptTokens.count >= windowSize else { continue }
            for start in 0...(transcriptTokens.count - windowSize) {
                let windowTokens: Set<String> = Set(transcriptTokens[start..<(start + windowSize)])
                let score: Double = tokenJaccardSimilarity(lhsTokens: quoteSet, rhsTokens: windowTokens)
                if score > bestScore {
                    bestScore = score
                }
            }
        }
        return bestScore
    }

    private static func tokenJaccardSimilarity(lhsTokens: Set<String>, rhsTokens: Set<String>) -> Double {
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }
        let intersection: Int = lhsTokens.intersection(rhsTokens).count
        let union: Int = lhsTokens.union(rhsTokens).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func meaningfulWords(in text: String) -> Set<String> {
        Set(meaningfulTokenList(in: normalizeForFuzzyMatch(text)))
    }

    private static func meaningfulTokenList(in normalizedText: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "at", "is", "it", "this", "that", "we", "i", "you", "they", "he", "she", "be", "was", "were", "are"
        ]

        return normalizedText
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) }
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
