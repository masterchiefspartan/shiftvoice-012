import Speech
import AVFoundation

nonisolated struct TranscribeResponse: Codable, Sendable {
    let success: Bool
    let text: String?
    let language: String?
    let error: String?
}

nonisolated enum TranscriptionFailureReason: Sendable {
    case noAudioFile
    case emptyAudioFile
    case corruptAudioFile
    case cloudFailed
    case localFailed(String)
    case noResult

    var userMessage: String {
        switch self {
        case .noAudioFile:
            return "No audio file found. The recording may not have saved."
        case .emptyAudioFile:
            return "The recording appears to be empty (zero length)."
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

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?

    private let cloudSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

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
        case corrupt
    }

    func validateAudioFile(at url: URL) -> AudioValidationResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > 0 else { return .empty }
        guard AVURLAsset(url: url).isPlayable else { return .corrupt }
        return .valid
    }

    func transcribeAudioFile(at url: URL, authToken: String? = nil, userId: String? = nil) async -> String? {
        isTranscribing = true
        transcribedText = ""
        errorMessage = nil
        usedCloudTranscription = false
        failureReason = nil

        switch validateAudioFile(at: url) {
        case .missing:
            failureReason = .noAudioFile
            errorMessage = TranscriptionFailureReason.noAudioFile.userMessage
            isTranscribing = false
            return nil
        case .empty:
            failureReason = .emptyAudioFile
            errorMessage = TranscriptionFailureReason.emptyAudioFile.userMessage
            isTranscribing = false
            return nil
        case .corrupt:
            failureReason = .corruptAudioFile
            errorMessage = TranscriptionFailureReason.corruptAudioFile.userMessage
            isTranscribing = false
            return nil
        case .valid:
            break
        }

        if !baseURL.isEmpty {
            if let cloudResult = await transcribeViaCloud(audioURL: url, authToken: authToken, userId: userId) {
                usedCloudTranscription = true
                transcribedText = cloudResult
                isTranscribing = false
                return cloudResult
            }
        }

        let localResult = await transcribeLocally(at: url)
        if localResult == nil && failureReason == nil {
            failureReason = .noResult
            errorMessage = TranscriptionFailureReason.noResult.userMessage
        }
        isTranscribing = false
        return localResult
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

        init(_ continuation: CheckedContinuation<T, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            lock.lock()
            defer { lock.unlock() }
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }
    }

    private func transcribeLocally(at url: URL) async -> String? {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            failureReason = .localFailed("Speech recognition is not available.")
            errorMessage = "Speech recognition is not available."
            return nil
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return await withCheckedContinuation { continuation in
            let guard_ = ContinuationGuard<String?>(continuation)
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    if let result {
                        self?.transcribedText = result.bestTranscription.formattedString
                        if result.isFinal {
                            guard_.resume(returning: result.bestTranscription.formattedString)
                        }
                    } else if let error {
                        self?.failureReason = .localFailed("Transcription failed: \(error.localizedDescription)")
                        self?.errorMessage = "Transcription failed: \(error.localizedDescription)"
                        guard_.resume(returning: nil)
                    }
                }
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
}
