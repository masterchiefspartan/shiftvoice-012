import Foundation

nonisolated enum WriteErrorCategory: String, Codable, Sendable {
    case permissionDenied
    case unauthenticated
    case notFound
    case invalidArgument
    case failedPrecondition
    case resourceExhausted
    case unavailable
    case unknown
}

nonisolated enum WriteOperationType: String, Codable, Sendable {
    case setData
    case updateData
    case delete
    case batch
    case transaction
}

nonisolated struct WriteFailure: Codable, Equatable, Sendable {
    let category: WriteErrorCategory
    let documentPath: String?
    let operation: WriteOperationType
    let timestamp: Date
    let underlyingCode: Int?
    let message: String?
}

nonisolated func categorizeFirestoreError(_ error: Error) -> WriteErrorCategory {
    let nsError = error as NSError

    switch nsError.code {
    case 7:
        return .permissionDenied
    case 16:
        return .unauthenticated
    case 5:
        return .notFound
    case 3:
        return .invalidArgument
    case 9:
        return .failedPrecondition
    case 8:
        return .resourceExhausted
    case 14:
        return .unavailable
    default:
        return .unknown
    }
}

nonisolated func isSafeToRetry(op: WriteOperationType, data: [String: Any]?) -> Bool {
    switch op {
    case .setData:
        guard let data else { return false }
        return data["lastClientMutationId"] as? String != nil
    case .updateData:
        guard let data else { return false }
        return data["lastClientMutationId"] as? String != nil
    case .delete:
        return true
    case .batch, .transaction:
        return false
    }
}
