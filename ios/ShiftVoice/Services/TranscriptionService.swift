import AVFoundation
import OSLog

nonisolated struct TranscribeResponse: Codable, Sendable {
    let success: Bool
    let text: String?
    let language: String?
    let error: String?
}

nonisolated struct ToolkitSTTResponse: Codable, Sendable {
    let text: String?
    let language: String?
}

nonisolated struct TranscriptionErrorResponse: Codable, Sendable {
    let success: Bool?
    let error: String?
    let code: String?
}

nonisolated enum TranscriptionFailureReason: Sendable, Equatable {
    case noAudioFile
    case emptyAudioFile
    case audioTooShort(minimum: TimeInterval, actual: TimeInterval)
    case unsupportedAudioFormat
    case corruptAudioFile
    case noConnection
    case rateLimited
    case quotaExceeded
    case fileTooLarge
    case durationExceeded
    case unauthorized
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
        case .noConnection:
            return "No connection — transcription requires internet."
        case .rateLimited:
            return "Transcription is busy right now. Please retry in a moment."
        case .quotaExceeded:
            return "Transcription quota exhausted. Please try again later."
        case .fileTooLarge:
            return "Recording is too large to transcribe (max 25MB)."
        case .durationExceeded:
            return "Recording is too long. Please keep it under 3 minutes."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .cloudFailed:
            return "Cloud transcription failed."
        case .noResult:
            return "No speech was detected in the recording."
        }
    }
}

@Observable
final class TranscriptionService {
    private struct AttemptContext {
        let id: String
        let source: String
    }
    var transcribedText: String = ""
    var isTranscribing: Bool = false
    var errorMessage: String?
    var usedCloudTranscription: Bool = true
    var failureReason: TranscriptionFailureReason?

