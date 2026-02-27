import SwiftUI

struct NoteReviewView: View {
    @Bindable var viewModel: AppViewModel
    @State private var rawTranscript: String
    let audioDuration: TimeInterval
    let audioUrl: String?
    let shiftInfo: ShiftDisplayInfo
    let onDiscard: () -> Void
    let onPublish: (ShiftNote) -> Void

    @State private var summary: String
    @State private var editableCategorizedItems: [EditableCategorizedItem]
    @State private var editableActionItems: [EditableActionItem]
    @State private var showAddItem: Bool = false
    @State private var showAddAction: Bool = false
    @State private var editingItemId: String?
    @State private var showDiscardAlert: Bool = false
    @State private var showAssignSheet: Bool = false
    @State private var assigningActionId: String?
    @State private var publishValidationError: String?
    @State private var isPublishing: Bool = false
    @State private var structuringWarning: String?
    @State private var transcriptionFailed: Bool
    @State private var transcriptionFailureMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(
        viewModel: AppViewModel,
        rawTranscript: String,
        audioDuration: TimeInterval,
        audioUrl: String?,
        shiftInfo: ShiftDisplayInfo,
        summary: String,
        categorizedItems: [CategorizedItem],
        actionItems: [ActionItem],
        structuringWarning: String? = nil,
        transcriptionFailed: Bool = false,
        transcriptionFailureMessage: String? = nil,
        onDiscard: @escaping () -> Void,
        onPublish: @escaping (ShiftNote) -> Void
    ) {
        self.viewModel = viewModel
        _rawTranscript = State(initialValue: rawTranscript)
        self.audioDuration = audioDuration
        self.audioUrl = audioUrl
        self.shiftInfo = shiftInfo
        self.onDiscard = onDiscard
        self.onPublish = onPublish
        _summary = State(initialValue: summary)
        _editableCategorizedItems = State(initialValue: categorizedItems.map { EditableCategorizedItem(from: $0) })
        _editableActionItems = State(initialValue: actionItems.map { EditableActionItem(from: $0) })
        _structuringWarning = State(initialValue: structuringWarning)
        _transcriptionFailed = State(initialValue: transcriptionFailed)
        _transcriptionFailureMessage = State(initialValue: transcriptionFailureMessage)
    }

