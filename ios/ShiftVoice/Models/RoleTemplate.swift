import Foundation

nonisolated struct RoleTemplate: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let name: String
    let sortOrder: Int

    init(id: String = UUID().uuidString, name: String, sortOrder: Int) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

extension ManagerRole {
    func toTemplate() -> RoleTemplate {
        RoleTemplate(
            id: "legacy_\(rawValue)",
            name: rawValue,
            sortOrder: sortOrder
        )
    }

    static func fromTemplate(_ template: RoleTemplate) -> ManagerRole? {
        ManagerRole.allCases.first { $0.rawValue == template.name }
    }
}

extension ManagerRole: CaseIterable {
    static let allCases: [ManagerRole] = [.owner, .generalManager, .manager, .shiftLead]
}
