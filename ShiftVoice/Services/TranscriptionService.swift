import Speech
import AVFoundation
import OSLog

nonisolated struct TranscribeResponse: Codable, Sendable {
    let success: Bool
    let text: String?
    let language: String?
    let error: String?
}

nonisolated enum TranscriptionFailureReason: Sendable {
    case noAudioFile
    case emptyAudioFile
    case audioTooShort(minimum: TimeInterval, actual: TimeInterval)
    case unsupportedAudioFormat
    case corruptAudioFile
    case cloudFailed
    case localFailed(String)
    case noResult

    var isEmptyRecording: Bool {
        switch self {
        case .emptyAudioFile, .audioTooShort, .noResult:
            return true
        default:
            return false
        }
    }

    var userMessage: String {
        switch self {
        case .noAudioFile:
            return "No audio file found. The recording may not have saved."
        case .emptyAudioFile:
            return "The recording appears to be empty (zero length)."
        case .audioTooShort(let minimum, let actual):
            return "The recording is too short (\(String(format: "%.2f", actual))s). Please record at least \(String(format: "%.1f", minimum)) seconds."
        case .unsupportedAudioFormat:
            return "Unsupported audio format. Please try recording again."
        case .corruptAudioFile:
            return "The audio file could not be read. It may be corrupted."
        case .cloudFailed:
            return "Cloud transcription failed."
        case .localFailed(let msg):
            return msg
        case .noResult:
            return "No speech was detected in the recording."
        }
    }
}

@Observable
final class TranscriptionService {
    var transcribedText: String = ""
    var isTranscribing: Bool = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var errorMessage: String?
    var usedCloudTranscription: Bool = false
    var failureReason: TranscriptionFailureReason?
    var transcriptSegments: [TranscriptSegment] = []
    var lowConfidenceSegments: [TranscriptSegment] = []
    var averageSegmentConfidence: Double = 1.0

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?

    private let cloudSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShiftVoice", category: "TranscriptionValidation")
    private let minimumDurationSeconds: TimeInterval = 0.5
    private let supportedAudioExtensions: Set<String> = ["m4a", "aac", "mp4"]

    private var baseURL: String {
        let url = Config.EXPO_PUBLIC_RORK_API_BASE_URL
        if url.isEmpty || url == "EXPO_PUBLIC_RORK_API_BASE_URL" { return "" }
        return url
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor [weak self] in
                    self?.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    enum AudioValidationResult {
        case valid
        case missing
        case empty
        case unsupportedFormat
        case tooShort(actualDuration: TimeInterval)
        case corrupt
    }

    func validateAudioFile(at url: URL) async -> AudioValidationResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > 0 else { return .empty }

        let ext = url.pathExtension.lowercased()
        guard supportedAudioExtensions.contains(ext) else { return .unsupportedFormat }

        let asset = AVURLAsset(url: url)
        do {
            let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
            guard isPlayable else { return .corrupt }
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else { return .corrupt }
            guard durationSeconds >= minimumDurationSeconds else { return .tooShort(actualDuration: durationSeconds) }
            return .valid
        } catch {
            return .corrupt
        }
    }

    func validateBeforeTranscription(at url: URL) async -> Bool {
        errorMessage = nil
        failureReason = nil
        let validationResult = await validateAudioFile(at: url)
        return handleValidationResult(validationResult, for: url)
    }

    func transcribeAudioFile(at url: URL, authToken: String? = nil, userId: String? = nil) async -> String? {
        isTranscribing = true
        transcribedText = ""
        errorMessage = nil
        usedCloudTranscription = false
        failureReason = nil
        transcriptSegments = []
        lowConfidenceSegments = []
        averageSegmentConfidence = 1.0

        let validationResult = await validateAudioFile(at: url)
        guard handleValidationResult(validationResult, for: url) else {
            isTranscribing = false
            return nil
        }

        let result = await raceTranscription(audioURL: url, authToken: authToken, userId: userId)
        if result == nil && failureReason == nil {
            failureReason = .noResult
            errorMessage = TranscriptionFailureReason.noResult.userMessage
        }
        isTranscribing = false
        return result
    }

