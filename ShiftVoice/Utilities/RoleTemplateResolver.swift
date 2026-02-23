import Foundation

enum RoleTemplateResolver {
    private static var allTemplatesById: [String: RoleTemplate] = {
        var map: [String: RoleTemplate] = [:]
        for template in IndustrySeed.all {
            for role in template.defaultRoles {
                map[role.id] = role
            }
        }
        return map
    }()

    static func resolve(id: String) -> RoleTemplate? {
        allTemplatesById[id]
    }
}
