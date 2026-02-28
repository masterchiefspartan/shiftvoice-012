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
    private let structuringCache = StructuringCache.shared

    var isProcessing: Bool = false
    var processingStage: ProcessingStage? = nil
    var structuringWarning: String?
    var pendingReviewData: PendingNoteReviewData?
    var processingElapsed: TimeInterval = 0
    var transcriptionFailed: Bool = false
    var transcriptionFailureMessage: String?
    var isRetryingTranscription: Bool = false
    private var hasUserEditedReview: Bool = false
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
        let liveText = transcriptionService.transcribedText
        audioRecorder.stopRecording()
        isProcessing = true
        processingStage = .transcribing
        hasUserEditedReview = false
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
            await processRecording(audioURL: audioURL, duration: duration, shiftInfo: shiftInfo, businessType: businessType, authToken: authToken, userId: userId, liveTranscript: liveText)
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
                    try? await Task.sleep(for: .seconds(15))
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
            let reason = transcriptionService.failureReason
            transcriptionFailed = !(reason?.isEmptyRecording ?? false)
            transcriptionFailureMessage = reason?.userMessage ?? "Transcription failed. Please try again."
        }
        isRetryingTranscription = false
    }

    private func processRecording(audioURL: URL?, duration: TimeInterval, shiftInfo: ShiftDisplayInfo, businessType: String, authToken: String?, userId: String?, liveTranscript: String = "") async {
        let hasLiveText = !liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasLiveText {
            processingStage = .structuring

            let (instantSummary, instantCategories, instantActions, instantUsedAI, instantWarning) = instantStructureTranscript(
                liveTranscript,
                businessType: businessType
            )

            processingStage = .finalizing

            pendingReviewData = PendingNoteReviewData(
                rawTranscript: liveTranscript,
                audioDuration: duration,
                audioUrl: audioURL?.lastPathComponent,
                shiftInfo: shiftInfo,
                summary: instantSummary,
                categorizedItems: instantCategories,
                actionItems: instantActions,
                usedAI: instantUsedAI,
                structuringWarning: instantWarning,
                transcriptionFailed: false
            )
            stopProcessingTimer()
            processingStage = nil
            isProcessing = false

            if let audioURL {
                Task {
                    await refineWithFullTranscription(
                        audioURL: audioURL, duration: duration, shiftInfo: shiftInfo,
                        businessType: businessType, authToken: authToken, userId: userId,
                        previousTranscript: liveTranscript
                    )
                }
            }
        } else {
            var transcript = ""
            var didTranscriptionFail = false
            var failMessage: String?

            processingStage = .transcribing

            if let audioURL {
                if let result = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId) {
                    transcript = result
                } else {
                    let reason = transcriptionService.failureReason
                    didTranscriptionFail = !(reason?.isEmptyRecording ?? false)
                    failMessage = reason?.userMessage
                }
            } else {
                didTranscriptionFail = true
                failMessage = "No audio file was recorded."
            }

            var summary: String
            var categorizedItems: [CategorizedItem]
            var actionItems: [ActionItem]
            var usedAI = false
            var warning: String?

            if !transcript.isEmpty {
                processingStage = .structuring
                (summary, categorizedItems, actionItems, usedAI, warning) = await structureTranscript(
                    transcript, businessType: businessType, authToken: authToken, userId: userId
                )
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
                structuringWarning: warning,
                transcriptionFailed: didTranscriptionFail,
                transcriptionFailureMessage: failMessage
            )
            stopProcessingTimer()
            processingStage = nil
            isProcessing = false
        }
    }

    private func structureTranscript(_ transcript: String, businessType: String, authToken: String?, userId: String?) async -> (String, [CategorizedItem], [ActionItem], Bool, String?) {
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
            structuringCache.cacheResult(result, businessType: businessType)
            return (result.summary, result.categorizedItems, result.actionItems, true, result.warning)
        case .failure(let error):
            return offlineFallback(transcript: transcript, businessType: businessType, warning: "AI structuring unavailable \u{2014} structured locally. \(error.userMessage)")
        case .none:
            return offlineFallback(transcript: transcript, businessType: businessType, warning: "AI structuring timed out \u{2014} structured locally.")
        }
    }

    private func instantStructureTranscript(_ transcript: String, businessType: String) -> (String, [CategorizedItem], [ActionItem], Bool, String?) {
        let summary = TranscriptProcessor.generateSummary(from: transcript)
        let categories = TranscriptProcessor.generateCategories(from: transcript, businessType: businessType)
        let actions = TranscriptProcessor.generateActionItems(from: categories)
        return (summary, categories, actions, false, "Refining in background with full transcription…")
    }

    private func offlineFallback(transcript: String, businessType: String, warning: String) -> (String, [CategorizedItem], [ActionItem], Bool, String?) {
        let summary = TranscriptProcessor.generateSummary(from: transcript)
        let categories = TranscriptProcessor.generateCategories(from: transcript, businessType: businessType)
        let actions = TranscriptProcessor.generateActionItems(from: categories)
        return (summary, categories, actions, false, warning)
    }

    private func refineWithFullTranscription(audioURL: URL, duration: TimeInterval, shiftInfo: ShiftDisplayInfo, businessType: String, authToken: String?, userId: String?, previousTranscript: String) async {
        guard let fullTranscript = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId) else { return }

        let trimmedFull = fullTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrevious = previousTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedFull.count > trimmedPrevious.count + 20 else { return }

        let (summary, categorizedItems, actionItems, usedAI, warning) = await structureTranscript(
            fullTranscript, businessType: businessType, authToken: authToken, userId: userId
        )

        guard usedAI else { return }
        guard !hasUserEditedReview else { return }

        pendingReviewData = PendingNoteReviewData(
            rawTranscript: fullTranscript,
            audioDuration: duration,
            audioUrl: audioURL.lastPathComponent,
            shiftInfo: shiftInfo,
            summary: summary,
            categorizedItems: categorizedItems,
            actionItems: actionItems,
            usedAI: usedAI,
            structuringWarning: warning,
            transcriptionFailed: false
        )
    }

    func cancelProcessing() {
        stopProcessingTimer()
        processingStage = nil
        isProcessing = false
        pendingReviewData = nil
    }

    func discardPendingNote() {
        processingStage = nil
        pendingReviewData = nil
    }

    func markReviewAsUserEdited() {
        hasUserEditedReview = true
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
