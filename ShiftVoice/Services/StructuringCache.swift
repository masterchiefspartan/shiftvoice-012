import Foundation

nonisolated struct CachedStructuring: Codable, Sendable {
    let keywords: [String]
    let category: String
    let urgency: String
    let hasAction: Bool
    let timestamp: TimeInterval
}

nonisolated struct StructuringCacheStore: Codable, Sendable {
    var entries: [CachedStructuring]
    var businessType: String
}

final class StructuringCache {
    static let shared = StructuringCache()

    private let maxEntries = 200
    private let cacheKey = "sv_structuring_cache"
    private let defaults = UserDefaults.standard

    private init() {}

    func cacheResult(_ result: StructuringResult, businessType: String) {
        var store = loadStore(businessType: businessType)

        for item in result.categorizedItems {
            let words = extractKeywords(from: item.content)
            guard !words.isEmpty else { continue }
            let entry = CachedStructuring(
                keywords: words,
                category: item.category.rawValue,
                urgency: item.urgency.rawValue,
                hasAction: true,
                timestamp: Date().timeIntervalSince1970
            )
            store.entries.append(entry)
        }

        if store.entries.count > maxEntries {
            store.entries = Array(store.entries.suffix(maxEntries))
        }

        saveStore(store)
    }

    func enhancedOfflineCategories(from transcript: String, businessType: String) -> [CategorizedItem]? {
        let store = loadStore(businessType: businessType)
        guard !store.entries.isEmpty else { return nil }

        let segments = TranscriptProcessor.splitTranscriptIntoSegments(transcript)
        guard !segments.isEmpty else { return nil }

        var items: [CategorizedItem] = []

        for segment in segments {
            let segmentWords = Set(extractKeywords(from: segment))
            guard !segmentWords.isEmpty else { continue }

            var bestMatch: CachedStructuring?
            var bestScore = 0

            for entry in store.entries {
                let entryWords = Set(entry.keywords)
                let overlap = segmentWords.intersection(entryWords).count
                if overlap > bestScore {
                    bestScore = overlap
                    bestMatch = entry
                }
            }

            if let match = bestMatch, bestScore >= 2 {
                let category = NoteCategory(rawValue: match.category) ?? .general
                let urgency = UrgencyLevel(rawValue: match.urgency) ?? .fyi
                items.append(CategorizedItem(
                    category: category,
                    categoryTemplateId: categoryTemplateId(for: category),
                    content: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                    urgency: urgency
                ))
            } else {
                let fallback = TranscriptProcessor.generateCategories(from: segment)
                items.append(contentsOf: fallback)
            }
        }

        return items.isEmpty ? nil : items
    }

    private func extractKeywords(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "was", "are", "were", "be", "been",
            "being", "have", "has", "had", "do", "does", "did", "will",
            "would", "could", "should", "may", "might", "can", "shall",
            "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "it", "its", "this", "that", "these", "those", "i", "we",
            "they", "he", "she", "you", "me", "us", "him", "her", "them",
            "my", "our", "your", "his", "their", "and", "or", "but",
            "not", "no", "so", "if", "then", "just", "also", "about",
            "up", "out", "into", "some", "all", "very", "really", "got",
        ]

        let words = text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        return Array(Set(words)).sorted()
    }

    private func categoryTemplateId(for category: NoteCategory) -> String? {
        switch category {
        case .eightySixed: return "cat_86"
        case .equipment: return "cat_equip"
        case .guestIssue: return "cat_guest"
        case .staffNote: return "cat_staff"
        case .reservation: return "cat_res"
        case .inventory: return "cat_inv"
        case .maintenance: return "cat_maint"
        case .healthSafety: return "cat_hs"
        case .general: return "cat_gen"
        case .incident: return "cat_incident"
        }
    }

    private func loadStore(businessType: String) -> StructuringCacheStore {
        guard let data = defaults.data(forKey: cacheKey),
              let store = try? JSONDecoder().decode(StructuringCacheStore.self, from: data),
              store.businessType == businessType else {
            return StructuringCacheStore(entries: [], businessType: businessType)
        }
        return store
    }

    private func saveStore(_ store: StructuringCacheStore) {
        guard let data = try? JSONEncoder().encode(store) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