    private func structuringWarningBanner(_ warning: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(SVTheme.amber)

            Text(warning)
                .font(.caption)
                .foregroundStyle(SVTheme.textSecondary)
                .lineSpacing(2)

            Spacer(minLength: 0)

            Button {
                structuringWarning = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SVTheme.textTertiary)
            }
        }
        .padding(12)
        .background(SVTheme.amber.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SVTheme.amber.opacity(0.2), lineWidth: 1)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if transcriptionFailed {
                        transcriptionFailedBanner
                    }
                    if let warning = structuringWarning {
                        structuringWarningBanner(warning)
                    }
                    headerInfo
                    summaryEditor
                    transcriptPreview
                    categorizedItemsEditor
                    actionItemsEditor
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(SVTheme.background)
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Review Note")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Discard") {
                        showDiscardAlert = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.urgentRed)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Discard Note?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { onDiscard() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("This will permanently delete this recording and all structured data.")
            }
            .sheet(isPresented: $showAssignSheet) {
                if let actionId = assigningActionId {
                    AssigneePickerView(
                        teamMembers: viewModel.teamMembers,
                        currentAssigneeId: editableActionItems.first(where: { $0.id == actionId })?.assigneeId
                    ) { selectedId, selectedName in
                        if let idx = editableActionItems.firstIndex(where: { $0.id == actionId }) {
                            editableActionItems[idx].assignee = selectedName
                            editableActionItems[idx].assigneeId = selectedId
                        }
                        showAssignSheet = false
                        assigningActionId = nil
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showAddAction) {
                AddActionItemSheet { task, category, urgency in
                    let newItem = EditableActionItem(
                        id: UUID().uuidString,
                        task: task,
                        category: category,
                        urgency: urgency,
                        assignee: nil
                    )
                    editableActionItems.append(newItem)
                    showAddAction = false
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: summary) { _, _ in
                viewModel.recording.markReviewAsUserEdited()
            }
            .onChange(of: editableCategorizedItems) { _, _ in
                viewModel.recording.markReviewAsUserEdited()
            }
            .onChange(of: editableActionItems) { _, _ in
                viewModel.recording.markReviewAsUserEdited()
            }
        }
    }

    private var headerInfo: some View {
        HStack(spacing: 12) {
            Text(viewModel.currentUserInitials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(SVTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(SVTheme.iconBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentUserName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                HStack(spacing: 8) {
                    ShiftTypeBadge(info: shiftInfo)
                    if audioDuration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption2)
                            Text(formatDuration(audioDuration))
                                .font(.caption2.monospacedDigit())
                        }
                        .foregroundStyle(SVTheme.textTertiary)
                    }
                }
            }

            Spacer()

            VStack(spacing: 2) {
                Text("\(editableActionItems.count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(SVTheme.accent)
                Text("actions")
                    .font(.caption2)
                    .foregroundStyle(SVTheme.textTertiary)
            }
        }
    }

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SUMMARY")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
                Spacer()
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            TextField("Summary of your shift note...", text: $summary, axis: .vertical)
                .font(.body)
                .foregroundStyle(SVTheme.textPrimary)
                .lineLimit(2...6)
                .lineSpacing(3)
        }
        .padding(16)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var transcriptionFailedBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(SVTheme.urgentRed)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Transcription Failed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text(transcriptionFailureMessage ?? "Could not transcribe audio.")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                Task {
                    await viewModel.recording.retryTranscription(
                        authToken: viewModel.backendAuthToken,
                        userId: viewModel.currentUserId,
                        businessType: viewModel.organizationBusinessType.rawValue.lowercased()
                    )
                    if let updated = viewModel.recording.pendingReviewData {
                        rawTranscript = updated.rawTranscript
                        summary = updated.summary
                        editableCategorizedItems = updated.categorizedItems.map { EditableCategorizedItem(from: $0) }
                        editableActionItems = updated.actionItems.map { EditableActionItem(from: $0) }
                        structuringWarning = updated.structuringWarning
                        transcriptionFailed = updated.transcriptionFailed
                        transcriptionFailureMessage = updated.transcriptionFailureMessage
                    }
                    if viewModel.recording.transcriptionFailed {
                        transcriptionFailed = true
                        transcriptionFailureMessage = viewModel.recording.transcriptionFailureMessage
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.recording.isRetryingTranscription {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    Text(viewModel.recording.isRetryingTranscription ? "Retrying..." : "Retry Transcription")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(SVTheme.accent)
                .clipShape(.rect(cornerRadius: 8))
            }
            .disabled(viewModel.recording.isRetryingTranscription)
        }
        .padding(14)
        .background(SVTheme.urgentRed.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.urgentRed.opacity(0.2), lineWidth: 1)
        )
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
                Text("RAW TRANSCRIPT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
            }

            if rawTranscript.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: transcriptionFailed ? "exclamationmark.triangle" : "waveform.slash")
                        .font(.caption)
                    Text(transcriptionFailed ? "Transcription failed — tap Retry above" : "No speech detected in recording")
                        .font(.caption)
                }
                .foregroundStyle(transcriptionFailed ? SVTheme.urgentRed : SVTheme.textTertiary)
            } else {
                Text(rawTranscript)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textSecondary)
                    .lineLimit(3)
                    .lineSpacing(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SVTheme.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 10))
    }

    private var categorizedItemsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CATEGORIZED ITEMS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
                Spacer()
                Text("\(editableCategorizedItems.count) items")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
            }

            ForEach($editableCategorizedItems) { $item in
                EditableCategorizedItemRow(
                    item: $item,
                    onDelete: {
                        editableCategorizedItems.removeAll { $0.id == item.id }
                    }
                )
            }
        }
    }

    private var actionItemsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTION ITEMS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
                Spacer()
                Button {
                    showAddAction = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                        Text("Add")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(SVTheme.accent)
                }
            }

            if editableActionItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.dashed")
                        .font(.title3)
                        .foregroundStyle(SVTheme.textTertiary)
                    Text("No action items yet. Tap + to add one.")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SVTheme.cardBackground)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SVTheme.surfaceBorder.opacity(0.5), lineWidth: 1)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(editableActionItems.enumerated()), id: \.element.id) { index, item in
                        EditableActionItemRow(
                            item: Binding(
                                get: { editableActionItems[index] },
                                set: { editableActionItems[index] = $0 }
                            ),
                            onAssign: {
                                assigningActionId = item.id
                                showAssignSheet = true
                            },
                            onDelete: {
                                editableActionItems.removeAll { $0.id == item.id }
                            }
                        )

                        if index < editableActionItems.count - 1 {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 16)
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
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showDiscardAlert = true
            } label: {
                Text("Discard")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(SVTheme.cardBackground)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )
            }

            Button {
                publishNote()
            } label: {
                HStack(spacing: 8) {
                    if isPublishing {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline)
                    }
                    Text("Send to Team")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isPublishing ? SVTheme.accent.opacity(0.6) : SVTheme.accent)
                .clipShape(.rect(cornerRadius: 10))
            }
            .disabled(isPublishing)
            .sensoryFeedback(.success, trigger: false)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            SVTheme.surface
                .shadow(color: .black.opacity(0.06), radius: 12, y: -4)
        )
        .overlay(alignment: .top) {
            if let error = publishValidationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(SVTheme.urgentRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(SVTheme.urgentRed.opacity(0.08))
                .clipShape(.rect(cornerRadius: 8))
                .offset(y: -44)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: publishValidationError)
    }

    private func publishNote() {
        publishValidationError = nil

        let validation = InputValidator.validateShiftNote(
            summary: summary,
            rawTranscript: rawTranscript,
            locationId: viewModel.selectedLocationId,
            authorId: viewModel.currentUserId
        )

        guard validation.isValid else {
            let firstError = validation.errors.values.first ?? "Please fix errors before publishing"
            publishValidationError = firstError
            return
        }

        let sanitizedSummary = InputValidator.sanitizeString(summary)
        let sanitizedTranscript = InputValidator.sanitizeString(rawTranscript)

        let categorizedItems = editableCategorizedItems.map { $0.toCategorizedItem() }
        let actionItems = editableActionItems.map { $0.toActionItem() }

        isPublishing = true

        let note = ShiftNote(
            authorId: viewModel.currentUserId,
            authorName: viewModel.currentUserName,
            authorInitials: viewModel.currentUserInitials,
            locationId: viewModel.selectedLocationId,
            shiftType: viewModel.currentShiftType,
            shiftTemplateId: shiftInfo.id,
            rawTranscript: sanitizedTranscript,
            audioUrl: audioUrl,
            audioDuration: audioDuration,
            summary: sanitizedSummary,
            categorizedItems: categorizedItems,
            actionItems: actionItems
        )

        onPublish(note)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct EditableCategorizedItem: Identifiable, Equatable {
    let id: String
    var category: NoteCategory
    var categoryTemplateId: String?
    var content: String
    var urgency: UrgencyLevel

    init(from item: CategorizedItem) {
        self.id = item.id
        self.category = item.category
        self.categoryTemplateId = item.categoryTemplateId
        self.content = item.content
        self.urgency = item.urgency
    }

    func toCategorizedItem() -> CategorizedItem {
        CategorizedItem(
            id: id,
            category: category,
            categoryTemplateId: categoryTemplateId,
            content: content,
            urgency: urgency
        )
    }
}

struct EditableActionItem: Identifiable, Equatable {
    let id: String
    var task: String
    var category: NoteCategory
    var categoryTemplateId: String?
    var urgency: UrgencyLevel
    var assignee: String?
    var assigneeId: String?

    init(id: String, task: String, category: NoteCategory, categoryTemplateId: String? = nil, urgency: UrgencyLevel, assignee: String? = nil, assigneeId: String? = nil) {
        self.id = id
        self.task = task
        self.category = category
        self.categoryTemplateId = categoryTemplateId
        self.urgency = urgency
        self.assignee = assignee
        self.assigneeId = assigneeId
    }

    init(from item: ActionItem) {
        self.id = item.id
        self.task = item.task
        self.category = item.category
        self.categoryTemplateId = item.categoryTemplateId
        self.urgency = item.urgency
        self.assignee = item.assignee
        self.assigneeId = item.assigneeId
    }

    func toActionItem() -> ActionItem {
        ActionItem(
            id: id,
            task: task,
            category: category,
            categoryTemplateId: categoryTemplateId,
            urgency: urgency,
            assignee: assignee,
            assigneeId: assigneeId
        )
    }
}

struct EditableCategorizedItemRow: View {
    @Binding var item: EditableCategorizedItem
    let onDelete: () -> Void
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.category.icon)
                    .font(.caption)
                    .foregroundStyle(SVTheme.categoryColor(item.category))
                    .frame(width: 28, height: 28)
                    .background(SVTheme.categoryColor(item.category).opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.content)
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textPrimary)
                        .lineLimit(isExpanded ? nil : 2)
                        .lineSpacing(2)

                    HStack(spacing: 6) {
                        CategoryPill(info: CategoryDisplayInfo(from: item.category))
                        UrgencyBadge(urgency: item.urgency)
                    }
                }

                Spacer(minLength: 4)

                Menu {
                    Button { isExpanded.toggle() } label: {
                        Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    Menu("Change Category") {
                        ForEach(NoteCategory.allCases) { cat in
                            Button {
                                item.category = cat
                            } label: {
                                Label(cat.rawValue, systemImage: cat.icon)
                            }
                        }
                    }
                    Menu("Change Urgency") {
                        ForEach(UrgencyLevel.allCases) { level in
                            Button {
                                item.urgency = level
                            } label: {
                                Label(level.rawValue, systemImage: "circle.fill")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
            .padding(14)
        }
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

struct EditableActionItemRow: View {
    @Binding var item: EditableActionItem
    let onAssign: () -> Void
    let onDelete: () -> Void
    @State private var isEditing: Bool = false
    @State private var showSuggestion: Bool = true

    private var qualityHint: String? {
        let tempAction = ActionItem(
            id: item.id,
            task: item.task,
            category: item.category,
            urgency: item.urgency,
            assignee: item.assignee,
            assigneeId: item.assigneeId
        )
        if case .needsWork(let hint) = ActionItemScorer.evaluate(tempAction) {
            return hint
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Action item...", text: $item.task, axis: .vertical)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textPrimary)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(SVTheme.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: 8))
                    .onSubmit { isEditing = false }
            } else {
                Text(item.task)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textPrimary)
                    .lineSpacing(2)
            }

            if let hint = qualityHint, showSuggestion {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SVTheme.amber)
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        withAnimation { showSuggestion = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(SVTheme.textTertiary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(SVTheme.amber.opacity(0.06))
                .clipShape(.rect(cornerRadius: 6))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }

            HStack(spacing: 8) {
                UrgencyBadge(urgency: item.urgency)

                Button {
                    onAssign()
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

                Spacer()

                Menu {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Menu("Urgency") {
                        ForEach(UrgencyLevel.allCases) { level in
                            Button {
                                item.urgency = level
                            } label: {
                                Label(level.rawValue, systemImage: "circle.fill")
                            }
                        }
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(16)
    }
}

struct AddActionItemSheet: View {
    let onAdd: (String, NoteCategory, UrgencyLevel) -> Void

    @State private var task: String = ""
    @State private var category: NoteCategory = .general
    @State private var urgency: UrgencyLevel = .nextShift
    @State private var taskError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Task Description")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textSecondary)

                    TextField("What needs to be done?", text: $task, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(SVTheme.surfaceSecondary)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(taskError != nil ? SVTheme.urgentRed.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                        .onChange(of: task) { _, _ in taskError = nil }

                    if let error = taskError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 10))
                            Text(error)
                                .font(.caption)
                        }
                        .foregroundStyle(SVTheme.urgentRed)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textSecondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(NoteCategory.allCases) { cat in
                                Button {
                                    category = cat
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: cat.icon)
                                            .font(.caption2)
                                        Text(cat.rawValue)
                                            .font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(category == cat ? .white : SVTheme.categoryColor(cat))
                                    .background(category == cat ? SVTheme.categoryColor(cat) : SVTheme.categoryColor(cat).opacity(0.08))
                                    .clipShape(.rect(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    .contentMargins(.horizontal, 0)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Urgency")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(UrgencyLevel.allCases) { level in
                            Button {
                                urgency = level
                            } label: {
                                Text(level.rawValue)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(urgency == level ? .white : SVTheme.urgencyColor(level))
                                    .background(urgency == level ? SVTheme.urgencyColor(level) : SVTheme.urgencyColor(level).opacity(0.08))
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Add Action Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SVTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        taskError = nil
                        if let error = InputValidator.validateActionItemTask(task) {
                            taskError = error
                            return
                        }
                        onAdd(InputValidator.sanitizeString(task, maxLength: 500), category, urgency)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(task.trimmingCharacters(in: .whitespaces).isEmpty ? SVTheme.textTertiary : SVTheme.accent)
                    .disabled(task.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
