import Foundation

nonisolated enum ReviewEntrySource: String, Codable, Hashable, Sendable {
    case record
}

nonisolated enum ReviewReturnDestination: String, Codable, Hashable, Sendable {
    case recording
    case inboxDetail
}

nonisolated enum ReviewDropOffReason: String, Codable, Hashable, Sendable {
    case discarded
    case backNavigation
    case dismissed
}

nonisolated enum ReviewFlowEvent: Hashable, Sendable {
    case enteredReview(source: ReviewEntrySource, returnDestination: ReviewReturnDestination)
    case exitedWithoutSave(source: ReviewEntrySource, returnDestination: ReviewReturnDestination, reason: ReviewDropOffReason)
    case published(source: ReviewEntrySource, returnDestination: ReviewReturnDestination, noteId: String)
    case publishFailed(source: ReviewEntrySource, returnDestination: ReviewReturnDestination, message: String)
}

nonisolated enum ReviewFlowEventKind: String, Codable, Sendable {
    case enteredReview
    case exitedWithoutSave
    case published
    case publishFailed
}

nonisolated struct ReviewFlowEventRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let kind: ReviewFlowEventKind
    let source: ReviewEntrySource
    let returnDestination: ReviewReturnDestination
    let reason: ReviewDropOffReason?
    let noteId: String?
    let message: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: ReviewFlowEventKind,
        source: ReviewEntrySource,
        returnDestination: ReviewReturnDestination,
        reason: ReviewDropOffReason? = nil,
        noteId: String? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.source = source
        self.returnDestination = returnDestination
        self.reason = reason
        self.noteId = noteId
        self.message = message
    }
}
