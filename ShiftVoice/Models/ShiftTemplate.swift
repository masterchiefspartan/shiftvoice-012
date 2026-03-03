import Foundation

nonisolated struct ShiftTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let icon: String
    let defaultStartHour: Int

    init(id: String = UUID().uuidString, name: String, icon: String, defaultStartHour: Int) {
        self.id = id
        self.name = name
        self.icon = icon
        self.defaultStartHour = defaultStartHour
    }
}

extension ShiftType {
    func toTemplate() -> ShiftTemplate {
        switch self {
        case .opening:
            return ShiftTemplate(id: "legacy_opening", name: "Opening", icon: "sunrise.fill", defaultStartHour: 6)
        case .mid:
            return ShiftTemplate(id: "legacy_mid", name: "Mid", icon: "sun.max.fill", defaultStartHour: 14)
        case .closing:
            return ShiftTemplate(id: "legacy_closing", name: "Closing", icon: "moon.stars.fill", defaultStartHour: 22)
        case .unscheduled:
            return ShiftTemplate(id: "legacy_unscheduled", name: "Unscheduled", icon: "clock.fill", defaultStartHour: 0)
        }
    }

    static func fromTemplate(_ template: ShiftTemplate) -> ShiftType? {
        ShiftType.allCases.first { $0.rawValue == template.name }
    }
}
