import SwiftUI
import AVFoundation
import OSLog

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShiftVoice", category: "RecordingFlow")
    private let structuringTelemetryLogger = StructuringTelemetryLogger.shared

    var isProcessing: Bool = false
    var processingStage: ProcessingStage? = nil
    var structuringWarning: String?
    var pendingReviewData: PendingNoteReviewData?
    var processingElapsed: TimeInterval = 0
    var recordingFailureState: RecordingFailureState = .none
    var isRetryingTranscription: Bool = false
    var selectedVisibility: NoteVisibility = .team
    private var hasUserEditedReview: Bool = false
    private var processingTimer: Task<Void, Never>?
    private var lastStopParams: StopParams?

    struct StopParams {
        let selectedShift: ShiftDisplayInfo?
        let defaultShift: ShiftDisplayInfo
        let businessType: String
        let authToken: String?
        let userId: String?
        let locationId: String?
        let industryType: String?
        let resolvedShiftType: String?
    }

    var isRecording: Bool { audioRecorder.isRecording }
    var recordingDuration: TimeInterval { audioRecorder.recordingDuration }
    var audioLevels: [CGFloat] { audioRecorder.audioLevels }

    func hasRecordingPermission() -> Bool {
        audioRecorder.hasMicrophonePermission()
    }

    func isRecordingPermissionDenied() -> Bool {
        audioRecorder.isMicrophonePermissionDenied()
    }

    func requestRecordingPermissionsIfNeeded() async -> Bool {
        await audioRecorder.requestPermissionIfNeeded()
    }

    func startRecording() {
        audioRecorder.startRecording()
    }

    func stopRecording(
        selectedShift: ShiftDisplayInfo?,
        defaultShift: ShiftDisplayInfo,
        businessType: String,
        authToken: String?,
        userId: String?,
        locationId: String? = nil,
        industryType: String? = nil,
        resolvedShiftType: String? = nil
    ) {
        let duration = audioRecorder.recordingDuration
        let audioURL = audioRecorder.currentAudioURL
        audioRecorder.stopRecording()
        isProcessing = true
        processingStage = .transcribing
        hasUserEditedReview = false
        structuringWarning = nil
        recordingFailureState = .none
        processingElapsed = 0
        startProcessingTimer()

        lastStopParams = StopParams(
            selectedShift: selectedShift,
            defaultShift: defaultShift,
            businessType: businessType,
            authToken: authToken,
            userId: userId,
            locationId: locationId,
            industryType: industryType,
            resolvedShiftType: resolvedShiftType
        )

        let shiftInfo = selectedShift ?? defaultShift

        Task {
            await processRecording(audioURL: audioURL, duration: duration, shiftInfo: shiftInfo, businessType: businessType, authToken: authToken, userId: userId, locationId: locationId, industryType: industryType, resolvedShiftType: resolvedShiftType)
        }
    }

    func retryTranscription(authToken: String?, userId: String?, businessType: String) async {
        guard let reviewData = pendingReviewData else {
            recordingFailureState = .transcriptionFailed(message: "Couldn't retry because no review data is available.")
            return
        }
        guard let audioFilename = reviewData.audioUrl, !audioFilename.isEmpty else {
            recordingFailureState = .transcriptionFailed(message: "Original audio file is unavailable. Please record a new note.")
            pendingReviewData = PendingNoteReviewData(
                rawTranscript: reviewData.rawTranscript,
                audioDuration: reviewData.audioDuration,
                audioUrl: reviewData.audioUrl,
                shiftInfo: reviewData.shiftInfo,
                summary: reviewData.summary,
                categorizedItems: reviewData.categorizedItems,
                actionItems: reviewData.actionItems,
                usedAI: reviewData.usedAI,
                structuringWarning: reviewData.structuringWarning,
                recordingFailureState: recordingFailureState,
                transcriptSegments: reviewData.transcriptSegments,
                lowConfidenceSegments: reviewData.lowConfidenceSegments,
                averageTranscriptConfidence: reviewData.averageTranscriptConfidence,
                confidenceScore: reviewData.confidenceScore,
                validationWarnings: reviewData.validationWarnings,
                warningItemIDs: reviewData.warningItemIDs
            )
            return
        }

        let recordingDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftVoiceRecordings", isDirectory: true)
        let audioURL = recordingDir.appendingPathComponent(audioFilename)

        isRetryingTranscription = true
        recordingFailureState = .none

        let isValid = await transcriptionService.validateBeforeTranscription(at: audioURL)
        guard isValid else {
            logger.error("Retry transcription blocked by validation for file \(audioURL.lastPathComponent, privacy: .public)")
            let reason = transcriptionService.failureReason
            recordingFailureState = failureState(from: reason)
            isRetryingTranscription = false
            return
        }
        logger.info("Retry transcription validation passed for file \(audioURL.lastPathComponent, privacy: .public)")

        let retryVocab = industryVocabulary(for: businessTypeEnum(from: businessType))
        if let result = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId, industryVocabulary: retryVocab) {
            let cleanedTranscript = TranscriptCleaner.clean(result)
            let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
                group.addTask {
                    await self.noteStructuring.structureTranscript(
                        cleanedTranscript.text,
                        businessType: businessType,
                        authToken: authToken,
                        userId: userId,
                        context: self.buildStructuringContext(cleanedTranscript: cleanedTranscript, businessType: businessType),
                        shiftType: self.lastStopParams?.resolvedShiftType,
                        locationId: self.lastStopParams?.locationId,
                        industryType: self.lastStopParams?.industryType
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
            let cleanedEstimatedTopicCount = cleanedTranscript.estimatedTopicCount
            var transcriptCoverage: String?

            switch aiResult {
            case .success(let structured):
                summary = structured.summary
                categorizedItems = structured.categorizedItems
                actionItems = structured.actionItems
                usedAI = true
                warning = structured.warning
                transcriptCoverage = structured.transcriptCoverage
                structuringTelemetryLogger.log(.aiStructuringSucceeded(itemCount: structured.categorizedItems.count))
            case .failure(let error):
                summary = TranscriptProcessor.generateSummary(from: result)
                categorizedItems = TranscriptProcessor.generateCategories(from: result, businessType: businessType)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                warning = "AI structuring unavailable — structured locally. \(error.userMessage)"
                structuringTelemetryLogger.log(.aiFallbackUsed(reason: error.userMessage))
            case .none:
                summary = TranscriptProcessor.generateSummary(from: result)
                categorizedItems = TranscriptProcessor.generateCategories(from: result, businessType: businessType)
                actionItems = TranscriptProcessor.generateActionItems(from: categorizedItems)
                warning = "AI structuring timed out — structured locally."
                structuringTelemetryLogger.log(.aiTimeoutFallbackUsed)
            }

            let validationResult = StructuringValidator.validate(
                transcript: cleanedTranscript.text,
                items: categorizedItems,
                estimatedTopicCount: cleanedEstimatedTopicCount,
                transcriptCoverage: transcriptCoverage
            )
            let reviewState = adjustedReviewState(validationResult: validationResult, usedAI: usedAI)
            let combinedWarning = combineWarnings(
                warning,
                validationWarnings: validationResult.warnings,
                needsUserReview: reviewState.needsUserReview,
                usedAI: usedAI
            )
            structuringTelemetryLogger.log(
                .validationEvaluated(
                    warningCount: validationResult.warnings.count,
                    confidenceScore: reviewState.confidenceScore,
                    needsUserReview: reviewState.needsUserReview
                )
            )

            pendingReviewData = PendingNoteReviewData(
                rawTranscript: result,
                audioDuration: reviewData.audioDuration,
                audioUrl: reviewData.audioUrl,
                shiftInfo: reviewData.shiftInfo,
                summary: summary,
                categorizedItems: validationResult.items,
                actionItems: actionItems,
                usedAI: usedAI,
                structuringWarning: combinedWarning,
                recordingFailureState: .none,
                transcriptSegments: [],
                lowConfidenceSegments: [],
                averageTranscriptConfidence: nil,
                confidenceScore: reviewState.confidenceScore,
                validationWarnings: validationResult.warnings,
                warningItemIDs: validationResult.warningItemIDs
            )
        } else {
            let reason = transcriptionService.failureReason
            recordingFailureState = failureState(from: reason)
        }
        isRetryingTranscription = false
    }

    private func processRecording(audioURL: URL?, duration: TimeInterval, shiftInfo: ShiftDisplayInfo, businessType: String, authToken: String?, userId: String?, locationId: String? = nil, industryType: String? = nil, resolvedShiftType: String? = nil) async {
        var transcript = ""
        var currentFailureState: RecordingFailureState = .none

        processingStage = .transcribing

        if let audioURL {
            let isValid = await transcriptionService.validateBeforeTranscription(at: audioURL)
            if isValid {
                logger.info("Process recording validation passed for file \(audioURL.lastPathComponent, privacy: .public)")
                let vocab = industryVocabulary(for: businessTypeEnum(from: businessType))
                if let result = await transcriptionService.transcribeAudioFile(at: audioURL, authToken: authToken, userId: userId, industryVocabulary: vocab) {
                    transcript = result
                } else {
                    let reason = transcriptionService.failureReason
                    currentFailureState = failureState(from: reason)
                }
            } else {
                logger.error("Process recording blocked by validation for file \(audioURL.lastPathComponent, privacy: .public)")
                let reason = transcriptionService.failureReason
                currentFailureState = failureState(from: reason)
            }
        } else {
            currentFailureState = .transcriptionFailed(message: "No audio file was recorded.")
        }

        var summary: String
        var categorizedItems: [CategorizedItem]
        var actionItems: [ActionItem]
        var usedAI = false
        var warning: String?
        var transcriptCoverage: String?

        if !transcript.isEmpty {
            processingStage = .structuring
            (summary, categorizedItems, actionItems, usedAI, warning, transcriptCoverage) = await structureTranscript(
                transcript, businessType: businessType, authToken: authToken, userId: userId, locationId: locationId, industryType: industryType, resolvedShiftType: resolvedShiftType
            )
        } else {
            summary = ""
            categorizedItems = []
            actionItems = []
        }

        processingStage = .finalizing

        recordingFailureState = currentFailureState

        let cleanedTranscript = TranscriptCleaner.clean(transcript)
        let validationResult = StructuringValidator.validate(
            transcript: cleanedTranscript.text,
            items: categorizedItems,
            estimatedTopicCount: cleanedTranscript.estimatedTopicCount,
            transcriptCoverage: transcriptCoverage
        )
        let reviewState = adjustedReviewState(validationResult: validationResult, usedAI: usedAI)
        let combinedWarning = combineWarnings(
            warning,
            validationWarnings: validationResult.warnings,
            needsUserReview: reviewState.needsUserReview,
            usedAI: usedAI
        )
        structuringTelemetryLogger.log(
            .validationEvaluated(
                warningCount: validationResult.warnings.count,
                confidenceScore: reviewState.confidenceScore,
                needsUserReview: reviewState.needsUserReview
            )
        )

        pendingReviewData = PendingNoteReviewData(
            rawTranscript: transcript,
            audioDuration: duration,
            audioUrl: audioURL?.lastPathComponent,
            shiftInfo: shiftInfo,
            summary: summary,
            categorizedItems: validationResult.items,
            actionItems: actionItems,
            usedAI: usedAI,
            structuringWarning: combinedWarning,
            recordingFailureState: currentFailureState,
            transcriptSegments: [],
            lowConfidenceSegments: [],
            averageTranscriptConfidence: nil,
            confidenceScore: reviewState.confidenceScore,
            validationWarnings: validationResult.warnings,
            warningItemIDs: validationResult.warningItemIDs
        )
        stopProcessingTimer()
        processingStage = nil
        isProcessing = false
    }

    private func structureTranscript(_ transcript: String, businessType: String, authToken: String?, userId: String?, locationId: String? = nil, industryType: String? = nil, resolvedShiftType: String? = nil) async -> (String, [CategorizedItem], [ActionItem], Bool, String?, String?) {
        let cleanedTranscript = TranscriptCleaner.clean(transcript)
        let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
            group.addTask {
                await self.noteStructuring.structureTranscript(
                    cleanedTranscript.text,
                    businessType: businessType,
                    authToken: authToken,
                    userId: userId,
                    context: self.buildStructuringContext(cleanedTranscript: cleanedTranscript, businessType: businessType),
                    shiftType: resolvedShiftType,
                    locationId: locationId,
                    industryType: industryType
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
            structuringTelemetryLogger.log(.aiStructuringSucceeded(itemCount: result.categorizedItems.count))
            return (result.summary, result.categorizedItems, result.actionItems, true, result.warning, result.transcriptCoverage)
        case .failure(let error):
            let fallback = offlineFallback(transcript: transcript, businessType: businessType, warning: "AI structuring unavailable \u{2014} structured locally. \(error.userMessage)")
            structuringTelemetryLogger.log(.aiFallbackUsed(reason: error.userMessage))
            return (fallback.0, fallback.1, fallback.2, fallback.3, fallback.4, nil)
        case .none:
            let fallback = offlineFallback(transcript: transcript, businessType: businessType, warning: "AI structuring timed out \u{2014} structured locally.")
            structuringTelemetryLogger.log(.aiTimeoutFallbackUsed)
            return (fallback.0, fallback.1, fallback.2, fallback.3, fallback.4, nil)
        }
    }

    private func offlineFallback(transcript: String, businessType: String, warning: String) -> (String, [CategorizedItem], [ActionItem], Bool, String?) {
        let summary = TranscriptProcessor.generateSummary(from: transcript)
        let categories = TranscriptProcessor.generateCategories(from: transcript, businessType: businessType)
        let actions = TranscriptProcessor.generateActionItems(from: categories)
        return (summary, categories, actions, false, warning)
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

    private func businessTypeEnum(from value: String) -> BusinessType {
        BusinessType(rawValue: value) ?? .restaurant
    }

    private func industryVocabulary(for businessType: BusinessType) -> [String] {
        IndustrySeed.template(for: businessType).terminology.allVocabulary
    }

    private func categorizationHints(for businessType: BusinessType) -> [String] {
        let template = IndustrySeed.template(for: businessType)
        return template.defaultCategories.map { category in
            "\(category.name): \(category.id)"
        }
    }

    private func buildStructuringContext(cleanedTranscript: CleanedTranscript, businessType: String) -> StructuringRequestContext {
        let bt = businessTypeEnum(from: businessType)
        let terminology = IndustrySeed.template(for: bt).terminology
        return StructuringRequestContext(
            estimatedTopicCount: cleanedTranscript.estimatedTopicCount,
            averageSegmentConfidence: nil,
            lowConfidencePhrases: cleanedTranscript.lowConfidencePhrases,
            availableCategories: IndustrySeed.template(for: bt).defaultCategories.map(\.name),
            industryVocabulary: industryVocabulary(for: bt),
            categorizationHints: categorizationHints(for: bt),
            industryRoles: terminology.roles,
            industryEquipment: terminology.equipment,
            industrySlang: terminology.slang
        )
    }

    private func adjustedReviewState(validationResult: ValidationResult, usedAI: Bool) -> (confidenceScore: Double, needsUserReview: Bool) {
        if usedAI {
            return (validationResult.confidenceScore, validationResult.needsUserReview)
        }
        return (min(validationResult.confidenceScore, 0.55), true)
    }

    private func combineWarnings(_ warning: String?, validationWarnings: [ValidationWarning], needsUserReview: Bool, usedAI: Bool) -> String? {
        var messages: [String] = []
        if let warning, !warning.isEmpty {
            messages.append(warning)
        }
        if !validationWarnings.isEmpty {
            let warningText = validationWarnings
                .map(\.rawValue)
                .joined(separator: ", ")
            messages.append("Validation: \(warningText)")
        }
        if !usedAI {
            messages.append("Local estimate — review before saving.")
        }
        if needsUserReview {
            messages.append("Review recommended before saving.")
        }
        let combined = messages.joined(separator: " ")
        return combined.isEmpty ? nil : combined
    }

    private func failureState(from reason: TranscriptionFailureReason?) -> RecordingFailureState {
        guard let reason else {
            return .transcriptionFailed(message: "Couldn't process audio. Please retry transcription.")
        }
        if reason.isEmptyRecording {
            return .emptyRecording(message: reason.userMessage)
        }
        return .transcriptionFailed(message: reason.userMessage)
    }
}
