import Foundation

enum CategoryTemplateResolver {
    private static var allTemplatesById: [String: CategoryTemplate] = {
        var map: [String: CategoryTemplate] = [:]
        for template in IndustrySeed.all {
            for cat in template.defaultCategories {
                map[cat.id] = cat
            }
        }
        return map
    }()

    static func resolve(id: String) -> CategoryTemplate? {
        allTemplatesById[id]
    }
}