    private func handleValidationResult(_ result: AudioValidationResult, for url: URL) -> Bool {
        switch result {
        case .missing:
            failureReason = .noAudioFile
            errorMessage = TranscriptionFailureReason.noAudioFile.userMessage
            logger.error("Validation failed: missing file at path: \(url.path, privacy: .public)")
            return false
        case .empty:
            failureReason = .emptyAudioFile
            errorMessage = TranscriptionFailureReason.emptyAudioFile.userMessage
            logger.error("Validation failed: empty file at path: \(url.path, privacy: .public)")
            return false
        case .unsupportedFormat:
            failureReason = .unsupportedAudioFormat
            errorMessage = TranscriptionFailureReason.unsupportedAudioFormat.userMessage
            logger.error("Validation failed: unsupported extension \(url.pathExtension, privacy: .public) for file \(url.lastPathComponent, privacy: .public)")
            return false
        case .tooShort(let actualDuration):
            failureReason = .audioTooShort(minimum: minimumDurationSeconds, actual: actualDuration)
            errorMessage = failureReason?.userMessage
            logger.error("Validation failed: duration too short \(actualDuration, privacy: .public)s for file \(url.lastPathComponent, privacy: .public)")
            return false
        case .corrupt:
            failureReason = .corruptAudioFile
            errorMessage = TranscriptionFailureReason.corruptAudioFile.userMessage
            logger.error("Validation failed: corrupt or unreadable audio file \(url.lastPathComponent, privacy: .public)")
            return false
        case .valid:
            logger.info("Validation passed for file \(url.lastPathComponent, privacy: .public)")
            return true
        }
    }

