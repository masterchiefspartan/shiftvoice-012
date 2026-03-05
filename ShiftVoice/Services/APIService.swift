import Foundation

nonisolated enum APIError: Error, Sendable, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)
    case noData
    case rateLimited
    case validationError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .unauthorized: return "Session expired. Please sign in again."
        case .serverError(let msg): return msg
        case .networkError(let err): return err.localizedDescription
        case .decodingError: return "Unable to process server response"
        case .noData: return "No data available"
        case .rateLimited: return "Too many requests. Please wait a moment."
        case .validationError(let msg): return msg
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .rateLimited: return true
        default: return false
        }
    }
}

nonisolated struct AuthResponse: Codable, Sendable {
    let success: Bool
    let userId: String?
    let token: String?
    let name: String?
    let email: String?
    let error: String?
}

nonisolated struct SyncPullResponse: Codable, Sendable {
    let hasData: Bool
    let data: SyncData?
    let isDelta: Bool?
}

nonisolated struct SyncData: Codable, Sendable {
    let userId: String?
    let organization: OrganizationDTO?
    let locations: [LocationDTO]?
    let teamMembers: [TeamMemberDTO]?
    let shiftNotes: [ShiftNoteDTO]?
    let recurringIssues: [RecurringIssueDTO]?
    let selectedLocationId: String?
    let updatedAt: String?
}

nonisolated struct ActionItemUpdateResponse: Codable, Sendable {
    let success: Bool
    let noteId: String?
    let actionItemId: String?
    let status: String?
    let error: String?
}

nonisolated struct NoteUpdateResponse: Codable, Sendable {
    let success: Bool
    let noteId: String?
    let error: String?
}

nonisolated struct OrganizationDTO: Codable, Sendable {
    let id: String
    let name: String
    let ownerId: String
    let plan: String?
    let industryType: String?
}

nonisolated struct LocationDTO: Codable, Sendable {
    let id: String
    let name: String
    let address: String?
    let timezone: String?
    let openingTime: String?
    let midTime: String?
    let closingTime: String?
    let managerIds: [String]?
}

nonisolated struct TeamMemberDTO: Codable, Sendable {
    let id: String
    let name: String
    let email: String
    let role: String?
    let roleTemplateId: String?
    let locationIds: [String]?
    let inviteStatus: String?
    let avatarInitials: String?
    let updatedAt: String?
}

nonisolated struct AcknowledgmentDTO: Codable, Sendable {
    let id: String
    let userId: String
    let userName: String
    let timestamp: String?
}

nonisolated struct CategorizedItemDTO: Codable, Sendable {
    let id: String
    let category: String?
    let categoryTemplateId: String?
    let content: String?
    let urgency: String?
    let isResolved: Bool?
    let entityType: String?
    let normalizedSubject: String?
    let actionClass: String?
}

nonisolated struct ChangeHistoryEntryDTO: Codable, Sendable {
    let id: String
    let field: String?
    let fromValue: String?
    let toValue: String?
    let changedBy: String?
    let changedAt: String?
}

nonisolated struct ActionItemDTO: Codable, Sendable {
    let id: String
    let task: String?
    let category: String?
    let categoryTemplateId: String?
    let urgency: String?
    let status: String?
    let assignee: String?
    let updatedAt: String?
    let statusUpdatedAt: String?
    let assigneeUpdatedAt: String?
    let entityType: String?
    let normalizedSubject: String?
    let actionClass: String?
    let changeHistory: [ChangeHistoryEntryDTO]?
    let resolvedAt: String?
}

nonisolated struct VoiceReplyDTO: Codable, Sendable {
    let id: String
    let authorId: String?
    let authorName: String?
    let transcript: String?
    let timestamp: String?
    let parentItemId: String?
}

nonisolated struct ShiftNoteDTO: Codable, Sendable {
    let id: String
    let authorId: String?
    let authorName: String?
    let authorInitials: String?
    let locationId: String?
    let shiftType: String?
    let shiftTemplateId: String?
    let rawTranscript: String?
    let audioUrl: String?
    let audioDuration: Double?
    let summary: String?
    let categorizedItems: [CategorizedItemDTO]?
    let actionItems: [ActionItemDTO]?
    let photoUrls: [String]?
    let acknowledgments: [AcknowledgmentDTO]?
    let voiceReplies: [VoiceReplyDTO]?
    let createdAt: String?
    let updatedAt: String?
    let visibility: String?
    let isSynced: Bool?
}

