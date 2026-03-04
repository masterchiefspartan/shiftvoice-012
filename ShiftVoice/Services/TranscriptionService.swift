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
        case .noResult:
            return "No speech was detected in the recording."
        }
    }
}

@Observable
final class TranscriptionService {
    var transcribedText: String = ""
    var isTranscribing: Bool = false
    var errorMessage: String?
    var usedCloudTranscription: Bool = true
    var failureReason: TranscriptionFailureReason?

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

    func transcribeAudioFile(at url: URL, authToken: String? = nil, userId: String? = nil, industryVocabulary: [String] = []) async -> String? {
        isTranscribing = true
        transcribedText = ""
        errorMessage = nil
        usedCloudTranscription = true
        failureReason = nil

        let validationResult = await validateAudioFile(at: url)
        guard handleValidationResult(validationResult, for: url) else {
            isTranscribing = false
            return nil
        }

        let result = await transcribeViaCloud(audioURL: url, authToken: authToken, userId: userId, industryVocabulary: industryVocabulary)
        if let result {
            transcribedText = result
        } else if failureReason == nil {
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

    private func transcribeViaCloud(audioURL: URL, authToken: String?, userId: String?, industryVocabulary: [String]) async -> String? {
        guard !baseURL.isEmpty else {
            failureReason = .cloudFailed
            errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
            return nil
        }
        guard let endpoint = URL(string: "\(baseURL)/api/rest/transcribe") else {
            failureReason = .cloudFailed
            errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
            return nil
        }

        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            failureReason = .cloudFailed
            errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
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

        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en".data(using: .utf8)!)

        let prompt = buildWhisperPrompt(industryVocabulary: industryVocabulary)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append(prompt.data(using: .utf8)!)

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await cloudSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                failureReason = .cloudFailed
                errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
                return nil
            }

            let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
            guard result.success, let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failureReason = .noResult
                errorMessage = TranscriptionFailureReason.noResult.userMessage
                return nil
            }

            return text
        } catch {
            failureReason = .cloudFailed
            errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
            return nil
        }
    }

    private func buildWhisperPrompt(industryVocabulary: [String]) -> String {
        WhisperPromptBuilder.build(from: industryVocabulary)
    }

    func cancel() {
        isTranscribing = false
    }
}
