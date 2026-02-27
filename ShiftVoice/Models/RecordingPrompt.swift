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
        let template = businessType.industryTemplate
        let shiftSpecific = shiftPrompts(shiftName: shiftName, shifts: template.defaultShifts, terminology: template.terminology)
        let categorySpecific = categoryPrompts(from: template.defaultCategories, terminology: template.terminology)
        let universal = universalPrompts(terminology: template.terminology)

        var seenTexts: Set<String> = []
        let combined = (shiftSpecific + categorySpecific + universal).filter { prompt in
            seenTexts.insert(prompt.text).inserted
        }

        return combined.shuffled()
    }

    private static func shiftPrompts(shiftName: String, shifts: [ShiftTemplate], terminology: IndustryTerminology) -> [RecordingPrompt] {
        guard let matchedShift = resolveShift(named: shiftName, from: shifts) else {
            return [
                RecordingPrompt(text: "Anything the previous shift flagged for this \(terminology.location.lowercased())?", icon: "arrow.left.circle"),
                RecordingPrompt(text: "Any priorities to hand off in this \(terminology.shiftHandoff.lowercased())?", icon: "arrow.right.circle")
            ]
        }

        switch shiftPhase(for: matchedShift, in: shifts) {
        case .opening:
            return [
                RecordingPrompt(text: "What needs setup before this shift gets busy?", icon: "sunrise"),
                RecordingPrompt(text: "Any carryover from the previous \(terminology.shiftHandoff.lowercased())?", icon: "arrow.left.circle"),
                RecordingPrompt(text: "Any staffing coverage gaps for this shift?", icon: "person.badge.clock")
            ]
        case .middle:
            return [
                RecordingPrompt(text: "Any new \(terminology.customer.lowercased()) issues since the shift started?", icon: "person.crop.circle.badge.exclamationmark"),
                RecordingPrompt(text: "What changed since the last handoff that the next team should know?", icon: "arrow.triangle.2.circlepath"),
                RecordingPrompt(text: "Any blockers that need support before handoff?", icon: "exclamationmark.circle")
            ]
        case .closing:
            return [
                RecordingPrompt(text: "What must be completed before this shift wraps?", icon: "checkmark.circle"),
                RecordingPrompt(text: "Anything unfinished that should be in the next \(terminology.shiftHandoff.lowercased())?", icon: "arrow.right.circle"),
                RecordingPrompt(text: "Any incidents or risks to flag before close?", icon: "exclamationmark.shield")
            ]
        }
    }

    private static func categoryPrompts(from categories: [CategoryTemplate], terminology: IndustryTerminology) -> [RecordingPrompt] {
        let prioritized = categories
            .filter { !$0.name.localizedCaseInsensitiveContains("general") }
            .prefix(4)

        var prompts = prioritized.map { category in
            RecordingPrompt(
                text: "Any updates on \(category.name.lowercased())?",
                icon: category.icon
            )
        }

        let hasStockCategory = categories.contains {
            $0.name.localizedCaseInsensitiveContains("86") ||
            $0.name.localizedCaseInsensitiveContains("stock") ||
            $0.name.localizedCaseInsensitiveContains("inventory") ||
            $0.name.localizedCaseInsensitiveContains("supply")
        }

        if hasStockCategory {
            prompts.append(
                RecordingPrompt(
                    text: "Anything currently marked as \(terminology.outOfStock.lowercased())?",
                    icon: "shippingbox"
                )
            )
        }

        return prompts
    }

    private static func universalPrompts(terminology: IndustryTerminology) -> [RecordingPrompt] {
        [
            RecordingPrompt(text: "Anything the next shift needs immediately?", icon: "arrow.right.circle"),
            RecordingPrompt(text: "Any follow-ups from earlier today still open?", icon: "arrow.clockwise"),
            RecordingPrompt(text: "Any equipment or maintenance concerns to include in the \(terminology.shiftHandoff.lowercased())?", icon: "wrench.and.screwdriver")
        ]
    }

    private static func resolveShift(named shiftName: String, from shifts: [ShiftTemplate]) -> ShiftTemplate? {
        let normalized = normalize(shiftName)

        if let exact = shifts.first(where: { normalize($0.name) == normalized }) {
            return exact
        }

        return shifts.first { shift in
            let candidate = normalize(shift.name)
            return normalized.contains(candidate) || candidate.contains(normalized)
        }
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func shiftPhase(for current: ShiftTemplate, in shifts: [ShiftTemplate]) -> ShiftPhase {
        let ordered = shifts.sorted { $0.defaultStartHour < $1.defaultStartHour }
        guard let index = ordered.firstIndex(where: { $0.id == current.id }) else {
            return .middle
        }

        if index == 0 { return .opening }
        if index == ordered.count - 1 { return .closing }
        return .middle
    }
}

nonisolated enum ShiftPhase: Sendable {
    case opening
    case middle
    case closing
}
