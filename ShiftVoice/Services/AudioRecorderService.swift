import AVFoundation
import Accelerate
import UIKit
import OSLog

@Observable
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0
    var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 30)
    var currentAudioURL: URL?
    var errorMessage: String?
    var didAutoStop: Bool = false
    var autoStopWarningActive: Bool = false
    var micSilent: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var levelHistory: [CGFloat] = []
    private var silentFrameCount: Int = 0
    private let silentThreshold: CGFloat = 0.08
    private let silentFrameLimit: Int = 60 // 3 seconds at 20fps metering
    private var recordingStartedAt: Date?
    private var didEmitAutoStopWarning: Bool = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var stopRecordingContinuation: CheckedContinuation<URL?, Never>?
    private var hasResumedStopRecordingContinuation: Bool = false
    private var pendingStopRecordingURL: URL?
    private var stopRecordingFallbackTask: Task<Void, Never>?
    private let stopRecordingWaitWindow: Duration = .seconds(2)
    private let stopRecordingFallbackDelay: Duration = .milliseconds(600)
    private let fileFinalizationPollInterval: Duration = .milliseconds(120)
    private let fileFinalizationPollAttempts: Int = 12
    private let minimumExpectedRecordedBytes: UInt64 = 256
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShiftVoice", category: "AudioRecorder")

    private var recordingDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftVoiceRecordings", isDirectory: true)
    }

    func hasMicrophonePermission() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    func isMicrophonePermissionDenied() -> Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    func requestPermissionIfNeeded() async -> Bool {
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func startRecording() {
        errorMessage = nil
        didAutoStop = false
        autoStopWarningActive = false
        micSilent = false
        silentFrameCount = 0
        didEmitAutoStopWarning = false

        do {
            try FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Could not create recordings directory."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Could not configure audio session."
            return
        }

        let filename = "shift_note_\(Int(Date().timeIntervalSince1970)).m4a"
        let fileURL = recordingDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            currentAudioURL = fileURL
            isRecording = true
            recordingDuration = 0
            recordingStartedAt = Date()
            levelHistory = []
            startMetering()
            startDurationTimer()
            registerLifecycleObserversIfNeeded()
        } catch {
            errorMessage = "Could not start recording."
        }
    }

    func stopRecording() {
        stopRecordingNow()
    }

    func stopRecordingAndAwaitFinalizedFile() async -> URL? {
        let candidateURL = currentAudioURL
        stopRecordingNow()

        guard let candidateURL else {
            return nil
        }

        if await isAudioFileReady(at: candidateURL) {
            return candidateURL
        }

        return await withCheckedContinuation { continuation in
            stopRecordingFallbackTask?.cancel()
            stopRecordingContinuation = continuation
            hasResumedStopRecordingContinuation = false
            pendingStopRecordingURL = candidateURL
            stopRecordingFallbackTask = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: stopRecordingWaitWindow)
                await self.resumeStopRecordingContinuationIfNeeded(with: candidateURL)
            }
        }
    }

    private func startMetering() {
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMeters()
            }
        }
    }

    private func updateMeters() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()

        let power = recorder.averagePower(forChannel: 0)
        let normalizedLevel = CGFloat(max(0, (power + 50) / 50))
        let smoothed = max(0.05, normalizedLevel)

        if smoothed < silentThreshold {
            silentFrameCount += 1
        } else {
            silentFrameCount = 0
        }
        micSilent = silentFrameCount >= silentFrameLimit

        levelHistory.append(smoothed)
        if levelHistory.count > 30 {
            levelHistory.removeFirst(levelHistory.count - 30)
        }

        var newLevels = Array(repeating: CGFloat(0.05), count: 30)
        let startIndex = 30 - levelHistory.count
        for (i, level) in levelHistory.enumerated() {
            newLevels[startIndex + i] = level
        }
        audioLevels = newLevels
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.syncRecordingTimeAndThresholds()
            }
        }
    }

    private func syncRecordingTimeAndThresholds() {
        guard isRecording else { return }

        let elapsedFromWallClock = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingDuration = max(recordingDuration, elapsedFromWallClock)

        if recordingDuration >= 180 {
            autoStopWarningActive = false
            didAutoStop = true
            stopRecording()
            return
        }

        if recordingDuration >= 150 {
            autoStopWarningActive = true
            didEmitAutoStopWarning = true
        }
    }

    private func registerLifecycleObserversIfNeeded() {
        guard lifecycleObservers.isEmpty else { return }

        let notificationCenter = NotificationCenter.default
        let names: [NSNotification.Name] = [
            UIApplication.didBecomeActiveNotification,
            UIApplication.willEnterForegroundNotification
        ]

        lifecycleObservers = names.map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, self.isRecording else { return }
                self.syncRecordingTimeAndThresholds()
            }
        }
    }

    private func unregisterLifecycleObservers() {
        let notificationCenter = NotificationCenter.default
        for observer in lifecycleObservers {
            notificationCenter.removeObserver(observer)
        }
        lifecycleObservers.removeAll()
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
            autoStopWarningActive = false
            recordingStartedAt = nil
            unregisterLifecycleObservers()
            if !flag {
                errorMessage = "Recording finished unexpectedly."
            }

            let finalizedURL = pendingStopRecordingURL ?? currentAudioURL
            if let finalizedURL {
                stopRecordingFallbackTask?.cancel()
                stopRecordingFallbackTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    if await self.isAudioFileReady(at: finalizedURL) {
                        await self.resumeStopRecordingContinuationIfNeeded(with: finalizedURL)
                        return
                    }
                    try? await Task.sleep(for: stopRecordingFallbackDelay)
                    await self.resumeStopRecordingContinuationIfNeeded(with: finalizedURL)
                }
            } else {
                await resumeStopRecordingContinuationIfNeeded(with: nil)
            }
        }
    }

    private func stopRecordingNow() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        audioRecorder?.stop()
        isRecording = false
        autoStopWarningActive = false
        recordingStartedAt = nil
        unregisterLifecycleObservers()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {}
    }

    private func isAudioFileReady(at url: URL) async -> Bool {
        let fileManager = FileManager.default
        for _ in 0..<fileFinalizationPollAttempts {
            guard fileManager.fileExists(atPath: url.path),
                  let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? UInt64,
                  size >= minimumExpectedRecordedBytes else {
                try? await Task.sleep(for: fileFinalizationPollInterval)
                continue
            }

            let asset = AVURLAsset(url: url)
            if let isPlayable = try? await asset.load(.isPlayable), isPlayable {
                return true
            }

            try? await Task.sleep(for: fileFinalizationPollInterval)
        }

        logger.error("Recorded file was not ready in wait window for \(url.lastPathComponent, privacy: .public)")
        return false
    }

    private func resumeStopRecordingContinuationIfNeeded(with url: URL?) async {
        guard !hasResumedStopRecordingContinuation else { return }
        hasResumedStopRecordingContinuation = true
        pendingStopRecordingURL = nil
        stopRecordingFallbackTask?.cancel()
        stopRecordingFallbackTask = nil
        let continuation = stopRecordingContinuation
        stopRecordingContinuation = nil
        continuation?.resume(returning: url)
    }
}