    private func raceTranscription(audioURL: URL, authToken: String?, userId: String?) async -> String? {
        let canCloud = !baseURL.isEmpty

        if !canCloud {
            return await transcribeLocally(at: audioURL)
        }

        return await withTaskGroup(of: (String?, Bool).self) { group in
            group.addTask {
                let result = await self.transcribeViaCloud(audioURL: audioURL, authToken: authToken, userId: userId)
                return (result, true)
            }
            group.addTask {
                let result = await self.transcribeLocally(at: audioURL)
                return (result, false)
            }

            var firstResult: String?
            var firstWasCloud = false

            for await (result, isCloud) in group {
                if let text = result, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    usedCloudTranscription = isCloud
                    if isCloud {
                        transcriptSegments = []
                        lowConfidenceSegments = []
                        averageSegmentConfidence = 1.0
                    }
                    transcribedText = text
                    group.cancelAll()
                    return text
                }
                if firstResult == nil {
                    firstResult = result
                    firstWasCloud = isCloud
                }
            }

            if let text = firstResult, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                usedCloudTranscription = firstWasCloud
                if firstWasCloud {
                    transcriptSegments = []
                    lowConfidenceSegments = []
                    averageSegmentConfidence = 1.0
                }
                transcribedText = text
                return text
            }
            return nil
        }
    }

    private func transcribeViaCloud(audioURL: URL, authToken: String?, userId: String?) async -> String? {
        guard let endpoint = URL(string: "\(baseURL)/api/rest/transcribe") else { return nil }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            return nil
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid = userId {
            request.setValue(uid, forHTTPHeaderField: "X-User-Id")
        }

        let filename = audioURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/\(audioURL.pathExtension)"

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        do {
            let (data, response) = try await cloudSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }

            let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
            guard result.success, let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return text
        } catch {
            return nil
        }
    }

    private final class ContinuationGuard<T: Sendable>: @unchecked Sendable {
        private var hasResumed = false
        private let lock = NSLock()
        private let continuation: CheckedContinuation<T, Never>
        private let onResume: (() -> Void)?

        init(_ continuation: CheckedContinuation<T, Never>, onResume: (() -> Void)? = nil) {
            self.continuation = continuation
            self.onResume = onResume
        }

        func resume(returning value: T) {
            lock.lock()
            let shouldResume = !hasResumed
            if shouldResume {
                hasResumed = true
            }
            lock.unlock()

            guard shouldResume else { return }
            onResume?()
            continuation.resume(returning: value)
        }
    }

    private var activeLocalContinuation: ContinuationGuard<String?>?
    private var localRecognitionTimeoutTask: Task<Void, Never>?
    private let localRecognitionTimeout: Duration = .seconds(20)

    deinit {
        localRecognitionTimeoutTask?.cancel()
        recognitionTask?.cancel()
        activeLocalContinuation?.resume(returning: nil)
    }

    private func finishLocalRecognition(with value: String?) {
        localRecognitionTimeoutTask?.cancel()
        localRecognitionTimeoutTask = nil
        recognitionTask = nil
        activeLocalContinuation?.resume(returning: value)
        activeLocalContinuation = nil
    }

    private func failLocalRecognition(_ reason: TranscriptionFailureReason) {
        failureReason = reason
        errorMessage = reason.userMessage
        finishLocalRecognition(with: nil)
    }

    private func startLocalRecognitionTimeout() {
        localRecognitionTimeoutTask?.cancel()
        localRecognitionTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.localRecognitionTimeout ?? .seconds(20))
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.activeLocalContinuation != nil else { return }
                self.failLocalRecognition(.localFailed("Transcription timed out. Please try again."))
            }
        }
    }

    private func handleLocalRecognitionCancellation() {
        recognitionTask?.cancel()
        failLocalRecognition(.localFailed("Transcription was cancelled."))
    }

    private func transcribeLocally(at url: URL) async -> String? {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            failureReason = .localFailed("Speech recognition is not available.")
            errorMessage = "Speech recognition is not available."
            return nil
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        localRecognitionTimeoutTask?.cancel()
        localRecognitionTimeoutTask = nil
        activeLocalContinuation = nil

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let continuationGuard = ContinuationGuard<String?>(continuation) { [weak self] in
                    self?.localRecognitionTimeoutTask?.cancel()
                    self?.localRecognitionTimeoutTask = nil
                }
                activeLocalContinuation = continuationGuard
                startLocalRecognitionTimeout()

                recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            continuationGuard.resume(returning: nil)
                            return
                        }

                        if let result {
                            self.transcribedText = result.bestTranscription.formattedString
                            if result.isFinal {
                                self.updateSegmentConfidence(from: result)
                                self.finishLocalRecognition(with: result.bestTranscription.formattedString)
                            }
                            return
                        }

                        if let error {
                            self.failLocalRecognition(.localFailed("Transcription failed: \(error.localizedDescription)"))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.handleLocalRecognitionCancellation()
            }
        }
    }

    func startLiveTranscription(engine: AVAudioEngine) {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available."
            return
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        transcribedText = ""
        errorMessage = nil
        isTranscribing = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        do {
            try engine.start()
        } catch {
            errorMessage = "Could not start audio engine for transcription."
            isTranscribing = false
            return
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                if let result {
                    self?.transcribedText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self?.updateSegmentConfidence(from: result)
                        self?.isTranscribing = false
                    }
                }
                if error != nil {
                    self?.isTranscribing = false
                    engine.stop()
                    inputNode.removeTap(onBus: 0)
                }
            }
        }
    }

    func stopLiveTranscription(engine: AVAudioEngine) {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        recognitionTask?.finish()
        recognitionTask = nil
        isTranscribing = false
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        isTranscribing = false
    }

    private func updateSegmentConfidence(from result: SFSpeechRecognitionResult) {
        let segments: [TranscriptSegment] = result.bestTranscription.segments.compactMap { segment in
            let trimmed = segment.substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return TranscriptSegment(
                text: trimmed,
                confidence: Double(segment.confidence),
                timestamp: segment.timestamp,
                duration: segment.duration
            )
        }

        transcriptSegments = segments
        lowConfidenceSegments = segments.filter { $0.confidence < 0.5 }
        if segments.isEmpty {
            averageSegmentConfidence = 1.0
        } else {
            let totalConfidence = segments.reduce(0.0) { partialResult, segment in
                partialResult + segment.confidence
            }
            averageSegmentConfidence = totalConfidence / Double(segments.count)
        }
    }
}

