import SwiftUI

struct RecordView: View {
    @Bindable var viewModel: AppViewModel
    @State private var selectedShiftDisplay: ShiftDisplayInfo? = nil
    @State private var showSuccess: Bool = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var permissionGranted: Bool = true
    @State private var showPermissionAlert: Bool = false

    @State private var showReview: Bool = false
    @State private var guidedPrompts: [RecordingPrompt] = []
    @State private var currentPromptIndex: Int = 0
    @State private var promptVisible: Bool = true
    @State private var promptRotationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let subscription = SubscriptionService.shared
    @State private var shouldResumeRecordingAfterPaywall: Bool = false
    @State private var allowVisibilityOverrideForThisRecording: Bool = false
    @AppStorage("defaultNoteVisibility") private var defaultVisibility: String = "team"

    private var recording: RecordingViewModel { viewModel.recording }

    private var resolvedDefaultVisibility: NoteVisibility {
        switch defaultVisibility {
        case "private":
            return .personal
        default:
            return .team
        }
    }

    private var shouldShowVisibilityToggle: Bool {
        defaultVisibility == "ask" || allowVisibilityOverrideForThisRecording
    }

    private var currentShiftDisplay: ShiftDisplayInfo {
        selectedShiftDisplay ?? viewModel.currentShiftDisplayInfo
    }

    private var isPrivateMode: Bool {
        recording.selectedVisibility == .personal
    }

    private var recordingModeTitle: String {
        isPrivateMode ? "Private Note" : "Team Handoff"
    }

    private var recordingModeSubtitle: String {
        isPrivateMode ? "Only you will see this note" : "Your team will receive this note"
    }

    private var recordingModeAccent: Color {
        isPrivateMode ? .indigo : SVTheme.accent
    }

    private var recordingModeBackground: Color {
        isPrivateMode ? Color.indigo.opacity(0.1) : SVTheme.surface
    }

    private var recordingModeBorder: Color {
        isPrivateMode ? Color.indigo.opacity(0.35) : SVTheme.surfaceBorder
    }

    private var recordingButtonHelperText: String {
        isPrivateMode ? "Recording private note" : "Recording team note"
    }

    var body: some View {
        recordingFlow
    }

