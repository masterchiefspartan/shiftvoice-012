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

nonisolated struct TeamInvite: Identifiable, Sendable {
    let id: String
    var email: String
    var roleTemplate: RoleTemplate

    init(id: String = UUID().uuidString, email: String = "", roleTemplate: RoleTemplate) {
        self.id = id
        self.email = email
        self.roleTemplate = roleTemplate
    }
}

@Observable
final class OnboardingViewModel {
    var currentStep: Int = 0
    let totalSteps: Int = 3

    var businessType: BusinessType = .restaurant
    var locationName: String = ""
    var detectedTimezone: String = TimeZone.current.identifier

    var selectedCategoryTemplates: Set<CategoryTemplate> = Set(IndustrySeed.restaurant.defaultCategories)
    var selectedShiftTemplates: [ShiftTemplate] = IndustrySeed.restaurant.defaultShifts
    var availableRoleTemplates: [RoleTemplate] = IndustrySeed.restaurant.defaultRoles

    var requireAcknowledgment: Bool = true

    var teamInvites: [TeamInvite] = []

    var locationNameError: String?
    var categoryError: String?
    var inviteErrors: [String: String] = [:]

    var selectedCategories: Set<NoteCategory> {
        let mapped = selectedCategoryTemplates.compactMap { NoteCategory.fromTemplate($0) }
        return Set(mapped)
    }

    var canAdvance: Bool {
        switch currentStep {
        case 0:
            return !locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !selectedCategoryTemplates.isEmpty
        case 2:
            return true
        default:
            return true
        }
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
        categoryError = nil
        inviteErrors = [:]

        switch currentStep {
        case 0:
            if locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                locationNameError = "Give your \(businessType.terminology.location.lowercased()) a name to continue"
                return false
            }
            return true
        case 1:
            if selectedCategoryTemplates.isEmpty {
                categoryError = "Select at least one category"
                return false
            }
            return true
        case 2:
            var valid = true
            for invite in teamInvites where !invite.email.isEmpty {
                if !isValidEmail(invite.email) {
                    inviteErrors[invite.id] = "Enter a valid email"
                    valid = false
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

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    var formattedTimezone: String {
        let tz = TimeZone(identifier: detectedTimezone) ?? .current
        let abbreviation = tz.abbreviation() ?? ""
        let name = detectedTimezone.replacingOccurrences(of: "_", with: " ").split(separator: "/").last.map(String.init) ?? detectedTimezone
        return "\(name) (\(abbreviation))"
    }

    var shiftTimeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }
}
