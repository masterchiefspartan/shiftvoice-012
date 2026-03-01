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
    case restaurantBar = "Restaurant/Bar"
    case hotelHospitality = "Hotel/Hospitality"
    case facilitiesMaintenance = "Facilities/Maintenance"
    case warehouseLogistics = "Warehouse/Logistics"
    case healthcare = "Healthcare"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .restaurantBar: return "fork.knife"
        case .hotelHospitality: return "bed.double.fill"
        case .facilitiesMaintenance: return "wrench.and.screwdriver.fill"
        case .warehouseLogistics: return "shippingbox.fill"
        case .healthcare: return "cross.case.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }

    var businessType: BusinessType {
        switch self {
        case .restaurantBar: return .restaurant
        case .hotelHospitality: return .hotel
        case .facilitiesMaintenance: return .security
        case .warehouseLogistics: return .manufacturing
        case .healthcare: return .healthcare
        case .other: return .other
        }
    }
}

nonisolated enum OnboardingPainPoint: String, CaseIterable, Identifiable, Sendable {
    case forgottenHandoffs = "Forgotten handoffs"
    case buriedInfo = "Buried info"
    case recurringIssues = "Recurring issues"
    case firefighting = "Constant firefighting"

    var id: String { rawValue }

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
    var selectedIndustry: OnboardingIndustry = .restaurantBar
    var businessType: BusinessType = .restaurant
    var selectedPainPoints: Set<OnboardingPainPoint> = []
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
        selectedShiftTemplates = template.defaultShifts
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
        if selectedPainPoints.contains(point) {
            selectedPainPoints.remove(point)
        } else {
            selectedPainPoints.insert(point)
        }
    }

    var mirrorMomentText: String {
        let role = selectedRole?.title ?? "operator"
        let industry = selectedIndustry == .restaurantBar ? "Restaurant" : selectedIndustry.rawValue
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
            painPhrase = selectedOrdered[0].rawValue.lowercased()
        } else if selectedOrdered.count == 2 {
            painPhrase = "\(selectedOrdered[0].rawValue.lowercased()) and \(selectedOrdered[1].rawValue.lowercased())"
        } else {
            let prefix = selectedOrdered.dropLast().map { $0.rawValue.lowercased() }.joined(separator: ", ")
            painPhrase = "\(prefix), and \(selectedOrdered.last?.rawValue.lowercased() ?? "")"
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
