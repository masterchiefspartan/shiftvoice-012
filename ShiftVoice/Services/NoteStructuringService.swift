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

    func structureTranscript(_ transcript: String, businessType: String, authToken: String?, userId: String?) async -> (summary: String, categorizedItems: [CategorizedItem], actionItems: [ActionItem])? {
        guard !baseURL.isEmpty, !transcript.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/rest/structure-transcript") else { return nil }

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

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let aiResponse = try decoder.decode(AIStructureResponse.self, from: data)
            guard aiResponse.success, let structured = aiResponse.structured else { return nil }

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

            for item in structured.items {
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

            if categorizedItems.isEmpty {
                return nil
            }

            return (structured.summary, categorizedItems, actionItems)
        } catch {
            return nil
        }
    }
}
