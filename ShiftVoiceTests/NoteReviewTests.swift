import Testing
@testable import ShiftVoice

struct NoteReviewTests {

    // MARK: - EditableCategorizedItem Tests

    @Test func editableCategorizedItemFromCategorizedItem() {
        let original = CategorizedItem(
            id: "ci1",
            category: .equipment,
            categoryTemplateId: "cat_equip",
            content: "Broken fryer in kitchen",
            urgency: .immediate
        )

        let editable = EditableCategorizedItem(from: original)

        #expect(editable.id == "ci1")
        #expect(editable.category == .equipment)
        #expect(editable.categoryTemplateId == "cat_equip")
        #expect(editable.content == "Broken fryer in kitchen")
        #expect(editable.urgency == .immediate)
    }

    @Test func editableCategorizedItemRoundTrip() {
        let original = CategorizedItem(
            category: .inventory,
            content: "Low on napkins",
            urgency: .nextShift
        )

        let editable = EditableCategorizedItem(from: original)
        let converted = editable.toCategorizedItem()

        #expect(converted.id == original.id)
        #expect(converted.category == original.category)
        #expect(converted.content == original.content)
        #expect(converted.urgency == original.urgency)
    }

    @Test func editableCategorizedItemMutation() {
        let original = CategorizedItem(
            category: .general,
            content: "Note about something",
            urgency: .fyi
        )

        var editable = EditableCategorizedItem(from: original)
        editable.category = .maintenance
        editable.urgency = .thisWeek
        editable.content = "Updated content"

        let converted = editable.toCategorizedItem()

        #expect(converted.category == .maintenance)
        #expect(converted.urgency == .thisWeek)
        #expect(converted.content == "Updated content")
        #expect(converted.id == original.id)
    }

    @Test func editableCategorizedItemPreservesNilTemplateId() {
        let original = CategorizedItem(
            category: .healthSafety,
            content: "Spill in aisle 3",
            urgency: .immediate
        )

        let editable = EditableCategorizedItem(from: original)

        #expect(editable.categoryTemplateId == nil)

        let converted = editable.toCategorizedItem()
        #expect(converted.categoryTemplateId == nil)
    }

    // MARK: - EditableActionItem Tests

    @Test func editableActionItemFromActionItem() {
        let original = ActionItem(
            id: "ai1",
            task: "Fix the oven",
            category: .equipment,
            categoryTemplateId: "cat_equip",
            urgency: .immediate,
            status: .open,
            assignee: "John Doe"
        )

        let editable = EditableActionItem(from: original)

        #expect(editable.id == "ai1")
        #expect(editable.task == "Fix the oven")
        #expect(editable.category == .equipment)
        #expect(editable.categoryTemplateId == "cat_equip")
        #expect(editable.urgency == .immediate)
        #expect(editable.assignee == "John Doe")
    }

    @Test func editableActionItemRoundTrip() {
        let original = ActionItem(
            task: "Restock supplies",
            category: .inventory,
            urgency: .nextShift,
            assignee: "Jane Smith"
        )

        let editable = EditableActionItem(from: original)
        let converted = editable.toActionItem()

        #expect(converted.id == original.id)
        #expect(converted.task == original.task)
        #expect(converted.category == original.category)
        #expect(converted.urgency == original.urgency)
        #expect(converted.assignee == original.assignee)
    }

    @Test func editableActionItemDirectInit() {
        let editable = EditableActionItem(
            id: "new1",
            task: "Clean the grill",
            category: .maintenance,
            urgency: .thisWeek,
            assignee: nil
        )

        #expect(editable.id == "new1")
        #expect(editable.task == "Clean the grill")
        #expect(editable.category == .maintenance)
        #expect(editable.urgency == .thisWeek)
        #expect(editable.assignee == nil)
    }

    @Test func editableActionItemMutation() {
        var editable = EditableActionItem(
            id: "ai1",
            task: "Original task",
            category: .general,
            urgency: .fyi,
            assignee: nil
        )

        editable.task = "Updated task description"
        editable.category = .equipment
        editable.urgency = .immediate
        editable.assignee = "Bob"

        let converted = editable.toActionItem()

        #expect(converted.task == "Updated task description")
        #expect(converted.category == .equipment)
        #expect(converted.urgency == .immediate)
        #expect(converted.assignee == "Bob")
    }

    @Test func editableActionItemAssignmentCycle() {
        var editable = EditableActionItem(
            id: "ai1",
            task: "Task",
            category: .maintenance,
            urgency: .nextShift,
            assignee: nil
        )

        #expect(editable.assignee == nil)

        editable.assignee = "Alice"
        #expect(editable.assignee == "Alice")

        editable.assignee = "Bob"
        #expect(editable.assignee == "Bob")

        editable.assignee = nil
        #expect(editable.assignee == nil)
    }

