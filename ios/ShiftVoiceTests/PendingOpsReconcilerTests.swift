import Foundation
import Testing
@testable import ShiftVoice

@MainActor
struct PendingOpsReconcilerTests {
    @Test func offlineDeleteClearsAfterServerAbsenceEvenWithoutListPresence() async {
        let store = TestPendingOpsStore()
        let op = PendingOp(docId: "note-delete", type: .delete, mutationId: "m-del")
        store.upsert(op)

        let fetcher = TestPendingOpsFetcher(states: [
            "note-delete": .success(
                ShiftNoteServerState(
                    noteId: "note-delete",
                    exists: false,
                    note: nil,
                    lastClientMutationId: nil
                )
            )
        ])
        let reconciler = ConfirmationReconciler(pendingOpsStore: store, documentFetcher: fetcher)

        let result = await reconciler.reconcile(orgId: "org")

        #expect(result.encounteredError == nil)
        #expect(result.clearedDocIds.contains("note-delete"))
        #expect(result.remainingOps.isEmpty)
    }

    @Test func upsertClearsWhenServerMutationMatchesOutsideWindow() async {
        let store = TestPendingOpsStore()
        let op = PendingOp(docId: "note-upsert", type: .upsert, mutationId: "m-up")
        store.upsert(op)

        let serverNote = ShiftNote(
            id: "note-upsert",
            authorId: "u1",
            authorName: "User",
            authorInitials: "U",
            locationId: "loc",
            shiftType: .closing,
            rawTranscript: "r",
            summary: "s"
        )

        let fetcher = TestPendingOpsFetcher(states: [
            "note-upsert": .success(
                ShiftNoteServerState(
                    noteId: "note-upsert",
                    exists: true,
                    note: serverNote,
                    lastClientMutationId: "m-up"
                )
            )
        ])

        let reconciler = ConfirmationReconciler(pendingOpsStore: store, documentFetcher: fetcher)
        let result = await reconciler.reconcile(orgId: "org")

        #expect(result.encounteredError == nil)
        #expect(result.clearedDocIds.contains("note-upsert"))
        #expect(result.remainingOps.isEmpty)
    }

    @Test func upsertRemainsPendingWhenMutationMismatch() async {
        let store = TestPendingOpsStore()
        let op = PendingOp(docId: "note-mismatch", type: .upsert, mutationId: "local-m")
        store.upsert(op)

        let serverNote = ShiftNote(
            id: "note-mismatch",
            authorId: "u1",
            authorName: "User",
            authorInitials: "U",
            locationId: "loc",
            shiftType: .closing,
            rawTranscript: "r",
            summary: "s"
        )

        let fetcher = TestPendingOpsFetcher(states: [
            "note-mismatch": .success(
                ShiftNoteServerState(
                    noteId: "note-mismatch",
                    exists: true,
                    note: serverNote,
                    lastClientMutationId: "remote-m"
                )
            )
        ])

        let reconciler = ConfirmationReconciler(pendingOpsStore: store, documentFetcher: fetcher)
        let result = await reconciler.reconcile(orgId: "org")

        #expect(result.encounteredError == nil)
        #expect(result.clearedDocIds.isEmpty)
        #expect(result.remainingOps.count == 1)
        #expect(result.remainingOps.first?.docId == "note-mismatch")
        #expect(result.mismatchDocIds.contains("note-mismatch"))

        let syncInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: nil,
            pendingNoteCount: result.remainingOps.count,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(syncInput) == .syncing)
        #expect(SyncStateReducer.canClaimAllChangesSynced(for: syncInput) == false)
    }

    @Test func permissionDeniedDuringSweepReturnsErrorAndKeepsPending() async {
        let store = TestPendingOpsStore()
        store.upsert(PendingOp(docId: "note-auth", type: .upsert, mutationId: "m-auth"))

        let fetcher = TestPendingOpsFetcher(states: [
            "note-auth": .failure(TestFetcherError.permissionDenied)
        ])

        let reconciler = ConfirmationReconciler(pendingOpsStore: store, documentFetcher: fetcher)
        let result = await reconciler.reconcile(orgId: "org")

        #expect(result.encounteredError == .permissionDenied)
        #expect(result.remainingOps.count == 1)

        let syncInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: result.encounteredError,
            pendingNoteCount: result.remainingOps.count,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(syncInput) == .error)
    }
}

@MainActor
private final class TestPendingOpsStore: PendingOpsStoreProtocol {
    private(set) var pendingOps: [String: PendingOp] = [:]

    func configure(userId: String) {}

    func clearCurrentUser() {
        pendingOps = [:]
    }

    func all() -> [PendingOp] {
        pendingOps.values.sorted { $0.createdAtClient < $1.createdAtClient }
    }

    func summary() -> PendingOpsSummary {
        let pendingDocIds = Set(pendingOps.keys)
        let pendingDeleteCount = pendingOps.values.filter { $0.type == .delete }.count
        return PendingOpsSummary(pendingDocIds: pendingDocIds, pendingDeleteCount: pendingDeleteCount)
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

nonisolated private enum TestFetcherError: Error {
    case permissionDenied

    var asNSError: NSError {
        switch self {
        case .permissionDenied:
            return NSError(domain: "test", code: 7, userInfo: nil)
        }
    }
}

@MainActor
private final class TestPendingOpsFetcher: PendingOpsDocumentFetching {
    private let states: [String: Result<ShiftNoteServerState, TestFetcherError>]

    init(states: [String: Result<ShiftNoteServerState, TestFetcherError>]) {
        self.states = states
    }

    func fetchShiftNoteServerState(noteId: String, orgId: String) async throws -> ShiftNoteServerState {
        if let state = states[noteId] {
            switch state {
            case .success(let response):
                return response
            case .failure(let error):
                throw error.asNSError
            }
        }
        return ShiftNoteServerState(noteId: noteId, exists: false, note: nil, lastClientMutationId: nil)
    }
}
