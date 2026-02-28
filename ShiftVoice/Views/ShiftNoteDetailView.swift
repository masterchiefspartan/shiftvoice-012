import SwiftUI
import AVFoundation

struct ShiftNoteDetailView: View {
    let noteId: String
    let viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isPlayingAudio: Bool = false
    @State private var audioProgress: Double = 0
    @State private var showTranscript: Bool = false
    @State private var showAssignSheet: Bool = false
    @State private var assigningActionId: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var progressTimer: Timer?
    @State private var isAcknowledging: Bool = false
    @State private var showConflictSheet: Bool = false
    @State private var showQuickAppend: Bool = false
    @State private var showPromoteConfirmation: Bool = false

    private var note: ShiftNote? {
        viewModel.shiftNotes.first { $0.id == noteId }
    }

    private var isAcknowledged: Bool {
        guard let note else { return false }
        return viewModel.isNoteAcknowledged(note)
    }

    var body: some View {
        Group {
            if let note {
                noteContent(note)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.questionmark")
                        .font(.system(size: 36))
                        .foregroundStyle(SVTheme.textTertiary)
                    Text("Note not found")
                        .font(.headline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SVTheme.background)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Shift Note")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SVTheme.textPrimary)
            }
        }
        .toolbarBackground(SVTheme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showAssignSheet) {
            if let actionId = assigningActionId, let note {
                AssigneePickerView(
                    teamMembers: viewModel.teamMembers,
                    currentAssigneeId: note.actionItems.first(where: { $0.id == actionId })?.assigneeId
                ) { selectedId, selectedName in
                    viewModel.updateActionItemAssignee(noteId: noteId, actionItemId: actionId, assignee: selectedName, assigneeId: selectedId)
                    showAssignSheet = false
                    assigningActionId = nil
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showQuickAppend) {
            if let note {
                QuickAppendView(
                    noteId: note.id,
                    viewModel: viewModel
                ) { newCategories, newActions in
                    viewModel.appendItemsToNote(
                        noteId: note.id,
                        categorizedItems: newCategories,
                        actionItems: newActions
                    )
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showConflictSheet) {
            if viewModel.featureFlags.conflictUIEnabled {
                ConflictDetailView(noteId: noteId, viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationContentInteraction(.scrolls)
            }
        }
    }

    private func noteContent(_ note: ShiftNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if note.isPrivate {
                    privateNoteBanner
                }
                headerSection(note)
                if !note.isPrivate, viewModel.featureFlags.conflictUIEnabled, !viewModel.activeConflictsForNote(note.id).isEmpty {
                    conflictSection(note.id)
                }
                summarySection(note)
                if note.audioDuration > 0 {
                    audioPlayerSection(note)
                }
                categorizedItemsSection(note)
                if !note.actionItems.isEmpty {
                    actionItemsSection(note)
                }
                if !note.isPrivate, !note.acknowledgments.isEmpty {
                    acknowledgmentsSection(note)
                }
                if !note.isPrivate, !note.voiceReplies.isEmpty {
                    repliesSection(note)
                }
                quickAppendButton
                if note.isPrivate {
                    shareWithTeamButton
                } else if !isAcknowledged {
                    acknowledgeButton
                }
            }
            .padding(24)
            .padding(.bottom, 32)
        }
        .background(SVTheme.background)
        .onDisappear {
            stopAudioPlayback()
        }
    }

    private func headerSection(_ note: ShiftNote) -> some View {
        HStack(spacing: 14) {
            Text(note.authorInitials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SVTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(SVTheme.iconBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(note.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                HStack(spacing: 8) {
                    ShiftTypeBadge(info: note.shiftDisplayInfo)
                    Text(note.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }

            Spacer()

            UrgencyBadge(urgency: note.highestUrgency)
        }
    }

    private func conflictSection(_ noteId: String) -> some View {
        Button {
            showConflictSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(SVTheme.amber.opacity(0.12))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Conflict detected")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("\(viewModel.activeConflictsForNote(noteId).count) field\(viewModel.activeConflictsForNote(noteId).count == 1 ? "" : "s") need review")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SVTheme.amber.opacity(0.1))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.amber.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Conflict detected")
        .accessibilityHint("Open conflict details")
    }

    private func summarySection(_ note: ShiftNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            Text(note.summary)
                .font(.body)
                .foregroundStyle(SVTheme.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func audioPlayerSection(_ note: ShiftNote) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    if isPlayingAudio {
                        pauseAudioPlayback()
                    } else {
                        startAudioPlayback(note)
                    }
                } label: {
                    Image(systemName: isPlayingAudio ? "pause.fill" : "play.fill")
                        .font(.body)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(SVTheme.accent)
                        .clipShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }

                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(SVTheme.divider)
                                .frame(height: 3)
                            Capsule()
                                .fill(SVTheme.accent)
                                .frame(width: geo.size.width * audioProgress, height: 3)
                        }
                    }
                    .frame(height: 3)

                    HStack {
                        Text(formatTime(note.audioDuration * audioProgress))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(SVTheme.textTertiary)
                        Spacer()
                        Text(formatTime(note.audioDuration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(SVTheme.textTertiary)
                    }
                }
            }

            Button {
                showTranscript.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption)
                    Text(showTranscript ? "Hide Transcript" : "Show Transcript")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(SVTheme.textSecondary)
            }

            if showTranscript {
                Text(note.rawTranscript)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
                    .lineSpacing(2)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SVTheme.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(20)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func categorizedItemsSection(_ note: ShiftNote) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CATEGORIZED ITEMS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            let grouped = Dictionary(grouping: note.categorizedItems, by: \.displayInfo)
            let sortedKeys = Array(grouped.keys).sorted { $0.name < $1.name }
            ForEach(sortedKeys) { info in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: info.icon)
                            .font(.caption)
                            .foregroundStyle(info.color)
                            .frame(width: 28, height: 28)
                            .background(info.color.opacity(0.08))
                            .clipShape(.rect(cornerRadius: 6))
                        Text(info.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SVTheme.textPrimary)
                    }

                    if let items = grouped[info] {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(SVTheme.urgencyColor(item.urgency))
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.content)
                                        .font(.subheadline)
                                        .foregroundStyle(SVTheme.textPrimary)
                                        .lineSpacing(2)
                                    UrgencyBadge(urgency: item.urgency)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SVTheme.cardBackground)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                )
            }
        }
    }

