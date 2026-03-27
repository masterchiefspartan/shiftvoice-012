import SwiftUI

nonisolated struct CategoryDisplayInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String

    var color: Color {
        SVTheme.color(fromHex: colorHex)
    }

    init(id: String, name: String, icon: String, colorHex: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
    }

    init(from template: CategoryTemplate) {
        self.id = template.id
        self.name = template.name
        self.icon = template.icon
        self.colorHex = template.colorHex
    }

    init(from legacy: NoteCategory) {
        self.id = "legacy_\(legacy.rawValue)"
        self.name = legacy.rawValue
        self.icon = legacy.icon
        self.colorHex = NoteCategory.legacyColorHex(legacy)
    }
}