nonisolated struct RecurringIssueDTO: Codable, Sendable {
    let id: String
    let description: String?
    let category: String?
    let categoryTemplateId: String?
    let locationId: String?
    let locationName: String?
    let mentionCount: Int?
    let relatedNoteIds: [String]?
    let firstMentioned: String?
    let lastMentioned: String?
    let status: String?
}

nonisolated struct SimpleResponse: Codable, Sendable {
    let success: Bool
    let error: String?
}

nonisolated struct SyncPushResponse: Codable, Sendable {
    let success: Bool
    let updatedAt: String?
    let error: String?
}

nonisolated struct PaginatedNotesResponse: Codable, Sendable {
    let notes: [ShiftNoteDTO]
    let totalCount: Int
    let hasMore: Bool
    let nextCursor: String?
}

final class APIService {
    static let shared = APIService()
    typealias UnauthorizedRecoveryHandler = () async -> Bool

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateFormatter: ISO8601DateFormatter

    private(set) var authToken: String?
    private var userId: String?
    private var unauthorizedRecoveryHandler: UnauthorizedRecoveryHandler?

    var currentAuthToken: String? { authToken }
    var currentUserId: String? { userId }

    private var baseURL: String {
        let url = Config.EXPO_PUBLIC_RORK_API_BASE_URL
        if url.isEmpty || url == "EXPO_PUBLIC_RORK_API_BASE_URL" {
            return ""
        }
        return url
    }

    var isConfigured: Bool {
        !baseURL.isEmpty
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        dateFormatter = ISO8601DateFormatter()
    }

    func setAuth(token: String, userId: String) {
        self.authToken = token
        self.userId = userId
    }

    func clearAuth() {
        authToken = nil
        userId = nil
    }

    func setUnauthorizedRecoveryHandler(_ handler: UnauthorizedRecoveryHandler?) {
        unauthorizedRecoveryHandler = handler
    }

    func recoverUnauthorizedSessionIfNeeded() async -> Bool {
        guard let unauthorizedRecoveryHandler else { return false }
        return await unauthorizedRecoveryHandler()
    }

    private func makeRequest(path: String, method: String = "GET", body: Any? = nil, shouldAttemptUnauthorizedRecovery: Bool = true) async throws -> Data {
        guard !baseURL.isEmpty else { throw APIError.invalidURL }
        guard let url = URL(string: "\(baseURL)/api/rest/\(path)") else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                if shouldAttemptUnauthorizedRecovery,
                   let unauthorizedRecoveryHandler,
                   await unauthorizedRecoveryHandler() {
                    return try await makeRequest(
                        path: path,
                        method: method,
                        body: body,
                        shouldAttemptUnauthorizedRecovery: false
                    )
                }
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 429 {
                throw APIError.rateLimited
            }
            if httpResponse.statusCode == 400 {
                if let errorResponse = try? decoder.decode(SimpleResponse.self, from: data),
                   let errorMsg = errorResponse.error {
                    throw APIError.validationError(errorMsg)
                }
                throw APIError.validationError("Invalid request")
            }
            if httpResponse.statusCode >= 500 {
                throw APIError.serverError("Server error (\(httpResponse.statusCode))")
            }
        }

