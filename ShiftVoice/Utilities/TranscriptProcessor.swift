import Foundation

enum TranscriptProcessor {
    static func generateSummary(from transcript: String) -> String {
        guard !transcript.isEmpty else { return "Voice note recorded (no transcription available)." }
        let sentences = transcript.components(separatedBy: ". ")
        if sentences.count <= 2 { return transcript }
        return sentences.prefix(3).joined(separator: ". ") + "."
    }

    static func generateCategories(from transcript: String) -> [CategorizedItem] {
        guard !transcript.isEmpty else { return [] }
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
                        urgency: category == .healthSafety || category == .eightySixed ? .immediate : .nextShift
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
                    urgency: .fyi
                ))
            }
        }

        if items.isEmpty {
            items.append(CategorizedItem(
                category: .general,
                categoryTemplateId: "cat_gen",
                content: transcript,
                urgency: .fyi
            ))
        }

        return items
    }

    static func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        categorized.compactMap { item in
            let taskDescription: String
            switch item.category {
            case .equipment: taskDescription = "Check and address: \(item.content.prefix(80))"
            case .inventory: taskDescription = "Restock: \(item.content.prefix(80))"
            case .maintenance: taskDescription = "Fix: \(item.content.prefix(80))"
            case .healthSafety: taskDescription = "Resolve safety issue: \(item.content.prefix(80))"
            case .staffNote: taskDescription = "Follow up: \(item.content.prefix(80))"
            case .guestIssue: taskDescription = "Guest concern: \(item.content.prefix(80))"
            case .eightySixed: taskDescription = "86'd - restock: \(item.content.prefix(80))"
            case .reservation: taskDescription = "Reservation follow-up: \(item.content.prefix(80))"
            case .incident: taskDescription = "Incident follow-up: \(item.content.prefix(80))"
            case .general: taskDescription = "Review: \(item.content.prefix(80))"
            }
            return ActionItem(
                task: taskDescription,
                category: item.category,
                categoryTemplateId: item.categoryTemplateId,
                urgency: item.urgency
            )
        }
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