    @Test func editableActionItemToActionItemDefaultsStatus() {
        let editable = EditableActionItem(
            id: "ai1",
            task: "New task",
            category: .equipment,
            urgency: .immediate,
            assignee: nil
        )

        let converted = editable.toActionItem()
        #expect(converted.status == .open)
    }

    // MARK: - Batch Conversion Tests

    @Test func multipleCategorizedItemsConversion() {
        let originals = [
            CategorizedItem(category: .equipment, content: "Broken fryer", urgency: .immediate),
            CategorizedItem(category: .inventory, content: "Low on cups", urgency: .nextShift),
            CategorizedItem(category: .healthSafety, content: "Wet floor", urgency: .immediate)
        ]

        let editables = originals.map { EditableCategorizedItem(from: $0) }
        #expect(editables.count == 3)

        let converted = editables.map { $0.toCategorizedItem() }
        #expect(converted.count == 3)

        for (original, result) in zip(originals, converted) {
            #expect(original.id == result.id)
            #expect(original.category == result.category)
            #expect(original.content == result.content)
            #expect(original.urgency == result.urgency)
        }
    }

    @Test func multipleActionItemsConversion() {
        let originals = [
            ActionItem(task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "John"),
            ActionItem(task: "Order supplies", category: .inventory, urgency: .thisWeek, assignee: nil),
            ActionItem(task: "Clean spill", category: .maintenance, urgency: .nextShift, assignee: "Jane")
        ]

        let editables = originals.map { EditableActionItem(from: $0) }
        #expect(editables.count == 3)

        let converted = editables.map { $0.toActionItem() }
        #expect(converted[0].assignee == "John")
        #expect(converted[1].assignee == nil)
        #expect(converted[2].assignee == "Jane")
    }

    // MARK: - PendingNoteReviewData Tests

    @Test func pendingNoteReviewDataCreation() {
        let shiftInfo = ShiftDisplayInfo(id: "shift_opening", name: "Opening", icon: "sunrise.fill")
        let items = [CategorizedItem(category: .equipment, content: "Test", urgency: .immediate)]
        let actions = [ActionItem(task: "Fix it", category: .equipment, urgency: .immediate)]

        let pending = PendingNoteReviewData(
            rawTranscript: "The fryer is broken",
            audioDuration: 45.5,
            audioUrl: "recording.m4a",
            shiftInfo: shiftInfo,
            summary: "Equipment issue",
            categorizedItems: items,
            actionItems: actions
        )

        #expect(pending.rawTranscript == "The fryer is broken")
        #expect(pending.audioDuration == 45.5)
        #expect(pending.audioUrl == "recording.m4a")
        #expect(pending.shiftInfo.name == "Opening")
        #expect(pending.summary == "Equipment issue")
        #expect(pending.categorizedItems.count == 1)
        #expect(pending.actionItems.count == 1)
    }

    @Test func pendingNoteReviewDataNilAudioUrl() {
        let shiftInfo = ShiftDisplayInfo(id: "shift_mid", name: "Mid", icon: "sun.max.fill")

        let pending = PendingNoteReviewData(
            rawTranscript: "All clear",
            audioDuration: 0,
            audioUrl: nil,
            shiftInfo: shiftInfo,
            summary: "All clear",
            categorizedItems: [],
            actionItems: []
        )

        #expect(pending.audioUrl == nil)
        #expect(pending.audioDuration == 0)
        #expect(pending.categorizedItems.isEmpty)
        #expect(pending.actionItems.isEmpty)
    }

    // MARK: - ShiftDisplayInfo Tests

    @Test func shiftDisplayInfoFromShiftType() {
        let opening = ShiftDisplayInfo(from: ShiftType.opening)
        #expect(opening.name == "Opening")
        #expect(opening.icon == "sunrise.fill")
        #expect(opening.id == "legacy_Opening")

        let mid = ShiftDisplayInfo(from: ShiftType.mid)
        #expect(mid.name == "Mid")
        #expect(mid.icon == "sun.max.fill")

        let closing = ShiftDisplayInfo(from: ShiftType.closing)
        #expect(closing.name == "Closing")
        #expect(closing.icon == "moon.stars.fill")
    }

