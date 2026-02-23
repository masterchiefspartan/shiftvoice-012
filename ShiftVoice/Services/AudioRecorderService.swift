import AVFoundation
import Accelerate

@Observable
final class AudioRecorderService: NSObject, AVAudioRecorderDelegate {
    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0
    var audioLevels: [CGFloat] = Array(repeating: 0.05, count: 30)
    var currentAudioURL: URL?
    var errorMessage: String?
    var didAutoStop: Bool = false

    private var audioRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var durationTimer: Timer?
    private var levelHistory: [CGFloat] = []

    private var recordingDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftVoiceRecordings", isDirectory: true)
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() {
        errorMessage = nil
        didAutoStop = false

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
            levelHistory = []
            startMetering()
            startDurationTimer()
        } catch {
            errorMessage = "Could not start recording."
        }
    }

    func stopRecording() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        audioRecorder?.stop()
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {}
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
                self.recordingDuration += 1
                if self.recordingDuration >= 180 {
                    self.didAutoStop = true
                    self.stopRecording()
                }
            }
        }
    }

    func deleteRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            isRecording = false
            if !flag {
                errorMessage = "Recording finished unexpectedly."
            }
        }
    }
}
