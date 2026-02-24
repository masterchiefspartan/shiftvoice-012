import Foundation

nonisolated enum ShiftType: String, CaseIterable, Identifiable, Codable, Sendable {
    case opening = "Opening"
    case mid = "Mid"
    case closing = "Closing"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .opening: return "sunrise.fill"
        case .mid: return "sun.max.fill"
        case .closing: return "moon.stars.fill"
        }
    }
}

nonisolated enum UrgencyLevel: String, CaseIterable, Identifiable, Codable, Sendable {
    case immediate = "Immediate"
    case nextShift = "Next Shift"
    case thisWeek = "This Week"
    case fyi = "FYI"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .immediate: return 0
        case .nextShift: return 1
        case .thisWeek: return 2
        case .fyi: return 3
        }
    }
}

nonisolated enum NoteCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case eightySixed = "86'd Items"
    case equipment = "Equipment"
    case guestIssue = "Guest Issues"
    case staffNote = "Staff Notes"
    case reservation = "Reservations/VIP"
    case inventory = "Inventory"
    case maintenance = "Maintenance"
    case healthSafety = "Health & Safety"
    case general = "General"
    case incident = "Incident Report"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .eightySixed: return "xmark.circle.fill"
        case .equipment: return "wrench.and.screwdriver.fill"
        case .guestIssue: return "person.crop.circle.badge.exclamationmark.fill"
        case .staffNote: return "person.2.fill"
        case .reservation: return "star.fill"
        case .inventory: return "shippingbox.fill"
        case .maintenance: return "hammer.fill"
        case .healthSafety: return "cross.circle.fill"
        case .general: return "doc.text.fill"
        case .incident: return "exclamationmark.shield.fill"
        }
    }
}

nonisolated enum ActionItemStatus: String, Codable, Sendable {
    case open = "Open"
    case inProgress = "In Progress"
    case resolved = "Resolved"
}

nonisolated struct CategorizedItem: Identifiable, Codable, Sendable {
    let id: String
    let category: NoteCategory
    let categoryTemplateId: String?
    let content: String
    let urgency: UrgencyLevel
    var isResolved: Bool

    init(id: String = UUID().uuidString, category: NoteCategory, categoryTemplateId: String? = nil, content: String, urgency: UrgencyLevel, isResolved: Bool = false) {
        self.id = id
        self.category = category
        self.categoryTemplateId = categoryTemplateId
        self.content = content
        self.urgency = urgency
        self.isResolved = isResolved
    }

    var displayInfo: CategoryDisplayInfo {
        if let templateId = categoryTemplateId,
           let template = CategoryTemplateResolver.resolve(id: templateId) {
            return CategoryDisplayInfo(from: template)
        }
        return CategoryDisplayInfo(from: category)
    }
}

nonisolated struct ActionItem: Identifiable, Codable, Sendable {
    let id: String
    let task: String
    let category: NoteCategory
    let categoryTemplateId: String?
    let urgency: UrgencyLevel
    var status: ActionItemStatus
    var assignee: String?
    var updatedAt: Date
    var statusUpdatedAt: Date
    var assigneeUpdatedAt: Date
    var hasConflict: Bool
    var conflictDescription: String?

    init(id: String = UUID().uuidString, task: String, category: NoteCategory, categoryTemplateId: String? = nil, urgency: UrgencyLevel, status: ActionItemStatus = .open, assignee: String? = nil, updatedAt: Date = Date(), statusUpdatedAt: Date? = nil, assigneeUpdatedAt: Date? = nil, hasConflict: Bool = false, conflictDescription: String? = nil) {
        self.id = id
        self.task = task
        self.category = category
        self.categoryTemplateId = categoryTemplateId
        self.urgency = urgency
        self.status = status
        self.assignee = assignee
        self.updatedAt = updatedAt
        self.statusUpdatedAt = statusUpdatedAt ?? updatedAt
        self.assigneeUpdatedAt = assigneeUpdatedAt ?? updatedAt
        self.hasConflict = hasConflict
        self.conflictDescription = conflictDescription
    }

    var displayInfo: CategoryDisplayInfo {
        if let templateId = categoryTemplateId,
           let template = CategoryTemplateResolver.resolve(id: templateId) {
            return CategoryDisplayInfo(from: template)
        }
        return CategoryDisplayInfo(from: category)
    }
}

