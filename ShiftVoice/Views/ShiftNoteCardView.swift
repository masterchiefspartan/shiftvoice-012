import SwiftUI

struct ShiftNoteCardView: View {
    let note: ShiftNote
    let isAcknowledged: Bool
    let activeConflictCount: Int
    let onTapConflictBadge: (() -> Void)?

    private var hasConflicts: Bool {
        activeConflictCount > 0
    }

    private var isPendingSync: Bool {
        !note.isSynced
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(SVTheme.urgencyColor(note.highestUrgency))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(note.authorInitials)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SVTheme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(SVTheme.iconBackground)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SVTheme.textPrimary)
                        Text(note.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        statusBadge
                        ShiftTypeBadge(info: note.shiftDisplayInfo)
                    }
                }

                Text(note.summary)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
                    .lineLimit(3)
                    .lineSpacing(2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(note.categoryDisplayInfos) { info in
                            CategoryPill(info: info)
                        }
                    }
                }

                HStack(spacing: 12) {
                    if !note.actionItems.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checklist")
                                .font(.caption2)
                            Text("\(note.resolvedActionCount)/\(note.actionItems.count)")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(SVTheme.textTertiary)
                    }

                    if !note.acknowledgments.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                            Text("\(note.acknowledgments.count) ack'd")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(isAcknowledged ? SVTheme.successGreen : SVTheme.textTertiary)
                    }

                    Spacer()

                    if note.audioDuration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                            Text(formatDuration(note.audioDuration))
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(SVTheme.textTertiary)
                    }

                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if hasConflicts {
            Button {
                onTapConflictBadge?()
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 28)
                    .background(SVTheme.amber.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Conflict detected")
            .accessibilityHint("Open conflict details")
        } else if isPendingSync {
            Image(systemName: "icloud.and.arrow.up.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.amber)
                .frame(width: 28, height: 28)
                .background(SVTheme.amber.opacity(0.12))
                .clipShape(Circle())
                .accessibilityLabel("Pending sync")
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct ShiftTypeBadge: View {
    let info: ShiftDisplayInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(.caption2)
            Text(info.name)
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(SVTheme.textSecondary)
        .background(SVTheme.iconBackground)
        .clipShape(.rect(cornerRadius: 6))
    }
}

struct CategoryPill: View {
    let info: CategoryDisplayInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: info.icon)
                .font(.system(size: 9))
            Text(info.name)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(info.color)
        .background(info.color.opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
    }
}

struct UrgencyBadge: View {
    let urgency: UrgencyLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SVTheme.urgencyColor(urgency))
                .frame(width: 5, height: 5)
            Text(urgency.rawValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(SVTheme.urgencyColor(urgency))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(SVTheme.urgencyColor(urgency).opacity(0.08))
        .clipShape(.rect(cornerRadius: 6))
    }
}
