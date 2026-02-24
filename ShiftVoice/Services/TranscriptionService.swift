import Speech
import AVFoundation

nonisolated struct TranscribeResponse: Codable, Sendable {
    let success: Bool
    let text: String?
    let language: String?
    let error: String?
}

@Observable
final class TranscriptionService {
    var transcribedText: String = ""
    var isTranscribing: Bool = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    var errorMessage: String?
    var usedCloudTranscription: Bool = false

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

    func transcribeAudioFile(at url: URL, authToken: String? = nil, userId: String? = nil) async -> String? {
        isTranscribing = true
        transcribedText = ""
        errorMessage = nil
        usedCloudTranscription = false

        if !baseURL.isEmpty {
            if let cloudResult = await transcribeViaCloud(audioURL: url, authToken: authToken, userId: userId) {
                usedCloudTranscription = true
                transcribedText = cloudResult
                isTranscribing = false
                return cloudResult
            }
        }

        let localResult = await transcribeLocally(at: url)
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

    private func transcribeLocally(at url: URL) async -> String? {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available."
            return nil
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return await withCheckedContinuation { continuation in
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    if let result {
                        self?.transcribedText = result.bestTranscription.formattedString
                        if result.isFinal {
                            continuation.resume(returning: result.bestTranscription.formattedString)
                        }
                    } else if let error {
                        self?.errorMessage = "Transcription failed: \(error.localizedDescription)"
                        continuation.resume(returning: nil)
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