    @Test func shiftDisplayInfoCustomInit() {
        let info = ShiftDisplayInfo(id: "custom_shift", name: "Happy Hour", icon: "wineglass.fill")

        #expect(info.id == "custom_shift")
        #expect(info.name == "Happy Hour")
        #expect(info.icon == "wineglass.fill")
    }

    @Test func shiftDisplayInfoHashable() {
        let a = ShiftDisplayInfo(id: "s1", name: "Opening", icon: "sunrise.fill")
        let b = ShiftDisplayInfo(id: "s1", name: "Opening", icon: "sunrise.fill")
        let c = ShiftDisplayInfo(id: "s2", name: "Closing", icon: "moon.stars.fill")

        #expect(a == b)
        #expect(a != c)

        var set = Set<ShiftDisplayInfo>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - TeamMember Filtering Tests (AssigneePickerView logic)

    @Test func teamMemberFilterByName() {
        let members = [
            TeamMember(name: "John Doe", email: "john@test.com", role: .manager),
            TeamMember(name: "Jane Smith", email: "jane@test.com", role: .shiftLead),
            TeamMember(name: "Bob Johnson", email: "bob@test.com", role: .generalManager)
        ]

        let searchText = "Jane"
        let filtered = members.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.email.localizedStandardContains(searchText)
        }

        #expect(filtered.count == 1)
        #expect(filtered[0].name == "Jane Smith")
    }

    @Test func teamMemberFilterByEmail() {
        let members = [
            TeamMember(name: "John Doe", email: "john@test.com", role: .manager),
            TeamMember(name: "Jane Smith", email: "jane@test.com", role: .shiftLead)
        ]

        let searchText = "john@"
        let filtered = members.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.email.localizedStandardContains(searchText)
        }