    private func actionItemsSection(_ note: ShiftNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTION ITEMS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(note.resolvedActionCount)/\(note.actionItems.count) done")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SVTheme.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(note.actionItems.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.status == .resolved ? "checkmark.circle.fill" : "circle")
                            .font(.body)
                            .foregroundStyle(item.status == .resolved ? SVTheme.successGreen : SVTheme.textTertiary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.task)
                                .font(.subheadline)
                                .foregroundStyle(item.status == .resolved ? SVTheme.textTertiary : SVTheme.textPrimary)
                                .strikethrough(item.status == .resolved)
                                .lineSpacing(2)

                            HStack(spacing: 8) {
                                UrgencyBadge(urgency: item.urgency)

                                if !note.isPrivate {
                                    Button {
                                        assigningActionId = item.id
                                        showAssignSheet = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: item.assignee != nil ? "person.fill" : "person.badge.plus")
                                                .font(.system(size: 10))
                                            Text(item.assignee ?? "Assign")
                                                .font(.caption2.weight(.medium))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .foregroundStyle(item.assignee != nil ? SVTheme.accent : SVTheme.textTertiary)
                                        .background(item.assignee != nil ? SVTheme.accent.opacity(0.08) : SVTheme.iconBackground)
                                        .clipShape(.rect(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if index < note.actionItems.count - 1 {
                        Rectangle()
                            .fill(SVTheme.divider)
                            .frame(height: 1)
                            .padding(.leading, 44)
                    }
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func acknowledgmentsSection(_ note: ShiftNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACKNOWLEDGED BY")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(note.acknowledgments.enumerated()), id: \.element.id) { index, ack in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.successGreen)
                        Text(ack.userName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textPrimary)
                        Spacer()
                        Text(ack.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < note.acknowledgments.count - 1 {
                        Rectangle()
                            .fill(SVTheme.divider)
                            .frame(height: 1)
                            .padding(.leading, 42)
                    }
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private func repliesSection(_ note: ShiftNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REPLIES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(note.voiceReplies.enumerated()), id: \.element.id) { index, reply in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(reply.authorName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SVTheme.textPrimary)
                            Spacer()
                            Text(reply.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                        Text(reply.transcript)
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textSecondary)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    if index < note.voiceReplies.count - 1 {
                        Rectangle()
                            .fill(SVTheme.divider)
                            .frame(height: 1)
                    }
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var quickAppendButton: some View {
        Button {
            showQuickAppend = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.plus")
                    .font(.subheadline.weight(.semibold))
                Text("Add to This Note")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(SVTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(SVTheme.accent.opacity(0.08))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SVTheme.accent.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private var privateNoteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.indigo)
                .frame(width: 32, height: 32)
                .background(Color.indigo.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Private Note")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text("Only you can see this note")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textSecondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.indigo.opacity(0.15), lineWidth: 1)
        )
    }

    private var shareWithTeamButton: some View {
        Button {
            showPromoteConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Share with Team")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(SVTheme.accent)
            .clipShape(.rect(cornerRadius: 8))
        }
        .confirmationDialog("Share with Team?", isPresented: $showPromoteConfirmation, titleVisibility: .visible) {
            Button("Share with Team") {
                viewModel.promoteNoteToTeam(noteId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will make the note visible to your entire team. This can’t be undone.")
        }
    }

    private var acknowledgeButton: some View {
        Button {
            guard !isAcknowledging else { return }
            isAcknowledging = true
            viewModel.acknowledgeNote(noteId)
        } label: {
            HStack(spacing: 8) {
                if isAcknowledging {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                    Text("Acknowledge & Start Shift")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isAcknowledging ? SVTheme.accent.opacity(0.6) : SVTheme.accent)
            .clipShape(.rect(cornerRadius: 8))
        }
        .disabled(isAcknowledging)
        .sensoryFeedback(.success, trigger: isAcknowledged)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func resolveAudioURL(for note: ShiftNote) -> URL? {
        guard let audioFilename = note.audioUrl else { return nil }
        if audioFilename.hasPrefix("http://") || audioFilename.hasPrefix("https://") {
            return URL(string: audioFilename)
        }
        let recordingDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ShiftVoiceRecordings", isDirectory: true)
        return recordingDir.appendingPathComponent(audioFilename)
    }

    private func startAudioPlayback(_ note: ShiftNote) {
        if let player = audioPlayer {
            player.play()
            isPlayingAudio = true
            startProgressTimer(duration: player.duration)
            return
        }

        guard let url = resolveAudioURL(for: note),
              FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlayingAudio = true
            audioProgress = 0
            startProgressTimer(duration: player.duration)
        } catch {}
    }

    private func pauseAudioPlayback() {
        audioPlayer?.pause()
        isPlayingAudio = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func stopAudioPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingAudio = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startProgressTimer(duration: TimeInterval) {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                guard let player = audioPlayer else {
                    progressTimer?.invalidate()
                    progressTimer = nil
                    return
                }
                if player.isPlaying {
                    audioProgress = player.currentTime / max(player.duration, 1)
                } else if player.currentTime >= player.duration - 0.15 {
                    audioProgress = 1.0
                    isPlayingAudio = false
                    progressTimer?.invalidate()
                    progressTimer = nil
                    audioPlayer = nil
                }
            }
        }
    }
}
