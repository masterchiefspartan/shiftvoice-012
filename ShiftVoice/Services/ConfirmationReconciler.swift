import Foundation

@MainActor
final class ConfirmationReconciler: PendingOpReconciling {
    private let pendingOpsStore: PendingOpsStoreProtocol
    private let documentFetcher: PendingOpsDocumentFetching
    private let syncEventLogger: SyncEventLogger

    init(
        pendingOpsStore: PendingOpsStoreProtocol,
        documentFetcher: PendingOpsDocumentFetching,
        syncEventLogger: SyncEventLogger = .shared
    ) {
        self.pendingOpsStore = pendingOpsStore
        self.documentFetcher = documentFetcher
        self.syncEventLogger = syncEventLogger
    }

    func reconcile(orgId: String) async -> PendingOpReconcileResult {
        let startedAt = Date()
        let operations = pendingOpsStore.all()
        syncEventLogger.reconciliationStarted(pendingCount: operations.count)
        guard !operations.isEmpty else {
            return PendingOpReconcileResult(
                remainingOps: [],
                clearedDocIds: [],
                mismatchDocIds: [],
                mismatches: [],
                encounteredError: nil
            )
        }

        var clearedDocIds: Set<String> = []
        var mismatchDocIds: Set<String> = []
        var mismatches: [PendingOpReconcileMismatch] = []

        for chunk in operations.chunked(into: 25) {
            for operation in chunk {
                pendingOpsStore.markAttempt(docId: operation.docId, at: Date())

                do {
                    let serverState = try await documentFetcher.fetchShiftNoteServerState(noteId: operation.docId, orgId: orgId)

                    switch operation.type {
                    case .delete:
                        if !serverState.exists {
                            pendingOpsStore.remove(docId: operation.docId)
                            clearedDocIds.insert(operation.docId)
                            syncEventLogger.pendingOpConfirmed(
                                docId: operation.docId,
                                type: operation.type,
                                durationSeconds: Date().timeIntervalSince(operation.createdAtClient)
                            )
                        } else {
                            mismatchDocIds.insert(operation.docId)
                            mismatches.append(
                                PendingOpReconcileMismatch(
                                    docId: operation.docId,
                                    expectedMutationId: operation.mutationId,
                                    serverMutationId: serverState.lastClientMutationId
                                )
                            )
                        }
                    case .upsert:
                        if serverState.exists && serverState.lastClientMutationId == operation.mutationId {
                            pendingOpsStore.remove(docId: operation.docId)
                            clearedDocIds.insert(operation.docId)
                            syncEventLogger.pendingOpConfirmed(
                                docId: operation.docId,
                                type: operation.type,
                                durationSeconds: Date().timeIntervalSince(operation.createdAtClient)
                            )
                        } else {
                            mismatchDocIds.insert(operation.docId)
                            mismatches.append(
                                PendingOpReconcileMismatch(
                                    docId: operation.docId,
                                    expectedMutationId: operation.mutationId,
                                    serverMutationId: serverState.lastClientMutationId
                                )
                            )
                        }
                    }
                } catch {
                    let syncError = SyncError(error: error)
                    syncEventLogger.pendingOpFailed(
                        docId: operation.docId,
                        type: operation.type,
                        error: (error as NSError).localizedDescription
                    )
                    syncEventLogger.reconciliationCompleted(
                        confirmedCount: clearedDocIds.count,
                        remainingCount: pendingOpsStore.all().count,
                        durationSeconds: Date().timeIntervalSince(startedAt)
                    )
                    return PendingOpReconcileResult(
                        remainingOps: pendingOpsStore.all(),
                        clearedDocIds: clearedDocIds,
                        mismatchDocIds: mismatchDocIds,
                        mismatches: mismatches,
                        encounteredError: syncError
                    )
                }
            }
        }

        let remainingOps = pendingOpsStore.all()
        syncEventLogger.reconciliationCompleted(
            confirmedCount: clearedDocIds.count,
            remainingCount: remainingOps.count,
            durationSeconds: Date().timeIntervalSince(startedAt)
        )

        return PendingOpReconcileResult(
            remainingOps: remainingOps,
            clearedDocIds: clearedDocIds,
            mismatchDocIds: mismatchDocIds,
            mismatches: mismatches,
            encounteredError: nil
        )
    }
}

nonisolated private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<next]))
            index = next
        }
        return chunks
    }
}
