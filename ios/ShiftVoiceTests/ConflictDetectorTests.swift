import Foundation
import Testing
@testable import ShiftVoice

struct ConflictDetectorTests {
    @Test @MainActor func detectsConflictWhenTrackedFieldUpdatedOnServerWithPendingEdit() {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: "ConflictDetectorDetects"))
        store.configure(userId: "user-1")
        let detector = ConflictDetector(conflictStore: store)

        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let pendingEdit = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m1",
            intendedFields: ["status": "Resolved", "assigneeId": "u1", "priority": "FYI"]
        )

        let serverNote = makeNote(
            id: "note-1",
            status: .open,
            assigneeId: "u1",
            urgency: .fyi,
            updatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 120)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: serverNote,
            localPendingEdit: pendingEdit,
            editBaseline: baseline,
            isFromCache: false
        )

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.fieldName == "status")
    }

    @Test @MainActor func doesNotDetectConflictWithoutPendingEdit() {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: "ConflictDetectorNoPending"))
        store.configure(userId: "user-2")
        let detector = ConflictDetector(conflictStore: store)

        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let serverNote = makeNote(
            id: "note-1",
            status: .resolved,
            assigneeId: "u1",
            urgency: .fyi,
            updatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 120)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: serverNote,
            localPendingEdit: nil,
            editBaseline: baseline,
            isFromCache: false
        )

        #expect(conflicts.isEmpty)
    }

    @Test @MainActor func doesNotDetectConflictWhenValueMatchesLocalIntent() {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: "ConflictDetectorSameValue"))
        store.configure(userId: "user-3")
        let detector = ConflictDetector(conflictStore: store)

        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pendingEdit = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m2",
            intendedFields: ["status": "Resolved", "assigneeId": "u1", "priority": "FYI"]
        )

        let serverNote = makeNote(
            id: "note-1",
            status: .resolved,
            assigneeId: "u1",
            urgency: .fyi,
            updatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 120)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: serverNote,
            localPendingEdit: pendingEdit,
            editBaseline: baseline,
            isFromCache: false
        )

        #expect(conflicts.isEmpty)
    }

    @Test @MainActor func doesNotDetectConflictForCacheSnapshot() {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: "ConflictDetectorCache"))
        store.configure(userId: "user-4")
        let detector = ConflictDetector(conflictStore: store)

        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pendingEdit = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m3",
            intendedFields: ["status": "Resolved", "assigneeId": "u2", "priority": "Immediate"]
        )

        let serverNote = makeNote(
            id: "note-1",
            status: .open,
            assigneeId: "u9",
            urgency: .immediate,
            updatedAtServer: Date(timeIntervalSince1970: 180),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 170),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 180)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: serverNote,
            localPendingEdit: pendingEdit,
            editBaseline: baseline,
            isFromCache: true
        )

        #expect(conflicts.isEmpty)
    }

    @Test @MainActor func detectsMultipleTrackedFieldConflicts() {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: "ConflictDetectorMultiple"))
        store.configure(userId: "user-5")
        let detector = ConflictDetector(conflictStore: store)

        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pendingEdit = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m4",
            intendedFields: ["status": "Resolved", "assigneeId": "u2", "priority": "Immediate"]
        )

        let serverNote = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u9",
            urgency: .thisWeek,
            updatedAtServer: Date(timeIntervalSince1970: 180),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 175),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 176)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: serverNote,
            localPendingEdit: pendingEdit,
            editBaseline: baseline,
            isFromCache: false
        )

        #expect(conflicts.count == 3)
        #expect(Set(conflicts.map(\.fieldName)) == Set(["status", "assigneeId", "priority"]))
    }

    @MainActor
    private func testDirectory(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShiftVoiceTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeNote(
        id: String,
        status: ActionItemStatus,
        assigneeId: String?,
        urgency: UrgencyLevel,
        updatedAtServer: Date,
        statusUpdatedAtServer: Date,
        assigneeUpdatedAtServer: Date
    ) -> ShiftNote {
        let actionItem = ActionItem(
            id: "action-1",
            task: "task",
            category: .general,
            urgency: urgency,
            status: status,
            assignee: nil,
            assigneeId: assigneeId,
            updatedAt: updatedAtServer,
            statusUpdatedAt: statusUpdatedAtServer,
            statusUpdatedAtServer: statusUpdatedAtServer,
            statusUpdatedByUserId: "server-user",
            assigneeUpdatedAt: assigneeUpdatedAtServer,
            assigneeUpdatedAtServer: assigneeUpdatedAtServer,
            assigneeUpdatedByUserId: "server-user"
        )

        return ShiftNote(
            id: id,
            authorId: "author",
            authorName: "Author",
            authorInitials: "AU",
            locationId: "loc",
            shiftType: .opening,
            rawTranscript: "raw",
            summary: "summary",
            actionItems: [actionItem],
            updatedAt: updatedAtServer,
            updatedAtServer: updatedAtServer,
            updatedByUserId: "server-user"
        )
    }
}
