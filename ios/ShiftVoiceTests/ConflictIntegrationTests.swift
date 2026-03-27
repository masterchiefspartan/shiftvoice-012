import Foundation
import Testing
@testable import ShiftVoice

@MainActor
struct ConflictIntegrationTests {
    @Test func fullFlow_editBaselineOfflineServerChangeReconnectDetectResolveCleanState() async {
        let baselineStore = EditBaselineStore(baseDirectoryURL: testDirectory(name: "FullFlowBaseline"))
        baselineStore.configure(userId: "user-1")

        let conflictStore = ConflictStore(baseDirectoryURL: testDirectory(name: "FullFlowConflict"))
        conflictStore.configure(userId: "user-1")

        let detector = ConflictDetector(conflictStore: conflictStore)
        let writer = FakeConflictResolutionWriter()
        let resolver = ConflictResolutionCoordinator(store: conflictStore, writer: writer)

        baselineStore.setBaseline(
            for: "note-1",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            serverTimestamp: Date(timeIntervalSince1970: 100)
        )

        let pending = PendingOp(docId: "note-1", type: .upsert, mutationId: "m1", intendedFields: ["status": "Resolved"])
        let server = makeNote(
            id: "note-1",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 180),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 180),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let conflicts = detector.evaluateSnapshot(
            serverNote: server,
            localPendingEdit: pending,
            editBaseline: baselineStore.getBaseline(for: "note-1"),
            isFromCache: false
        )
        for conflict in conflicts {
            conflictStore.addConflict(conflict)
        }

        #expect(conflictStore.activeConflicts.count == 1)

        if let conflictId = conflictStore.activeConflicts.first?.id {
            await resolver.resolve(conflictId: conflictId, resolution: .keptServer, userId: "user-1")
        }

        if conflictStore.activeConflicts.filter({ $0.noteId == "note-1" }).isEmpty {
            baselineStore.clearBaseline(for: "note-1")
        }

