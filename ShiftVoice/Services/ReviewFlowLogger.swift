import Foundation

@MainActor
final class ReviewFlowLogger {
    static let shared = ReviewFlowLogger()

    private var events: [ReviewFlowEventRecord] = []
    private let maxEvents: Int = 500

    func log(_ event: ReviewFlowEvent) {
        switch event {
        case .enteredReview(let source, let returnDestination):
            append(
                ReviewFlowEventRecord(
                    kind: .enteredReview,
                    source: source,
                    returnDestination: returnDestination
                )
            )
        case .exitedWithoutSave(let source, let returnDestination, let reason):
            append(
                ReviewFlowEventRecord(
                    kind: .exitedWithoutSave,
                    source: source,
                    returnDestination: returnDestination,
                    reason: reason
                )
            )
        case .published(let source, let returnDestination, let noteId):
            append(
                ReviewFlowEventRecord(
                    kind: .published,
                    source: source,
                    returnDestination: returnDestination,
                    noteId: noteId
                )
            )
        case .publishFailed(let source, let returnDestination, let message):
            append(
                ReviewFlowEventRecord(
                    kind: .publishFailed,
                    source: source,
                    returnDestination: returnDestination,
                    message: message
                )
            )
        }
    }

    func recentEvents(limit: Int) -> [ReviewFlowEventRecord] {
        Array(events.suffix(limit).reversed())
    }

    var dropOffEventCount: Int {
        events.filter { $0.kind == .exitedWithoutSave }.count
    }

    private func append(_ event: ReviewFlowEventRecord) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
}
