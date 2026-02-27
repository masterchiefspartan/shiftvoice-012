import Foundation

nonisolated struct AIStructuredItem: Codable, Sendable {
    let content: String
    let category: String
    let urgency: String
    let actionRequired: Bool
    let actionTask: String?
}

nonisolated struct AIStructuredNote: Codable, Sendable {
    let summary: String
    let items: [AIStructuredItem]
}

nonisolated struct AIStructureResponse: Codable, Sendable {
    let success: Bool
    let structured: AIStructuredNote?
    let error: String?
}

nonisolated enum StructuringError: Error, Sendable {
    case emptyTranscript
    case noBaseURL
    case invalidURL
    case serverError(String)
    case aiUnavailable(String)
    case decodingError
    case timeout

    var userMessage: String {
        switch self {
        case .emptyTranscript: return "No transcript to process."
        case .noBaseURL, .invalidURL: return "Service configuration error."
        case .serverError(let msg): return msg
        case .aiUnavailable(let msg): return msg
        case .decodingError: return "Failed to parse AI response."
        case .timeout: return "Processing timed out. Your note was structured locally."
        }
    }
}

nonisolated struct StructuringResult: Sendable {
    let summary: String
    let categorizedItems: [CategorizedItem]
    let actionItems: [ActionItem]
    let usedAI: Bool
    let warning: String?
}

final class NoteStructuringService {
    static let shared = NoteStructuringService()

    private let session: URLSession
    private let decoder: JSONDecoder

    private var baseURL: String {
        let url = Config.EXPO_PUBLIC_RORK_API_BASE_URL
        if url.isEmpty || url == "EXPO_PUBLIC_RORK_API_BASE_URL" { return "" }
        return url
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func structureTranscript(_ transcript: String, businessType: String, authToken: String?, userId: String?) async -> Result<StructuringResult, StructuringError> {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyTranscript)
        }
        guard !baseURL.isEmpty else { return .failure(.noBaseURL) }
        guard let url = URL(string: "\(baseURL)/api/rest/structure-transcript") else { return .failure(.invalidURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }

        let body: [String: Any] = [
            "transcript": transcript,
            "businessType": businessType
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.serverError("Invalid server response."))
            }

            guard httpResponse.statusCode == 200 else {
                if let errorResp = try? decoder.decode(AIStructureResponse.self, from: data), let msg = errorResp.error {
                    return .failure(.aiUnavailable(msg))
                }
                return .failure(.serverError("Server returned status \(httpResponse.statusCode)."))
            }

            let aiResponse: AIStructureResponse
            do {
                aiResponse = try decoder.decode(AIStructureResponse.self, from: data)
            } catch {
                return .failure(.decodingError)
            }

            guard aiResponse.success, let structured = aiResponse.structured else {
                return .failure(.aiUnavailable(aiResponse.error ?? "AI structuring returned no results."))
            }

            let (categorizedItems, actionItems) = mapAIItems(structured.items)

            if categorizedItems.isEmpty {
                return .failure(.aiUnavailable("AI returned no structured items."))
            }

            let warning = confidenceWarning(transcript: transcript, itemCount: categorizedItems.count)

            return .success(StructuringResult(
                summary: structured.summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems,
                usedAI: true,
                warning: warning
            ))
        } catch is URLError {
            return .failure(.timeout)
        } catch {
            return .failure(.serverError("Network error: \(error.localizedDescription)"))
        }
    }

    private func mapAIItems(_ items: [AIStructuredItem]) -> ([CategorizedItem], [ActionItem]) {
        let categoryMap: [String: (NoteCategory, String?)] = [
            "86'd Items": (.eightySixed, "cat_86"),
            "Equipment": (.equipment, "cat_equip"),
            "Guest Issues": (.guestIssue, "cat_guest"),
            "Staff Notes": (.staffNote, "cat_staff"),
            "Reservations/VIP": (.reservation, "cat_res"),
            "Inventory": (.inventory, "cat_inv"),
            "Maintenance": (.maintenance, "cat_maint"),
            "Health & Safety": (.healthSafety, "cat_hs"),
            "General": (.general, "cat_gen"),
            "Incident Report": (.incident, "cat_incident")
        ]

        let urgencyMap: [String: UrgencyLevel] = [
            "Immediate": .immediate,
            "Next Shift": .nextShift,
            "This Week": .thisWeek,
            "FYI": .fyi
        ]

        var categorizedItems: [CategorizedItem] = []
        var actionItems: [ActionItem] = []

        for item in items {
            let (category, templateId) = categoryMap[item.category] ?? (.general, "cat_gen")
            let urgency = urgencyMap[item.urgency] ?? .fyi

            categorizedItems.append(CategorizedItem(
                category: category,
                categoryTemplateId: templateId,
                content: item.content,
                urgency: urgency
            ))

            if item.actionRequired, let task = item.actionTask, !task.isEmpty {
                actionItems.append(ActionItem(
                    task: task,
                    category: category,
                    categoryTemplateId: templateId,
                    urgency: urgency
                ))
            }
        }

        return (categorizedItems, actionItems)
    }

    private func confidenceWarning(transcript: String, itemCount: Int) -> String? {
        let lower = transcript.lowercased()
        let wordCount = transcript.split(separator: " ").count

        let ordinalCues = ["first", "second", "third", "fourth", "fifth",
                           "number one", "number two", "number three",
                           "next thing", "another thing", "also ", "and then ",
                           "on top of that", "additionally"]
        let numberedCues = lower.matches(of: /\b\d+[\.\)\:]\s/).count

        var cueCount = numberedCues
        for cue in ordinalCues {
            if lower.contains(cue) { cueCount += 1 }
        }

        let imperativeVerbs = ["check ", "fix ", "order ", "replace ", "clean ", "call ",
                               "tell ", "ask ", "make sure ", "follow up", "restock ",
                               "notify ", "schedule ", "update "]
        var imperativeCount = 0
        for verb in imperativeVerbs {
            if lower.contains(verb) { imperativeCount += 1 }
        }

        let expectedMinItems = max(cueCount, imperativeCount > 2 ? imperativeCount : 0)

        if expectedMinItems >= 2 && itemCount < expectedMinItems {
            return "This transcript appears to contain \(expectedMinItems)+ distinct items but only \(itemCount) were extracted. Review and split items if needed."
        }

        if wordCount > 40 && itemCount <= 1 {
            return "This transcript may contain multiple topics that were grouped together. Review and split items if needed."
        }
        return nil
    }
}
