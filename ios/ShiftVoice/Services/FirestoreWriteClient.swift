import Foundation
import FirebaseFirestore

protocol FirestoreWriteClient: AnyObject {
    func setData(_ data: [String: Any], to docRef: DocumentReference, merge: Bool) async throws
    func updateData(_ data: [String: Any], in docRef: DocumentReference) async throws
    func delete(_ docRef: DocumentReference) async throws
    func commitBatch(_ build: (WriteBatch) -> Void) async throws
    func runTransaction<T>(_ block: @escaping (Transaction) throws -> T) async throws -> T
}

@MainActor
final class DefaultFirestoreWriteClient: FirestoreWriteClient {
    private let db: Firestore
    private let failureStore: WriteFailureStore
    private let restartListenersHook: (() -> Void)?
    private let syncEventLogger: SyncEventLogger
    private var retryClosure: (() async -> Void)?

    init(
        db: Firestore = Firestore.firestore(),
        failureStore: WriteFailureStore,
        restartListenersHook: (() -> Void)? = nil,
        syncEventLogger: SyncEventLogger = .shared
    ) {
        self.db = db
        self.failureStore = failureStore
        self.restartListenersHook = restartListenersHook
        self.syncEventLogger = syncEventLogger
    }

    var triggerReauthFlag: Bool {
        failureStore.triggerReauthFlag
    }

    func restartListeners() {
        syncEventLogger.listenerRestarted(reason: "write_recovery")
        restartListenersHook?()
    }

    func retryLastSafeWrite() async {
        guard let retryClosure else { return }
        await retryClosure()
    }

    func setData(_ data: [String: Any], to docRef: DocumentReference, merge: Bool) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                docRef.setData(data, merge: merge) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            clearTransientFailureIfNeeded()
        } catch {
            handleWriteError(error, operation: .setData, documentPath: docRef.path, data: data)
            throw error
        }
    }

    func updateData(_ data: [String: Any], in docRef: DocumentReference) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                docRef.updateData(data) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            clearTransientFailureIfNeeded()
        } catch {
            handleWriteError(error, operation: .updateData, documentPath: docRef.path, data: data)
            throw error
        }
    }

    func delete(_ docRef: DocumentReference) async throws {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                docRef.delete { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            clearTransientFailureIfNeeded()
        } catch {
            handleWriteError(error, operation: .delete, documentPath: docRef.path, data: nil)
            throw error
        }
    }

    func commitBatch(_ build: (WriteBatch) -> Void) async throws {
        let batch = db.batch()
        build(batch)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                batch.commit { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            clearTransientFailureIfNeeded()
        } catch {
            handleWriteError(error, operation: .batch, documentPath: nil, data: nil)
            throw error
        }
    }

    func runTransaction<T>(_ block: @escaping (Transaction) throws -> T) async throws -> T {
        do {
            let result: T = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                db.runTransaction({ transaction, errorPointer in
                    do {
                        return try block(transaction)
                    } catch {
                        errorPointer?.pointee = error as NSError
                        return nil
                    }
                }) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let typedValue = value as? T {
                        continuation.resume(returning: typedValue)
                    } else {
                        let fallback = NSError(domain: "FirestoreWriteClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transaction result type mismatch"]) 
                        continuation.resume(throwing: fallback)
                    }
                }
            }
            clearTransientFailureIfNeeded()
            return result
        } catch {
            handleWriteError(error, operation: .transaction, documentPath: nil, data: nil)
            throw error
        }
    }

    private func handleWriteError(_ error: Error, operation: WriteOperationType, documentPath: String?, data: [String: Any]?) {
        let category = categorizeFirestoreError(error)
        let failure = WriteFailure(
            category: category,
            documentPath: documentPath,
            operation: operation,
            timestamp: Date(),
            underlyingCode: (error as NSError).code,
            message: (error as NSError).localizedDescription
        )
        failureStore.setFailure(failure)
        syncEventLogger.writeFailure(category: category, operation: operation, docPath: documentPath)

        if isSafeToRetry(op: operation, data: data), let documentPath {
            retryClosure = { [weak self] in
                guard let self else { return }
                let docRef = self.db.document(documentPath)
                do {
                    switch operation {
                    case .setData:
                        guard let data else { return }
                        try await self.setData(data, to: docRef, merge: true)
                    case .updateData:
                        guard let data else { return }
                        try await self.updateData(data, in: docRef)
                    case .delete:
                        try await self.delete(docRef)
                    case .batch, .transaction:
                        return
                    }
                } catch {
                    return
                }
            }
        } else {
            retryClosure = nil
        }
    }

    private func clearTransientFailureIfNeeded() {
        guard let last = failureStore.lastWriteError else { return }
        if last.category == .unavailable || last.category == .resourceExhausted {
            failureStore.clearFailure()
        }
    }
}
