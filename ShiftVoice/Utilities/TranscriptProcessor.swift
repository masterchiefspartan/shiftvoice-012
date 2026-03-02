import Foundation

enum TranscriptProcessor {
    static func generateSummary(from transcript: String) -> String {
        guard !transcript.isEmpty else { return "Voice note recorded (no transcription available)." }
        let sentences = transcript.components(separatedBy: ". ")
        if sentences.count <= 2 { return transcript }
        return sentences.prefix(3).joined(separator: ". ") + "."
    }

    static func generateCategories(from transcript: String, businessType: String? = nil) -> [CategorizedItem] {
        guard !transcript.isEmpty else { return [] }

        if let businessType,
           let cachedItems = StructuringCache.shared.enhancedOfflineCategories(from: transcript, businessType: businessType),
           !cachedItems.isEmpty {
            return cachedItems
        }

        let segments = splitTranscriptIntoSegments(transcript)
        var items: [CategorizedItem] = []

        let keywords: [(NoteCategory, String?, [String])] = [
            (.equipment, "cat_equip", ["broken", "repair", "fix", "malfunction", "not working", "equipment", "machine", "fryer", "oven", "grill"]),
            (.inventory, "cat_inv", ["out of", "running low", "restock", "order", "inventory", "supply", "supplies", "shortage"]),
            (.maintenance, "cat_maint", ["leak", "clean", "maintenance", "plumbing", "hvac", "light", "bulb"]),
            (.healthSafety, "cat_hs", ["safety", "hazard", "injury", "slip", "spill", "health", "sanitation"]),
            (.staffNote, "cat_staff", ["staff", "employee", "called out", "no show", "late", "schedule", "training"]),
            (.guestIssue, "cat_guest", ["guest", "customer", "complaint", "unhappy", "refund", "comped"]),
            (.eightySixed, "cat_86", ["86", "eighty-six", "ran out", "sold out", "unavailable"])
        ]

        for segment in segments {
            let lower = segment.lowercased()
            var matched = false
            for (category, templateId, words) in keywords {
                if words.contains(where: { lower.contains($0) }) {
                    items.append(CategorizedItem(
                        category: category,
                        categoryTemplateId: templateId,
                        content: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                        urgency: fallbackUrgency(for: category, segment: segment),
                        sourceQuote: segment.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    matched = true
                    break
                }
            }
            if !matched {
                items.append(CategorizedItem(
                    category: .general,
                    categoryTemplateId: "cat_gen",
                    content: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                    urgency: .fyi,
                    sourceQuote: segment.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }

        if items.isEmpty {
            items.append(CategorizedItem(
                category: .general,
                categoryTemplateId: "cat_gen",
                content: transcript,
                urgency: .fyi,
                sourceQuote: transcript
            ))
        }

        return items
    }

    static func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        categorized.compactMap { item in
            let snippet = String(item.content.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !snippet.isEmpty else { return nil }

            let taskDescription: String
            switch item.category {
            case .equipment: taskDescription = "Inspect equipment and resolve \(snippet)"
            case .inventory: taskDescription = "Restock inventory for \(snippet)"
            case .maintenance: taskDescription = "Repair and verify \(snippet)"
            case .healthSafety: taskDescription = "Resolve safety issue for \(snippet)"
            case .staffNote: taskDescription = "Follow up with staff about \(snippet)"
            case .guestIssue: taskDescription = "Resolve guest concern about \(snippet)"
            case .eightySixed: taskDescription = "Restock 86'd item for \(snippet)"
            case .reservation: taskDescription = "Confirm reservation details for \(snippet)"
            case .incident: taskDescription = "Document and resolve incident for \(snippet)"
            case .general: taskDescription = "Review and address \(snippet)"
            }
            return ActionItem(
                task: polishActionTask(taskDescription),
                category: item.category,
                categoryTemplateId: item.categoryTemplateId,
                urgency: item.urgency
            )
        }
    }

    static func polishActionTask(_ task: String) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Review and follow up." }

        let collapsedWhitespace = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let cleanedPunctuation = collapsedWhitespace.replacingOccurrences(of: #"\s*([:;,])\s*"#, with: "$1 ", options: .regularExpression)
        let fillerReduced = cleanedPunctuation
            .replacingOccurrences(of: #"\b(please|just|kind of|sort of|maybe)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = fillerReduced.replacingOccurrences(of: #"\bneed to\b"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let first = normalized.first else { return "Review and follow up." }
        let sentenceCased = String(first).uppercased() + normalized.dropFirst()
        let withoutTrailingJunk = sentenceCased.replacingOccurrences(of: #"[\s\.,;:!\?]+$"#, with: "", options: .regularExpression)
        return withoutTrailingJunk + "."
    }

    static func splitTranscriptIntoSegments(_ transcript: String) -> [String] {
        let sentenceDelimiters = CharacterSet(charactersIn: ".!?")
        let rawSentences = transcript.components(separatedBy: sentenceDelimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 5 }

        let separators = [
            " also ", " and then ", " next ", " another thing ",
            " additionally ", " plus ", " on top of that ",
            " second ", " third ", " finally ", " lastly ",
            ", and ", " as well as ", " besides that ",
            " one more thing ", " other than that ", " apart from that ",
            " number one ", " number two ", " number three ",
            " first ", " then "
        ]

        var segments: [String] = []

        for sentence in rawSentences {
            let subSegments = recursiveSplit(sentence, separators: separators)
            segments.append(contentsOf: subSegments)
        }

        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 5 }
    }

    private static func fallbackUrgency(for category: NoteCategory, segment: String) -> UrgencyLevel {
        let lower: String = segment.lowercased()
        let explicitCriticalSignals: [String] = [
            "fire", "gas leak", "carbon monoxide", "unconscious", "bleeding", "electrical shock", "severe injury", "active hazard"
        ]

        if category == .healthSafety,
           explicitCriticalSignals.contains(where: { lower.contains($0) }) {
            return .immediate
        }

        if category == .eightySixed {
            return .nextShift
        }

        if category == .healthSafety || category == .equipment || category == .maintenance {
            return .nextShift
        }

        return .fyi
    }

    private static func recursiveSplit(_ text: String, separators: [String]) -> [String] {
        let lower = text.lowercased()

        for sep in separators {
            guard let range = lower.range(of: sep) else { continue }
            let originalRange = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))

            let before = String(text[text.startIndex..<originalRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(text[originalRange.upperBound..<text.endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var results: [String] = []
            if before.count > 5 { results.append(before) }
            if after.count > 5 {
                results.append(contentsOf: recursiveSplit(after, separators: separators))
            }
            if !results.isEmpty { return results }
        }

        return [text]
    }
}