nonisolated struct Acknowledgment: Identifiable, Codable, Sendable {
    let id: String
    let userId: String
    let userName: String
    let timestamp: Date

    init(id: String = UUID().uuidString, userId: String, userName: String, timestamp: Date = Date()) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.timestamp = timestamp
    }
}

nonisolated struct VoiceReply: Identifiable, Codable, Sendable {
    let id: String
    let authorId: String
    let authorName: String
    let transcript: String
    let timestamp: Date
    let parentItemId: String?

    init(id: String = UUID().uuidString, authorId: String, authorName: String, transcript: String, timestamp: Date = Date(), parentItemId: String? = nil) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.transcript = transcript
        self.timestamp = timestamp
        self.parentItemId = parentItemId
    }
}

nonisolated struct ShiftNote: Identifiable, Codable, Sendable {
    let id: String
    let authorId: String
    let authorName: String
    let authorInitials: String
    let locationId: String
    let shiftType: ShiftType
    let shiftTemplateId: String?
    let rawTranscript: String
    let audioUrl: String?
    let audioDuration: TimeInterval
    let summary: String
    let categorizedItems: [CategorizedItem]
    var actionItems: [ActionItem]
    let photoUrls: [String]
    var acknowledgments: [Acknowledgment]
    var voiceReplies: [VoiceReply]
    let createdAt: Date
    var updatedAt: Date
    var isSynced: Bool
    var isDirty: Bool

    init(
        id: String = UUID().uuidString,
        authorId: String,
        authorName: String,
        authorInitials: String,
        locationId: String,
        shiftType: ShiftType,
        shiftTemplateId: String? = nil,
        rawTranscript: String,
        audioUrl: String? = nil,
        audioDuration: TimeInterval = 0,
        summary: String,
        categorizedItems: [CategorizedItem] = [],
        actionItems: [ActionItem] = [],
        photoUrls: [String] = [],
        acknowledgments: [Acknowledgment] = [],
        voiceReplies: [VoiceReply] = [],
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isSynced: Bool = true,
        isDirty: Bool = false
    ) {
        self.id = id
        self.authorId = authorId
        self.authorName = authorName
        self.authorInitials = authorInitials
        self.locationId = locationId
        self.shiftType = shiftType
        self.shiftTemplateId = shiftTemplateId
        self.rawTranscript = rawTranscript
        self.audioUrl = audioUrl
        self.audioDuration = audioDuration
        self.summary = summary
        self.categorizedItems = categorizedItems
        self.actionItems = actionItems
        self.photoUrls = photoUrls
        self.acknowledgments = acknowledgments
        self.voiceReplies = voiceReplies
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isSynced = isSynced
        self.isDirty = isDirty
    }

    var highestUrgency: UrgencyLevel {
        let allUrgencies = categorizedItems.map(\.urgency) + actionItems.map(\.urgency)
        return allUrgencies.min(by: { $0.sortOrder < $1.sortOrder }) ?? .fyi
    }

    var unresolvedActionCount: Int {
        actionItems.filter { $0.status != .resolved }.count
    }

    var resolvedActionCount: Int {
        actionItems.filter { $0.status == .resolved }.count
    }

    var categories: [NoteCategory] {
        Array(Set(categorizedItems.map(\.category))).sorted(by: { $0.rawValue < $1.rawValue })
    }

    var categoryDisplayInfos: [CategoryDisplayInfo] {
        let infos = categorizedItems.map(\.displayInfo)
        var seen = Set<String>()
        return infos.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }

    var shiftDisplayInfo: ShiftDisplayInfo {
        if let templateId = shiftTemplateId,
           let template = ShiftTemplateResolver.resolve(id: templateId) {
            return ShiftDisplayInfo(from: template)
        }
        return ShiftDisplayInfo(from: shiftType)
    }
}
