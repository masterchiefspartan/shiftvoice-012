import Foundation

nonisolated enum SubscriptionPlan: String, Codable, Sendable {
    case free = "Free"
    case starter = "Starter"
    case professional = "Professional"
    case enterprise = "Enterprise"

    var maxLocations: Int {
        switch self {
        case .free: return 1
        case .starter: return 5
        case .professional: return 20
        case .enterprise: return .max
        }
    }

    var maxManagersPerLocation: Int {
        switch self {
        case .free: return 3
        case .starter: return 6
        case .professional: return 10
        case .enterprise: return .max
        }
    }

    var monthlyPrice: String {
        switch self {
        case .free: return "Free"
        case .starter: return "$39/loc/mo"
        case .professional: return "$79/loc/mo"
        case .enterprise: return "Custom"
        }
    }
}

nonisolated enum IndustryType: String, CaseIterable, Codable, Sendable {
    case restaurant = "Restaurant"
    case bar = "Bar"
    case hotel = "Hotel"
    case cafe = "Café"
    case catering = "Catering"
    case other = "Other"
}

nonisolated enum ManagerRole: String, Codable, Sendable {
    case owner = "Owner"
    case generalManager = "General Manager"
    case manager = "Manager"
    case shiftLead = "Shift Lead"

    var sortOrder: Int {
        switch self {
        case .owner: return 0
        case .generalManager: return 1
        case .manager: return 2
        case .shiftLead: return 3
        }
    }
}

nonisolated enum InviteStatus: String, Codable, Sendable {
    case pending = "Pending"
    case accepted = "Accepted"
    case deactivated = "Deactivated"
}

nonisolated struct Organization: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let ownerId: String
    var plan: SubscriptionPlan
    let industryType: IndustryType

    init(id: String = UUID().uuidString, name: String, ownerId: String, plan: SubscriptionPlan = .free, industryType: IndustryType = .restaurant) {
        self.id = id
        self.name = name
        self.ownerId = ownerId
        self.plan = plan
        self.industryType = industryType
    }
}

nonisolated struct Location: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let address: String
    let timezone: String
    let openingTime: String
    let midTime: String
    let closingTime: String
    let managerIds: [String]

    init(id: String = UUID().uuidString, name: String, address: String, timezone: String = "America/New_York", openingTime: String = "06:00", midTime: String = "14:00", closingTime: String = "22:00", managerIds: [String] = []) {
        self.id = id
        self.name = name
        self.address = address
        self.timezone = timezone
        self.openingTime = openingTime
        self.midTime = midTime
        self.closingTime = closingTime
        self.managerIds = managerIds
    }

    nonisolated static func == (lhs: Location, rhs: Location) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct TeamMember: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let email: String
    let role: ManagerRole
    let roleTemplateId: String?
    let locationIds: [String]
    let inviteStatus: InviteStatus
    let avatarInitials: String
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, email: String, role: ManagerRole, roleTemplateId: String? = nil, locationIds: [String] = [], inviteStatus: InviteStatus = .accepted, avatarInitials: String? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.roleTemplateId = roleTemplateId
        self.locationIds = locationIds
        self.inviteStatus = inviteStatus
        self.updatedAt = updatedAt
        if let initials = avatarInitials {
            self.avatarInitials = initials
        } else {
            let parts = name.split(separator: " ")
            self.avatarInitials = parts.count >= 2
                ? "\(parts[0].prefix(1))\(parts[1].prefix(1))"
                : String(name.prefix(2)).uppercased()
        }
    }

    var roleDisplayInfo: RoleDisplayInfo {
        if let templateId = roleTemplateId,
           let template = RoleTemplateResolver.resolve(id: templateId) {
            return RoleDisplayInfo(from: template)
        }
        return RoleDisplayInfo(from: role)
    }
}

nonisolated struct RecurringIssue: Identifiable, Codable, Sendable {
    let id: String
    let description: String
    let category: NoteCategory
    let categoryTemplateId: String?
    let locationId: String
    let locationName: String
    let mentionCount: Int
    let relatedNoteIds: [String]
    let firstMentioned: Date
    let lastMentioned: Date
    var status: RecurringIssueStatus

    init(id: String = UUID().uuidString, description: String, category: NoteCategory, categoryTemplateId: String? = nil, locationId: String, locationName: String, mentionCount: Int, relatedNoteIds: [String] = [], firstMentioned: Date, lastMentioned: Date, status: RecurringIssueStatus = .active) {
        self.id = id
        self.description = description
        self.category = category
        self.categoryTemplateId = categoryTemplateId
        self.locationId = locationId
        self.locationName = locationName
        self.mentionCount = mentionCount
        self.relatedNoteIds = relatedNoteIds
        self.firstMentioned = firstMentioned
        self.lastMentioned = lastMentioned
        self.status = status
    }

    var displayInfo: CategoryDisplayInfo {
        if let templateId = categoryTemplateId,
           let template = CategoryTemplateResolver.resolve(id: templateId) {
            return CategoryDisplayInfo(from: template)
        }
        return CategoryDisplayInfo(from: category)
    }
}

nonisolated enum RecurringIssueStatus: String, Codable, Sendable {
    case active = "Active"
    case acknowledged = "Acknowledged"
    case resolved = "Resolved"
}
