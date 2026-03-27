import Foundation
import OSLog

nonisolated struct AIStructuredItem: Codable, Sendable {
    let content: String
    let category: String
    let urgency: String
    let actionRequired: Bool
    let actionTask: String?
    let sourceQuote: String?
    let entityType: String?
    let normalizedSubject: String?
    let actionClass: String?

    enum CodingKeys: String, CodingKey {
        case content
        case category
        case urgency
        case actionRequired
        case actionTask
        case sourceQuote = "source_quote"
        case entityType = "entity_type"
        case normalizedSubject = "normalized_subject"
        case actionClass = "action_class"
    }
}

nonisolated struct AIStructuredNote: Codable, Sendable {
    let summary: String
    let items: [AIStructuredItem]
    let itemCount: Int?
    let transcriptCoverage: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case summary
        case items
        case itemCount = "item_count"
        case transcriptCoverage = "transcript_coverage"
        case notes
    }
}

nonisolated enum TranscriptCoverage: String, Sendable {
    case complete
    case partial
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
    case invalidResponse(String)
    case timeout

    var userMessage: String {
        switch self {
        case .emptyTranscript: return "No transcript to process."
        case .noBaseURL, .invalidURL: return "Service configuration error."
        case .serverError(let msg): return msg
        case .aiUnavailable(let msg): return msg
        case .decodingError: return "Failed to parse AI response."
        case .invalidResponse(let details): return "AI response failed validation. \(details)"
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
    let transcriptCoverage: String?

    init(
        summary: String,
        categorizedItems: [CategorizedItem],
        actionItems: [ActionItem],
        usedAI: Bool,
        warning: String?,
        transcriptCoverage: String? = nil
    ) {
        self.summary = summary
        self.categorizedItems = categorizedItems
        self.actionItems = actionItems
        self.usedAI = usedAI
        self.warning = warning
        self.transcriptCoverage = transcriptCoverage
    }
}

nonisolated struct StructuringRequestContext: Sendable {
    let estimatedTopicCount: Int
    let averageSegmentConfidence: Double?
    let lowConfidencePhrases: [String]
    let availableCategories: [String]
    let industryVocabulary: [String]
    let categorizationHints: [String]
    let industryRoles: [String]
    let industryEquipment: [String]
    let industrySlang: [String]

    init(
        estimatedTopicCount: Int,
        averageSegmentConfidence: Double? = nil,
        lowConfidencePhrases: [String] = [],
        availableCategories: [String] = [],
        industryVocabulary: [String] = [],
        categorizationHints: [String] = [],
        industryRoles: [String] = [],
        industryEquipment: [String] = [],
        industrySlang: [String] = []
    ) {
        self.estimatedTopicCount = estimatedTopicCount
        self.averageSegmentConfidence = averageSegmentConfidence
        self.lowConfidencePhrases = lowConfidencePhrases
        self.availableCategories = availableCategories
        self.industryVocabulary = industryVocabulary
        self.categorizationHints = categorizationHints
        self.industryRoles = industryRoles
        self.industryEquipment = industryEquipment
        self.industrySlang = industrySlang
    }
}

final class NoteStructuringService {
    static let shared = NoteStructuringService()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let featureFlags: FeatureFlagService
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShiftVoice", category: "NoteStructuring")

    private var baseURL: String {
        let url = Config.EXPO_PUBLIC_RORK_API_BASE_URL
        if url.isEmpty || url == "EXPO_PUBLIC_RORK_API_BASE_URL" { return "" }
        return url
    }

    private init(featureFlags: FeatureFlagService = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        self.featureFlags = featureFlags
    }

    func structureTranscript(_ transcript: String, businessType: String, authToken: String?, userId: String?, context: StructuringRequestContext? = nil, shiftType: String? = nil, locationId: String? = nil, industryType: String? = nil, attemptId: String? = nil, shouldAttemptUnauthorizedRecovery: Bool = true) async -> Result<StructuringResult, StructuringError> {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyTranscript)
        }
        guard !baseURL.isEmpty else { return .failure(.noBaseURL) }
        guard let url = URL(string: "\(baseURL)/api/rest/structure-transcript") else { return .failure(.invalidURL) }
        let correlationId = attemptId ?? UUID().uuidString

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let apiToken = APIService.shared.currentAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiUserId = APIService.shared.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedToken = apiToken?.isEmpty == false ? apiToken : authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedUserId = apiUserId?.isEmpty == false ? apiUserId : userId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if ((resolvedToken?.isEmpty ?? true) || (resolvedUserId?.isEmpty ?? true)) && shouldAttemptUnauthorizedRecovery {
            logger.info("Structuring attempt=\(correlationId, privacy: .public) missing auth headers; triggering recovery")
            let recovered = await APIService.shared.recoverUnauthorizedSessionIfNeeded()
            if recovered {
                resolvedToken = APIService.shared.currentAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedUserId = APIService.shared.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let token = resolvedToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid = resolvedUserId, !uid.isEmpty {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }

        var body: [String: Any] = [
            "transcript": transcript,
            "businessType": businessType
        ]
        if let shiftType { body["shiftType"] = shiftType }
        if let locationId { body["locationId"] = locationId }
        if let industryType { body["industryType"] = industryType }
        if let estimatedTopicCount = context?.estimatedTopicCount {
            body["estimatedTopicCount"] = estimatedTopicCount
        }
        if let averageSegmentConfidence = context?.averageSegmentConfidence {
            body["averageSegmentConfidence"] = averageSegmentConfidence
        }
        if let lowConfidencePhrases = context?.lowConfidencePhrases, !lowConfidencePhrases.isEmpty {
            body["lowConfidencePhrases"] = lowConfidencePhrases
        }
        if let availableCategories = context?.availableCategories, !availableCategories.isEmpty {
            body["availableCategories"] = availableCategories
        }
        if let industryVocabulary = context?.industryVocabulary, !industryVocabulary.isEmpty {
            body["industryVocabulary"] = industryVocabulary
        }
        if let categorizationHints = context?.categorizationHints, !categorizationHints.isEmpty {
            body["categorizationHints"] = categorizationHints
        }
        if let industryRoles = context?.industryRoles, !industryRoles.isEmpty {
            body["industryRoles"] = industryRoles
        }
        if let industryEquipment = context?.industryEquipment, !industryEquipment.isEmpty {
            body["industryEquipment"] = industryEquipment
        }
        if let industrySlang = context?.industrySlang, !industrySlang.isEmpty {
            body["industrySlang"] = industrySlang
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.serverError("Invalid server response."))
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401, shouldAttemptUnauthorizedRecovery,
                   await APIService.shared.recoverUnauthorizedSessionIfNeeded() {
                    logger.info("Structuring attempt=\(correlationId, privacy: .public) recovered after 401; retrying once")
                    return await structureTranscript(
                        transcript,
                        businessType: businessType,
                        authToken: APIService.shared.currentAuthToken,
                        userId: APIService.shared.currentUserId,
                        context: context,
                        shiftType: shiftType,
                        locationId: locationId,
                        industryType: industryType,
                        attemptId: correlationId,
                        shouldAttemptUnauthorizedRecovery: false
                    )
                }
                if let errorResp = try? decoder.decode(AIStructureResponse.self, from: data), let msg = errorResp.error {
                    logger.error("Structuring attempt=\(correlationId, privacy: .public) failed status=\(httpResponse.statusCode, privacy: .public) error=\(msg, privacy: .public)")
                    return .failure(.aiUnavailable(msg))
                }
                logger.error("Structuring attempt=\(correlationId, privacy: .public) failed status=\(httpResponse.statusCode, privacy: .public)")
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

            if featureFlags.structuringStrictValidationEnabled,
               let validationError = validateStructuredPayload(structured) {
                return .failure(.invalidResponse(validationError))
            }

            let (categorizedItems, actionItems) = mapAIItems(structured.items, strictValidation: featureFlags.structuringStrictValidationEnabled)

            if categorizedItems.isEmpty {
                return .failure(.aiUnavailable("AI returned no structured items."))
            }

            let warning = confidenceWarning(transcript: transcript, itemCount: categorizedItems.count)

            return .success(StructuringResult(
                summary: structured.summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems,
                usedAI: true,
                warning: warning,
                transcriptCoverage: structured.transcriptCoverage
            ))
        } catch let error as URLError {
            if error.code == .timedOut {
                return .failure(.timeout)
            }
            return .failure(.serverError("Network unavailable. Structured locally."))
        } catch {
            return .failure(.serverError("Network error: \(error.localizedDescription)"))
        }
    }

    private func mapAIItems(_ items: [AIStructuredItem], strictValidation: Bool) -> ([CategorizedItem], [ActionItem]) {
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
            guard !strictValidation || categoryMap[item.category] != nil else { continue }
            guard !strictValidation || urgencyMap[item.urgency] != nil else { continue }

            let (category, templateId) = categoryMap[item.category] ?? (.general, "cat_gen")
            let urgency = urgencyMap[item.urgency] ?? .fyi

            categorizedItems.append(CategorizedItem(
                category: category,
                categoryTemplateId: templateId,
                content: item.content,
                urgency: urgency,
                sourceQuote: item.sourceQuote,
                entityType: item.entityType,
                normalizedSubject: item.normalizedSubject,
                actionClass: item.actionClass
            ))

            if item.actionRequired, let task = item.actionTask, !task.isEmpty {
                actionItems.append(ActionItem(
                    task: TranscriptProcessor.polishActionTask(task),
                    category: category,
                    categoryTemplateId: templateId,
                    urgency: urgency,
                    entityType: item.entityType,
                    normalizedSubject: item.normalizedSubject,
                    actionClass: item.actionClass
                ))
            }
        }

        return (categorizedItems, actionItems)
    }

    private func validateStructuredPayload(_ structured: AIStructuredNote) -> String? {
        if structured.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Missing summary."
        }

        if structured.items.isEmpty {
            return "No items were returned."
        }

        if let itemCount = structured.itemCount, itemCount != structured.items.count {
            return "item_count does not match items length."
        }

        if let transcriptCoverage = structured.transcriptCoverage?.lowercased(), TranscriptCoverage(rawValue: transcriptCoverage) == nil {
            return "transcript_coverage must be complete or partial."
        }

        let validUrgencies: Set<String> = ["Immediate", "Next Shift", "This Week", "FYI"]
        let validCategories: Set<String> = [
            "86'd Items", "Equipment", "Guest Issues", "Staff Notes", "Reservations/VIP", "Inventory", "Maintenance", "Health & Safety", "General", "Incident Report"
        ]

        for item in structured.items {
            if item.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Item content is required."
            }
            if !validUrgencies.contains(item.urgency) {
                return "Invalid urgency value: \(item.urgency)."
            }
            if !validCategories.contains(item.category) {
                return "Invalid category value: \(item.category)."
            }
            let quote = item.sourceQuote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if quote.isEmpty {
                return "source_quote is required for every item."
            }
        }

        return nil
    }

    func refineActionItemText(_ text: String, authToken: String?, userId: String?) async -> String? {
        guard !baseURL.isEmpty else { return nil }
        guard let url = URL(string: "\(baseURL)/api/rest/refine-action-item") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }

        let body: [String: Any] = ["text": text]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let success = json["success"] as? Bool, success,
                  let refined = json["refined"] as? String, !refined.isEmpty else { return nil }
            return refined
        } catch {
            return nil
        }
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
