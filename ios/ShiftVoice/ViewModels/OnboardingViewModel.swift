import SwiftUI

nonisolated enum BusinessType: String, CaseIterable, Identifiable, Sendable {
    case restaurant = "Restaurant"
    case barPub = "Bar / Pub"
    case hotel = "Hotel"
    case cafe = "Café"
    case retail = "Retail"
    case healthcare = "Healthcare / Nursing"
    case manufacturing = "Manufacturing / Warehouse"
    case security = "Security / Facilities"
    case propertyManagement = "Property Management"
    case construction = "Construction"
    case other = "Other"

    var id: String { rawValue }

    var industryTemplate: IndustryTemplate {
        IndustrySeed.template(for: self)
    }

    var icon: String { industryTemplate.icon }

    var terminology: IndustryTerminology { industryTemplate.terminology }

    var defaultCategories: Set<NoteCategory> {
        let templates = industryTemplate.defaultCategories
        let mapped = templates.compactMap { NoteCategory.fromTemplate($0) }
        return Set(mapped)
    }

    var defaultCategoryTemplates: [CategoryTemplate] {
        industryTemplate.defaultCategories
    }
}

nonisolated enum OnboardingRole: String, CaseIterable, Identifiable, Sendable {
    case shiftLead = "shift_lead"
    case gmOwner = "gm_owner"
    case multiUnit = "multi_unit"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shiftLead: return "Shift Lead / Floor Manager"
        case .gmOwner: return "General Manager / Owner"
        case .multiUnit: return "Operations / Multi-Unit"
        }
    }

    var subtitle: String {
        switch self {
        case .shiftLead: return "You run the shift day-to-day"
        case .gmOwner: return "You oversee the full operation"
        case .multiUnit: return "You manage across locations"
        }
    }

    var icon: String {
        switch self {
        case .shiftLead: return "person.badge.clock"
        case .gmOwner: return "building.2"
        case .multiUnit: return "map"
        }
    }
}

nonisolated struct TeamInvite: Identifiable, Sendable {
    let id: String
    var contact: String
    var roleTemplate: RoleTemplate

    init(id: String = UUID().uuidString, contact: String = "", roleTemplate: RoleTemplate) {
        self.id = id
        self.contact = contact
        self.roleTemplate = roleTemplate
    }
}

nonisolated enum OnboardingIndustry: String, CaseIterable, Identifiable, Sendable {
    case restaurant = "restaurant"
    case hotel = "hotel"
    case facilities = "facilities"
    case warehouse = "warehouse"
    case healthcare = "healthcare"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restaurant: return "Restaurant / Bar"
        case .hotel: return "Hotel / Hospitality"
        case .facilities: return "Facilities / Maintenance"
        case .warehouse: return "Warehouse / Logistics"
        case .healthcare: return "Healthcare"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .hotel: return "bed.double.fill"
        case .facilities: return "wrench.and.screwdriver.fill"
        case .warehouse: return "shippingbox.fill"
        case .healthcare: return "cross.case.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var businessType: BusinessType {
        switch self {
        case .restaurant: return .restaurant
        case .hotel: return .hotel
        case .facilities: return .security
        case .warehouse: return .manufacturing
        case .healthcare: return .healthcare
        case .other: return .other
        }
    }

    var defaultShiftNames: [String] {
        switch self {
        case .restaurant: return ["Opening", "Mid", "Closing"]
        case .hotel: return ["Morning", "Afternoon", "Night"]
        case .facilities, .warehouse: return ["Day", "Swing", "Night"]
        case .healthcare: return ["Day", "Evening", "Night"]
        case .other: return ["Morning", "Afternoon", "Evening"]
        }
    }

    var defaultShiftHours: [Int] {
        switch self {
        case .restaurant: return [6, 11, 16]
        case .hotel: return [7, 15, 23]
        case .facilities, .warehouse: return [6, 14, 22]
        case .healthcare: return [7, 15, 23]
        case .other: return [8, 12, 16]
        }
    }

    var locationPlaceholder: String {
        switch self {
        case .restaurant: return "e.g., The Blue Ox Kitchen"
        case .hotel: return "e.g., Downtown Marriott"
        case .facilities: return "e.g., Building A — Main Campus"
        case .warehouse: return "e.g., West Distribution Center"
        case .healthcare: return "e.g., St. Mary's — East Wing"
        case .other: return "e.g., Main Office"
        }
    }
}

