import SwiftUI
import AVFoundation

enum ProcessingStage: Sendable {
    case transcribing
    case structuring
    case finalizing
}

@Observable
final class RecordingViewModel {
    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()
    private let noteStructuring = NoteStructuringService.shared

    var isProcessing: Bool = false
    var processingStage: ProcessingStage = .transcribing
    var structuringWarning: String?
    var pendingReviewData: PendingNoteReviewData?
    var processingElapsed: TimeInterval = 0
    var transcriptionFailed: Bool = false
    var transcriptionFailureMessage: String?
    var isRetryingTranscription: Bool = false
    private var processingTimer: Task<Void, Never>?
    private var lastStopParams: StopParams?

    struct StopParams {
        let selectedShift: ShiftDisplayInfo?
        let defaultShift: ShiftDisplayInfo
        let businessType: String
        let authToken: String?
        let userId: String?
    }

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
        transcriptionFailed = false
        transcriptionFailureMessage = nil
        processingElapsed = 0
        startProcessingTimer()

        lastStopParams = StopParams(
            selectedShift: selectedShift,
            defaultShift: defaultShift,
            businessType: businessType,
            authToken: authToken,
            userId: userId
        )

        let shiftInfo = selectedShift ?? defaultShift

        Task {
            await processRecording(audioURL: audioURL, duration: duration, shiftInfo: shiftInfo, businessType: businessType, authToken: authToken, userId: userId)
        }
    }

    func retryTranscription(authToken: String?, userId: String?, businessType: String) async {
        guard let reviewData = pendingReviewData,
              let audioFilename = reviewData.audioUrl else { return }

        let recordingDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftVoiceRecordings", isDirectory: true)
        let audioURL = recordingDir.appendingPathComponent(audioFilename)

        isRetryingTranscription = true
        transcriptionFailed = false
        transcriptionFailureMessage = nil

        if let result = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId) {
            let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
                group.addTask {
                    await self.noteStructuring.structureTranscript(
                        result,
                        businessType: businessType,
                        authToken: authToken,
                        userId: userId
                    )
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                    return nil
                }
                for await r in group {
                    if let r {
                        group.cancelAll()
                        return r
                    }
                }
                group.cancelAll()
                return .failure(.timeout)
            }

            var summary: String
            var categorizedItems: [CategorizedItem]
            var actionItems: [ActionItem]
            var usedAI = false
            var warning: String?

            switch aiResult {
            case .success(let structured):
                summary = structured.summary
                categorizedItems = structured.categorizedItems
                actionItems = structured.actionItems
                usedAI = true
                warning = structured.warning
            case .failure(let error):
                summary = TranscriptProcessor.generateSummary(from: result)
                categorizedItems = TranscriptProcessor.generateCategories(from: result)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                warning = "AI structuring unavailable — structured locally. \(error.userMessage)"
            case .none:
                summary = TranscriptProcessor.generateSummary(from: result)
                categorizedItems = TranscriptProcessor.generateCategories(from: result)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                warning = "AI structuring timed out — structured locally."
            }

            pendingReviewData = PendingNoteReviewData(
                rawTranscript: result,
                audioDuration: reviewData.audioDuration,
                audioUrl: reviewData.audioUrl,
                shiftInfo: reviewData.shiftInfo,
                summary: summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems,
                usedAI: usedAI,
                structuringWarning: warning,
                transcriptionFailed: false
            )
        } else {
            transcriptionFailed = true
            transcriptionFailureMessage = transcriptionService.failureReason?.userMessage ?? "Transcription failed. Please try again."
        }
        isRetryingTranscription = false
    }

    private func processRecording(audioURL: URL?, duration: TimeInterval, shiftInfo: ShiftDisplayInfo, businessType: String, authToken: String?, userId: String?) async {
        var transcript = ""
        var didTranscriptionFail = false
        var failMessage: String?

        processingStage = .transcribing

        if let audioURL {
            if let result = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId) {
                transcript = result
            } else {
                didTranscriptionFail = true
                failMessage = transcriptionService.failureReason?.userMessage
            }
        } else {
            didTranscriptionFail = true
            failMessage = "No audio file was recorded."
        }

        var summary: String
        var categorizedItems: [CategorizedItem]
        var actionItems: [ActionItem]
        var usedAI = false

        if !transcript.isEmpty {
            processingStage = .structuring

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
                    try? await Task.sleep(for: .seconds(15))
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
                structuringWarning = "AI structuring unavailable — structured locally. \(error.userMessage)"
            case .none:
                summary = TranscriptProcessor.generateSummary(from: transcript)
                categorizedItems = TranscriptProcessor.generateCategories(from: transcript)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                structuringWarning = "AI structuring timed out — structured locally."
            }
        } else {
            summary = ""
            categorizedItems = []
            actionItems = []
        }

        processingStage = .finalizing

        transcriptionFailed = didTranscriptionFail
        transcriptionFailureMessage = failMessage

        pendingReviewData = PendingNoteReviewData(
            rawTranscript: transcript,
            audioDuration: duration,
            audioUrl: audioURL?.lastPathComponent,
            shiftInfo: shiftInfo,
            summary: summary,
            categorizedItems: categorizedItems,
            actionItems: actionItems,
            usedAI: usedAI,
            structuringWarning: structuringWarning,
            transcriptionFailed: didTranscriptionFail,
            transcriptionFailureMessage: failMessage
        )
        stopProcessingTimer()
        isProcessing = false
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
