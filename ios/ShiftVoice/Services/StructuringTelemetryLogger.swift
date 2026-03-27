import Foundation

nonisolated enum StructuringTelemetryEventKind: String, Codable, Sendable {
    case aiStructuringSucceeded
    case aiFallbackUsed
    case aiTimeoutFallbackUsed
    case validationEvaluated
}

nonisolated struct StructuringTelemetryEvent: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let kind: StructuringTelemetryEventKind
    let message: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: StructuringTelemetryEventKind,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

nonisolated enum StructuringTelemetryLogEvent: Sendable {
    case aiStructuringSucceeded(itemCount: Int)
    case aiFallbackUsed(reason: String)
    case aiTimeoutFallbackUsed
    case validationEvaluated(warningCount: Int, confidenceScore: Double, needsUserReview: Bool)
}

@MainActor
final class StructuringTelemetryLogger {
    static let shared = StructuringTelemetryLogger()

    private let maxEvents: Int = 500
    private var events: [StructuringTelemetryEvent] = []

    func log(_ event: StructuringTelemetryLogEvent) {
        switch event {
        case .aiStructuringSucceeded(let itemCount):
            append(
                StructuringTelemetryEvent(
                    kind: .aiStructuringSucceeded,
                    message: "AI structuring succeeded with \(itemCount) items"
                )
            )
        case .aiFallbackUsed(let reason):
            append(
                StructuringTelemetryEvent(
                    kind: .aiFallbackUsed,
                    message: "AI fallback used: \(reason)"
                )
            )
        case .aiTimeoutFallbackUsed:
            append(
                StructuringTelemetryEvent(
                    kind: .aiTimeoutFallbackUsed,
                    message: "AI fallback used due to timeout"
                )
            )
        case .validationEvaluated(let warningCount, let confidenceScore, let needsUserReview):
            append(
                StructuringTelemetryEvent(
                    kind: .validationEvaluated,
                    message: "Validation warnings=\(warningCount) confidence=\(String(format: "%.2f", confidenceScore)) needsReview=\(needsUserReview)"
                )
            )
        }
    }

    func recentEvents(limit: Int) -> [StructuringTelemetryEvent] {
        Array(events.suffix(limit).reversed())
    }

    var fallbackEventCount: Int {
        events.filter { $0.kind == .aiFallbackUsed || $0.kind == .aiTimeoutFallbackUsed }.count
    }

    private func append(_ event: StructuringTelemetryEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
}
