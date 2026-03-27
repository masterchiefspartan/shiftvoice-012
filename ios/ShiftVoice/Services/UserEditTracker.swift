import Foundation

nonisolated enum EditType: String, Codable, Sendable {
    case splitItem
    case mergedItems
    case changedCategory
    case changedUrgency
    case editedContent
    case editedAction
    case deletedItem
    case addedItem
}

nonisolated struct UserEditItem: Codable, Sendable {
    let id: String
    let kind: UserEditItemKind
    let text: String
    let category: NoteCategory?
    let urgency: UrgencyLevel?
}

nonisolated enum UserEditItemKind: String, Codable, Sendable {
    case categorized
    case action
}

nonisolated struct UserEdit: Codable, Sendable {
    let originalItem: UserEditItem?
    let editedItem: UserEditItem?
    let editType: EditType
    let timestamp: Date
    let transcriptId: String
}

nonisolated final class UserEditTracker: Sendable {
    static let shared = UserEditTracker()

    private let storageKey: String = "sv_user_edits"
    private let maxStoredEdits: Int = 1_500
    private let defaults: UserDefaults = .standard
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func diff(
        initialCategorizedItems: [CategorizedItem],
        initialActionItems: [ActionItem],
        finalCategorizedItems: [CategorizedItem],
        finalActionItems: [ActionItem],
        transcriptId: String,
        timestamp: Date = Date()
    ) -> [UserEdit] {
        var edits: [UserEdit] = []

        let initial = normalize(categorized: initialCategorizedItems, action: initialActionItems)
        let final = normalize(categorized: finalCategorizedItems, action: finalActionItems)

        let initialById = Dictionary(uniqueKeysWithValues: initial.map { ($0.id, $0) })
        let finalById = Dictionary(uniqueKeysWithValues: final.map { ($0.id, $0) })

        let removed = initial.filter { finalById[$0.id] == nil }
        let added = final.filter { initialById[$0.id] == nil }

        var consumedRemovedIds: Set<String> = []
        var consumedAddedIds: Set<String> = []

        for removedItem in removed {
            let candidateAdded = added.filter { similarity($0.text, removedItem.text) >= 0.35 }
            if candidateAdded.count >= 2 {
                consumedRemovedIds.insert(removedItem.id)
                for item in candidateAdded {
                    consumedAddedIds.insert(item.id)
                    edits.append(UserEdit(
                        originalItem: removedItem,
                        editedItem: item,
                        editType: .splitItem,
                        timestamp: timestamp,
                        transcriptId: transcriptId
                    ))
                }
            }
        }

        for addedItem in added where !consumedAddedIds.contains(addedItem.id) {
            let candidateRemoved = removed.filter { !consumedRemovedIds.contains($0.id) && similarity($0.text, addedItem.text) >= 0.35 }
            if candidateRemoved.count >= 2 {
                consumedAddedIds.insert(addedItem.id)
                for item in candidateRemoved {
                    consumedRemovedIds.insert(item.id)
                    edits.append(UserEdit(
                        originalItem: item,
                        editedItem: addedItem,
                        editType: .mergedItems,
                        timestamp: timestamp,
                        transcriptId: transcriptId
                    ))
                }
            }
        }

        for item in removed where !consumedRemovedIds.contains(item.id) {
            edits.append(UserEdit(
                originalItem: item,
                editedItem: nil,
                editType: .deletedItem,
                timestamp: timestamp,
                transcriptId: transcriptId
            ))
        }

        for item in added where !consumedAddedIds.contains(item.id) {
            edits.append(UserEdit(
                originalItem: nil,
                editedItem: item,
                editType: .addedItem,
                timestamp: timestamp,
                transcriptId: transcriptId
            ))
        }

        for original in initial {
            guard let updated = finalById[original.id] else { continue }

            if original.kind == .categorized {
                if original.text != updated.text {
                    edits.append(UserEdit(
                        originalItem: original,
                        editedItem: updated,
                        editType: .editedContent,
                        timestamp: timestamp,
                        transcriptId: transcriptId
                    ))
                }
            } else if original.text != updated.text {
                edits.append(UserEdit(
                    originalItem: original,
                    editedItem: updated,
                    editType: .editedAction,
                    timestamp: timestamp,
                    transcriptId: transcriptId
                ))
            }

            if original.category != updated.category {
                edits.append(UserEdit(
                    originalItem: original,
                    editedItem: updated,
                    editType: .changedCategory,
                    timestamp: timestamp,
                    transcriptId: transcriptId
                ))
            }

            if original.urgency != updated.urgency {
                edits.append(UserEdit(
                    originalItem: original,
                    editedItem: updated,
                    editType: .changedUrgency,
                    timestamp: timestamp,
                    transcriptId: transcriptId
                ))
            }
        }

        return edits
    }

    func store(_ edits: [UserEdit]) {
        guard !edits.isEmpty else { return }
        var all = load()
        all.append(contentsOf: edits)
        if all.count > maxStoredEdits {
            all = Array(all.suffix(maxStoredEdits))
        }
        guard let data = try? encoder.encode(all) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func load() -> [UserEdit] {
        guard let data = defaults.data(forKey: storageKey),
              let edits = try? decoder.decode([UserEdit].self, from: data) else {
            return []
        }
        return edits
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    static func transcriptIdentifier(audioUrl: String?, originalTranscript: String) -> String {
        if let audioUrl, !audioUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "audio:\(audioUrl)"
        }
        let normalized = originalTranscript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "transcript:\(stableHash(normalized))"
    }

    private func normalize(categorized: [CategorizedItem], action: [ActionItem]) -> [UserEditItem] {
        let categorizedItems = categorized.map {
            UserEditItem(
                id: $0.id,
                kind: .categorized,
                text: normalizedText($0.content),
                category: $0.category,
                urgency: $0.urgency
            )
        }
        let actionItems = action.map {
            UserEditItem(
                id: $0.id,
                kind: .action,
                text: normalizedText($0.task),
                category: $0.category,
                urgency: $0.urgency
            )
        }
        return categorizedItems + actionItems
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsWords = Set(normalizedText(lhs).split(separator: " ").map(String.init))
        let rhsWords = Set(normalizedText(rhs).split(separator: " ").map(String.init))
        guard !lhsWords.isEmpty || !rhsWords.isEmpty else { return 1.0 }
        guard !lhsWords.isEmpty, !rhsWords.isEmpty else { return 0.0 }
        let intersection = lhsWords.intersection(rhsWords).count
        let union = lhsWords.union(rhsWords).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 1469598103934665603
        let prime: UInt64 = 1099511628211
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }
        return String(hash, radix: 16)
    }
}
