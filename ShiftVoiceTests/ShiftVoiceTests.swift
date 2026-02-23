import Testing
@testable import ShiftVoice

struct ShiftVoiceTests {

    // MARK: - ShiftNote Model Tests

    @Test func shiftNoteCreation() {
        let note = ShiftNote(
            authorId: "user1",
            authorName: "John Doe",
            authorInitials: "JD",
            locationId: "loc1",
            shiftType: .opening,
            rawTranscript: "Test transcript",
            summary: "Test summary"
        )

        #expect(note.authorId == "user1")
        #expect(note.authorName == "John Doe")
        #expect(note.shiftType == .opening)
        #expect(note.isSynced == true)
        #expect(!note.id.isEmpty)
    }

    @Test func shiftNoteHighestUrgency() {
        let items = [
            CategorizedItem(category: .general, content: "Test", urgency: .fyi),
            CategorizedItem(category: .equipment, content: "Broken", urgency: .nextShift),
            CategorizedItem(category: .healthSafety, content: "Spill", urgency: .immediate)
        ]

        let note = ShiftNote(
            authorId: "user1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "",
            summary: "",
            categorizedItems: items
        )

        #expect(note.highestUrgency == .immediate)
    }

    @Test func shiftNoteHighestUrgencyDefaultsFYI() {
        let note = ShiftNote(
            authorId: "user1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .mid,
            rawTranscript: "",
            summary: ""
        )

        #expect(note.highestUrgency == .fyi)
    }

    @Test func shiftNoteActionItemCounts() {
        let actions = [
            ActionItem(task: "Fix fryer", category: .equipment, urgency: .immediate, status: .open),
            ActionItem(task: "Restock napkins", category: .inventory, urgency: .nextShift, status: .resolved),
            ActionItem(task: "Clean spill", category: .maintenance, urgency: .nextShift, status: .inProgress)
        ]

        let note = ShiftNote(
            authorId: "user1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "",
            summary: "",
            actionItems: actions
        )

        #expect(note.unresolvedActionCount == 2)
        #expect(note.resolvedActionCount == 1)
    }

    @Test func shiftNoteCategories() {
        let items = [
            CategorizedItem(category: .equipment, content: "Broken", urgency: .nextShift),
            CategorizedItem(category: .equipment, content: "Another", urgency: .fyi),
            CategorizedItem(category: .inventory, content: "Low", urgency: .thisWeek)
        ]

        let note = ShiftNote(
            authorId: "user1",
            authorName: "Test",
            authorInitials: "T",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "",
            summary: "",
            categorizedItems: items
        )

        #expect(note.categories.count == 2)
        #expect(note.categories.contains(.equipment))
        #expect(note.categories.contains(.inventory))
    }

    // MARK: - Organization Model Tests

    @Test func organizationCreation() {
        let org = Organization(
            name: "Test Restaurant",
            ownerId: "owner1",
            plan: .starter,
            industryType: .restaurant
        )

        #expect(org.name == "Test Restaurant")
        #expect(org.plan == .starter)
        #expect(org.industryType == .restaurant)
        #expect(!org.id.isEmpty)
    }

    @Test func subscriptionPlanLimits() {
        #expect(SubscriptionPlan.free.maxLocations == 1)
        #expect(SubscriptionPlan.starter.maxLocations == 5)
        #expect(SubscriptionPlan.professional.maxLocations == 20)
        #expect(SubscriptionPlan.enterprise.maxLocations == .max)

        #expect(SubscriptionPlan.free.maxManagersPerLocation == 3)
        #expect(SubscriptionPlan.starter.maxManagersPerLocation == 6)
    }

    // MARK: - Location Model Tests

    @Test func locationCreation() {
        let loc = Location(
            name: "Downtown",
            address: "123 Main St",
            timezone: "America/Chicago",
            managerIds: ["user1", "user2"]
        )

        #expect(loc.name == "Downtown")
        #expect(loc.managerIds.count == 2)
        #expect(!loc.id.isEmpty)
    }

    @Test func locationEquality() {
        let id = "test-id"
        let loc1 = Location(id: id, name: "A", address: "")
        let loc2 = Location(id: id, name: "B", address: "Different")

        #expect(loc1 == loc2)
    }

    @Test func locationHashing() {
        let loc1 = Location(id: "same", name: "A", address: "")
        let loc2 = Location(id: "same", name: "B", address: "")

        var set = Set<Location>()
        set.insert(loc1)
        set.insert(loc2)
        #expect(set.count == 1)
    }

    // MARK: - TeamMember Model Tests

    @Test func teamMemberAutoInitials() {
        let member = TeamMember(
            name: "John Doe",
            email: "john@test.com",
            role: .manager
        )

        #expect(member.avatarInitials == "JD")
    }

    @Test func teamMemberSingleNameInitials() {
        let member = TeamMember(
            name: "John",
            email: "john@test.com",
            role: .shiftLead
        )

        #expect(member.avatarInitials == "JO")
    }

    @Test func teamMemberCustomInitials() {
        let member = TeamMember(
            name: "John Doe",
            email: "john@test.com",
            role: .manager,
            avatarInitials: "XX"
        )

        #expect(member.avatarInitials == "XX")
    }

    @Test func managerRoleSortOrder() {
        #expect(ManagerRole.owner.sortOrder < ManagerRole.generalManager.sortOrder)
        #expect(ManagerRole.generalManager.sortOrder < ManagerRole.manager.sortOrder)
        #expect(ManagerRole.manager.sortOrder < ManagerRole.shiftLead.sortOrder)
    }

