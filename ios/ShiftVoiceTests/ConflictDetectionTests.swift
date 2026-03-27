import Foundation
import Testing
@testable import ShiftVoice

@MainActor
struct ConflictDetectionTests {
    @Test func twoUsersEditSameStatusField_detectsConflict() {
        let context = makeContext(name: "SameStatus")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m1",
            intendedFields: ["status": "Resolved", "assigneeId": "u1", "priority": "FYI"]
        )
        let server = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let conflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)

        #expect(conflicts.count == 1)
        #expect(conflicts.first?.fieldName == "status")
    }

    @Test func twoUsersEditDifferentFields_onlyChangedFieldConflicted() {
        let context = makeContext(name: "DifferentFields")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m2",
            intendedFields: ["status": "Resolved", "assigneeId": "u1", "priority": "FYI"]
        )
        let server = makeNote(
            id: "note-1",
            status: .open,
            assigneeId: "u9",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 170),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 100),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 170)
        )

        let conflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)

        #expect(conflicts.isEmpty)
    }

    @Test func convergentEdit_sameServerValue_noConflict() {
        let context = makeContext(name: "Convergent")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(
            docId: "note-1",
            type: .upsert,
            mutationId: "m3",
            intendedFields: ["status": "Resolved", "assigneeId": "u1", "priority": "FYI"]
        )
        let server = makeNote(
            id: "note-1",
            status: .resolved,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let conflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)

        #expect(conflicts.isEmpty)
    }

    @Test func offlineEdit_thenReconnect_serverChanged_conflictOnServerSnapshot() {
        let context = makeContext(name: "OfflineReconnect")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m4", intendedFields: ["status": "Resolved"])
        let server = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 200),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 200),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let cacheConflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: true)
        let serverConflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)

        #expect(cacheConflicts.isEmpty)
        #expect(serverConflicts.count == 1)
        #expect(serverConflicts.first?.fieldName == "status")
    }

    @Test func userEditsNonTrackedField_noConflict() {
        let context = makeContext(name: "NonTracked")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m5", intendedFields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"])
        let server = makeNote(
            id: "note-1",
            status: .open,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 200),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 100),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100),
            summary: "Server-only summary change"
        )

        let conflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)

        #expect(conflicts.isEmpty)
    }

    @Test func serverSnapshotFromCache_noConflictEvaluation() {
        let context = makeContext(name: "CacheSnapshot")
        let baseline = EditBaseline(
            noteId: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m6", intendedFields: ["status": "Resolved"])
        let server = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 150),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 150),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let conflicts = context.detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: true)

        #expect(conflicts.isEmpty)
    }

    @Test @MainActor func multipleSequentialEdits_onlyLatestBaselineUsed() {
        let directory = testDirectory(name: "LatestBaseline")
        let baselineStore = EditBaselineStore(baseDirectoryURL: directory)
        baselineStore.configure(userId: "user-1")

        baselineStore.setBaseline(
            for: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            serverTimestamp: Date(timeIntervalSince1970: 100)
        )
        baselineStore.setBaseline(
            for: "note-1",
            fields: ["status": "In Progress", "assigneeId": "u1", "priority": "FYI"],
            serverTimestamp: Date(timeIntervalSince1970: 180)
        )

        let context = makeContext(name: "LatestBaselineDetector")
        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m7", intendedFields: ["status": "Resolved"])
        let server = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 170),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 170),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 120)
        )

        let conflicts = context.detector.evaluateSnapshot(
            serverNote: server,
            localPendingEdit: pending,
            editBaseline: baselineStore.getBaseline(for: "note-1"),
            isFromCache: false
        )

        #expect(conflicts.isEmpty)
    }

    @Test @MainActor func baselineClearedAfterSuccessfulNonConflictingSync() {
        let directory = testDirectory(name: "ClearBaselineAfterSync")
        let baselineStore = EditBaselineStore(baseDirectoryURL: directory)
        baselineStore.configure(userId: "user-2")

        baselineStore.setBaseline(
            for: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            serverTimestamp: Date(timeIntervalSince1970: 100)
        )

        let context = makeContext(name: "ClearBaselineDetector")
        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m8", intendedFields: ["status": "Resolved"])
        let server = makeNote(
            id: "note-1",
            status: .resolved,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 170),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 170),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 120)
        )

        let conflicts = context.detector.evaluateSnapshot(
            serverNote: server,
            localPendingEdit: pending,
            editBaseline: baselineStore.getBaseline(for: "note-1"),
            isFromCache: false
        )
        #expect(conflicts.isEmpty)

        baselineStore.clearBaseline(for: "note-1")
        #expect(baselineStore.getBaseline(for: "note-1") == nil)
    }

    private func makeContext(name: String) -> (store: ConflictStore, detector: ConflictDetector) {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: name))
        store.configure(userId: "test-user")
        return (store: store, detector: ConflictDetector(conflictStore: store))
    }

    private func makeNote(
        id: String,
        status: ActionItemStatus,
        assigneeId: String?,
        urgency: UrgencyLevel,
        noteUpdatedAtServer: Date,
        statusUpdatedAtServer: Date,
        assigneeUpdatedAtServer: Date,
        summary: String = "summary"
    ) -> ShiftNote {
        let actionItem = ActionItem(
            id: "action-1",
            task: "task",
            category: .general,
            urgency: urgency,
            status: status,
            assignee: nil,
            assigneeId: assigneeId,
            updatedAt: noteUpdatedAtServer,
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
            summary: summary,
            actionItems: [actionItem],
            updatedAt: noteUpdatedAtServer,
            updatedAtServer: noteUpdatedAtServer,
            updatedByUserId: "server-user"
        )
    }

    private func testDirectory(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShiftVoiceTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
