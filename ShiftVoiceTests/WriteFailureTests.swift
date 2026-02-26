import Foundation
import Testing
@testable import ShiftVoice

struct WriteFailureTests {
    @Test func categorizeFirestoreErrorPermissionDenied() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 7, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .permissionDenied)
    }

    @Test func categorizeFirestoreErrorUnauthenticated() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 16, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .unauthenticated)
    }

    @Test func categorizeFirestoreErrorNotFound() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 5, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .notFound)
    }

    @Test func categorizeFirestoreErrorInvalidArgument() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 3, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .invalidArgument)
    }

    @Test func categorizeFirestoreErrorFailedPrecondition() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 9, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .failedPrecondition)
    }

    @Test func categorizeFirestoreErrorResourceExhausted() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 8, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .resourceExhausted)
    }

    @Test func categorizeFirestoreErrorUnavailable() {
        let error = NSError(domain: "FIRFirestoreErrorDomain", code: 14, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .unavailable)
    }

    @Test func categorizeFirestoreErrorUnknown() {
        let error = NSError(domain: "Other", code: 999, userInfo: nil)
        #expect(categorizeFirestoreError(error) == .unknown)
    }

    @Test @MainActor func writeFailureStoreDedupesIdenticalFailuresWithinThirtySeconds() {
        let persistence = InMemoryWriteFailurePersistence()
        let store = WriteFailureStore(persistence: persistence, dedupeInterval: 30)
        let now = Date()

        let first = WriteFailure(
            category: .permissionDenied,
            documentPath: "organizations/org1/shiftNotes/n1",
            operation: .updateData,
            timestamp: now,
            underlyingCode: 7,
            message: "denied"
        )
        let duplicate = WriteFailure(
            category: .permissionDenied,
            documentPath: "organizations/org1/shiftNotes/n1",
            operation: .updateData,
            timestamp: now.addingTimeInterval(5),
            underlyingCode: 7,
            message: "denied again"
        )

        store.setFailure(first)
        store.setFailure(duplicate)

        #expect(store.lastWriteError == first)
    }

    @Test @MainActor func writeFailureStoreAcceptsSameSignatureAfterDedupWindow() {
        let persistence = InMemoryWriteFailurePersistence()
        let store = WriteFailureStore(persistence: persistence, dedupeInterval: 30)
        let now = Date()

        let first = WriteFailure(
            category: .permissionDenied,
            documentPath: "organizations/org1/shiftNotes/n1",
            operation: .updateData,
            timestamp: now,
            underlyingCode: 7,
            message: "denied"
        )
        let second = WriteFailure(
            category: .permissionDenied,
            documentPath: "organizations/org1/shiftNotes/n1",
            operation: .updateData,
            timestamp: now.addingTimeInterval(31),
            underlyingCode: 7,
            message: "denied later"
        )

        store.setFailure(first)
        store.setFailure(second)

        #expect(store.lastWriteError == second)
    }

    @Test @MainActor func writeFailureStoreFlagsReauthAndRetryCorrectly() {
        let persistence = InMemoryWriteFailurePersistence()
        let store = WriteFailureStore(persistence: persistence)

        store.setFailure(
            WriteFailure(
                category: .unauthenticated,
                documentPath: nil,
                operation: .batch,
                timestamp: Date(),
                underlyingCode: 16,
                message: nil
            )
        )

        #expect(store.shouldPromptReauth == true)
        #expect(store.triggerReauthFlag == true)
        #expect(store.shouldRecommendRetry == false)

        store.setFailure(
            WriteFailure(
                category: .unavailable,
                documentPath: nil,
                operation: .batch,
                timestamp: Date().addingTimeInterval(31),
                underlyingCode: 14,
                message: nil
            )
        )

        #expect(store.shouldPromptReauth == false)
        #expect(store.shouldRecommendRetry == true)
    }

    @Test func safeRetryRules() {
        #expect(isSafeToRetry(op: .setData, data: ["lastClientMutationId": "m1"]))
        #expect(isSafeToRetry(op: .updateData, data: ["lastClientMutationId": "m2"]))
        #expect(isSafeToRetry(op: .delete, data: nil))

        #expect(!isSafeToRetry(op: .setData, data: ["foo": "bar"]))
        #expect(!isSafeToRetry(op: .updateData, data: nil))
        #expect(!isSafeToRetry(op: .batch, data: ["lastClientMutationId": "m3"]))
        #expect(!isSafeToRetry(op: .transaction, data: ["lastClientMutationId": "m4"]))
    }
}

nonisolated final class InMemoryWriteFailurePersistence: WriteFailurePersisting {
    private var failure: WriteFailure?

    func saveLastWriteFailure(_ failure: WriteFailure) {
        self.failure = failure
    }

    func loadLastWriteFailure() -> WriteFailure? {
        failure
    }

    func clearLastWriteFailure() {
        failure = nil
    }
}