nonisolated enum OnboardingPainPoint: String, CaseIterable, Identifiable, Sendable {
    case forgottenHandoffs = "forgotten_handoffs"
    case buriedInfo = "buried_info"
    case recurringIssues = "recurring_issues"
    case firefighting = "firefighting"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forgottenHandoffs: return "Handoffs get forgotten"
        case .buriedInfo: return "Info buried in texts & group chats"
        case .recurringIssues: return "Same problems keep recurring"
        case .firefighting: return "Too much time firefighting"
        }
    }

    var subtitle: String {
        switch self {
        case .forgottenHandoffs: return "The next shift didn't know about the issue"
        case .buriedInfo: return "Important updates lost in WhatsApp/text chaos"
        case .recurringIssues: return "You've flagged it before but there's no record"
        case .firefighting: return "Reacting to problems instead of running operations"
        }
    }

    var mirrorPhrase: String {
        switch self {
        case .forgottenHandoffs: return "forgotten handoffs"
        case .buriedInfo: return "buried info"
        case .recurringIssues: return "recurring issues"
        case .firefighting: return "firefighting"
        }
    }

    var icon: String {
        switch self {
        case .forgottenHandoffs: return "arrow.left.arrow.right.circle"
        case .buriedInfo: return "tray.full"
        case .recurringIssues: return "arrow.triangle.2.circlepath"
        case .firefighting: return "flame.fill"
        }
    }
}

nonisolated enum OnboardingCurrentTool: String, CaseIterable, Identifiable, Sendable {
    case talkItThrough = "We just talk it through"
    case notesApp = "Notes app"
    case groupChat = "Group chat"
    case paperLog = "Paper log"
    case other = "Other"

    var id: String { rawValue }

    var mirrorPhrase: String {
        switch self {
        case .talkItThrough: return "talking it through"
        case .notesApp: return "using a notes app"
        case .groupChat: return "relying on group chat"
        case .paperLog: return "using a paper log"
        case .other: return "using your current process"
        }
    }
}

@Observable
final class OnboardingViewModel {
    var currentStep: Int = 0
    let totalSteps: Int = 9

    var selectedRole: OnboardingRole?
    var selectedIndustry: OnboardingIndustry = .restaurant
    var businessType: BusinessType = .restaurant
    var selectedPainPoints: [OnboardingPainPoint] = []
    var selectedTool: OnboardingCurrentTool?
    var locationName: String = ""
    var detectedTimezone: String = TimeZone.current.identifier

    var selectedCategoryTemplates: Set<CategoryTemplate> = Set(IndustrySeed.restaurant.defaultCategories)
    var selectedShiftTemplates: [ShiftTemplate] = IndustrySeed.restaurant.defaultShifts
    var availableRoleTemplates: [RoleTemplate] = IndustrySeed.restaurant.defaultRoles

    var teamInvites: [TeamInvite] = []
    var inviteInput: String = ""

    var locationNameError: String?
    var inviteErrors: [String: String] = [:]

    var paywallSkipped: Bool = false
    var usedSamplePath: Bool = false
    var recordingSeconds: Int = 0

    var selectedCategories: Set<NoteCategory> {
        let mapped = selectedCategoryTemplates.compactMap { NoteCategory.fromTemplate($0) }
        return Set(mapped)
    }

    var progress: Double {
        Double(currentStep + 1) / Double(totalSteps)
    }

    var canAdvance: Bool {
        switch currentStep {
        case 0: return selectedRole != nil
        case 1: return true
        case 2: return !selectedPainPoints.isEmpty
        case 3: return selectedTool != nil
        case 4: return false
        case 5: return false
        case 6: return false
        case 7: return !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 8: return false
        default: return true
        }
    }

    func selectRole(_ role: OnboardingRole) {
        selectedRole = role
    }

    func selectIndustry(_ industry: OnboardingIndustry) {
        selectedIndustry = industry
        businessType = industry.businessType
        let template = businessType.industryTemplate
        selectedCategoryTemplates = Set(template.defaultCategories)

        let shiftIds = ["shift_1", "shift_2", "shift_3"]
        let shiftIcons = ["sunrise.fill", "sun.max.fill", "moon.stars.fill"]
        selectedShiftTemplates = zip(zip(shiftIds, industry.defaultShiftNames), zip(shiftIcons, industry.defaultShiftHours)).map { left, right in
            ShiftTemplate(id: left.0, name: left.1, icon: right.0, defaultStartHour: right.1)
        }

        availableRoleTemplates = template.defaultRoles
    }