        return data
    }

    private func makeRequestWithRetry(path: String, method: String = "GET", body: Any? = nil, maxRetries: Int = 3) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await makeRequest(path: path, method: method, body: body)
            } catch let error as APIError where error.isRetryable {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt) * 0.5
                    try? await Task.sleep(for: .seconds(delay))
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? APIError.noData
    }

    // MARK: - Auth

    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        let body: [String: Any] = ["name": name, "email": email, "password": password, "authMethod": "email"]
        let data = try await makeRequest(path: "auth/register", method: "POST", body: body)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await makeRequest(path: "auth/login", method: "POST", body: body)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func googleAuth(googleUserId: String, name: String, email: String) async throws -> AuthResponse {
        let body: [String: Any] = ["googleUserId": googleUserId, "name": name, "email": email]
        let data = try await makeRequest(path: "auth/google", method: "POST", body: body)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func firebaseAuth(idToken: String, uid: String, name: String, email: String) async throws -> AuthResponse {
        let body: [String: Any] = ["idToken": idToken, "uid": uid, "name": name, "email": email]
        let data = try await makeRequest(path: "auth/firebase", method: "POST", body: body)
        return try decoder.decode(AuthResponse.self, from: data)
    }

    func logout() async throws {
        _ = try await makeRequest(path: "auth/logout", method: "POST", body: [:] as [String: String])
    }

    func registerDeviceToken(_ token: String) async throws -> SimpleResponse {
        let body: [String: Any] = ["deviceToken": token, "platform": "ios"]
        let data = try await makeRequest(path: "auth/device-token", method: "POST", body: body)
        return try decoder.decode(SimpleResponse.self, from: data)
    }

    // MARK: - Sync

    func pullData(updatedSince: Date? = nil) async throws -> SyncPullResponse {
        var path = "sync"
        if let since = updatedSince {
            let sinceStr = dateFormatter.string(from: since)
            path += "?updatedSince=\(sinceStr)"
        }
        let data = try await makeRequestWithRetry(path: path)
        return try decoder.decode(SyncPullResponse.self, from: data)
    }

    func pushData(appData: AppData) async throws -> SyncPushResponse {
        let orgDict = encodeOrganization(appData.organization)
        let locationsArr = appData.locations.map { encodeLocation($0) }
        let teamArr = appData.teamMembers.map { encodeTeamMember($0) }
        let notesArr = appData.shiftNotes.map { encodeShiftNote($0) }
        let issuesArr = appData.recurringIssues.map { encodeRecurringIssue($0) }

        let body: [String: Any] = [
            "organization": orgDict,
            "locations": locationsArr,
            "teamMembers": teamArr,
            "shiftNotes": notesArr,
            "recurringIssues": issuesArr,
            "selectedLocationId": appData.selectedLocationId as Any
        ]

        let data = try await makeRequestWithRetry(path: "sync", method: "POST", body: body)
        return try decoder.decode(SyncPushResponse.self, from: data)
    }

    // MARK: - Paginated Notes

    func fetchNotes(locationId: String?, shiftFilter: String? = nil, cursor: String? = nil, limit: Int = 20) async throws -> PaginatedNotesResponse {
        var queryItems: [String] = []
        if let locationId { queryItems.append("locationId=\(locationId)") }
        if let shiftFilter { queryItems.append("shiftFilter=\(shiftFilter)") }
        if let cursor { queryItems.append("cursor=\(cursor)") }
        queryItems.append("limit=\(limit)")
        queryItems.append("visibilityScope=team")
        let query = queryItems.joined(separator: "&")
        let data = try await makeRequest(path: "shift-notes?\(query)")
        return try decoder.decode(PaginatedNotesResponse.self, from: data)
    }

    // MARK: - Granular Note Operations

    func updateNote(noteId: String, updates: [String: Any]) async throws -> NoteUpdateResponse {
        let data = try await makeRequestWithRetry(path: "shift-notes/\(noteId)", method: "PATCH", body: updates)
        return try decoder.decode(NoteUpdateResponse.self, from: data)
    }

    func updateActionItemStatus(noteId: String, actionItemId: String, status: String) async throws -> ActionItemUpdateResponse {
        let body: [String: Any] = ["status": status]
        let data = try await makeRequestWithRetry(path: "shift-notes/\(noteId)/action-items/\(actionItemId)", method: "PATCH", body: body)
        return try decoder.decode(ActionItemUpdateResponse.self, from: data)
    }

    func acknowledgeNote(noteId: String, userId: String, userName: String) async throws -> SimpleResponse {
        let body: [String: Any] = [
            "id": UUID().uuidString,
            "userId": userId,
            "userName": userName,
            "timestamp": dateFormatter.string(from: Date())
        ]
        let data = try await makeRequestWithRetry(path: "shift-notes/\(noteId)/acknowledge", method: "POST", body: body)
        return try decoder.decode(SimpleResponse.self, from: data)
    }

    func updateLocation(locationId: String, updates: [String: Any]) async throws -> SimpleResponse {
        let data = try await makeRequestWithRetry(path: "locations/\(locationId)", method: "PATCH", body: updates)
        return try decoder.decode(SimpleResponse.self, from: data)
    }

    func updateTeamMember(memberId: String, updates: [String: Any]) async throws -> SimpleResponse {
        let data = try await makeRequestWithRetry(path: "team/\(memberId)", method: "PATCH", body: updates)
        return try decoder.decode(SimpleResponse.self, from: data)
    }

    // MARK: - Encoding Helpers

    private func encodeOrganization(_ org: Organization) -> [String: Any] {
        [
            "id": org.id,
            "name": org.name,
            "ownerId": org.ownerId,
            "plan": org.plan.rawValue,
            "industryType": org.industryType.rawValue
        ]
    }

    private func encodeLocation(_ loc: Location) -> [String: Any] {
        [
            "id": loc.id,
            "name": loc.name,
            "address": loc.address,
            "timezone": loc.timezone,
            "openingTime": loc.openingTime,
            "midTime": loc.midTime,
            "closingTime": loc.closingTime,
            "managerIds": loc.managerIds
        ]
    }

    private func encodeTeamMember(_ member: TeamMember) -> [String: Any] {
        var dict: [String: Any] = [
            "id": member.id,
            "name": member.name,
            "email": member.email,
            "role": member.role.rawValue,
            "locationIds": member.locationIds,
            "inviteStatus": member.inviteStatus.rawValue,
            "avatarInitials": member.avatarInitials,
            "updatedAt": dateFormatter.string(from: member.updatedAt)
        ]
        if let templateId = member.roleTemplateId {
            dict["roleTemplateId"] = templateId
        }
        return dict
    }

    private func encodeShiftNote(_ note: ShiftNote) -> [String: Any] {
        var dict: [String: Any] = [
            "id": note.id,
            "authorId": note.authorId,
            "authorName": note.authorName,
            "authorInitials": note.authorInitials,
            "locationId": note.locationId,
            "shiftType": note.shiftType.rawValue,
            "rawTranscript": note.rawTranscript,
            "audioDuration": note.audioDuration,
            "summary": note.summary,
            "photoUrls": note.photoUrls,
            "createdAt": dateFormatter.string(from: note.createdAt),
            "updatedAt": dateFormatter.string(from: note.updatedAt),
            "isSynced": note.isSynced,
            "visibility": note.visibility.rawValue,
            "categorizedItems": note.categorizedItems.map { encodeCategorizedItem($0) },
            "actionItems": note.actionItems.map { encodeActionItem($0) },
            "acknowledgments": note.acknowledgments.map { encodeAcknowledgment($0) },
            "voiceReplies": note.voiceReplies.map { encodeVoiceReply($0) }
        ]
        if let templateId = note.shiftTemplateId { dict["shiftTemplateId"] = templateId }
        if let audioUrl = note.audioUrl { dict["audioUrl"] = audioUrl }
        return dict
    }

    private func encodeCategorizedItem(_ item: CategorizedItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "category": item.category.rawValue,
            "content": item.content,
            "urgency": item.urgency.rawValue,
            "isResolved": item.isResolved
        ]
        if let templateId = item.categoryTemplateId { dict["categoryTemplateId"] = templateId }
        if let entityType = item.entityType { dict["entityType"] = entityType }
        if let normalizedSubject = item.normalizedSubject { dict["normalizedSubject"] = normalizedSubject }
        if let actionClass = item.actionClass { dict["actionClass"] = actionClass }
        return dict
    }

    private func encodeActionItem(_ item: ActionItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "task": item.task,
            "category": item.category.rawValue,
            "urgency": item.urgency.rawValue,
            "status": item.status.rawValue,
            "updatedAt": dateFormatter.string(from: item.updatedAt),
            "statusUpdatedAt": dateFormatter.string(from: item.statusUpdatedAt),
            "assigneeUpdatedAt": dateFormatter.string(from: item.assigneeUpdatedAt)
        ]
        if let templateId = item.categoryTemplateId { dict["categoryTemplateId"] = templateId }
        if let assignee = item.assignee { dict["assignee"] = assignee }
        if let entityType = item.entityType { dict["entityType"] = entityType }
        if let normalizedSubject = item.normalizedSubject { dict["normalizedSubject"] = normalizedSubject }
        if let actionClass = item.actionClass { dict["actionClass"] = actionClass }
        if !item.changeHistory.isEmpty {
            dict["changeHistory"] = item.changeHistory.map { encodeChangeHistoryEntry($0) }
        }
        if let resolvedAt = item.resolvedAt { dict["resolvedAt"] = dateFormatter.string(from: resolvedAt) }
        return dict
    }

    private func encodeChangeHistoryEntry(_ entry: ChangeHistoryEntry) -> [String: Any] {
        var dict: [String: Any] = [
            "id": entry.id,
            "field": entry.field,
            "toValue": entry.toValue,
            "changedBy": entry.changedBy,
            "changedAt": dateFormatter.string(from: entry.changedAt)
        ]
        if let fromValue = entry.fromValue { dict["fromValue"] = fromValue }
        return dict
    }

    private func encodeAcknowledgment(_ ack: Acknowledgment) -> [String: Any] {
        [
            "id": ack.id,
            "userId": ack.userId,
            "userName": ack.userName,
            "timestamp": dateFormatter.string(from: ack.timestamp)
        ]
    }

    private func encodeVoiceReply(_ reply: VoiceReply) -> [String: Any] {
        var dict: [String: Any] = [
            "id": reply.id,
            "authorId": reply.authorId,
            "authorName": reply.authorName,
            "transcript": reply.transcript,
            "timestamp": dateFormatter.string(from: reply.timestamp)
        ]
        if let parentId = reply.parentItemId { dict["parentItemId"] = parentId }
        return dict
    }

    private func encodeRecurringIssue(_ issue: RecurringIssue) -> [String: Any] {
        var dict: [String: Any] = [
            "id": issue.id,
            "description": issue.description,
            "category": issue.category.rawValue,
            "locationId": issue.locationId,
            "locationName": issue.locationName,
            "mentionCount": issue.mentionCount,
            "relatedNoteIds": issue.relatedNoteIds,
            "firstMentioned": dateFormatter.string(from: issue.firstMentioned),
            "lastMentioned": dateFormatter.string(from: issue.lastMentioned),
            "status": issue.status.rawValue
        ]
        if let templateId = issue.categoryTemplateId { dict["categoryTemplateId"] = templateId }
        return dict
    }

    // MARK: - Decoding Helpers

    func decodeOrganization(_ dto: OrganizationDTO) -> Organization {
        Organization(
            id: dto.id,
            name: dto.name,
            ownerId: dto.ownerId,
            plan: SubscriptionPlan(rawValue: dto.plan ?? "Free") ?? .free,
            industryType: IndustryType(rawValue: dto.industryType ?? "Restaurant") ?? .restaurant
        )
    }

    func decodeLocation(_ dto: LocationDTO) -> Location {
        Location(
            id: dto.id,
            name: dto.name,
            address: dto.address ?? "",
            timezone: dto.timezone ?? "America/New_York",
            openingTime: dto.openingTime ?? "06:00",
            midTime: dto.midTime ?? "14:00",
            closingTime: dto.closingTime ?? "22:00",
            managerIds: dto.managerIds ?? []
        )
    }

    func decodeTeamMember(_ dto: TeamMemberDTO) -> TeamMember {
        let updatedAt: Date = {
            if let str = dto.updatedAt { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        return TeamMember(
            id: dto.id,
            name: dto.name,
            email: dto.email,
            role: ManagerRole(rawValue: dto.role ?? "Manager") ?? .manager,
            roleTemplateId: dto.roleTemplateId,
            locationIds: dto.locationIds ?? [],
            inviteStatus: InviteStatus(rawValue: dto.inviteStatus ?? "Accepted") ?? .accepted,
            avatarInitials: dto.avatarInitials,
            updatedAt: updatedAt
        )
    }

    func decodeShiftNote(_ dto: ShiftNoteDTO) -> ShiftNote {
        let createdAt: Date = {
            if let str = dto.createdAt { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        let updatedAt: Date = {
            if let str = dto.updatedAt { return dateFormatter.date(from: str) ?? createdAt }
            return createdAt
        }()
        return ShiftNote(
            id: dto.id,
            authorId: dto.authorId ?? "",
            authorName: dto.authorName ?? "",
            authorInitials: dto.authorInitials ?? "",
            locationId: dto.locationId ?? "",
            shiftType: ShiftType(rawValue: dto.shiftType ?? "Closing") ?? .closing,
            shiftTemplateId: dto.shiftTemplateId,
            rawTranscript: dto.rawTranscript ?? "",
            audioUrl: dto.audioUrl,
            audioDuration: dto.audioDuration ?? 0,
            summary: dto.summary ?? "",
            categorizedItems: (dto.categorizedItems ?? []).map { decodeCategorizedItem($0) },
            actionItems: (dto.actionItems ?? []).map { decodeActionItem($0) },
            photoUrls: dto.photoUrls ?? [],
            acknowledgments: (dto.acknowledgments ?? []).map { decodeAcknowledgment($0) },
            voiceReplies: (dto.voiceReplies ?? []).map { decodeVoiceReply($0) },
            createdAt: createdAt,
            updatedAt: updatedAt,
            visibility: NoteVisibility(rawValue: dto.visibility ?? "team") ?? .team,
            isSynced: dto.isSynced ?? true
        )
    }

    private func decodeCategorizedItem(_ dto: CategorizedItemDTO) -> CategorizedItem {
        CategorizedItem(
            id: dto.id,
            category: NoteCategory(rawValue: dto.category ?? "General") ?? .general,
            categoryTemplateId: dto.categoryTemplateId,
            content: dto.content ?? "",
            urgency: UrgencyLevel(rawValue: dto.urgency ?? "FYI") ?? .fyi,
            isResolved: dto.isResolved ?? false,
            entityType: dto.entityType,
            normalizedSubject: dto.normalizedSubject,
            actionClass: dto.actionClass
        )
    }

    private func decodeActionItem(_ dto: ActionItemDTO) -> ActionItem {
        let updatedAt: Date = {
            if let str = dto.updatedAt { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        let statusUpdatedAt: Date = {
            if let str = dto.statusUpdatedAt { return dateFormatter.date(from: str) ?? updatedAt }
            return updatedAt
        }()
        let assigneeUpdatedAt: Date = {
            if let str = dto.assigneeUpdatedAt { return dateFormatter.date(from: str) ?? updatedAt }
            return updatedAt
        }()
        let changeHistory: [ChangeHistoryEntry] = (dto.changeHistory ?? []).compactMap { entryDTO in
            guard let field = entryDTO.field, let toValue = entryDTO.toValue, let changedBy = entryDTO.changedBy else { return nil }
            let changedAt: Date = {
                if let str = entryDTO.changedAt { return dateFormatter.date(from: str) ?? Date() }
                return Date()
            }()
            return ChangeHistoryEntry(id: entryDTO.id, field: field, fromValue: entryDTO.fromValue, toValue: toValue, changedBy: changedBy, changedAt: changedAt)
        }
        let resolvedAt: Date? = {
            if let str = dto.resolvedAt { return dateFormatter.date(from: str) }
            return nil
        }()
        return ActionItem(
            id: dto.id,
            task: dto.task ?? "",
            category: NoteCategory(rawValue: dto.category ?? "General") ?? .general,
            categoryTemplateId: dto.categoryTemplateId,
            urgency: UrgencyLevel(rawValue: dto.urgency ?? "FYI") ?? .fyi,
            status: ActionItemStatus(rawValue: dto.status ?? "Open") ?? .open,
            assignee: dto.assignee,
            updatedAt: updatedAt,
            statusUpdatedAt: statusUpdatedAt,
            assigneeUpdatedAt: assigneeUpdatedAt,
            entityType: dto.entityType,
            normalizedSubject: dto.normalizedSubject,
            actionClass: dto.actionClass,
            changeHistory: changeHistory,
            resolvedAt: resolvedAt
        )
    }

    private func decodeAcknowledgment(_ dto: AcknowledgmentDTO) -> Acknowledgment {
        let timestamp: Date = {
            if let str = dto.timestamp { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        return Acknowledgment(id: dto.id, userId: dto.userId, userName: dto.userName, timestamp: timestamp)
    }

    private func decodeVoiceReply(_ dto: VoiceReplyDTO) -> VoiceReply {
        let timestamp: Date = {
            if let str = dto.timestamp { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        return VoiceReply(
            id: dto.id,
            authorId: dto.authorId ?? "",
            authorName: dto.authorName ?? "",
            transcript: dto.transcript ?? "",
            timestamp: timestamp,
            parentItemId: dto.parentItemId
        )
    }

    func decodeRecurringIssue(_ dto: RecurringIssueDTO) -> RecurringIssue {
        let firstMentioned: Date = {
            if let str = dto.firstMentioned { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        let lastMentioned: Date = {
            if let str = dto.lastMentioned { return dateFormatter.date(from: str) ?? Date() }
            return Date()
        }()
        return RecurringIssue(
            id: dto.id,
            description: dto.description ?? "",
            category: NoteCategory(rawValue: dto.category ?? "General") ?? .general,
            categoryTemplateId: dto.categoryTemplateId,
            locationId: dto.locationId ?? "",
            locationName: dto.locationName ?? "",
            mentionCount: dto.mentionCount ?? 0,
            relatedNoteIds: dto.relatedNoteIds ?? [],
            firstMentioned: firstMentioned,
            lastMentioned: lastMentioned,
            status: RecurringIssueStatus(rawValue: dto.status ?? "Active") ?? .active
        )
    }
}
