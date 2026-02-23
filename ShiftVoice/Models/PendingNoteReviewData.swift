import Foundation

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
}
