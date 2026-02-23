import SwiftUI

struct ShiftNoteDetailView: View {
    let note: ShiftNote
    let isAcknowledged: Bool
    let onAcknowledge: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPlayingAudio: Bool = false
    @State private var audioProgress: Double = 0
    @State private var showTranscript: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                summarySection
                if note.audioDuration > 0 {
                    audioPlayerSection
                }
                categorizedItemsSection
                if !note.actionItems.isEmpty {
                    actionItemsSection
                }
                if !note.acknowledgments.isEmpty {
                    acknowledgmentsSection
                }
                if !note.voiceReplies.isEmpty {
                    repliesSection
                }
                if !isAcknowledged {
                    acknowledgeButton
                }
            }
            .padding(24)
            .padding(.bottom, 32)
        }
        .background(SVTheme.background)
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
    }

    private var headerSection: some View {
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

    private var summarySection: some View {
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

    private var audioPlayerSection: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    isPlayingAudio.toggle()
                    if isPlayingAudio {
                        simulatePlayback()
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

    private var categorizedItemsSection: some View {
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

    private var actionItemsSection: some View {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.task)
                                .font(.subheadline)
                                .foregroundStyle(item.status == .resolved ? SVTheme.textTertiary : SVTheme.textPrimary)
                                .strikethrough(item.status == .resolved)
                                .lineSpacing(2)

                            HStack(spacing: 8) {
                                UrgencyBadge(urgency: item.urgency)
                                if let assignee = item.assignee {
                                    Text(assignee)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(SVTheme.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(SVTheme.accent.opacity(0.08))
                                        .clipShape(.rect(cornerRadius: 4))
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

    private var acknowledgmentsSection: some View {
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

    private var repliesSection: some View {
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

    private var acknowledgeButton: some View {
        Button {
            onAcknowledge()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                Text("Acknowledge & Start Shift")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(SVTheme.accent)
            .clipShape(.rect(cornerRadius: 8))
        }
        .sensoryFeedback(.success, trigger: isAcknowledged)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func simulatePlayback() {
        audioProgress = 0
        Task {
            for i in 1...50 {
                try? await Task.sleep(for: .milliseconds(100))
                guard isPlayingAudio else { return }
                audioProgress = Double(i) / 50.0
            }
            isPlayingAudio = false
        }
    }
}
