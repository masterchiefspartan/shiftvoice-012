import Foundation

enum ShiftTemplateResolver {
    private static var allTemplatesById: [String: ShiftTemplate] = {
        var map: [String: ShiftTemplate] = [:]
        for template in IndustrySeed.all {
            for shift in template.defaultShifts {
                map[shift.id] = shift
            }
        }
        return map
    }()

    static func resolve(id: String) -> ShiftTemplate? {
        allTemplatesById[id]
    }
}