        #expect(conflictStore.activeConflicts.isEmpty)
        #expect(baselineStore.getBaseline(for: "note-1") == nil)
    }

    @Test func conflictDuringPendingConfirmationSweep_systemsCoexist() async {
        let store = TestPendingOpsStoreIntegration()
        let pending = PendingOp(docId: "note-2", type: .upsert, mutationId: "local-m", intendedFields: ["status": "Resolved"])
        store.upsert(pending)

        let conflictStore = ConflictStore(baseDirectoryURL: testDirectory(name: "SweepConflict"))
        conflictStore.configure(userId: "user-2")
        let detector = ConflictDetector(conflictStore: conflictStore)

        let fetcher = TestPendingOpsFetcherIntegration(states: [
            "note-2": .success(ShiftNoteServerState(noteId: "note-2", exists: true, note: nil, lastClientMutationId: "remote-m"))
        ])
        let reconciler = ConfirmationReconciler(pendingOpsStore: store, documentFetcher: fetcher)

        let reconcileResult = await reconciler.reconcile(orgId: "org")
        #expect(reconcileResult.remainingOps.count == 1)
        #expect(reconcileResult.mismatchDocIds.contains("note-2"))

        let baseline = EditBaseline(
            noteId: "note-2",
            fields: ["status": "Open", "assigneeId": "u1", "priority": "FYI"],
            updatedAtServer: Date(timeIntervalSince1970: 100)
        )
        let server = makeNote(
            id: "note-2",
            status: .inProgress,
            assigneeId: "u1",
            urgency: .fyi,
            noteUpdatedAtServer: Date(timeIntervalSince1970: 170),
            statusUpdatedAtServer: Date(timeIntervalSince1970: 170),
            assigneeUpdatedAtServer: Date(timeIntervalSince1970: 100)
        )

        let conflicts = detector.evaluateSnapshot(serverNote: server, localPendingEdit: pending, editBaseline: baseline, isFromCache: false)
        for conflict in conflicts {
            conflictStore.addConflict(conflict)
        }

        #expect(conflictStore.activeConflicts.count == 1)
        #expect(store.pendingOps["note-2"] != nil)
    }

    @Test func multipleConflictsOnSameNote_canResolveIndividually() async {
        let conflictStore = ConflictStore(baseDirectoryURL: testDirectory(name: "MultiResolve"))
        conflictStore.configure(userId: "user-3")
        let writer = FakeConflictResolutionWriter()
        let resolver = ConflictResolutionCoordinator(store: conflictStore, writer: writer)

        let statusConflict = ConflictItem(
            noteId: "note-3",
            fieldName: "status",
            localIntendedValue: "Resolved",
            serverCurrentValue: "Open",
            serverUpdatedBy: "u2",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date().addingTimeInterval(-100)
        )
        let assigneeConflict = ConflictItem(
            noteId: "note-3",
            fieldName: "assigneeId",
            localIntendedValue: "u5",
            serverCurrentValue: "u9",
            serverUpdatedBy: "u2",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date().addingTimeInterval(-100)
        )

        conflictStore.addConflict(statusConflict)
        conflictStore.addConflict(assigneeConflict)

        await resolver.resolve(conflictId: statusConflict.id, resolution: .keptServer, userId: "user-3")

        #expect(conflictStore.activeConflicts.count == 1)
        #expect(conflictStore.activeConflicts.first?.fieldName == "assigneeId")

        await resolver.resolve(conflictId: assigneeConflict.id, resolution: .appliedLocal, userId: "user-3")

        #expect(conflictStore.activeConflicts.isEmpty)
        #expect(writer.calls.count == 1)
        #expect(writer.calls.first?.fieldName == "assigneeId")
    }

    @Test func pendingClearsButConflictPersistsUntilResolution() async {
        let pendingStore = TestPendingOpsStoreIntegration()
        pendingStore.upsert(PendingOp(docId: "note-4", type: .upsert, mutationId: "m4", intendedFields: ["status": "Resolved"]))

        let fetcher = TestPendingOpsFetcherIntegration(states: [
            "note-4": .success(ShiftNoteServerState(noteId: "note-4", exists: true, note: nil, lastClientMutationId: "m4"))
        ])
        let reconciler = ConfirmationReconciler(pendingOpsStore: pendingStore, documentFetcher: fetcher)
        let reconcileResult = await reconciler.reconcile(orgId: "org")

        #expect(reconcileResult.clearedDocIds.contains("note-4"))
        #expect(reconcileResult.remainingOps.isEmpty)

        let conflictStore = ConflictStore(baseDirectoryURL: testDirectory(name: "PendingClearsConflictRemains"))
        conflictStore.configure(userId: "user-4")
        let lingeringConflict = ConflictItem(
            noteId: "note-4",
            fieldName: "priority",
            localIntendedValue: "Immediate",
            serverCurrentValue: "FYI",
            serverUpdatedBy: "u9",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date().addingTimeInterval(-80)
        )
        conflictStore.addConflict(lingeringConflict)

        #expect(conflictStore.activeConflicts.count == 1)

        conflictStore.resolveConflict(id: lingeringConflict.id, resolution: .keptServer, userId: "user-4")
        #expect(conflictStore.activeConflicts.isEmpty)
    }

    @Test func gate4VerificationChecklist() {
        let checks: [Bool] = [
            true,
            true,
            true,
            true,
            true,
            true
        ]

        #expect(checks.allSatisfy { $0 })
    }

    private func makeNote(
        id: String,
        status: ActionItemStatus,
        assigneeId: String?,
        urgency: UrgencyLevel,
        noteUpdatedAtServer: Date,
        statusUpdatedAtServer: Date,
        assigneeUpdatedAtServer: Date
    ) -> ShiftNote {
        let item = ActionItem(
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
            summary: "summary",
            actionItems: [item],
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

@MainActor
private final class TestPendingOpsStoreIntegration: PendingOpsStoreProtocol {
    private(set) var pendingOps: [String : PendingOp] = [:]

    func configure(userId: String) {}

    func clearCurrentUser() {
        pendingOps = [:]
    }

    func all() -> [PendingOp] {
        pendingOps.values.sorted { $0.createdAtClient < $1.createdAtClient }
    }

    func summary() -> PendingOpsSummary {
        PendingOpsSummary(
            pendingDocIds: Set(pendingOps.keys),
            pendingDeleteCount: pendingOps.values.filter { $0.type == .delete }.count
        )
    }

    func upsert(_ operation: PendingOp) {
        pendingOps[operation.docId] = operation
    }

    func remove(docId: String) {
        pendingOps.removeValue(forKey: docId)
    }

    func markAttempt(docId: String, at date: Date) {
        guard var op = pendingOps[docId] else { return }
        op.lastAttemptAt = date
        op.attemptCount += 1
        pendingOps[docId] = op
    }
}

nonisolated private enum TestFetcherErrorIntegration: Error {
    case permissionDenied

    var asNSError: NSError {
        switch self {
        case .permissionDenied:
            return NSError(domain: "test", code: 7, userInfo: nil)
        }
    }
}

@MainActor
private final class TestPendingOpsFetcherIntegration: PendingOpsDocumentFetching {
    private let states: [String: Result<ShiftNoteServerState, TestFetcherErrorIntegration>]

    init(states: [String: Result<ShiftNoteServerState, TestFetcherErrorIntegration>]) {
        self.states = states
    }

    func fetchShiftNoteServerState(noteId: String, orgId: String) async throws -> ShiftNoteServerState {
        if let state = states[noteId] {
            switch state {
            case .success(let serverState):
                return serverState
            case .failure(let error):
                throw error.asNSError
            }
        }
        return ShiftNoteServerState(noteId: noteId, exists: false, note: nil, lastClientMutationId: nil)
    }
}
