import Foundation

nonisolated enum RecordingFailureState: Sendable {
    case none
    case emptyRecording(message: String)
    case transcriptionFailed(message: String)
}

struct PendingNoteReviewData {
    let rawTranscript: String
    let audioDuration: TimeInterval
    let audioUrl: String?
    let shiftInfo: ShiftDisplayInfo
    let summary: String
    let categorizedItems: [CategorizedItem]
    let actionItems: [ActionItem]
    var usedAI: Bool = true
    var structuringWarning: String? = nil
    var recordingFailureState: RecordingFailureState = .none
    var visibility: NoteVisibility = .team
    var transcriptSegments: [TranscriptSegment] = []
    var lowConfidenceSegments: [TranscriptSegment] = []
    var averageTranscriptConfidence: Double? = nil
    var confidenceScore: Double = 1.0
    var validationWarnings: [ValidationWarning] = []
}