        #expect(filtered.count == 1)
        #expect(filtered[0].email == "john@test.com")
    }

    @Test func teamMemberFilterCaseInsensitive() {
        let members = [
            TeamMember(name: "John Doe", email: "john@test.com", role: .manager)
        ]

        let searchText = "JOHN"
        let filtered = members.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.email.localizedStandardContains(searchText)
        }

        #expect(filtered.count == 1)
    }

    @Test func teamMemberFilterEmptyReturnsAll() {
        let members = [
            TeamMember(name: "John Doe", email: "john@test.com", role: .manager),
            TeamMember(name: "Jane Smith", email: "jane@test.com", role: .shiftLead),
            TeamMember(name: "Bob Johnson", email: "bob@test.com", role: .generalManager)
        ]

        let searchText = ""
        let filtered: [TeamMember]
        if searchText.isEmpty {
            filtered = members
        } else {
            filtered = members.filter {
                $0.name.localizedStandardContains(searchText) ||
                $0.email.localizedStandardContains(searchText)
            }
        }

        #expect(filtered.count == 3)
    }

    @Test func teamMemberFilterNoResults() {
        let members = [
            TeamMember(name: "John Doe", email: "john@test.com", role: .manager),
            TeamMember(name: "Jane Smith", email: "jane@test.com", role: .shiftLead)
        ]

        let searchText = "zzznotfound"
        let filtered = members.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.email.localizedStandardContains(searchText)
        }

        #expect(filtered.isEmpty)
    }

    // MARK: - Action Item Assignment Integration Tests

    @Test func actionItemAssignmentViaViewModel() {
        let vm = AppViewModel()

        let action = ActionItem(task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: nil)
        let note = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "",
            actionItems: [action]
        )

        vm.shiftNotes = [note]

        #expect(vm.shiftNotes[0].actionItems[0].assignee == nil)

        vm.shiftNotes[0].actionItems[0].assignee = "Jane Smith"
        #expect(vm.shiftNotes[0].actionItems[0].assignee == "Jane Smith")
    }

    @Test func actionItemUnassignmentViaViewModel() {
        let vm = AppViewModel()

        let action = ActionItem(task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "John")
        let note = ShiftNote(
            authorId: "u1", authorName: "A", authorInitials: "A",
            locationId: "loc1", shiftType: .closing, rawTranscript: "", summary: "",
            actionItems: [action]
        )

        vm.shiftNotes = [note]

        #expect(vm.shiftNotes[0].actionItems[0].assignee == "John")

        vm.shiftNotes[0].actionItems[0].assignee = nil
        #expect(vm.shiftNotes[0].actionItems[0].assignee == nil)
    }

    // MARK: - Note Publishing Flow Tests

    @Test func notePublishingFromEditableItems() {
        let editableCategories = [
            EditableCategorizedItem(from: CategorizedItem(category: .equipment, content: "Broken fryer", urgency: .immediate)),
            EditableCategorizedItem(from: CategorizedItem(category: .inventory, content: "Low cups", urgency: .nextShift))
        ]

        var editableActions = [
            EditableActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: nil),
            EditableActionItem(id: "a2", task: "Order cups", category: .inventory, urgency: .nextShift, assignee: nil)
        ]

        editableActions[0].assignee = "John"
        editableActions[1].assignee = "Jane"

        let categorizedItems = editableCategories.map { $0.toCategorizedItem() }
        let actionItems = editableActions.map { $0.toActionItem() }

        let note = ShiftNote(
            authorId: "u1",
            authorName: "Test User",
            authorInitials: "TU",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "The fryer is broken and we're low on cups",
            summary: "Equipment and inventory issues",
            categorizedItems: categorizedItems,
            actionItems: actionItems
        )

        #expect(note.categorizedItems.count == 2)
        #expect(note.actionItems.count == 2)
        #expect(note.actionItems[0].assignee == "John")
        #expect(note.actionItems[1].assignee == "Jane")
        #expect(note.highestUrgency == .immediate)
        #expect(note.unresolvedActionCount == 2)
        #expect(note.categories.contains(.equipment))
        #expect(note.categories.contains(.inventory))
    }

    @Test func notePublishingWithEmptyActions() {
        let editableCategories = [
            EditableCategorizedItem(from: CategorizedItem(category: .general, content: "All good", urgency: .fyi))
        ]
        let editableActions: [EditableActionItem] = []

        let categorizedItems = editableCategories.map { $0.toCategorizedItem() }
        let actionItems = editableActions.map { $0.toActionItem() }

        let note = ShiftNote(
            authorId: "u1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .mid,
            rawTranscript: "Everything is fine",
            summary: "All good",
            categorizedItems: categorizedItems,
            actionItems: actionItems
        )

        #expect(note.actionItems.isEmpty)
        #expect(note.unresolvedActionCount == 0)
        #expect(note.highestUrgency == .fyi)
    }

    // MARK: - Editable Items Deletion Tests

    @Test func editableCategorizedItemDeletion() {
        var items = [
            EditableCategorizedItem(from: CategorizedItem(id: "c1", category: .equipment, content: "A", urgency: .immediate)),
            EditableCategorizedItem(from: CategorizedItem(id: "c2", category: .inventory, content: "B", urgency: .fyi)),
            EditableCategorizedItem(from: CategorizedItem(id: "c3", category: .general, content: "C", urgency: .fyi))
        ]

        items.removeAll { $0.id == "c2" }

        #expect(items.count == 2)
        #expect(items[0].id == "c1")
        #expect(items[1].id == "c3")
    }

    @Test func editableActionItemDeletion() {
        var items = [
            EditableActionItem(id: "a1", task: "Task 1", category: .equipment, urgency: .immediate, assignee: "John"),
            EditableActionItem(id: "a2", task: "Task 2", category: .inventory, urgency: .nextShift, assignee: nil),
            EditableActionItem(id: "a3", task: "Task 3", category: .maintenance, urgency: .thisWeek, assignee: "Jane")
        ]

        items.removeAll { $0.id == "a1" }

        #expect(items.count == 2)
        #expect(items[0].id == "a2")
        #expect(items[1].id == "a3")
    }

    // MARK: - ActionItem Codable with Assignee Tests

    @Test func actionItemCodableWithAssignee() throws {
        let original = ActionItem(
            task: "Fix fryer",
            category: .equipment,
            urgency: .immediate,
            assignee: "John Doe"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ActionItem.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.task == "Fix fryer")
        #expect(decoded.assignee == "John Doe")
        #expect(decoded.status == .open)
    }

    @Test func actionItemCodableWithNilAssignee() throws {
        let original = ActionItem(
            task: "General cleanup",
            category: .maintenance,
            urgency: .fyi,
            assignee: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActionItem.self, from: data)

        #expect(decoded.assignee == nil)
    }

    // MARK: - ShiftNote with shiftTemplateId Tests

    @Test func shiftNoteWithTemplateId() {
        let note = ShiftNote(
            authorId: "u1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .opening,
            shiftTemplateId: "shift_opening",
            rawTranscript: "Test",
            summary: "Test"
        )

        #expect(note.shiftTemplateId == "shift_opening")
        #expect(note.shiftType == .opening)
    }

    @Test func shiftNoteWithoutTemplateId() {
        let note = ShiftNote(
            authorId: "u1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "Test",
            summary: "Test"
        )

        #expect(note.shiftTemplateId == nil)
        let info = note.shiftDisplayInfo
        #expect(info.name == "Closing")
    }
}
