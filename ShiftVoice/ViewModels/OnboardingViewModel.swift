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

@Observable
final class OnboardingViewModel {
    var currentStep: Int = 0
    let totalSteps: Int = 6

    var selectedRole: OnboardingRole?
    var businessType: BusinessType = .restaurant
    var locationName: String = ""
    var detectedTimezone: String = TimeZone.current.identifier

    var selectedCategoryTemplates: Set<CategoryTemplate> = Set(IndustrySeed.restaurant.defaultCategories)
    var selectedShiftTemplates: [ShiftTemplate] = IndustrySeed.restaurant.defaultShifts
    var availableRoleTemplates: [RoleTemplate] = IndustrySeed.restaurant.defaultRoles

    var teamInvites: [TeamInvite] = []

    var locationNameError: String?
    var inviteErrors: [String: String] = [:]

    var paywallSkipped: Bool = false

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
        case 2: return !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 3: return true
        case 4: return true
        case 5: return true
        default: return true
        }
    }

    func selectRole(_ role: OnboardingRole) {
        selectedRole = role
    }

    func selectBusinessType(_ type: BusinessType) {
        businessType = type
        let template = type.industryTemplate
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
        case 1:
            return true
        case 2:
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
            return true
        case 3:
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
