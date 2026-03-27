import Testing
@testable import ShiftVoice

struct StructuringRegressionAuditTests {

    @Test func oneTopicTranscriptProducesOneItem() {
        let vm = AppViewModel()
        let transcript = "The walk-in cooler is making a weird noise."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 1)
    }

    @Test func twoDistinctTopicsProduceTwoItems() {
        let vm = AppViewModel()
        let transcript = "The fryer is making that noise again, and also we're completely out of salmon."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 2)
        #expect(items.contains(where: { $0.category == .equipment || $0.category == .maintenance }))
        #expect(items.contains(where: { $0.category == .inventory || $0.category == .eightySixed }))
    }

    @Test func threeDistinctTopicsProduceThreeItems() {
        let vm = AppViewModel()
        let transcript = "The walk-in cooler is making noise again, we're out of salmon, and tell Sarah she's training the new host on Thursday."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 3)
    }

    @Test func fillerHeavySpeechStillStructuresIntoTwoItems() {
        let vm = AppViewModel()
        let transcript = "Um so like the dishwasher, it's uh, not working again. And we also need to order more paper towels."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 2)
        #expect(!items.contains(where: { $0.content.lowercased() == "and we" }))
    }

    @Test func separateBrokenItemsAreNotMerged() {
        let vm = AppViewModel()
        let transcript = "The fryer is broken and the grill is broken."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 2)
    }

    @Test func repeatedReferencesStaySingleItem() {
        let vm = AppViewModel()
        let transcript = "Tell the morning crew about the cooler. The cooler's been making noise. I already called the repair company about the cooler."

        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count == 1)
    }

    @Test func nothingToReportCreatesNoIssuesAndNoActions() {
        let vm = AppViewModel()
        let transcript = "Had a great shift, nothing to report."

        let items = vm.testGenerateCategories(from: transcript)
        let actions = vm.testGenerateActionItems(from: items)

        #expect(items.isEmpty)
        #expect(actions.isEmpty)
    }

    @Test func generatedActionItemsAreSpecificForOperationalIssues() {
        let vm = AppViewModel()
        let transcript = "The fryer is making that noise again, and also we're completely out of salmon."

        let items = vm.testGenerateCategories(from: transcript)
        let actions = vm.testGenerateActionItems(from: items)

        #expect(actions.count == 2)
        #expect(actions.allSatisfy { !$0.task.lowercased().contains("review and address") })
    }
}
