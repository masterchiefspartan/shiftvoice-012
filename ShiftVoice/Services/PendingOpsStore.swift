import Foundation

@MainActor
final class PendingOpsStore: PendingOpsStoreProtocol {
    private(set) var pendingOps: [String: PendingOp] = [:]

    private let persistence: PendingOpsPersisting
    private var currentUserId: String?

    init(persistence: PendingOpsPersisting) {
        self.persistence = persistence
    }

    func configure(userId: String) {
        currentUserId = userId
        pendingOps = persistence.loadPendingOpsSnapshot(for: userId)?.pendingOps ?? [:]
    }

    func clearCurrentUser() {
        if let currentUserId {
            persistence.clearPendingOpsSnapshot(for: currentUserId)
        }
        currentUserId = nil
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
        if operation.type == .delete {
            pendingOps[operation.docId] = operation
        } else {
            let existing = pendingOps[operation.docId]
            if existing?.type == .delete {
                pendingOps[operation.docId] = existing
            } else {
                pendingOps[operation.docId] = operation
            }
        }
        persist()
    }

    func remove(docId: String) {
        pendingOps.removeValue(forKey: docId)
        persist()
    }

    func markAttempt(docId: String, at date: Date) {
        guard var op = pendingOps[docId] else { return }
        op.attemptCount += 1
        op.lastAttemptAt = date
        pendingOps[docId] = op
        persist()
    }

    private func persist() {
        guard let currentUserId else { return }
        persistence.savePendingOpsSnapshot(PendingOpsSnapshot(pendingOps: pendingOps), for: currentUserId)
    }
}