    private let cloudSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config)
    }()

    private let toolkitSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
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

    private var toolkitURL: String {
        let url = Config.EXPO_PUBLIC_TOOLKIT_URL
        if url.isEmpty || url == "EXPO_PUBLIC_TOOLKIT_URL" { return "" }
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

    func transcribeAudioFile(at url: URL, durationSeconds: TimeInterval? = nil, authToken: String? = nil, userId: String? = nil, industryVocabulary: [String] = [], attemptId: String? = nil, source: String = "record") async -> String? {
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

        let context = AttemptContext(id: attemptId ?? UUID().uuidString, source: source)
        logger.info("Transcription pipeline started attempt=\(context.id, privacy: .public) source=\(context.source, privacy: .public)")

        let result = await transcribeViaCloud(
            audioURL: url,
            durationSeconds: durationSeconds,
            authToken: authToken,
            userId: userId,
            industryVocabulary: industryVocabulary,
            shouldAttemptUnauthorizedRecovery: true,
            context: context
        )

        if let result {
            transcribedText = result
            isTranscribing = false
            return result
        }

        let backendFailure = failureReason
        if backendFailure == .cloudFailed || backendFailure == nil {
            logger.info("Transcription attempt=\(context.id, privacy: .public) backend failed, trying toolkit fallback")
            failureReason = nil
            errorMessage = nil

            let audioData: Data? = try? Data(contentsOf: url)
            if let audioData {
                let toolkitResult = await transcribeViaToolkit(audioData: audioData, audioURL: url, context: context)
                if let toolkitResult {
                    transcribedText = toolkitResult
                    isTranscribing = false
                    return toolkitResult
                }
            }

            if failureReason == nil {
                failureReason = backendFailure ?? .cloudFailed
                errorMessage = (backendFailure ?? .cloudFailed).userMessage
            }
        }

        if failureReason == nil {
            failureReason = .noResult
            errorMessage = TranscriptionFailureReason.noResult.userMessage
        }

        isTranscribing = false
        return nil
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

    private func transcribeViaToolkit(audioData: Data, audioURL: URL, context: AttemptContext) async -> String? {
        guard !toolkitURL.isEmpty else {
            logger.error("Toolkit STT attempt=\(context.id, privacy: .public) skipped: no toolkit URL configured")
            return nil
        }

        let sttEndpoint = toolkitURL.hasSuffix("/") ? "\(toolkitURL)stt/transcribe/" : "\(toolkitURL)/stt/transcribe/"
        guard let url = URL(string: sttEndpoint) else {
            logger.error("Toolkit STT attempt=\(context.id, privacy: .public) skipped: invalid URL")
            return nil
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

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

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        logger.info("Toolkit STT attempt=\(context.id, privacy: .public) sending request")

        do {
            let (data, response) = try await toolkitSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Toolkit STT attempt=\(context.id, privacy: .public) invalid response")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Toolkit STT attempt=\(context.id, privacy: .public) failed status=\(httpResponse.statusCode, privacy: .public)")
                return nil
            }

            let result = try JSONDecoder().decode(ToolkitSTTResponse.self, from: data)
            guard let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                logger.info("Toolkit STT attempt=\(context.id, privacy: .public) returned empty text")
                failureReason = .noResult
                errorMessage = TranscriptionFailureReason.noResult.userMessage
                return nil
            }

            logger.info("Toolkit STT attempt=\(context.id, privacy: .public) succeeded")
            return text
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                    failureReason = .noConnection
                    errorMessage = TranscriptionFailureReason.noConnection.userMessage
                default:
                    break
                }
            }
            logger.error("Toolkit STT attempt=\(context.id, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func transcribeViaCloud(
        audioURL: URL,
        durationSeconds: TimeInterval?,
        authToken: String?,
        userId: String?,
        industryVocabulary: [String],
        shouldAttemptUnauthorizedRecovery: Bool,
        context: AttemptContext
    ) async -> String? {
        guard !baseURL.isEmpty else {
            failureReason = .cloudFailed
            errorMessage = "Transcription service is not configured yet. Please update the app and try again."
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

        let apiToken = APIService.shared.currentAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiUserId = APIService.shared.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedToken = apiToken?.isEmpty == false ? apiToken : authToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedUserId = apiUserId?.isEmpty == false ? apiUserId : userId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if (trimmedToken?.isEmpty ?? true) || (trimmedUserId?.isEmpty ?? true) {
            trimmedToken = APIService.shared.currentAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
            trimmedUserId = APIService.shared.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if ((trimmedToken?.isEmpty ?? true) || (trimmedUserId?.isEmpty ?? true)) && shouldAttemptUnauthorizedRecovery {
            logger.info("Transcription attempt=\(context.id, privacy: .public) missing auth, triggering recovery")
            let recovered = await APIService.shared.recoverUnauthorizedSessionIfNeeded()
            if recovered {
                trimmedToken = APIService.shared.currentAuthToken?.trimmingCharacters(in: .whitespacesAndNewlines)
                trimmedUserId = APIService.shared.currentUserId?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let token = trimmedToken, !token.isEmpty, let uid = trimmedUserId, !uid.isEmpty else {
            logger.error("Transcription attempt=\(context.id, privacy: .public) failed due to missing auth after recovery")
            failureReason = .cloudFailed
            errorMessage = "Could not authenticate with transcription server. Trying fallback..."
            return nil
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(uid, forHTTPHeaderField: "X-User-Id")

        let filename = audioURL.lastPathComponent
        let mimeType = filename.hasSuffix(".m4a") ? "audio/m4a" : "audio/\(audioURL.pathExtension)"
        let resolvedDurationSeconds: TimeInterval
        if let durationSeconds {
            resolvedDurationSeconds = durationSeconds
        } else {
            resolvedDurationSeconds = await measuredDurationSeconds(for: audioURL)
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)

        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en".data(using: .utf8)!)

        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"durationSeconds\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(resolvedDurationSeconds)".data(using: .utf8)!)

        let prompt = buildWhisperPrompt(industryVocabulary: industryVocabulary)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
        body.append(prompt.data(using: .utf8)!)

        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await cloudSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                failureReason = .cloudFailed
                errorMessage = TranscriptionFailureReason.cloudFailed.userMessage
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    if shouldAttemptUnauthorizedRecovery,
                       await APIService.shared.recoverUnauthorizedSessionIfNeeded() {
                        logger.info("Transcription attempt=\(context.id, privacy: .public) recovered from backend 401, retrying once")
                        return await transcribeViaCloud(
                            audioURL: audioURL,
                            durationSeconds: durationSeconds,
                            authToken: APIService.shared.currentAuthToken,
                            userId: APIService.shared.currentUserId,
                            industryVocabulary: industryVocabulary,
                            shouldAttemptUnauthorizedRecovery: false,
                            context: context
                        )
                    }
                    failureReason = .cloudFailed
                    errorMessage = "Backend authentication failed. Trying fallback..."
                    return nil
                }
                if httpResponse.statusCode == 503 {
                    logger.error("Transcription attempt=\(context.id, privacy: .public) backend unavailable (503)")
                    failureReason = .cloudFailed
                    errorMessage = "Backend temporarily unavailable. Trying fallback..."
                    return nil
                }
                if let backendError = try? JSONDecoder().decode(TranscriptionErrorResponse.self, from: data) {
                    let mappedReason = mapBackendFailureReason(code: backendError.code)
                    failureReason = mappedReason
                    errorMessage = backendError.error.flatMap { mappedReason == .cloudFailed ? $0 : nil } ?? mappedReason.userMessage
                    logger.error("Transcription attempt=\(context.id, privacy: .public) failed status=\(httpResponse.statusCode, privacy: .public) code=\(backendError.code ?? "NONE", privacy: .public) mapped=\(String(describing: mappedReason), privacy: .public)")
                    return nil
                }
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
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                    failureReason = .noConnection
                    errorMessage = TranscriptionFailureReason.noConnection.userMessage
                case .timedOut:
                    failureReason = .cloudFailed
                    errorMessage = "Backend timed out. Trying fallback..."
                case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                    failureReason = .cloudFailed
                    errorMessage = "Could not reach backend. Trying fallback..."
                default:
                    failureReason = .cloudFailed
                    errorMessage = "Cloud transcription failed. Trying fallback..."
                }
                return nil
            }
            failureReason = .cloudFailed
            errorMessage = "Cloud transcription failed. Trying fallback..."
            return nil
        }
    }

    nonisolated static func mapBackendFailureReason(code: String?) -> TranscriptionFailureReason {
        switch code {
        case "STT_RATE_LIMITED":
            return .rateLimited
        case "STT_QUOTA_EXCEEDED":
            return .quotaExceeded
        case "STT_FILE_TOO_LARGE":
            return .fileTooLarge
        case "STT_DURATION_EXCEEDED":
            return .durationExceeded
        case "UNAUTHORIZED":
            return .unauthorized
        default:
            return .cloudFailed
        }
    }

    private func mapBackendFailureReason(code: String?) -> TranscriptionFailureReason {
        Self.mapBackendFailureReason(code: code)
    }

    private func buildWhisperPrompt(industryVocabulary: [String]) -> String {
        WhisperPromptBuilder.build(from: industryVocabulary)
    }

    private func measuredDurationSeconds(for audioURL: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: audioURL)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else { return 0 }
            return seconds
        } catch {
            return 0
        }
    }

    func cancel() {
        isTranscribing = false
    }
}
