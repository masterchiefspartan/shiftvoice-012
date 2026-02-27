import Foundation

nonisolated struct RecordingPrompt: Identifiable, Sendable {
    let id: String
    let text: String
    let icon: String

    init(id: String = UUID().uuidString, text: String, icon: String) {
        self.id = id
        self.text = text
        self.icon = icon
    }
}

nonisolated enum RecordingPromptProvider {
    static func prompts(for businessType: BusinessType, shiftName: String) -> [RecordingPrompt] {
        var result: [RecordingPrompt] = []

        result.append(contentsOf: shiftPrompts(shiftName: shiftName))
        result.append(contentsOf: industryPrompts(for: businessType))
        result.append(contentsOf: universalPrompts)

        return result.shuffled()
    }

    private static func shiftPrompts(shiftName: String) -> [RecordingPrompt] {
        let lower = shiftName.lowercased()
        if lower.contains("open") || lower.contains("morning") || lower.contains("day") {
            return [
                RecordingPrompt(text: "Anything from last night's close?", icon: "moon.stars"),
                RecordingPrompt(text: "Equipment working properly?", icon: "wrench.and.screwdriver"),
                RecordingPrompt(text: "Any deliveries expected today?", icon: "shippingbox"),
                RecordingPrompt(text: "Staff callouts or schedule changes?", icon: "person.badge.clock"),
            ]
        } else if lower.contains("clos") || lower.contains("night") || lower.contains("evening") {
            return [
                RecordingPrompt(text: "Anything unfinished for tomorrow?", icon: "arrow.right.circle"),
                RecordingPrompt(text: "Any incidents during your shift?", icon: "exclamationmark.shield"),
                RecordingPrompt(text: "Inventory that needs restocking?", icon: "shippingbox"),
                RecordingPrompt(text: "Equipment issues to report?", icon: "wrench.and.screwdriver"),
            ]
        } else {
            return [
                RecordingPrompt(text: "Updates from the morning crew?", icon: "arrow.left.circle"),
                RecordingPrompt(text: "Any guest issues to flag?", icon: "person.crop.circle.badge.exclamationmark"),
                RecordingPrompt(text: "Items running low?", icon: "chart.line.downtrend.xyaxis"),
            ]
        }
    }

    private static func industryPrompts(for businessType: BusinessType) -> [RecordingPrompt] {
        switch businessType {
        case .restaurant, .barPub, .cafe:
            return [
                RecordingPrompt(text: "Any 86'd items?", icon: "xmark.circle"),
                RecordingPrompt(text: "VIP reservations tonight?", icon: "star"),
                RecordingPrompt(text: "Kitchen equipment status?", icon: "flame"),
            ]
        case .hotel:
            return [
                RecordingPrompt(text: "Guest complaints to hand off?", icon: "person.crop.circle.badge.exclamationmark"),
                RecordingPrompt(text: "Room maintenance requests?", icon: "hammer"),
                RecordingPrompt(text: "VIP arrivals today?", icon: "star"),
            ]
        case .healthcare:
            return [
                RecordingPrompt(text: "Patient status changes?", icon: "heart.text.clipboard"),
                RecordingPrompt(text: "Medication updates?", icon: "pills"),
                RecordingPrompt(text: "Supply needs?", icon: "shippingbox"),
            ]
        case .manufacturing:
            return [
                RecordingPrompt(text: "Machine issues or downtime?", icon: "gearshape"),
                RecordingPrompt(text: "Quality concerns?", icon: "checkmark.seal"),
                RecordingPrompt(text: "Safety incidents?", icon: "exclamationmark.triangle"),
            ]
        case .retail:
            return [
                RecordingPrompt(text: "Customer escalations?", icon: "person.crop.circle.badge.exclamationmark"),
                RecordingPrompt(text: "Stock that needs replenishing?", icon: "shippingbox"),
                RecordingPrompt(text: "Loss prevention concerns?", icon: "exclamationmark.shield"),
            ]
        default:
            return [
                RecordingPrompt(text: "Equipment or facility issues?", icon: "wrench.and.screwdriver"),
                RecordingPrompt(text: "Safety concerns?", icon: "exclamationmark.triangle"),
            ]
        }
    }

    private static var universalPrompts: [RecordingPrompt] {
        [
            RecordingPrompt(text: "Anything the next shift needs to know?", icon: "arrow.right.circle"),
            RecordingPrompt(text: "Follow-ups from earlier today?", icon: "arrow.clockwise"),
            RecordingPrompt(text: "Any maintenance or repair needs?", icon: "hammer"),
        ]
    }
}
