import Testing
@testable import ShiftVoice

struct TranscriptSplittingTests {

    // MARK: - Basic Splitting Tests

    @Test func splitSingleSentence() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken")
        #expect(segments.count == 1)
        #expect(segments[0] == "The fryer is broken")
    }

    @Test func splitMultipleSentences() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken. We need more napkins. A guest complained about cold food.")
        #expect(segments.count == 3)
    }

    @Test func splitWithSeparatorAlso() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken also we need more napkins")
        #expect(segments.count == 2)
        #expect(segments[0].lowercased().contains("fryer"))
        #expect(segments[1].lowercased().contains("napkins"))
    }

    @Test func splitWithSeparatorAndThen() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken and then we noticed a leak in the bathroom")
        #expect(segments.count == 2)
    }

    @Test func splitWithSeparatorNext() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken next the ice machine stopped working")
        #expect(segments.count == 2)
    }

    // MARK: - Multi-Separator Recursive Splitting

    @Test func splitThreeItemsWithMultipleSeparators() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer is broken also we need more napkins and then a guest complained")
        #expect(segments.count >= 3)
    }

    @Test func splitWithCommaAnd() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The fryer needs repair, and the ice machine is leaking")
        #expect(segments.count == 2)
    }

    @Test func splitNumberedItems() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("First the fryer is broken then the dishwasher is leaking finally we are out of napkins")
        #expect(segments.count >= 3)
    }

    // MARK: - Edge Cases

    @Test func splitEmptyTranscript() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("")
        #expect(segments.isEmpty)
    }

    @Test func splitVeryShortText() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("OK")
        #expect(segments.isEmpty)
    }

    @Test func splitSingleLongSentence() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The commercial fryer in the main kitchen has been making a grinding noise since the beginning of the shift and the temperature gauge seems to be off by about twenty degrees")
        #expect(segments.count >= 1)
    }

    @Test func splitPreservesOriginalCase() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The Fryer is Broken also The Ice Machine Stopped")
        #expect(segments.count == 2)
        #expect(segments[0].contains("Fryer"))
    }

    @Test func splitFiltersShortSegments() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("OK. The fryer is broken. No.")
        #expect(segments.count == 1)
        #expect(segments[0].contains("fryer"))
    }

    // MARK: - Real-World Speech Patterns

    @Test func splitNaturalSpeechThreeItems() {
        let vm = AppViewModel()
        let transcript = "So the walk-in cooler temperature was reading 45 degrees which is too high. Also the fryer oil needs to be changed it's getting really dark. And then table 12 complained about the wait time for their entrees"
        let segments = vm.testSplitTranscript(transcript)
        #expect(segments.count >= 3)
    }

    @Test func splitWithBesidesThat() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The dishwasher is leaking besides that we ran out of to-go containers")
        #expect(segments.count == 2)
    }

    @Test func splitWithOnMoreThing() {
        let vm = AppViewModel()
        let segments = vm.testSplitTranscript("The register is short twenty dollars one more thing we need to order more printer paper")
        #expect(segments.count == 2)
    }

    // MARK: - Category Generation with New Splitting

    @Test func multiTopicTranscriptProducesMultipleCategories() {
        let vm = AppViewModel()
        let transcript = "The fryer is broken and needs repair. We are running low on supplies and need to restock. A guest complained about cold food."
        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count >= 3)
        let categories = Set(items.map(\.category))
        #expect(categories.count >= 2)
    }

    @Test func threeDistinctTopicsProduceThreeItems() {
        let vm = AppViewModel()
        let transcript = "The oven is not working. We ran out of napkins. There was a spill in the hallway creating a safety hazard."
        let items = vm.testGenerateCategories(from: transcript)
        #expect(items.count >= 3)
        #expect(items.contains(where: { $0.category == .equipment }))
        #expect(items.contains(where: { $0.category == .inventory }))
        #expect(items.contains(where: { $0.category == .healthSafety }))
    }

    // MARK: - Action Item Generation Improvements

    @Test func actionItemsGeneratedForAllNonFYICategories() {
        let categories = [
            CategorizedItem(category: .equipment, content: "Broken fryer", urgency: .immediate),
            CategorizedItem(category: .inventory, content: "Low on cups", urgency: .nextShift),
            CategorizedItem(category: .maintenance, content: "Leaky faucet", urgency: .thisWeek),
            CategorizedItem(category: .reservation, content: "VIP at 8pm", urgency: .nextShift),
            CategorizedItem(category: .incident, content: "Slip and fall", urgency: .immediate)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.count == 5)
        #expect(actions.contains(where: { $0.category == .reservation }))
        #expect(actions.contains(where: { $0.category == .incident }))
    }

    @Test func actionItemsHaveCorrectPrefixes() {
        let categories = [
            CategorizedItem(category: .equipment, content: "Broken fryer", urgency: .immediate),
            CategorizedItem(category: .inventory, content: "Low napkins", urgency: .nextShift),
            CategorizedItem(category: .maintenance, content: "Leaky pipe", urgency: .thisWeek),
            CategorizedItem(category: .healthSafety, content: "Wet floor", urgency: .immediate),
            CategorizedItem(category: .staffNote, content: "John called out", urgency: .nextShift),
            CategorizedItem(category: .guestIssue, content: "Table 5 upset", urgency: .nextShift),
            CategorizedItem(category: .eightySixed, content: "Salmon sold out", urgency: .immediate)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.count == 7)
        #expect(actions.first(where: { $0.category == .equipment })?.task.starts(with: "Check and address:") == true)
        #expect(actions.first(where: { $0.category == .inventory })?.task.starts(with: "Restock:") == true)
        #expect(actions.first(where: { $0.category == .maintenance })?.task.starts(with: "Fix:") == true)
        #expect(actions.first(where: { $0.category == .healthSafety })?.task.starts(with: "Resolve safety issue:") == true)
        #expect(actions.first(where: { $0.category == .staffNote })?.task.starts(with: "Follow up:") == true)
        #expect(actions.first(where: { $0.category == .guestIssue })?.task.starts(with: "Guest concern:") == true)
        #expect(actions.first(where: { $0.category == .eightySixed })?.task.starts(with: "86'd - restock:") == true)
    }

    @Test func generalFYISkippedButGeneralUrgentIncluded() {
        let categories = [
            CategorizedItem(category: .general, content: "Everything is fine", urgency: .fyi),
            CategorizedItem(category: .general, content: "Need manager review ASAP", urgency: .immediate),
            CategorizedItem(category: .general, content: "Check next shift", urgency: .nextShift)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.count == 2)
        #expect(!actions.contains(where: { $0.urgency == .fyi }))
    }

    // MARK: - StructuringError Tests

    @Test func structuringErrorMessages() {
        #expect(!StructuringError.emptyTranscript.userMessage.isEmpty)
        #expect(!StructuringError.noBaseURL.userMessage.isEmpty)
        #expect(!StructuringError.invalidURL.userMessage.isEmpty)
        #expect(!StructuringError.decodingError.userMessage.isEmpty)
        #expect(!StructuringError.timeout.userMessage.isEmpty)
        #expect(StructuringError.serverError("test error").userMessage == "test error")
        #expect(StructuringError.aiUnavailable("AI down").userMessage == "AI down")
    }

    // MARK: - StructuringResult Tests

    @Test func structuringResultCreation() {
        let result = StructuringResult(
            summary: "Test summary",
            categorizedItems: [CategorizedItem(category: .equipment, content: "Broken", urgency: .immediate)],
            actionItems: [ActionItem(task: "Fix it", category: .equipment, urgency: .immediate)],
            usedAI: true,
            warning: nil
        )

        #expect(result.summary == "Test summary")
        #expect(result.categorizedItems.count == 1)
        #expect(result.actionItems.count == 1)
        #expect(result.usedAI == true)
        #expect(result.warning == nil)
    }

    @Test func structuringResultWithWarning() {
        let result = StructuringResult(
            summary: "Summary",
            categorizedItems: [CategorizedItem(category: .general, content: "Long content", urgency: .fyi)],
            actionItems: [],
            usedAI: true,
            warning: "May contain multiple topics"
        )

        #expect(result.warning != nil)
        #expect(result.warning!.contains("multiple topics"))
    }

    // MARK: - PendingNoteReviewData Tests

    @Test func pendingReviewDataWithAIFields() {
        let shiftInfo = ShiftDisplayInfo(id: "shift_opening", name: "Opening", icon: "sunrise.fill")
        let pending = PendingNoteReviewData(
            rawTranscript: "Test",
            audioDuration: 30,
            audioUrl: nil,
            shiftInfo: shiftInfo,
            summary: "Test",
            categorizedItems: [],
            actionItems: [],
            usedAI: false,
            structuringWarning: "AI was unavailable"
        )

        #expect(pending.usedAI == false)
        #expect(pending.structuringWarning == "AI was unavailable")
    }

    @Test func pendingReviewDataDefaultValues() {
        let shiftInfo = ShiftDisplayInfo(id: "shift_mid", name: "Mid", icon: "sun.max.fill")
        let pending = PendingNoteReviewData(
            rawTranscript: "Test",
            audioDuration: 30,
            audioUrl: nil,
            shiftInfo: shiftInfo,
            summary: "Test",
            categorizedItems: [],
            actionItems: []
        )

        #expect(pending.usedAI == true)
        #expect(pending.structuringWarning == nil)
    }

    // MARK: - AI Response Decoding Tests

    @Test func aiStructuredItemDecoding() throws {
        let json = """
        {"content": "The fryer is broken", "category": "Equipment", "urgency": "Immediate", "actionRequired": true, "actionTask": "Fix the fryer"}
        """
        let data = json.data(using: .utf8)!
        let item = try JSONDecoder().decode(AIStructuredItem.self, from: data)

        #expect(item.content == "The fryer is broken")
        #expect(item.category == "Equipment")
        #expect(item.urgency == "Immediate")
        #expect(item.actionRequired == true)
        #expect(item.actionTask == "Fix the fryer")
    }

    @Test func aiStructuredNoteDecoding() throws {
        let json = """
        {
            "summary": "Equipment and inventory issues",
            "items": [
                {"content": "Fryer broken", "category": "Equipment", "urgency": "Immediate", "actionRequired": true, "actionTask": "Fix fryer"},
                {"content": "Low on napkins", "category": "Inventory", "urgency": "Next Shift", "actionRequired": true, "actionTask": "Restock napkins"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let note = try JSONDecoder().decode(AIStructuredNote.self, from: data)

        #expect(note.summary == "Equipment and inventory issues")
        #expect(note.items.count == 2)
    }

    @Test func aiStructureResponseSuccessDecoding() throws {
        let json = """
        {
            "success": true,
            "structured": {
                "summary": "Test",
                "items": [{"content": "Test item", "category": "General", "urgency": "FYI", "actionRequired": false, "actionTask": null}]
            },
            "error": null
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AIStructureResponse.self, from: data)

        #expect(response.success == true)
        #expect(response.structured != nil)
        #expect(response.error == nil)
    }

    @Test func aiStructureResponseErrorDecoding() throws {
        let json = """
        {"success": false, "structured": null, "error": "AI structuring unavailable"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(AIStructureResponse.self, from: data)

        #expect(response.success == false)
        #expect(response.structured == nil)
        #expect(response.error == "AI structuring unavailable")
    }

    // MARK: - End-to-End Local Fallback Tests

    @Test func fullLocalFallbackThreeTopics() {
        let vm = AppViewModel()
        let transcript = "The fryer is broken and needs repair. We are running low on supplies. There was a spill creating a safety hazard."

        let categories = vm.testGenerateCategories(from: transcript)
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(categories.count >= 3)
        #expect(actions.count >= 3)

        let actionCategories = Set(actions.map(\.category))
        #expect(actionCategories.contains(.equipment))
        #expect(actionCategories.contains(.inventory))
        #expect(actionCategories.contains(.healthSafety))
    }

    @Test func fullLocalFallbackSingleTopic() {
        let vm = AppViewModel()
        let transcript = "Everything was smooth today no issues at all."

        let categories = vm.testGenerateCategories(from: transcript)
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(categories.count >= 1)
        #expect(categories[0].category == .general)
        #expect(actions.isEmpty)
    }

    @Test func fullLocalFallback86dItems() {
        let vm = AppViewModel()
        let transcript = "We sold out of the salmon special and the chocolate cake is 86'd."

        let categories = vm.testGenerateCategories(from: transcript)
        #expect(categories.contains(where: { $0.category == .eightySixed }))

        let eightySixed = categories.first(where: { $0.category == .eightySixed })
        #expect(eightySixed?.urgency == .immediate)
    }

    @Test func fullLocalFallbackStaffNote() {
        let vm = AppViewModel()
        let transcript = "The new employee needs more training on the POS system."

        let categories = vm.testGenerateCategories(from: transcript)
        #expect(categories.contains(where: { $0.category == .staffNote }))
    }

    @Test func fullLocalFallbackGuestIssue() {
        let vm = AppViewModel()
        let transcript = "A guest at table 7 is unhappy with the service and wants to speak with a manager."

        let categories = vm.testGenerateCategories(from: transcript)
        #expect(categories.contains(where: { $0.category == .guestIssue }))
    }
}
