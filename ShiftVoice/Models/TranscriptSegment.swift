import Foundation

nonisolated struct TranscriptSegment: Sendable, Identifiable {
    let id: UUID
    let text: String
    let confidence: Double
    let timestamp: TimeInterval
    let duration: TimeInterval

    init(id: UUID = UUID(), text: String, confidence: Double, timestamp: TimeInterval, duration: TimeInterval) {
        self.id = id
        self.text = text
        self.confidence = confidence
        self.timestamp = timestamp
        self.duration = duration
    }
}
