import Testing
@testable import ShiftVoice

struct ViewModelTests {

    // MARK: - Category Generation Tests

    @Test func categoryGenerationFromEquipmentTranscript() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "The fryer is broken and needs repair")

        #expect(!notes.isEmpty)
        #expect(notes.contains(where: { $0.category == .equipment }))
    }

    @Test func categoryGenerationFromInventoryTranscript() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "We are running low on supplies and need to restock")

        #expect(!notes.isEmpty)
        #expect(notes.contains(where: { $0.category == .inventory }))
    }

    @Test func categoryGenerationFromSafetyTranscript() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "There was a spill creating a safety hazard")

        #expect(!notes.isEmpty)
        let safetyItem = notes.first(where: { $0.category == .healthSafety })
        #expect(safetyItem != nil)
        #expect(safetyItem?.urgency == .immediate)
    }

    @Test func categoryGenerationDefaultsToGeneral() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "Everything went smoothly today")

        #expect(notes.count == 1)
        #expect(notes[0].category == .general)
        #expect(notes[0].urgency == .fyi)
    }

    @Test func categoryGenerationEmptyTranscript() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "")

        #expect(notes.isEmpty)
    }

    @Test func multiCategoryDetection() {
        let vm = AppViewModel()
        let notes = vm.testGenerateCategories(from: "The equipment is broken and we ran out of inventory supplies")

        #expect(notes.count >= 2)
        #expect(notes.contains(where: { $0.category == .equipment }))
        #expect(notes.contains(where: { $0.category == .inventory }))
    }

    // MARK: - Action Item Generation Tests

    @Test func actionItemGenerationFromCategories() {
        let categories = [
            CategorizedItem(category: .equipment, content: "Broken", urgency: .immediate),
            CategorizedItem(category: .general, content: "Note", urgency: .fyi)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.count == 1)
        #expect(actions[0].category == .equipment)
        #expect(actions[0].status == .open)
    }

    @Test func actionItemGenerationSkipsGeneralFYI() {
        let categories = [
            CategorizedItem(category: .general, content: "All good", urgency: .fyi)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.isEmpty)
    }

    @Test func actionItemGenerationIncludesGeneralNonFYI() {
        let categories = [
            CategorizedItem(category: .general, content: "Urgent thing to review", urgency: .immediate)
        ]

        let vm = AppViewModel()
        let actions = vm.testGenerateActionItems(from: categories)

        #expect(actions.count == 1)
        #expect(actions[0].category == .general)
        #expect(actions[0].task.contains("Review"))
    }

    // MARK: - Summary Generation Tests

    @Test func summaryGenerationShortTranscript() {
        let vm = AppViewModel()
        let summary = vm.testGenerateSummary(from: "Short note")

        #expect(summary == "Short note")
    }

    @Test func summaryGenerationLongTranscript() {
        let vm = AppViewModel()
        let transcript = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence."
        let summary = vm.testGenerateSummary(from: transcript)

        #expect(summary.contains("First sentence"))
        #expect(summary.contains("Second sentence"))
        #expect(summary.contains("Third sentence"))
        #expect(!summary.contains("Fourth"))
    }

    @Test func summaryGenerationEmptyTranscript() {
        let vm = AppViewModel()
        let summary = vm.testGenerateSummary(from: "")

        #expect(summary.contains("no transcription"))
    }

    // MARK: - Feed Notes Tests

    @Test func feedNotesFiltering() {
        let vm = AppViewModel()
        vm.selectedLocationId = "loc1"

        let note1 = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        let note2 = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc2", shiftType: .closing, rawTranscript: "", summary: "")

        vm.shiftNotes = [note1, note2]

        let feed = vm.feedNotes
        #expect(feed.count == 1)
        #expect(feed[0].locationId == "loc1")
    }

    @Test func feedNotesSorting() {
        let vm = AppViewModel()
        vm.selectedLocationId = "loc1"

        let older = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "", createdAt: Date().addingTimeInterval(-3600))
        let newer = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "", createdAt: Date())

        vm.shiftNotes = [older, newer]

        let feed = vm.feedNotes
        #expect(feed.count == 2)
        #expect(feed[0].createdAt > feed[1].createdAt)
    }

    // MARK: - Acknowledgment Tests

    @Test func noteAcknowledgment() {
        let vm = AppViewModel()

        let note = ShiftNote(authorId: "u2", authorName: "Other", authorInitials: "O", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        vm.shiftNotes = [note]

        #expect(!vm.isNoteAcknowledged(note))

        vm.shiftNotes[0].acknowledgments.append(
            Acknowledgment(userId: vm.currentUserId, userName: "Me")
        )

        #expect(vm.isNoteAcknowledged(vm.shiftNotes[0]))
    }

    // MARK: - Unacknowledged Count Tests

    @Test func unacknowledgedCountCalculation() {
        let vm = AppViewModel()
        vm.selectedLocationId = "loc1"

        let note1 = ShiftNote(authorId: "u2", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        let note2 = ShiftNote(authorId: "u2", authorName: "B", authorInitials: "B", locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "")
        let note3 = ShiftNote(authorId: "u2", authorName: "C", authorInitials: "C", locationId: "loc2", shiftType: .mid, rawTranscript: "", summary: "")

        vm.shiftNotes = [note1, note2, note3]
        vm.updateUnacknowledgedCount()

        #expect(vm.unacknowledgedCount == 2)
    }

    // MARK: - Location Stats Tests

    @Test func locationStatsCalculation() {
        let vm = AppViewModel()

        let note1 = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "",
            categorizedItems: [CategorizedItem(category: .equipment, content: "", urgency: .immediate)]
        )
        let note2 = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "",
            categorizedItems: [CategorizedItem(category: .general, content: "", urgency: .fyi)]
        )

        vm.shiftNotes = [note1, note2]

        let stats = vm.locationStats("loc1")
        #expect(stats.noteCount == 2)
        #expect(stats.highestUrgency == .immediate)
    }

    // MARK: - Action Item Status Update Tests

    @Test func actionItemStatusUpdate() {
        let vm = AppViewModel()

        let action = ActionItem(task: "Fix it", category: .equipment, urgency: .immediate, status: .open)
        let note = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "",
            actionItems: [action]
        )

        vm.shiftNotes = [note]

        vm.updateActionItemStatus(noteId: note.id, actionItemId: action.id, newStatus: .inProgress)

        #expect(vm.shiftNotes[0].actionItems[0].status == .inProgress)
    }

    @Test func actionItemStatusUpdateNonexistent() {
        let vm = AppViewModel()
        vm.shiftNotes = []

        vm.updateActionItemStatus(noteId: "fake", actionItemId: "fake", newStatus: .resolved)
    }

    // MARK: - All Action Items Tests

    @Test func allActionItemsAggregation() {
        let vm = AppViewModel()

        let note1 = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "",
            actionItems: [
                ActionItem(task: "Task 1", category: .equipment, urgency: .immediate),
                ActionItem(task: "Task 2", category: .inventory, urgency: .nextShift)
            ]
        )
        let note2 = ShiftNote(
            authorId: "u2", authorName: "B", authorInitials: "B",
            locationId: "loc2", shiftType: .closing, rawTranscript: "", summary: "",
            actionItems: [
                ActionItem(task: "Task 3", category: .maintenance, urgency: .thisWeek)
            ]
        )

        vm.shiftNotes = [note1, note2]

        #expect(vm.allActionItems.count == 3)
        #expect(vm.allActionItemsWithDate.count == 3)
    }

    // MARK: - Current Shift Type Tests

    @Test func currentShiftTypeReturnsValidType() {
        let vm = AppViewModel()
        let shiftType = vm.currentShiftType

        #expect([ShiftType.opening, .mid, .closing].contains(shiftType))
    }

    // MARK: - Location Management Tests

    @Test func locationManagement() {
        let vm = AppViewModel()
        vm.locations = []

        let loc = Location(name: "New Place", address: "789 Elm St")
        vm.locations.append(loc)

        #expect(vm.locations.count == 1)
        #expect(vm.locationName(for: loc.id) == "New Place")
    }

    @Test func locationNameForUnknown() {
        let vm = AppViewModel()
        vm.locations = []

        #expect(vm.locationName(for: "nonexistent") == "Unknown")
    }

    // MARK: - Pagination State Tests

    @Test func resetPaginationState() {
        let vm = AppViewModel()
        vm.paginatedNotes = [
            ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        ]
        vm.paginationCursor = "some-cursor"
        vm.hasMoreNotes = false
        vm.totalNoteCount = 42

        vm.resetPagination()

        #expect(vm.paginatedNotes.isEmpty)
        #expect(vm.paginationCursor == nil)
        #expect(vm.hasMoreNotes == true)
        #expect(vm.totalNoteCount == 0)
    }

    // MARK: - Filtered Notes Tests

    @Test func filteredNotesWithShiftType() {
        let vm = AppViewModel()
        vm.selectedLocationId = "loc1"

        let opening = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        let closing = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "")

        vm.shiftNotes = [opening, closing]

        let filtered = vm.filteredNotes(shiftFilter: .opening)
        #expect(filtered.count == 1)
        #expect(filtered[0].shiftType == .opening)
    }

    @Test func filteredNotesNoFilter() {
        let vm = AppViewModel()
        vm.selectedLocationId = "loc1"

        let note1 = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        let note2 = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "")

        vm.shiftNotes = [note1, note2]

        let filtered = vm.filteredNotes(shiftFilter: nil)
        #expect(filtered.count == 2)
    }

    // MARK: - Delete Note Tests

    @Test func deleteNote() {
        let vm = AppViewModel()

        let note = ShiftNote(authorId: "u1", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "")
        vm.shiftNotes = [note]

        vm.shiftNotes.removeAll { $0.id == note.id }

        #expect(vm.shiftNotes.isEmpty)
    }

    // MARK: - Notes This Month Tests

    @Test func notesThisMonthCount() {
        let vm = AppViewModel()

        let thisMonth = ShiftNote(authorId: "", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .opening, rawTranscript: "", summary: "", createdAt: Date())
        let lastMonth = ShiftNote(authorId: "", authorName: "A", authorInitials: "A", locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "", createdAt: Date().addingTimeInterval(-86400 * 40))

        vm.shiftNotes = [thisMonth, lastMonth]

        #expect(vm.notesThisMonth == 1)
    }

    // MARK: - Recurring Issue Tests

    @Test func recurringIssueStatusTransitions() {
        let vm = AppViewModel()

        let issue = RecurringIssue(
            description: "Fryer breaking",
            category: .equipment,
            locationId: "loc1",
            locationName: "Downtown",
            mentionCount: 3,
            firstMentioned: Date(),
            lastMentioned: Date()
        )

        vm.recurringIssues = [issue]
        #expect(vm.recurringIssues[0].status == .active)

        vm.recurringIssues[0].status = .acknowledged
        #expect(vm.recurringIssues[0].status == .acknowledged)

        vm.recurringIssues[0].status = .resolved
        #expect(vm.recurringIssues[0].status == .resolved)
    }

    // MARK: - Business Type Mapping Tests

    @Test func industryTypeToBusinessType() {
        let vm = AppViewModel()

        vm.organization = Organization(name: "Test", ownerId: "o1", industryType: .restaurant)
        #expect(vm.organizationBusinessType == .restaurant)

        vm.organization = Organization(name: "Test", ownerId: "o1", industryType: .bar)
        #expect(vm.organizationBusinessType == .barPub)

        vm.organization = Organization(name: "Test", ownerId: "o1", industryType: .hotel)
        #expect(vm.organizationBusinessType == .hotel)

        vm.organization = Organization(name: "Test", ownerId: "o1", industryType: .cafe)
        #expect(vm.organizationBusinessType == .cafe)
    }
}
