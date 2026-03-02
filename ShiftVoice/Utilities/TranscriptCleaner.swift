import Foundation

nonisolated struct CleanedTranscript: Sendable {
    let originalText: String
    let text: String
    let estimatedTopicCount: Int
    let lowConfidencePhrases: [String]
}

nonisolated enum TranscriptCleaner {
    private static let fillerPhrases: [String] = [
        "you know",
        "i mean",
        "kind of",
        "sort of"
    ]

    private static let fillerWords: Set<String> = [
        "um", "uh", "erm", "ah", "hmm", "like", "basically", "actually", "literally", "honestly"
    ]

    private static let transitionCues: [String] = [
        "also", "and then", "next", "another thing", "on top of that", "additionally", "oh and", "plus", "as well", "besides that"
    ]

    static func clean(_ transcript: String, lowConfidenceSegments: [TranscriptSegment] = []) -> CleanedTranscript {
        let originalText: String = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowConfidencePhrases: [String] = normalizedLowConfidencePhrases(from: lowConfidenceSegments)
        guard !originalText.isEmpty else {
            return CleanedTranscript(originalText: "", text: "", estimatedTopicCount: 1, lowConfidencePhrases: lowConfidencePhrases)
        }

        var cleaned: String = " \(originalText) "
        for phrase in fillerPhrases {
            let pattern: String = "(?i)(^|[\\s,.;:!?-])" + NSRegularExpression.escapedPattern(for: phrase) + "(?=([\\s,.;:!?-]|$))"
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }

        let tokens: [Substring] = cleaned.split(separator: " ", omittingEmptySubsequences: true)
        let normalizedTokens: [String] = tokens.compactMap { token in
            let word = token.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if fillerWords.contains(word) {
                return nil
            }
            return String(token)
        }

        cleaned = normalizedTokens.joined(separator: " ")
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "([,.;:!?]){2,}", with: "$1", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        let finalText: String = cleaned.isEmpty ? originalText : cleaned
        let estimatedTopicCount: Int = estimateTopicCount(in: finalText)
        return CleanedTranscript(
            originalText: originalText,
            text: finalText,
            estimatedTopicCount: estimatedTopicCount,
            lowConfidencePhrases: lowConfidencePhrases
        )
    }

    private static func normalizedLowConfidencePhrases(from segments: [TranscriptSegment]) -> [String] {
        var seen: Set<String> = []
        var phrases: [String] = []

        for segment in segments {
            let phrase: String = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { continue }
            let key: String = phrase.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            phrases.append(phrase)
        }

        return phrases
    }

    private static func estimateTopicCount(in transcript: String) -> Int {
        let lower: String = transcript.lowercased()
        let explicitPattern: String = #"\b(two|three|four|five|six|seven|eight|nine|ten|\d+)\s+(things?|items?|issues?|points?|notes?)\b"#
        if let explicitRange = lower.range(of: explicitPattern, options: .regularExpression) {
            let match: String = String(lower[explicitRange])
            let components: [String] = match.split(separator: " ").map(String.init)
            if let first = components.first {
                let map: [String: Int] = ["two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
                if let mapped = map[first] {
                    return mapped
                }
                if let parsed = Int(first), parsed >= 2 {
                    return parsed
                }
            }
        }

        let ordinalsCount: Int = lower.matches(of: /\b(first|second|third|fourth|fifth|number one|number two|number three)\b/).count
        let numberedListCount: Int = lower.matches(of: /(?:^|\n|\. )\d+[\.\)\:]/).count
        let transitionCount: Int = transitionCues.reduce(into: 0) { partialResult, cue in
            partialResult += lower.matches(of: Regex<Substring>(verbatim: cue)).count
        }

        let imperativeCount: Int = lower.matches(of: /\b(check|fix|order|replace|clean|call|tell|restock|notify|schedule|follow up|make sure|need to|needs to|have to|has to)\b/).count

        var cues: Int = max(ordinalsCount, numberedListCount)
        if transitionCount > 0 {
            cues = max(cues, transitionCount + 1)
        }
        if imperativeCount >= 3 {
            cues = max(cues, Int(ceil(Double(imperativeCount) * 0.6)))
        }

        return max(1, cues)
    }
}
