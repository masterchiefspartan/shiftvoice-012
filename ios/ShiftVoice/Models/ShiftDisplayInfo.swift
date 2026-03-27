import SwiftUI

nonisolated struct ShiftDisplayInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let icon: String

    init(id: String, name: String, icon: String) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    init(from template: ShiftTemplate) {
        self.id = template.id
        self.name = template.name
        self.icon = template.icon
    }

    init(from legacy: ShiftType) {
        self.id = "legacy_\(legacy.rawValue)"
        self.name = legacy.rawValue
        self.icon = legacy.icon
    }
}
