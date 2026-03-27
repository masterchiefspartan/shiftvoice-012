import SwiftUI

struct ReviewView: View {
    @Bindable var viewModel: AppViewModel
    @Binding var navPath: NavigationPath
    @State private var isUnacknowledgedExpanded: Bool = true
    @State private var isPendingConfirmationsExpanded: Bool = true
    @State private var isUnassignedExpanded: Bool = true
    @State private var isStaleExpanded: Bool = true

    private var unacknowledgedNotes: [ShiftNote] {
        viewModel.unacknowledgedNotes
    }

    private var pendingConfirmationNotes: [ShiftNote] {
        viewModel.pendingConfirmationNotes
    }

    private var unassignedItems: [ReviewActionReference] {
        viewModel.unassignedActionItems.map { entry in
            ReviewActionReference(
                id: "\(entry.noteId)-\(entry.item.id)",
                noteId: entry.noteId,
                task: entry.item.task,
                authorName: entry.authorName,
                locationName: viewModel.locationName(for: entry.locationId),
                updatedAt: entry.item.updatedAt,
                urgency: entry.item.urgency
            )
        }
    }

    private var staleItems: [ReviewActionReference] {
        viewModel.staleActionItems.map { entry in
            ReviewActionReference(
                id: "\(entry.noteId)-\(entry.item.id)",
                noteId: entry.noteId,
                task: entry.item.task,
                authorName: entry.authorName,
                locationName: viewModel.locationName(for: entry.locationId),
                updatedAt: entry.item.updatedAt,
                urgency: entry.item.urgency
            )
        }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    sectionCard(title: "Unacknowledged", count: unacknowledgedNotes.count, isExpanded: $isUnacknowledgedExpanded) {
                        ForEach(unacknowledgedNotes) { note in
                            noteRow(note: note)
                        }
                    }

                    sectionCard(title: "Pending Confirmations", count: pendingConfirmationNotes.count, isExpanded: $isPendingConfirmationsExpanded) {
                        ForEach(pendingConfirmationNotes) { note in
                            noteRow(note: note)
                        }
                    }

                    sectionCard(title: "Unassigned Actions", count: unassignedItems.count, isExpanded: $isUnassignedExpanded) {
                        ForEach(unassignedItems) { item in
                            actionRow(item: item)
                        }
                    }

                    sectionCard(title: "Stale Actions", count: staleItems.count, isExpanded: $isStaleExpanded) {
                        ForEach(staleItems) { item in
                            actionRow(item: item)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(SVTheme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Review")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .shiftNoteDetail(let noteId):
                    ShiftNoteDetailView(noteId: noteId, viewModel: viewModel)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(SVTheme.divider)
                    .frame(height: 1 / UIScreen.main.scale)
                    .padding(.top, -1)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs Attention")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(SVTheme.textPrimary)
                .tracking(-0.5)
            Text("A proactive queue of unresolved handoff work")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textSecondary)
        }
    }

    private func sectionCard<Content: View>(title: String, count: Int, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if count == 0 {
                Text("All clear")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    content()
                }
                .padding(.top, 8)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(count > 0 ? .white : SVTheme.textTertiary)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(count > 0 ? SVTheme.urgentRed : SVTheme.iconBackground)
                    .clipShape(Circle())
            }
        }
        .tint(SVTheme.textPrimary)
        .padding(14)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func noteRow(note: ShiftNote) -> some View {
        Button {
            navPath.append(AppRoute.shiftNoteDetail(noteId: note.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(note.summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SVTheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(note.authorName)
                    Text("•")
                    Text(viewModel.locationName(for: note.locationId))
                    Text("•")
                    Text(note.createdAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(SVTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func actionRow(item: ReviewActionReference) -> some View {
        Button {
            navPath.append(AppRoute.shiftNoteDetail(noteId: item.noteId))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(SVTheme.urgencyColor(item.urgency))
                        .frame(width: 7, height: 7)
                    Text(item.task)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(item.authorName)
                    Text("•")
                    Text(item.locationName)
                    Text("•")
                    Text(item.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(SVTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

nonisolated struct ReviewActionReference: Identifiable, Hashable, Sendable {
    let id: String
    let noteId: String
    let task: String
    let authorName: String
    let locationName: String
    let updatedAt: Date
    let urgency: UrgencyLevel
}
