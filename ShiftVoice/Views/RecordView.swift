import SwiftUI

struct RecordView: View {
    @Bindable var viewModel: AppViewModel
    @State private var selectedShiftDisplay: ShiftDisplayInfo? = nil
    @State private var showSuccess: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var permissionGranted: Bool = true
    @State private var showPermissionAlert: Bool = false
    @State private var showPaywall: Bool = false
    @State private var showReview: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let subscription = SubscriptionService.shared

    private var currentShiftDisplay: ShiftDisplayInfo {
        selectedShiftDisplay ?? viewModel.currentShiftDisplayInfo
    }

    var body: some View {
        Group {
            if showReview, let reviewData = viewModel.pendingReviewData {
                NoteReviewView(
                    viewModel: viewModel,
                    rawTranscript: reviewData.rawTranscript,
                    audioDuration: reviewData.audioDuration,
                    audioUrl: reviewData.audioUrl,
                    shiftInfo: reviewData.shiftInfo,
                    summary: reviewData.summary,
                    categorizedItems: reviewData.categorizedItems,
                    actionItems: reviewData.actionItems,
                    onDiscard: {
                        viewModel.discardPendingNote()
                        dismiss()
                    },
                    onPublish: { note in
                        viewModel.publishReviewedNote(note)
                        showReview = false
                        showSuccess = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            showSuccess = false
                            dismiss()
                        }
                    }
                )
            } else {
                recordingFlow
            }
        }
    }

    private var recordingFlow: some View {
        NavigationStack {
            ZStack {
                SVTheme.background.ignoresSafeArea()

                if viewModel.isProcessing {
                    processingView
                } else if showSuccess {
                    successView
                } else {
                    recordingInterface
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("New Note")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Permissions Required", isPresented: $showPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("ShiftVoice needs microphone and speech recognition access to record and transcribe your shift notes. Please enable them in Settings.")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task {
                let granted = await viewModel.requestRecordingPermissions()
                permissionGranted = granted
            }
            .onChange(of: viewModel.audioRecorder.didAutoStop) { _, didAutoStop in
                if didAutoStop {
                    stopRecording()
                }
            }
            .onChange(of: viewModel.isProcessing) { oldValue, newValue in
                if oldValue && !newValue && viewModel.pendingReviewData != nil {
                    showReview = true
                }
            }
        }
    }

    private var recordingInterface: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Record Note")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .tracking(-0.5)

                Text(viewModel.selectedLocation?.name ?? "")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(viewModel.availableShifts) { shift in
                    Button {
                        selectedShiftDisplay = shift
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: shift.icon)
                                .font(.caption2)
                            Text(shift.name)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(currentShiftDisplay.id == shift.id ? SVTheme.textPrimary : SVTheme.surface)
                        .foregroundStyle(currentShiftDisplay.id == shift.id ? .white : SVTheme.textSecondary)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(currentShiftDisplay.id == shift.id ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.top, 24)

            Spacer()

            if viewModel.isRecording {
                liveTranscriptView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                waveformDisplay
                    .padding(.bottom, 24)
            }

            ZStack {
                if viewModel.isRecording && !reduceMotion {
                    Circle()
                        .stroke(SVTheme.urgentRed.opacity(0.12), lineWidth: 1)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                    Circle()
                        .stroke(SVTheme.urgentRed.opacity(0.06), lineWidth: 1)
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulseScale * 0.95)
                }

                Button {
                    if viewModel.isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? SVTheme.urgentRed : SVTheme.textPrimary)
                            .frame(width: 88, height: 88)

                        if viewModel.isRecording {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.white)
                                .frame(width: 26, height: 26)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: viewModel.isRecording)
            }
            .frame(height: 160)

            if viewModel.isRecording {
                VStack(spacing: 4) {
                    Text(formatDuration(viewModel.recordingDuration))
                        .font(.system(.title2, design: .monospaced).weight(.medium))
                        .foregroundStyle(SVTheme.urgentRed)
                    Text("3:00 max")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(.top, 16)
            } else {
                VStack(spacing: 4) {
                    Text("Tap to record")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("Record your shift handoff notes")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(.top, 16)
            }

            Spacer()

            if let error = viewModel.audioRecorder.errorMessage ?? viewModel.transcriptionService.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                }
                .foregroundStyle(SVTheme.amber)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }

            HStack(spacing: 32) {
                tipItem(icon: "hand.raised", text: "One-hand friendly")
                tipItem(icon: "clock", text: "Under 3 min")
                tipItem(icon: "sparkles", text: "AI structures it")
            }
            .padding(.bottom, 32)
        }
    }

    private var liveTranscriptView: some View {
        Group {
            if !viewModel.transcriptionService.transcribedText.isEmpty {
                ScrollView {
                    Text(viewModel.transcriptionService.transcribedText)
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .padding(12)
                .background(SVTheme.surfaceSecondary)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                )
            }
        }
    }

    private var waveformDisplay: some View {
        HStack(spacing: 3) {
            ForEach(0..<30, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SVTheme.urgentRed.opacity(0.5))
                    .frame(width: 3, height: max(3, viewModel.audioLevels[index] * 36))
            }
        }
        .frame(height: 40)
    }

    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(SVTheme.divider, lineWidth: 3)
                    .frame(width: 72, height: 72)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(SVTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(reduceMotion ? 0 : 360))
                    .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: reduceMotion)
            }

            VStack(spacing: 6) {
                Text("Processing your shift notes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text("Transcribing audio and categorizing")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            if !viewModel.transcriptionService.transcribedText.isEmpty {
                Text(viewModel.transcriptionService.transcribedText)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SVTheme.successGreen)
                .symbolEffect(.bounce, value: showSuccess)

            VStack(spacing: 6) {
                Text("Shift Note Sent")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text("Your team will be notified")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            Spacer()
        }
    }

    private func tipItem(icon: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(SVTheme.textTertiary)
        }
    }

    private func startRecording() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        let thisMonthCount = viewModel.notesThisMonth
        if !subscription.canRecordNote(currentMonthNoteCount: thisMonthCount) {
            showPaywall = true
            return
        }
        viewModel.startRecording()
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }

    private func stopRecording() {
        pulseScale = 1.0
        viewModel.stopRecording(selectedShift: selectedShiftDisplay)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
