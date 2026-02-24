import Testing
@testable import ShiftVoice

struct DataSyncTests {

    // MARK: - Per-Field Merge: Action Item Status

    @Test func perFieldMergeStatusNewerServerWins() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .open, updatedAt: older, statusUpdatedAt: older)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .resolved, updatedAt: newer, statusUpdatedAt: newer)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.status == .resolved)
        #expect(merged.hasConflict == false)
    }

    @Test func perFieldMergeStatusNewerLocalWins() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .inProgress, updatedAt: newer, statusUpdatedAt: newer)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .resolved, updatedAt: older, statusUpdatedAt: older)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.status == .inProgress)
        #expect(merged.hasConflict == false)
    }

    @Test func perFieldMergeSameTimestampDifferentStatusFlagsConflict() {
        let vm = AppViewModel()
        let sameTime = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .inProgress, updatedAt: sameTime, statusUpdatedAt: sameTime)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .resolved, updatedAt: sameTime, statusUpdatedAt: sameTime)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.hasConflict == true)
        #expect(merged.conflictDescription != nil)
        #expect(merged.conflictDescription!.contains("Status"))
    }

    // MARK: - Per-Field Merge: Assignee

    @Test func perFieldMergeAssigneeNewerServerWins() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "Alice", updatedAt: older, assigneeUpdatedAt: older)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "Bob", updatedAt: newer, assigneeUpdatedAt: newer)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.assignee == "Bob")
        #expect(merged.hasConflict == false)
    }

    @Test func perFieldMergeAssigneeNewerLocalWins() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "Alice", updatedAt: newer, assigneeUpdatedAt: newer)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, assignee: "Bob", updatedAt: older, assigneeUpdatedAt: older)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.assignee == "Alice")
        #expect(merged.hasConflict == false)
    }

    // MARK: - Per-Field Merge: Independent Fields

    @Test func perFieldMergeIndependentFieldsMergeSeparately() {
        let vm = AppViewModel()
        let t1 = Date().addingTimeInterval(-120)
        let t2 = Date().addingTimeInterval(-60)
        let t3 = Date()

        let local = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .inProgress, assignee: "Alice", updatedAt: t2, statusUpdatedAt: t3, assigneeUpdatedAt: t1)
        let server = ActionItem(id: "a1", task: "Fix fryer", category: .equipment, urgency: .immediate, status: .open, assignee: "Bob", updatedAt: t2, statusUpdatedAt: t1, assigneeUpdatedAt: t3)

        let merged = vm.mergeActionItemPerField(local: local, server: server)
        #expect(merged.status == .inProgress)
        #expect(merged.assignee == "Bob")
        #expect(merged.hasConflict == false)
    }

    // MARK: - Note-Level Merge with Conflict Detection

    @Test func mergeNotePreservesNewerLocal() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let localNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "updated summary",
            actionItems: [ActionItem(id: "a1", task: "Fix it", category: .equipment, urgency: .immediate, status: .inProgress, updatedAt: newer, statusUpdatedAt: newer)],
            createdAt: older, updatedAt: newer, isDirty: true
        )
        let serverNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "old summary",
            actionItems: [ActionItem(id: "a1", task: "Fix it", category: .equipment, urgency: .immediate, status: .open, updatedAt: older, statusUpdatedAt: older)],
            createdAt: older, updatedAt: older
        )

        let merged = vm.mergeNoteWithConflictDetection(local: localNote, server: serverNote)
        #expect(merged.summary == "updated summary")
        #expect(merged.actionItems.first?.status == .inProgress)
    }

    @Test func mergeNoteCombinesAcknowledgments() {
        let vm = AppViewModel()
        let now = Date()

        let ack1 = Acknowledgment(id: "ack1", userId: "u1", userName: "Alice", timestamp: now.addingTimeInterval(-60))
        let ack2 = Acknowledgment(id: "ack2", userId: "u2", userName: "Bob", timestamp: now)

        let localNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            acknowledgments: [ack1], createdAt: now, updatedAt: now
        )
        let serverNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            acknowledgments: [ack2], createdAt: now, updatedAt: now
        )

        let merged = vm.mergeNoteWithConflictDetection(local: localNote, server: serverNote)
        #expect(merged.acknowledgments.count == 2)
    }

    @Test func mergeNoteCombinesNewActionItems() {
        let vm = AppViewModel()
        let now = Date()

        let localNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            actionItems: [ActionItem(id: "a1", task: "Task A", category: .equipment, urgency: .immediate)],
            createdAt: now, updatedAt: now
        )
        let serverNote = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            actionItems: [ActionItem(id: "a2", task: "Task B", category: .maintenance, urgency: .nextShift)],
            createdAt: now, updatedAt: now
        )

        let merged = vm.mergeNoteWithConflictDetection(local: localNote, server: serverNote)
        #expect(merged.actionItems.count == 2)
    }

    // MARK: - Timestamp-Based Team Member Merge

    @Test func teamMemberMergeNewerServerWins() {
        let vm = AppViewModel()
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let localMember = TeamMember(id: "m1", name: "Old Name", email: "a@test.com", role: .manager, updatedAt: older)
        let serverMember = TeamMember(id: "m1", name: "New Name", email: "a@test.com", role: .generalManager, updatedAt: newer)

        #expect(serverMember.updatedAt >= localMember.updatedAt)
        #expect(serverMember.name == "New Name")
    }

    @Test func teamMemberMergeNewerLocalPreserved() {
        let older = Date().addingTimeInterval(-60)
        let newer = Date()

        let localMember = TeamMember(id: "m1", name: "Updated Name", email: "a@test.com", role: .manager, updatedAt: newer)
        let serverMember = TeamMember(id: "m1", name: "Old Name", email: "a@test.com", role: .generalManager, updatedAt: older)

        #expect(localMember.updatedAt > serverMember.updatedAt)
        #expect(localMember.name == "Updated Name")
    }

    // MARK: - Dirty Flag Tracking

    @Test func shiftNoteDefaultsToNotDirty() {
        let note = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum"
        )
        #expect(note.isDirty == false)
    }

    @Test func shiftNoteCanBeMarkedDirty() {
        var note = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum"
        )
        note.isDirty = true
        note.updatedAt = Date()
        #expect(note.isDirty == true)
    }

    // MARK: - Action Item Timestamps

    @Test func actionItemStatusUpdateSetsTimestamp() {
        let initial = Date().addingTimeInterval(-60)
        var item = ActionItem(id: "a1", task: "Fix it", category: .equipment, urgency: .immediate, updatedAt: initial, statusUpdatedAt: initial)

        let updateTime = Date()
        item.status = .inProgress
        item.statusUpdatedAt = updateTime
        item.updatedAt = updateTime

        #expect(item.statusUpdatedAt > initial)
        #expect(item.updatedAt > initial)
    }

    @Test func actionItemAssigneeUpdateSetsTimestamp() {
        let initial = Date().addingTimeInterval(-60)
        var item = ActionItem(id: "a1", task: "Fix it", category: .equipment, urgency: .immediate, updatedAt: initial, assigneeUpdatedAt: initial)

        let updateTime = Date()
        item.assignee = "Bob"
        item.assigneeUpdatedAt = updateTime
        item.updatedAt = updateTime

        #expect(item.assigneeUpdatedAt > initial)
    }

    // MARK: - Conflict Dismissal

    @Test func conflictCanBeDismissed() {
        var item = ActionItem(id: "a1", task: "Fix it", category: .equipment, urgency: .immediate, hasConflict: true, conflictDescription: "Status conflict")
        #expect(item.hasConflict == true)
        #expect(item.conflictDescription != nil)

        item.hasConflict = false
        item.conflictDescription = nil
        #expect(item.hasConflict == false)
        #expect(item.conflictDescription == nil)
    }

    // MARK: - Pending Action Queue

    @Test func pendingActionPersistenceRoundTrip() {
        let persistence = PersistenceService.shared
        let testUserId = "test_sync_\(UUID().uuidString)"

        let actions = [
            PendingAction(type: .syncNotes, payload: "note_001"),
            PendingAction(type: .updateActionItemStatus, payload: "note_001|action_001|Resolved"),
            PendingAction(type: .acknowledgeNote, payload: "note_002|user_001|John Doe")
        ]

        persistence.savePendingActions(actions, for: testUserId)
        let loaded = persistence.loadPendingActions(for: testUserId)

        #expect(loaded.count == 3)
        #expect(loaded[0].type == .syncNotes)
        #expect(loaded[0].payload == "note_001")
        #expect(loaded[1].type == .updateActionItemStatus)
        #expect(loaded[1].payload == "note_001|action_001|Resolved")
        #expect(loaded[2].type == .acknowledgeNote)

        persistence.clearPendingActions(for: testUserId)
        let cleared = persistence.loadPendingActions(for: testUserId)
        #expect(cleared.isEmpty)

        persistence.clearUserData(for: testUserId)
    }

    @Test func pendingActionRetryCountIncrements() {
        let action = PendingAction(type: .syncNotes, payload: "note_001")
        #expect(action.retryCount == 0)

        let retried = action.withIncrementedRetry()
        #expect(retried.retryCount == 1)
        #expect(retried.id == action.id)
        #expect(retried.type == action.type)

        let retriedAgain = retried.withIncrementedRetry()
        #expect(retriedAgain.retryCount == 2)
    }

    @Test func pendingActionEmptyQueueLoadsEmpty() {
        let persistence = PersistenceService.shared
        let testUserId = "test_empty_queue_\(UUID().uuidString)"
        let loaded = persistence.loadPendingActions(for: testUserId)
        #expect(loaded.isEmpty)
    }

    // MARK: - Snapshot Persistence

    @Test func snapshotSaveAndLoadRoundTrip() {
        let persistence = PersistenceService.shared
        let testUserId = "test_snapshot_\(UUID().uuidString)"

        let org = Organization(name: "Test Org", ownerId: testUserId)
        let location = Location(name: "Test Location", address: "123 Main St")
        let note = ShiftNote(
            id: "sn1", authorId: testUserId, authorName: "Test", authorInitials: "T",
            locationId: location.id, shiftType: .closing, rawTranscript: "test", summary: "sum"
        )

        let appData = AppData(
            organization: org,
            locations: [location],
            teamMembers: [],
            shiftNotes: [note],
            recurringIssues: [],
            selectedLocationId: location.id
        )

        persistence.saveSnapshot(appData, for: testUserId)
        let loaded = persistence.loadSnapshot(for: testUserId)

        #expect(loaded != nil)
        #expect(loaded?.shiftNotes.count == 1)
        #expect(loaded?.shiftNotes.first?.id == "sn1")
        #expect(loaded?.organization.name == "Test Org")

        persistence.clearSnapshot(for: testUserId)
        let cleared = persistence.loadSnapshot(for: testUserId)
        #expect(cleared == nil)

        persistence.clearUserData(for: testUserId)
    }

    // MARK: - Updated At Defaults

    @Test func shiftNoteUpdatedAtDefaultsToCreatedAt() {
        let created = Date().addingTimeInterval(-3600)
        let note = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            createdAt: created
        )
        #expect(note.updatedAt == created)
    }

    @Test func shiftNoteUpdatedAtCanBeExplicit() {
        let created = Date().addingTimeInterval(-3600)
        let updated = Date()
        let note = ShiftNote(
            id: "n1", authorId: "u1", authorName: "Test", authorInitials: "T",
            locationId: "l1", shiftType: .closing, rawTranscript: "test", summary: "sum",
            createdAt: created, updatedAt: updated
        )
        #expect(note.updatedAt == updated)
        #expect(note.updatedAt > note.createdAt)
    }

    @Test func actionItemPerFieldTimestampsDefault() {
        let item = ActionItem(id: "a1", task: "Test", category: .general, urgency: .fyi)
        #expect(item.statusUpdatedAt == item.updatedAt)
        #expect(item.assigneeUpdatedAt == item.updatedAt)
    }

    @Test func teamMemberUpdatedAtDefault() {
        let before = Date()
        let member = TeamMember(id: "m1", name: "Test", email: "t@t.com", role: .manager)
        #expect(member.updatedAt >= before)
    }

    // MARK: - Codable Backwards Compatibility

    @Test func shiftNoteDecodesWithoutNewFields() {
        let json = """
        {"id":"n1","authorId":"u1","authorName":"Test","authorInitials":"T","locationId":"l1","shiftType":"Closing","rawTranscript":"test","audioDuration":0,"summary":"sum","categorizedItems":[],"actionItems":[],"photoUrls":[],"acknowledgments":[],"voiceReplies":[],"createdAt":"2025-01-01T00:00:00Z","isSynced":true}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let note = try? decoder.decode(ShiftNote.self, from: Data(json.utf8))
        #expect(note != nil)
        #expect(note?.id == "n1")
        #expect(note?.isDirty == false)
    }

    @Test func actionItemDecodesWithoutNewFields() {
        let json = """
        {"id":"a1","task":"Test","category":"General","urgency":"FYI","status":"Open"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try? decoder.decode(ActionItem.self, from: Data(json.utf8))
        #expect(item != nil)
        #expect(item?.hasConflict == false)
    }

    @Test func teamMemberDecodesWithoutUpdatedAt() {
        let json = """
        {"id":"m1","name":"Test","email":"t@t.com","role":"Manager","locationIds":[],"inviteStatus":"Accepted","avatarInitials":"TE"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let member = try? decoder.decode(TeamMember.self, from: Data(json.utf8))
        #expect(member != nil)
        #expect(member?.name == "Test")
    }
}