    func validateCurrentStep() -> Bool {
        locationNameError = nil
        inviteErrors = [:]

        switch currentStep {
        case 0:
            return selectedRole != nil
        case 2:
            return !selectedPainPoints.isEmpty
        case 3:
            return selectedTool != nil
        case 7:
            let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                locationNameError = "Give your \(businessType.terminology.location.lowercased()) a name to continue"
                return false
            }
            if trimmed.count < 2 {
                locationNameError = "Name must be at least 2 characters"
                return false
            }
            if trimmed.count > 100 {
                locationNameError = "Name must be under 100 characters"
                return false
            }
            var valid = true
            var seenContacts = Set<String>()
            for invite in teamInvites where !invite.contact.isEmpty {
                let lower = invite.contact.lowercased().trimmingCharacters(in: .whitespaces)
                if !isValidContact(lower) {
                    inviteErrors[invite.id] = "Enter a valid email or phone number"
                    valid = false
                } else if seenContacts.contains(lower) {
                    inviteErrors[invite.id] = "Duplicate contact"
                    valid = false
                } else {
                    seenContacts.insert(lower)
                }
            }
            return valid
        default:
            return true
        }
    }

    func advance() {
        guard validateCurrentStep() else { return }
        if currentStep < totalSteps - 1 {
            currentStep += 1
        }
    }

    func goBack() {
        if currentStep > 0 {
            currentStep -= 1
        }
    }

    func continueFromDemoSetup(useSample: Bool) {
        guard currentStep == 4 else { return }
        usedSamplePath = useSample
        if useSample {
            currentStep = 6
        } else {
            currentStep = 5
            recordingSeconds = 0
        }
    }

    func continueFromLiveRecording() {
        if currentStep == 5 {
            currentStep = 6
        }
    }

    func continueFromAIReveal() {
        if currentStep == 6 {
            currentStep = 7
        }
    }

    func togglePainPoint(_ point: OnboardingPainPoint) {
        if let index = selectedPainPoints.firstIndex(of: point) {
            selectedPainPoints.remove(at: index)
        } else {
            selectedPainPoints.append(point)
        }
    }

    var mirrorMomentText: String {
        let role = selectedRole?.title ?? "operator"
        let industry = selectedIndustry == .restaurant ? "Restaurant" : selectedIndustry.title
        let toolPhrase = selectedTool?.mirrorPhrase ?? "using your current process"
        let points: [OnboardingPainPoint] = [
            .forgottenHandoffs,
            .buriedInfo,
            .recurringIssues,
            .firefighting
        ]
        let selectedOrdered = points.filter { selectedPainPoints.contains($0) }
        let painPhrase: String
        if selectedOrdered.isEmpty {
            painPhrase = "handoff issues"
        } else if selectedOrdered.count == 1 {
            painPhrase = selectedOrdered[0].mirrorPhrase
        } else if selectedOrdered.count == 2 {
            painPhrase = "\(selectedOrdered[0].mirrorPhrase) and \(selectedOrdered[1].mirrorPhrase)"
        } else {
            let prefix = selectedOrdered.dropLast().map { $0.mirrorPhrase }.joined(separator: ", ")
            painPhrase = "\(prefix), and \(selectedOrdered.last?.mirrorPhrase ?? "")"
        }
        return "As a \(role) in \(industry), \(toolPhrase) keeps creating \(painPhrase)."
    }

    func addInviteFromInput() {
        let trimmed = inviteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.lowercased()
        guard isValidContact(normalized) else { return }
        let duplicate = teamInvites.contains { $0.contact.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == normalized }
        guard !duplicate else { return }
        let defaultRole = availableRoleTemplates.last ?? RoleTemplate(id: "role_default", name: "Team Member", sortOrder: 0)
        teamInvites.append(TeamInvite(contact: trimmed, roleTemplate: defaultRole))
        inviteInput = ""
    }

    func addInvite() {
        let defaultRole = availableRoleTemplates.last ?? RoleTemplate(id: "role_default", name: "Team Member", sortOrder: 0)
        teamInvites.append(TeamInvite(roleTemplate: defaultRole))
    }

    func removeInvite(_ id: String) {
        teamInvites.removeAll { $0.id == id }
    }

    func toggleCategoryTemplate(_ template: CategoryTemplate) {
        if selectedCategoryTemplates.contains(template) {
            selectedCategoryTemplates.remove(template)
        } else {
            selectedCategoryTemplates.insert(template)
        }
    }

    var formattedTimezone: String {
        let tz = TimeZone(identifier: detectedTimezone) ?? .current
        let abbreviation = tz.abbreviation() ?? ""
        let name = detectedTimezone.replacingOccurrences(of: "_", with: " ").split(separator: "/").last.map(String.init) ?? detectedTimezone
        return "\(name) (\(abbreviation))"
    }

    private func isValidContact(_ contact: String) -> Bool {
        let emailPattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        if contact.range(of: emailPattern, options: .regularExpression) != nil {
            return true
        }
        let digits = contact.filter(\.isNumber)
        return digits.count >= 7 && digits.count <= 15
    }

    var validInvites: [TeamInvite] {
        teamInvites.filter { !$0.contact.isEmpty }
    }
}
