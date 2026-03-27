import Testing
@testable import ShiftVoice

struct APIValidationTests {

    // MARK: - DTO Decoding Tests

    @Test func authResponseDecoding() throws {
        let json = """
        {"success": true, "userId": "u1", "token": "tok123", "name": "John", "email": "john@test.com"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        #expect(response.success == true)
        #expect(response.userId == "u1")
        #expect(response.token == "tok123")
        #expect(response.error == nil)
    }

    @Test func authResponseErrorDecoding() throws {
        let json = """
        {"success": false, "error": "Account already exists"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)
        #expect(response.success == false)
        #expect(response.error == "Account already exists")
        #expect(response.userId == nil)
    }

    @Test func syncPullResponseDecoding() throws {
        let json = """
        {"hasData": false, "data": null}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncPullResponse.self, from: json)
        #expect(response.hasData == false)
        #expect(response.data == nil)
    }

    @Test func syncPullResponseWithDelta() throws {
        let json = """
        {"hasData": true, "data": {"organization": null, "locations": [], "teamMembers": [], "shiftNotes": [], "recurringIssues": [], "selectedLocationId": null, "updatedAt": "2026-02-01T00:00:00Z"}, "isDelta": true}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncPullResponse.self, from: json)
        #expect(response.hasData == true)
        #expect(response.isDelta == true)
    }

    @Test func paginatedNotesResponseDecoding() throws {
        let json = """
        {"notes": [], "totalCount": 0, "hasMore": false, "nextCursor": null}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PaginatedNotesResponse.self, from: json)
        #expect(response.notes.isEmpty)
        #expect(response.totalCount == 0)
        #expect(response.hasMore == false)
        #expect(response.nextCursor == nil)
    }

    @Test func paginatedNotesWithDataDecoding() throws {
        let json = """
        {
            "notes": [
                {
                    "id": "note1",
                    "authorId": "u1",
                    "authorName": "John",
                    "authorInitials": "JD",
                    "locationId": "loc1",
                    "shiftType": "Closing",
                    "rawTranscript": "Test",
                    "summary": "Summary",
                    "createdAt": "2026-02-01T12:00:00Z"
                }
            ],
            "totalCount": 50,
            "hasMore": true,
            "nextCursor": "note1"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(PaginatedNotesResponse.self, from: json)
        #expect(response.notes.count == 1)
        #expect(response.totalCount == 50)
        #expect(response.hasMore == true)
        #expect(response.nextCursor == "note1")
    }

    // MARK: - ShiftNoteDTO Decoding Tests

    @Test func shiftNoteDTOFullDecoding() throws {
        let json = """
        {
            "id": "note1",
            "authorId": "u1",
            "authorName": "John Doe",
            "authorInitials": "JD",
            "locationId": "loc1",
            "shiftType": "Opening",
            "shiftTemplateId": "shift_opening",
            "rawTranscript": "The fryer is broken",
            "audioUrl": "recording.m4a",
            "audioDuration": 45.5,
            "summary": "Equipment issue",
            "categorizedItems": [
                {"id": "ci1", "category": "Equipment", "content": "Broken fryer", "urgency": "Immediate", "isResolved": false}
            ],
            "actionItems": [
                {"id": "ai1", "task": "Fix fryer", "category": "Equipment", "urgency": "Immediate", "status": "Open"}
            ],
            "photoUrls": ["photo1.jpg"],
            "acknowledgments": [
                {"id": "ack1", "userId": "u2", "userName": "Jane", "timestamp": "2026-02-01T12:00:00Z"}
            ],
            "voiceReplies": [],
            "createdAt": "2026-02-01T10:00:00Z",
            "isSynced": true
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ShiftNoteDTO.self, from: json)
        #expect(dto.id == "note1")
        #expect(dto.shiftType == "Opening")
        #expect(dto.audioDuration == 45.5)
        #expect(dto.categorizedItems?.count == 1)
        #expect(dto.actionItems?.count == 1)
        #expect(dto.acknowledgments?.count == 1)
    }

    @Test func shiftNoteDTOMinimalDecoding() throws {
        let json = """
        {"id": "note1"}
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(ShiftNoteDTO.self, from: json)
        #expect(dto.id == "note1")
        #expect(dto.authorId == nil)
        #expect(dto.shiftType == nil)
    }

    // MARK: - DTO to Model Conversion Tests

    @Test func shiftNoteDTOToModel() {
        let api = APIService.shared
        let dto = ShiftNoteDTO(
            id: "note1",
            authorId: "u1",
            authorName: "John",
            authorInitials: "JD",
            locationId: "loc1",
            shiftType: "Opening",
            shiftTemplateId: nil,
            rawTranscript: "Test transcript",
            audioUrl: nil,
            audioDuration: 30.0,
            summary: "Summary",
            categorizedItems: nil,
            actionItems: nil,
            photoUrls: nil,
            acknowledgments: nil,
            voiceReplies: nil,
            createdAt: "2026-02-01T12:00:00Z",
            isSynced: true
        )

        let model = api.decodeShiftNote(dto)
        #expect(model.id == "note1")
        #expect(model.authorId == "u1")
        #expect(model.shiftType == .opening)
        #expect(model.audioDuration == 30.0)
        #expect(model.categorizedItems.isEmpty)
        #expect(model.isSynced == true)
    }

    @Test func organizationDTOToModel() {
        let api = APIService.shared
        let dto = OrganizationDTO(id: "org1", name: "Test Cafe", ownerId: "u1", plan: "Professional", industryType: "Café")

        let model = api.decodeOrganization(dto)
        #expect(model.id == "org1")
        #expect(model.name == "Test Cafe")
        #expect(model.plan == .professional)
        #expect(model.industryType == .cafe)
    }

    @Test func organizationDTOWithUnknownValues() {
        let api = APIService.shared
        let dto = OrganizationDTO(id: "org1", name: "Test", ownerId: "u1", plan: "UnknownPlan", industryType: "UnknownType")

        let model = api.decodeOrganization(dto)
        #expect(model.plan == .free)
        #expect(model.industryType == .restaurant)
    }

    @Test func locationDTOToModel() {
        let api = APIService.shared
        let dto = LocationDTO(id: "loc1", name: "Downtown", address: "123 Main St", timezone: "America/Chicago", openingTime: "07:00", midTime: "13:00", closingTime: "21:00", managerIds: ["u1"])

        let model = api.decodeLocation(dto)
        #expect(model.id == "loc1")
        #expect(model.timezone == "America/Chicago")
        #expect(model.managerIds == ["u1"])
    }

    @Test func locationDTOWithNilDefaults() {
        let api = APIService.shared
        let dto = LocationDTO(id: "loc1", name: "Test", address: nil, timezone: nil, openingTime: nil, midTime: nil, closingTime: nil, managerIds: nil)

        let model = api.decodeLocation(dto)
        #expect(model.address == "")
        #expect(model.timezone == "America/New_York")
        #expect(model.openingTime == "06:00")
        #expect(model.managerIds.isEmpty)
    }

    @Test func teamMemberDTOToModel() {
        let api = APIService.shared
        let dto = TeamMemberDTO(id: "m1", name: "Jane Smith", email: "jane@test.com", role: "General Manager", roleTemplateId: "role_gm", locationIds: ["loc1"], inviteStatus: "Accepted", avatarInitials: "JS")

        let model = api.decodeTeamMember(dto)
        #expect(model.role == .generalManager)
        #expect(model.inviteStatus == .accepted)
        #expect(model.avatarInitials == "JS")
    }

    // MARK: - Action Item Update Response Tests

    @Test func actionItemUpdateResponseDecoding() throws {
        let json = """
        {"success": true, "noteId": "note1", "actionItemId": "ai1", "status": "In Progress"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ActionItemUpdateResponse.self, from: json)
        #expect(response.success == true)
        #expect(response.status == "In Progress")
    }

    @Test func noteUpdateResponseDecoding() throws {
        let json = """
        {"success": true, "noteId": "note1"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(NoteUpdateResponse.self, from: json)
        #expect(response.success == true)
        #expect(response.noteId == "note1")
    }

    // MARK: - SimpleResponse Tests

    @Test func simpleResponseSuccess() throws {
        let json = """
        {"success": true}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SimpleResponse.self, from: json)
        #expect(response.success == true)
        #expect(response.error == nil)
    }

    @Test func simpleResponseError() throws {
        let json = """
        {"success": false, "error": "Rate limit exceeded. Try again later."}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SimpleResponse.self, from: json)
        #expect(response.success == false)
        #expect(response.error?.contains("Rate limit") == true)
    }

    // MARK: - SyncPushResponse Tests

    @Test func syncPushResponseDecoding() throws {
        let json = """
        {"success": true, "updatedAt": "2026-02-01T12:00:00Z"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncPushResponse.self, from: json)
        #expect(response.success == true)
        #expect(response.updatedAt != nil)
    }

    // MARK: - RecurringIssueDTO Tests

    @Test func recurringIssueDTOToModel() {
        let api = APIService.shared
        let dto = RecurringIssueDTO(
            id: "ri1",
            description: "Fryer keeps breaking",
            category: "Equipment",
            categoryTemplateId: "cat_equip",
            locationId: "loc1",
            locationName: "Downtown",
            mentionCount: 5,
            relatedNoteIds: ["n1", "n2"],
            firstMentioned: "2026-01-15T10:00:00Z",
            lastMentioned: "2026-02-01T10:00:00Z",
            status: "Active"
        )

        let model = api.decodeRecurringIssue(dto)
        #expect(model.description == "Fryer keeps breaking")
        #expect(model.category == .equipment)
        #expect(model.mentionCount == 5)
        #expect(model.status == .active)
    }

    // MARK: - Edge Case Tests

    @Test func emptyArraysInSyncData() throws {
        let json = """
        {
            "hasData": true,
            "data": {
                "userId": "u1",
                "organization": {"id": "org1", "name": "Test", "ownerId": "u1"},
                "locations": [],
                "teamMembers": [],
                "shiftNotes": [],
                "recurringIssues": [],
                "selectedLocationId": null,
                "updatedAt": "2026-02-01T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SyncPullResponse.self, from: json)
        #expect(response.hasData == true)
        #expect(response.data?.locations?.isEmpty == true)
        #expect(response.data?.shiftNotes?.isEmpty == true)
    }

    @Test func nullFieldsInDTOsHandledGracefully() {
        let api = APIService.shared

        let dto = ShiftNoteDTO(
            id: "note1",
            authorId: nil,
            authorName: nil,
            authorInitials: nil,
            locationId: nil,
            shiftType: nil,
            shiftTemplateId: nil,
            rawTranscript: nil,
            audioUrl: nil,
            audioDuration: nil,
            summary: nil,
            categorizedItems: nil,
            actionItems: nil,
            photoUrls: nil,
            acknowledgments: nil,
            voiceReplies: nil,
            createdAt: nil,
            isSynced: nil
        )

        let model = api.decodeShiftNote(dto)
        #expect(model.id == "note1")
        #expect(model.authorId == "")
        #expect(model.shiftType == .closing)
        #expect(model.rawTranscript == "")
        #expect(model.categorizedItems.isEmpty)
        #expect(model.isSynced == true)
    }
}
