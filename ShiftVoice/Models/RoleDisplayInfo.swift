import Foundation

nonisolated struct RoleDisplayInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let sortOrder: Int

    init(id: String, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }

    init(from template: RoleTemplate) {
        self.id = template.id
        self.name = template.name
        self.sortOrder = template.sortOrder
    }

    init(from legacy: ManagerRole) {
        self.id = "legacy_\(legacy.rawValue)"
        self.name = legacy.rawValue
        self.sortOrder = legacy.sortOrder
    }
}