    // MARK: - Urgency Level Tests

    @Test func urgencyLevelSortOrder() {
        #expect(UrgencyLevel.immediate.sortOrder < UrgencyLevel.nextShift.sortOrder)
        #expect(UrgencyLevel.nextShift.sortOrder < UrgencyLevel.thisWeek.sortOrder)
        #expect(UrgencyLevel.thisWeek.sortOrder < UrgencyLevel.fyi.sortOrder)
    }

    // MARK: - ActionItem Tests

    @Test func actionItemCreation() {
        let item = ActionItem(
            task: "Fix the oven",
            category: .equipment,
            categoryTemplateId: "cat_equip",
            urgency: .immediate
        )

        #expect(item.task == "Fix the oven")
        #expect(item.status == .open)
        #expect(item.category == .equipment)
        #expect(item.assignee == nil)
    }

    // MARK: - CategorizedItem Tests

    @Test func categorizedItemDisplayInfo() {
        let item = CategorizedItem(
            category: .equipment,
            content: "Broken fryer",
            urgency: .immediate
        )

        let info = item.displayInfo
        #expect(!info.name.isEmpty)
        #expect(!info.icon.isEmpty)
    }

    // MARK: - Acknowledgment Tests

    @Test func acknowledgmentCreation() {
        let ack = Acknowledgment(userId: "user1", userName: "John")

        #expect(ack.userId == "user1")
        #expect(ack.userName == "John")
        #expect(!ack.id.isEmpty)
    }

    // MARK: - VoiceReply Tests

    @Test func voiceReplyCreation() {
        let reply = VoiceReply(
            authorId: "user1",
            authorName: "John",
            transcript: "Noted, will fix it tomorrow"
        )

        #expect(reply.authorId == "user1")
        #expect(reply.parentItemId == nil)
        #expect(!reply.id.isEmpty)
    }

    // MARK: - RecurringIssue Tests

    @Test func recurringIssueCreation() {
        let issue = RecurringIssue(
            description: "Fryer keeps breaking",
            category: .equipment,
            locationId: "loc1",
            locationName: "Downtown",
            mentionCount: 3,
            firstMentioned: Date().addingTimeInterval(-86400 * 7),
            lastMentioned: Date()
        )

        #expect(issue.status == .active)
        #expect(issue.mentionCount == 3)
    }

    // MARK: - ShiftType Tests

    @Test func shiftTypeIcons() {
        #expect(ShiftType.opening.icon == "sunrise.fill")
        #expect(ShiftType.mid.icon == "sun.max.fill")
        #expect(ShiftType.closing.icon == "moon.stars.fill")
    }

    // MARK: - NoteCategory Tests

    @Test func noteCategoryIcons() {
        for category in NoteCategory.allCases {
            #expect(!category.icon.isEmpty, "Category \(category.rawValue) should have an icon")
        }
    }

    // MARK: - Codable Tests

    @Test func shiftNoteCodableRoundTrip() throws {
        let original = ShiftNote(
            authorId: "user1",
            authorName: "John",
            authorInitials: "JD",
            locationId: "loc1",
            shiftType: .closing,
            rawTranscript: "Everything is clean",
            summary: "Clean shift",
            categorizedItems: [
                CategorizedItem(category: .general, content: "All good", urgency: .fyi)
            ],
            actionItems: [
                ActionItem(task: "Restock", category: .inventory, urgency: .nextShift)
            ]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ShiftNote.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.authorId == original.authorId)
        #expect(decoded.shiftType == original.shiftType)
        #expect(decoded.categorizedItems.count == 1)
        #expect(decoded.actionItems.count == 1)
    }

    @Test func organizationCodableRoundTrip() throws {
        let original = Organization(
            name: "Test Cafe",
            ownerId: "owner1",
            plan: .professional,
            industryType: .cafe
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Organization.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Test Cafe")
        #expect(decoded.plan == .professional)
        #expect(decoded.industryType == .cafe)
    }

    @Test func locationCodableRoundTrip() throws {
        let original = Location(
            name: "Uptown",
            address: "456 Oak Ave",
            timezone: "America/Los_Angeles",
            managerIds: ["m1", "m2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Location.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.name == "Uptown")
        #expect(decoded.managerIds.count == 2)
    }

    // MARK: - APIError Tests

    @Test func apiErrorDescriptions() {
        #expect(APIError.invalidURL.errorDescription != nil)
        #expect(APIError.unauthorized.errorDescription != nil)
        #expect(APIError.rateLimited.errorDescription != nil)
        #expect(APIError.validationError("Bad input").errorDescription == "Bad input")
    }

    @Test func apiErrorRetryable() {
        #expect(APIError.rateLimited.isRetryable == true)
        #expect(APIError.serverError("500").isRetryable == true)
        #expect(APIError.unauthorized.isRetryable == false)
        #expect(APIError.invalidURL.isRetryable == false)
        #expect(APIError.validationError("Bad").isRetryable == false)
    }

    // MARK: - AppData Tests

    @Test func appDataCodableRoundTrip() throws {
        let org = Organization(name: "Test", ownerId: "o1")
        let loc = Location(name: "Main", address: "123 St")

        let appData = AppData(
            organization: org,
            locations: [loc],
            teamMembers: [],
            shiftNotes: [],
            recurringIssues: [],
            selectedLocationId: loc.id
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(appData)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppData.self, from: data)

        #expect(decoded.organization.name == "Test")
        #expect(decoded.locations.count == 1)
        #expect(decoded.selectedLocationId == loc.id)
    }
}
