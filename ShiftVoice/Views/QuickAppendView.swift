import SwiftUI
import AVFoundation

struct QuickAppendView: View {
    let noteId: String
    let viewModel: AppViewModel
    let onAppend: ([CategorizedItem], [ActionItem]) -> Void

    @State private var recorder = AudioRecorderService()
    @State private var transcription = TranscriptionService()
    @State private var isProcessing: Bool = false
    @State private var processingStage: ProcessingStage = .transcribing
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let noteStructuring = NoteStructuringService.shared
    private let maxDuration: TimeInterval = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isProcessing {
                    appendProcessingView
                } else {
                    appendRecordingView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SVTheme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Add to Note")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        recorder.stopRecording()
                        dismiss()
                    }
                    .foregroundStyle(SVTheme.textSecondary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onChange(of: recorder.recordingDuration) { _, newValue in
                if newValue >= maxDuration && recorder.isRecording {
                    stopAndProcess()
                }
            }
        }
    }

    private var appendRecordingView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(SVTheme.accent)
                Text("Quick Voice Append")
                    .font(.headline)
                    .foregroundStyle(SVTheme.textPrimary)
                Text("Record up to 30 seconds to add items")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            if recorder.isRecording {
                HStack(spacing: 3) {
                    ForEach(0..<30, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(SVTheme.accent.opacity(0.5))
                            .frame(width: 3, height: max(3, recorder.audioLevels[index] * 36))
                    }
                }
                .frame(height: 40)

                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .foregroundStyle(SVTheme.accent)

                HStack(spacing: 4) {
                    Circle()
                        .fill(SVTheme.accent)
                        .frame(width: 4, height: 4)
                    Text("\(Int(maxDuration - recorder.recordingDuration))s remaining")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }

            Button {
                if recorder.isRecording {
                    stopAndProcess()
                } else {
                    startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? SVTheme.urgentRed : SVTheme.accent)
                        .frame(width: 72, height: 72)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: recorder.isRecording)

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(SVTheme.urgentRed)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
    }

    private var appendProcessingView: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .controlSize(.large)
                .tint(SVTheme.accent)

            VStack(spacing: 6) {
                switch processingStage {
                case .transcribing:
                    Text("Transcribing…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("Converting speech to text")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                case .structuring:
                    Text("Extracting items…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("Categorizing new action items")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                case .finalizing:
                    Text("Adding to note…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("Almost done")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }

            Spacer()
        }
    }

    private func startRecording() {
        errorMessage = nil
        recorder.startRecording()
    }

    private func stopAndProcess() {
        let audioURL = recorder.currentAudioURL
        let liveText = transcription.transcribedText
        recorder.stopRecording()
        isProcessing = true

        Task {
            await processAppend(audioURL: audioURL, liveText: liveText)
        }
    }

    private func processAppend(audioURL: URL?, liveText: String) async {
        var transcript = ""

        let hasLive = !liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasLive {
            transcript = liveText
        } else {
            processingStage = .transcribing
            if let url = audioURL {
                let isValid = await transcription.validateBeforeTranscription(at: url)
                guard isValid else {
                    errorMessage = transcription.failureReason?.userMessage ?? "Unable to transcribe this recording."
                    isProcessing = false
                    return
                }
                if let result = await transcription.transcribeAudioFile(at: url, authToken: viewModel.backendAuthToken, userId: viewModel.currentUserId) {
                    transcript = result
                }
            }
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "No speech detected. Try again."
            isProcessing = false
            return
        }

        processingStage = .structuring
        let businessType = viewModel.organizationBusinessType.rawValue.lowercased()

        let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
            group.addTask {
                await self.noteStructuring.structureTranscript(
                    transcript,
                    businessType: businessType,
                    authToken: self.viewModel.backendAuthToken,
                    userId: self.viewModel.currentUserId
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

        var newCategories: [CategorizedItem]
        var newActions: [ActionItem]

        switch aiResult {
        case .success(let result):
            newCategories = result.categorizedItems
            newActions = result.actionItems
        case .failure, .none:
            newCategories = TranscriptProcessor.generateCategories(from: transcript)
            newActions = TranscriptProcessor.generateActionItems(from: newCategories)
        }

        processingStage = .finalizing

        onAppend(newCategories, newActions)
        dismiss()
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let s = Int(duration)
        return "0:\(String(format: "%02d", s))"
    }
}