    private var recordingFlow: some View {
        NavigationStack {
            ZStack {
                SVTheme.background.ignoresSafeArea()

                if recording.isProcessing {
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
            .navigationDestination(isPresented: $showReview) {
                if let reviewData = recording.pendingReviewData {
                    NoteReviewView(
                        viewModel: viewModel,
                        source: .record,
                        returnDestination: .inboxDetail,
                        rawTranscript: reviewData.rawTranscript,
                        audioDuration: reviewData.audioDuration,
                        audioUrl: reviewData.audioUrl,
                        shiftInfo: reviewData.shiftInfo,
                        summary: reviewData.summary,
                        categorizedItems: reviewData.categorizedItems,
                        actionItems: reviewData.actionItems,
                        visibility: recording.selectedVisibility,
                        structuringWarning: reviewData.structuringWarning,
                        recordingFailureState: reviewData.recordingFailureState,
                        confidenceScore: reviewData.confidenceScore,
                        validationWarnings: reviewData.validationWarnings,
                        warningItemIDs: reviewData.warningItemIDs,
                        usedAI: reviewData.usedAI,
                        onDiscard: {
                            showReview = false
                            recording.discardPendingNote()
                            dismiss()
                        },
                        onPublish: { note in
                            viewModel.publishReviewedNote(note)
                            guard viewModel.publishError == nil else {
                                return false
                            }
                            showReview = false
                            showSuccess = true
                            viewModel.completeReviewSession(noteId: note.id)
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                showSuccess = false
                                dismiss()
                            }
                            return true
                        }
                    )
                    .id(reviewData.rawTranscript + "|" + reviewData.summary)
                }
            }
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

            .task {
                let granted = await recording.requestRecordingPermissions()
                permissionGranted = granted
                recording.selectedVisibility = resolvedDefaultVisibility
                allowVisibilityOverrideForThisRecording = false
            }
            .onChange(of: defaultVisibility) { _, newValue in
                if newValue == "ask" {
                    allowVisibilityOverrideForThisRecording = false
                    return
                }
                recording.selectedVisibility = resolvedDefaultVisibility
                allowVisibilityOverrideForThisRecording = false
            }
            .onChange(of: recording.audioRecorder.didAutoStop) { _, didAutoStop in
                if didAutoStop {
                    stopRecording()
                }
            }
            .sensoryFeedback(.warning, trigger: recording.audioRecorder.autoStopWarningActive)
            .onChange(of: recording.isProcessing) { oldValue, newValue in
                if oldValue && !newValue && recording.pendingReviewData != nil {
                    viewModel.trackReviewFlowEvent(.enteredReview(source: .record, returnDestination: .inboxDetail))
                    showReview = true
                }
            }
            .onChange(of: viewModel.showPaywall) { oldValue, newValue in
                guard oldValue, !newValue, shouldResumeRecordingAfterPaywall else { return }
                shouldResumeRecordingAfterPaywall = false
                if subscription.canRecordNote(currentMonthNoteCount: viewModel.notesThisMonth) {
                    startRecording()
                }
            }
        }
    }

    private var recordingInterface: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(recordingModeTitle)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .tracking(-0.5)

                HStack(spacing: 8) {
                    Image(systemName: recording.selectedVisibility.icon)
                        .font(.caption.weight(.semibold))
                    Text(recordingModeSubtitle)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(recordingModeAccent)

                if !isPrivateMode {
                    Text(viewModel.selectedLocation?.name ?? "")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            HStack(spacing: 8) {
                ForEach(viewModel.availableShifts) { shift in
                    SVChip(
                        title: shift.name,
                        icon: shift.icon,
                        isSelected: currentShiftDisplay.id == shift.id
                    ) {
                        selectedShiftDisplay = shift
                    }
                }
            }
            .padding(.top, 24)

            Group {
                if shouldShowVisibilityToggle {
                    visibilityToggle
                } else {
                    lockedVisibilitySummary
                }
            }
            .padding(.top, 16)

            if isPrivateMode {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                    Text("Private mode is personal only and will not appear in Team Feed")
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                }
                .foregroundStyle(.indigo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.indigo.opacity(0.1))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.indigo.opacity(0.22), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.top, 10)
            }

            Spacer()

            if recording.isRecording {
                if !guidedPrompts.isEmpty && recording.transcriptionService.transcribedText.isEmpty {
                    guidedPromptBubble
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                liveTranscriptView
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                waveformDisplay
                    .padding(.bottom, 24)
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: recording.selectedVisibility.icon)
                        .font(.caption.weight(.semibold))
                    Text(recordingButtonHelperText.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.3)
                }
                .foregroundStyle(recordingModeAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(recordingModeBackground)
                .clipShape(.capsule)
                .overlay(
                    Capsule()
                        .stroke(recordingModeBorder, lineWidth: 1)
                )

                ZStack {
                    if recording.isRecording && !reduceMotion {
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
                        if recording.isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(recording.isRecording ? SVTheme.urgentRed : recordingModeAccent)
                                .frame(width: 88, height: 88)

                            if recording.isRecording {
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
                    .sensoryFeedback(.impact(weight: .heavy), trigger: recording.isRecording)
                }
                .frame(height: 120)
            }
            .frame(height: 160)

            if recording.isRecording {
                VStack(spacing: 4) {
                    Text(formatDuration(recording.recordingDuration))
                        .font(.system(.title2, design: .monospaced).weight(.medium))
                        .foregroundStyle(recording.audioRecorder.autoStopWarningActive ? SVTheme.amber : SVTheme.urgentRed)

                    if recording.audioRecorder.autoStopWarningActive {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Auto-stop in \(max(0, 180 - Int(recording.recordingDuration)))s")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(SVTheme.amber)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    } else {
                        Text("3:00 max")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    }

                    if recording.audioRecorder.micSilent {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.slash.fill")
                                .font(.caption2)
                            Text("No audio detected — check your microphone")
                                .font(.caption2)
                        }
                        .foregroundStyle(SVTheme.amber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(SVTheme.amber.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                        .transition(.opacity)
                    }
                }
                .padding(.top, 16)
                .animation(.easeInOut(duration: 0.3), value: recording.audioRecorder.autoStopWarningActive)
                .animation(.easeInOut(duration: 0.3), value: recording.audioRecorder.micSilent)
            } else {
                VStack(spacing: 4) {
                    Text("Tap to record")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text(isPrivateMode ? "Capture a private note for yourself" : "Record your shift handoff notes")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(.top, 16)
            }

            Spacer()

            if let error = recording.audioRecorder.errorMessage ?? recording.transcriptionService.errorMessage {
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
            if !recording.transcriptionService.transcribedText.isEmpty {
                ScrollView {
                    Text(recording.transcriptionService.transcribedText)
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
                    .frame(width: 3, height: max(3, recording.audioLevels[index] * 36))
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
                Text(processingTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text(processingSubtitle)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            if !recording.transcriptionService.transcribedText.isEmpty {
                Text(recording.transcriptionService.transcribedText)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }

            if recording.processingElapsed >= 15 {
                Button {
                    recording.cancelProcessing()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textSecondary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(SVTheme.surface)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: recording.processingElapsed >= 15)
    }

    private var processingTitle: String {
        if recording.processingElapsed >= 20 {
            return "Still working on it…"
        }
        guard let stage = recording.processingStage else {
            return fallbackProcessingTitle
        }
        switch stage {
        case .transcribing:
            return "Transcribing audio…"
        case .structuring:
            return "Extracting action items…"
        case .finalizing:
            return "Finalizing…"
        }
    }

    private var processingSubtitle: String {
        if recording.processingElapsed >= 20 {
            return "This is taking longer than usual"
        }
        guard let stage = recording.processingStage else {
            return "Please wait…"
        }
        switch stage {
        case .transcribing:
            return "Converting speech to text"
        case .structuring:
            return "Categorizing and creating action items"
        case .finalizing:
            return "Almost done"
        }
    }

    private var fallbackProcessingTitle: String { "Processing…" }

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SVTheme.successGreen)
                .symbolEffect(.bounce, value: showSuccess)

            VStack(spacing: 6) {
                Text(recording.selectedVisibility == .personal ? "Note Saved" : "Shift Note Sent")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text(recording.selectedVisibility == .personal ? "Saved to your private notes" : "Your team will be notified")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            Spacer()
        }
    }

    private var lockedVisibilitySummary: some View {
        HStack(spacing: 10) {
            Image(systemName: recording.selectedVisibility.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(recordingModeAccent)
            Text("Default: \(recording.selectedVisibility == .team ? "Team" : "Private")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SVTheme.textPrimary)
            Spacer()
            Button("Change") {
                allowVisibilityOverrideForThisRecording = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SVTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    private var visibilityToggle: some View {
        HStack(spacing: 10) {
            visibilityOptionButton(for: .team)
            visibilityOptionButton(for: .personal)
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.selection, trigger: recording.selectedVisibility)
    }

    private func visibilityOptionButton(for visibility: NoteVisibility) -> some View {
        let isSelected = recording.selectedVisibility == visibility
        let accent: Color = visibility == .personal ? .indigo : SVTheme.accent

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                recording.selectedVisibility = visibility
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: visibility.icon)
                        .font(.subheadline.weight(.semibold))
                    Text(visibility == .team ? "Team Note" : "Private Note")
                        .font(.subheadline.weight(.semibold))
                }

                Text(visibility == .team ? "Shared with your location team" : "Visible only to you")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : SVTheme.textTertiary)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isSelected ? .white : SVTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(isSelected ? accent : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? accent.opacity(0.95) : SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 76)
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

    private var guidedPromptBubble: some View {
        Group {
            if currentPromptIndex < guidedPrompts.count {
                let prompt = guidedPrompts[currentPromptIndex]
                HStack(spacing: 8) {
                    Image(systemName: prompt.icon)
                        .font(.caption)
                        .foregroundStyle(SVTheme.accent)
                    Text(prompt.text)
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(SVTheme.accent.opacity(0.06))
                .clipShape(.rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(SVTheme.accent.opacity(0.12), lineWidth: 1)
                )
                .opacity(promptVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: promptVisible)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    private func startPromptRotation() {
        guidedPrompts = RecordingPromptProvider.prompts(
            for: viewModel.organizationBusinessType,
            shiftName: currentShiftDisplay.name
        )
        currentPromptIndex = 0
        promptVisible = true
        promptRotationTask?.cancel()
        promptRotationTask = Task {
            while !Task.isCancelled && currentPromptIndex < guidedPrompts.count {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                withAnimation { promptVisible = false }
                try? await Task.sleep(for: .milliseconds(400))
                if Task.isCancelled { break }
                currentPromptIndex += 1
                if currentPromptIndex < guidedPrompts.count {
                    withAnimation { promptVisible = true }
                }
            }
        }
    }

    private func stopPromptRotation() {
        promptRotationTask?.cancel()
        promptRotationTask = nil
    }

    private func startRecording() {
        guard permissionGranted else {
            showPermissionAlert = true
            return
        }
        let thisMonthCount = viewModel.notesThisMonth
        if !subscription.canRecordNote(currentMonthNoteCount: thisMonthCount) {
            shouldResumeRecordingAfterPaywall = true
            viewModel.presentPaywall(reason: .recordingLimitReached)
            return
        }
        recording.startRecording()
        startPromptRotation()
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }

    private func stopRecording() {
        pulseScale = 1.0
        stopPromptRotation()
        recording.stopRecording(
            selectedShift: selectedShiftDisplay,
            defaultShift: viewModel.currentShiftDisplayInfo,
            businessType: viewModel.organizationBusinessType.rawValue.lowercased(),
            authToken: viewModel.backendAuthToken,
            userId: viewModel.currentUserId
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}
