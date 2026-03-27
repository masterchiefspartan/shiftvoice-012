import Foundation

nonisolated struct CategoryTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
    let isSystem: Bool

    init(id: String = UUID().uuidString, name: String, icon: String, colorHex: String, isSystem: Bool = true) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.isSystem = isSystem
    }
}

extension NoteCategory {
    func toTemplate() -> CategoryTemplate {
        CategoryTemplate(
            id: "legacy_\(rawValue)",
            name: rawValue,
            icon: icon,
            colorHex: Self.legacyColorHex(self),
            isSystem: true
        )
    }

    static func legacyColorHex(_ category: NoteCategory) -> String {
        switch category {
        case .eightySixed: return "#DC2626"
        case .equipment: return "#D97706"
        case .guestIssue: return "#BE185D"
        case .staffNote: return "#2563EB"
        case .reservation: return "#7C3AED"
        case .inventory: return "#D97706"
        case .maintenance: return "#EA580C"
        case .healthSafety: return "#DC2626"
        case .general: return "#9CA3AF"
        case .incident: return "#DC2626"
        }
    }

    static func fromTemplate(_ template: CategoryTemplate) -> NoteCategory? {
        NoteCategory.allCases.first { $0.rawValue == template.name }
    }
}
