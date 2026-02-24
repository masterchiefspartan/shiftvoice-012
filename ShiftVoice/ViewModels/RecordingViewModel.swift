import SwiftUI
import AVFoundation

@Observable
final class RecordingViewModel {
    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()
    private let noteStructuring = NoteStructuringService.shared

    var isProcessing: Bool = false
    var structuringWarning: String?
    var pendingReviewData: PendingNoteReviewData?
    var processingElapsed: TimeInterval = 0
    private var processingTimer: Task<Void, Never>?

    var isRecording: Bool { audioRecorder.isRecording }
    var recordingDuration: TimeInterval { audioRecorder.recordingDuration }
    var audioLevels: [CGFloat] { audioRecorder.audioLevels }

    func requestRecordingPermissions() async -> Bool {
        let micGranted = await audioRecorder.requestPermission()
        let speechGranted = await transcriptionService.requestPermission()
        return micGranted && speechGranted
    }

    func startRecording() {
        audioRecorder.startRecording()
    }

    func stopRecording(
        selectedShift: ShiftDisplayInfo?,
        defaultShift: ShiftDisplayInfo,
        businessType: String,
        authToken: String?,
        userId: String?
    ) {
        let duration = audioRecorder.recordingDuration
        let audioURL = audioRecorder.currentAudioURL
        audioRecorder.stopRecording()
        isProcessing = true
        structuringWarning = nil
        processingElapsed = 0
        startProcessingTimer()

        let shiftInfo = selectedShift ?? defaultShift

        Task {
            var transcript = ""
            if let audioURL {
                if let result = await transcriptionService.transcribeAudioFile(at: audioURL) {
                    transcript = result
                }
            }

            var summary: String
            var categorizedItems: [CategorizedItem]
            var actionItems: [ActionItem]
            var usedAI = false

            let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
                group.addTask {
                    await self.noteStructuring.structureTranscript(
                        transcript,
                        businessType: businessType,
                        authToken: authToken,
                        userId: userId
                    )
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                    return nil
                }
                for await result in group {
                    if let result {
                        group.cancelAll()
                        return result
                    }
                }
                group.cancelAll()
                return .failure(.timeout)
            }

            switch aiResult {
            case .success(let result):
                summary = result.summary
                categorizedItems = result.categorizedItems
                actionItems = result.actionItems
                usedAI = true
                structuringWarning = result.warning
            case .failure(let error):
                summary = TranscriptProcessor.generateSummary(from: transcript)
                categorizedItems = TranscriptProcessor.generateCategories(from: transcript)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                if !transcript.isEmpty {
                    structuringWarning = "AI structuring unavailable — structured locally. \(error.userMessage)"
                }
            case .none:
                summary = TranscriptProcessor.generateSummary(from: transcript)
                categorizedItems = TranscriptProcessor.generateCategories(from: transcript)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                structuringWarning = "AI structuring timed out — structured locally."
            }

            pendingReviewData = PendingNoteReviewData(
                rawTranscript: transcript,
                audioDuration: duration,
                audioUrl: audioURL?.lastPathComponent,
                shiftInfo: shiftInfo,
                summary: summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems,
                usedAI: usedAI,
                structuringWarning: structuringWarning
            )
            stopProcessingTimer()
            isProcessing = false
        }
    }

    func cancelProcessing() {
        stopProcessingTimer()
        isProcessing = false
        pendingReviewData = nil
    }

    func discardPendingNote() {
        pendingReviewData = nil
    }

    private func startProcessingTimer() {
        processingTimer?.cancel()
        processingTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                processingElapsed += 1
            }
        }
    }

    private func stopProcessingTimer() {
        processingTimer?.cancel()
        processingTimer = nil
    }
}
