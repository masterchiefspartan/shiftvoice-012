import Foundation

nonisolated enum ActionItemQuality: Sendable {
    case good
    case needsWork(String)
}

nonisolated enum ActionItemScorer {
    static func evaluate(_ item: ActionItem) -> ActionItemQuality {
        let task = item.task.trimmingCharacters(in: .whitespacesAndNewlines)

        if task.split(separator: " ").count < 3 {
            return .needsWork("Too brief — add more detail so the next person knows what to do")
        }

        let lower = task.lowercased()
        let startsWithVerb = imperativeVerbs.contains { lower.hasPrefix($0) }
        if !startsWithVerb {
            return .needsWork("Start with an action verb (e.g. \"Fix…\", \"Call…\", \"Check…\")")
        }

        let vaguePatterns = ["handle it", "deal with it", "take care of", "look into", "figure out", "do something"]
        for vague in vaguePatterns {
            if lower.contains(vague) {
                return .needsWork("Too vague — specify exactly what needs to happen")
            }
        }

        return .good
    }

    static func evaluateAll(_ items: [ActionItem]) -> [(item: ActionItem, quality: ActionItemQuality)] {
        items.map { ($0, evaluate($0)) }
    }

    static func hasIssues(_ items: [ActionItem]) -> Bool {
        items.contains { item in
            if case .needsWork = evaluate(item) { return true }
            return false
        }
    }

    private static let imperativeVerbs = [
        "check", "fix", "order", "replace", "clean", "call", "tell",
        "restock", "notify", "schedule", "follow up", "follow-up",
        "make sure", "update", "review", "inspect", "repair", "contact",
        "confirm", "prepare", "set up", "remove", "add", "move",
        "stock", "refill", "wash", "wipe", "test", "verify",
        "resolve", "escalate", "report", "arrange", "book",
        "86", "guest", "reorder", "send", "email", "text", "message",
    ]
}
