import SwiftUI

nonisolated private enum NoteReviewScreenState: Equatable {
    case loading
    case empty
    case ready
    case error(String)
    case publishing
    case success
}

nonisolated private enum ReviewConfidenceBand: Equatable {
    case high
    case medium
    case low
    case fallback
}

private enum BannerProminence {
    case subtle
    case strong
}

struct NoteReviewView: View {
    @Bindable var viewModel: AppViewModel
    let source: ReviewEntrySource
    let returnDestination: ReviewReturnDestination
    @State private var rawTranscript: String
    let audioDuration: TimeInterval
    let audioUrl: String?
    let shiftInfo: ShiftDisplayInfo
    let onDiscard: () -> Void
    let onPublish: (ShiftNote) -> Bool

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
    @State private var publishSucceeded: Bool = false
    @State private var structuringWarning: String?
    @State private var recordingFailureState: RecordingFailureState
    @State private var confidenceScore: Double
    @State private var validationWarnings: [ValidationWarning]
    @State private var warningItemIDs: Set<String>
    @State private var usedAI: Bool
    @State private var approvedActionItemIds: Set<String>
    @State private var showUnsavedExitDialog: Bool = false
    @State private var noteVisibility: NoteVisibility
    @Environment(\.dismiss) private var dismiss

    private let initialSummary: String
    private let initialRawTranscript: String
    private let initialCategorizedItems: [EditableCategorizedItem]
    private let initialActionItems: [EditableActionItem]
    private let initialApprovedActionItemIds: Set<String>

    init(
        viewModel: AppViewModel,
        source: ReviewEntrySource,
        returnDestination: ReviewReturnDestination,
        rawTranscript: String,
        audioDuration: TimeInterval,
        audioUrl: String?,
        shiftInfo: ShiftDisplayInfo,
        summary: String,
        categorizedItems: [CategorizedItem],
        actionItems: [ActionItem],
        visibility: NoteVisibility = .team,
        structuringWarning: String? = nil,
        recordingFailureState: RecordingFailureState = .none,
        confidenceScore: Double = 1.0,
        validationWarnings: [ValidationWarning] = [],
        warningItemIDs: Set<String> = [],
        usedAI: Bool = true,
        onDiscard: @escaping () -> Void,
        onPublish: @escaping (ShiftNote) -> Bool
    ) {
        self.viewModel = viewModel
        self.source = source
        self.returnDestination = returnDestination
        _rawTranscript = State(initialValue: rawTranscript)
        self.audioDuration = audioDuration
        self.audioUrl = audioUrl
        self.shiftInfo = shiftInfo
        self.onDiscard = onDiscard
        self.onPublish = onPublish
        _summary = State(initialValue: summary)
        let initialCategorizedItems = categorizedItems.map { EditableCategorizedItem(from: $0) }
        let initialActionItems = actionItems.map { EditableActionItem(from: $0) }
        _editableCategorizedItems = State(initialValue: initialCategorizedItems)
        _editableActionItems = State(initialValue: initialActionItems)
        self.initialSummary = summary
        self.initialRawTranscript = rawTranscript
        self.initialCategorizedItems = initialCategorizedItems
        self.initialActionItems = initialActionItems
        _structuringWarning = State(initialValue: structuringWarning)
        _recordingFailureState = State(initialValue: recordingFailureState)
        _confidenceScore = State(initialValue: confidenceScore)
        _validationWarnings = State(initialValue: validationWarnings)
        _warningItemIDs = State(initialValue: warningItemIDs)
        _usedAI = State(initialValue: usedAI)
        let initialApprovedActionItemIds: Set<String> = []
        _approvedActionItemIds = State(initialValue: initialApprovedActionItemIds)
        self.initialApprovedActionItemIds = initialApprovedActionItemIds
        _noteVisibility = State(initialValue: visibility)
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
                    switch screenState {
                    case .loading:
                        loadingStateView
                    case .empty:
                        emptyStateView
                    case .error(let message):
                        errorStateView(message)
                    case .ready, .publishing, .success:
                        visibilityBadge
                        if case .transcriptionFailed = recordingFailureState {
                            transcriptionFailedBanner
                        }
                        if let banner = confidenceReviewBanner {
                            banner
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
                }
                .padding(20)
                .padding(.bottom, 100)
            }
            .background(SVTheme.background)
            .safeAreaInset(edge: .bottom) {
                if screenState != .loading {
                    bottomBar
                }
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
                    Button {
                        if hasUnsavedChanges {
                            showUnsavedExitDialog = true
                        } else {
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.caption.weight(.semibold))
                            Text("Back")
                                .font(.subheadline)
                        }
                        .foregroundStyle(SVTheme.textSecondary)
                    }
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .alert("Discard Note?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    viewModel.trackReviewFlowEvent(.exitedWithoutSave(source: source, returnDestination: .recording, reason: .discarded))
                    onDiscard()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("This will permanently delete this recording and all structured data.")
            }
            .confirmationDialog("Discard your edits?", isPresented: $showUnsavedExitDialog, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    viewModel.trackReviewFlowEvent(.exitedWithoutSave(source: source, returnDestination: .recording, reason: .backNavigation))
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved edits in this review.")
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
            .onChange(of: editableActionItems) { _, newItems in
                viewModel.recording.markReviewAsUserEdited()
                let currentIds = Set(newItems.map(\.id))
                approvedActionItemIds = approvedActionItemIds.intersection(currentIds)
            }
            .navigationBarBackButtonHidden(true)
        }
    }

    private var hasUnsavedChanges: Bool {
        summary != initialSummary ||
        rawTranscript != initialRawTranscript ||
        editableCategorizedItems != initialCategorizedItems ||
        editableActionItems != initialActionItems ||
        approvedActionItemIds != initialApprovedActionItemIds
    }

    private var transcriptId: String {
        UserEditTracker.transcriptIdentifier(audioUrl: audioUrl, originalTranscript: initialRawTranscript)
    }

    private var screenState: NoteReviewScreenState {
        if isPublishing {
            return .publishing
        }

        if publishSucceeded {
            return .success
        }

        if viewModel.recording.isRetryingTranscription {
            return .loading
        }

        let hasTranscript: Bool = !rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSummary: Bool = !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasCategorizedItems: Bool = !editableCategorizedItems.isEmpty
        let hasActionItems: Bool = !editableActionItems.isEmpty
        let hasAnyContent: Bool = hasTranscript || hasSummary || hasCategorizedItems || hasActionItems

        if !hasAnyContent {
            switch recordingFailureState {
            case .none, .emptyRecording:
                return .empty
            case .transcriptionFailed(let message):
                return .error(message)
            }
        }

        return .ready
    }

    private var emptyRecordingMessage: String {
        switch recordingFailureState {
        case .emptyRecording(let message):
            return message
        case .transcriptionFailed, .none:
            return "No speech was detected in the recording. Retry transcription or discard this recording."
        }
    }

    private var transcriptionFailureMessage: String {
        switch recordingFailureState {
        case .transcriptionFailed(let message):
            return message
        case .emptyRecording, .none:
            return "Couldn't process audio. Please retry transcription."
        }
    }

    private var transcriptStatusSymbol: String {
        switch recordingFailureState {
        case .transcriptionFailed:
            return "exclamationmark.triangle"
        case .emptyRecording, .none:
            return "waveform.slash"
        }
    }

    private var transcriptStatusText: String {
        switch recordingFailureState {
        case .transcriptionFailed:
            return "Transcription failed — tap Retry above"
        case .emptyRecording, .none:
            return "No speech detected in recording"
        }
    }

    private var transcriptStatusColor: Color {
        switch recordingFailureState {
        case .transcriptionFailed:
            return SVTheme.urgentRed
        case .emptyRecording, .none:
            return SVTheme.textTertiary
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Refreshing transcript…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SVTheme.textPrimary)
            Text("Please keep this screen open while we rebuild your note.")
                .font(.caption)
                .foregroundStyle(SVTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContentUnavailableView {
                Label("Empty Recording", systemImage: "waveform.slash")
            } description: {
                Text(emptyRecordingMessage)
            }

            Button {
                Task {
                    await retryTranscription()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.recording.isRetryingTranscription {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.recording.isRetryingTranscription ? "Retrying…" : "Retry Transcription")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(SVTheme.accent)
            .disabled(viewModel.recording.isRetryingTranscription)

            Button {
                showDiscardAlert = true
            } label: {
                Text("Discard Recording")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .tint(SVTheme.urgentRed)
        }
    }

    private func errorStateView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentUnavailableView {
                Label("We Couldn't Build This Note", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }

            Button {
                Task {
                    await retryTranscription()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.recording.isRetryingTranscription {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.recording.isRetryingTranscription ? "Retrying…" : "Retry Transcription")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(SVTheme.accent)
            .disabled(viewModel.recording.isRetryingTranscription)

            Button {
                showDiscardAlert = true
            } label: {
                Text("Discard Recording")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .tint(SVTheme.urgentRed)
        }
    }

    private var visibilityBadge: some View {
        HStack(spacing: 0) {
            ForEach(NoteVisibility.allCases, id: \.rawValue) { vis in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        noteVisibility = vis
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: vis.icon)
                            .font(.caption2)
                        Text(vis.label)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(noteVisibility == vis ? .white : SVTheme.textSecondary)
                    .background(noteVisibility == vis ? (vis == .personal ? Color.indigo : SVTheme.textPrimary) : Color.clear)
                    .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: noteVisibility)
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
                    Text(transcriptionFailureMessage)
                        .font(.caption)
                        .foregroundStyle(SVTheme.textSecondary)
                }

                Spacer(minLength: 0)
            }

            Button {
                Task {
                    await retryTranscription()
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
                    Image(systemName: transcriptStatusSymbol)
                        .font(.caption)
                    Text(transcriptStatusText)
                        .font(.caption)
                }
                .foregroundStyle(transcriptStatusColor)
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

            if editableCategorizedItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(SVTheme.textTertiary)
                    Text("No categorized items yet. You can still send this note.")
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
                ForEach($editableCategorizedItems) { $item in
                    EditableCategorizedItemRow(
                        item: $item,
                        showsWarningIndicator: warningItemIDs.contains(item.id),
                        emphasizeWarning: shouldEmphasizeWarningRows,
                        showsOfflineEstimateBadge: !usedAI,
                        onDelete: {
                            editableCategorizedItems.removeAll { $0.id == item.id }
                        }
                    )
                }
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
                if !editableActionItems.isEmpty {
                    Button {
                        approvedActionItemIds = Set(editableActionItems.map(\.id))
                    } label: {
                        Text("Approve All")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.accent)
                    }
                }
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

            if !editableActionItems.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: approvedActionItemIds.count == editableActionItems.count ? "checkmark.seal.fill" : "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(approvedActionItemIds.count == editableActionItems.count ? SVTheme.accent : SVTheme.textTertiary)
                    Text(approvedActionItemsStatusText)
                        .font(.caption)
                        .foregroundStyle(SVTheme.textSecondary)
                    Spacer()
                    if noteVisibility == .team {
                        Text("Owner optional")
                            .font(.caption2)
                            .foregroundStyle(SVTheme.textTertiary)
                    }
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
                            isApproved: approvedActionItemIds.contains(item.id),
                            showsWarningIndicator: warningItemIDs.contains(item.id),
                            emphasizeWarning: shouldEmphasizeWarningRows,
                            hideAssignee: noteVisibility == .personal,
                            onApprove: {
                                approvedActionItemIds.insert(item.id)
                            },
                            onUnapprove: {
                                approvedActionItemIds.remove(item.id)
                            },
                            onAssign: {
                                assigningActionId = item.id
                                showAssignSheet = true
                            },
                            onDelete: {
                                approvedActionItemIds.remove(item.id)
                                editableActionItems.removeAll { $0.id == item.id }
                            }
                        )

                        if index < editableActionItems.count - 1 {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 18)
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
        VStack(spacing: 0) {
            Rectangle()
                .fill(SVTheme.surfaceBorder.opacity(0.8))
                .frame(height: 1)

            HStack(spacing: 12) {
                Button {
                    showDiscardAlert = true
                } label: {
                    Text("Discard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
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
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: noteVisibility == .personal ? "square.and.arrow.down.fill" : "paperplane.fill")
                                .font(.subheadline)
                        }
                        Text(noteVisibility == .personal ? "Save to My Notes" : "Approve & Send")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(isPublishing ? SVTheme.accent.opacity(0.6) : SVTheme.accent)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(isPublishing || screenState == .loading)
                .sensoryFeedback(.success, trigger: publishSucceeded)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
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

        let unapprovedCount = editableActionItems.count - approvedActionItemIds.count
        if unapprovedCount > 0 {
            publishValidationError = unapprovedCount == 1 ? "Approve the remaining action item before sending." : "Approve all action items before sending."
            return
        }

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
            actionItems: actionItems,
            visibility: noteVisibility
        )

        let didPublish = onPublish(note)
        guard didPublish else {
            isPublishing = false
            publishValidationError = viewModel.publishError ?? "Couldn't send note. Please review and try again."
            viewModel.trackReviewFlowEvent(.publishFailed(source: source, returnDestination: returnDestination, message: publishValidationError ?? "unknown"))
            return
        }

        let trackedEdits = UserEditTracker.shared.diff(
            initialCategorizedItems: initialCategorizedItems.map { $0.toCategorizedItem() },
            initialActionItems: initialActionItems.map { $0.toActionItem() },
            finalCategorizedItems: categorizedItems,
            finalActionItems: actionItems,
            transcriptId: transcriptId
        )
        UserEditTracker.shared.store(trackedEdits)

        viewModel.trackReviewFlowEvent(.published(source: source, returnDestination: returnDestination, noteId: note.id))
        publishSucceeded = true
    }

    private func retryTranscription() async {
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
            recordingFailureState = updated.recordingFailureState
            confidenceScore = updated.confidenceScore
            validationWarnings = updated.validationWarnings
            warningItemIDs = updated.warningItemIDs
            usedAI = updated.usedAI
        }

        recordingFailureState = viewModel.recording.recordingFailureState
    }

    private var shouldEmphasizeWarningRows: Bool {
        confidenceBand == .low
    }

    private var confidenceBand: ReviewConfidenceBand {
        if !usedAI {
            return .fallback
        }
        if confidenceScore < 0.60 {
            return .low
        }
        if confidenceScore < 0.85 {
            return .medium
        }
        return .high
    }

    private var confidenceReviewBanner: AnyView? {
        switch confidenceBand {
        case .high:
            return nil
        case .medium:
            return AnyView(confidenceBanner(
                title: "We structured your note. Tap any item to adjust.",
                subtitle: nil,
                symbol: "checkmark.seal",
                tint: SVTheme.amber,
                prominence: .subtle
            ))
        case .low:
            return AnyView(confidenceBanner(
                title: "We had trouble with some parts. Please review.",
                subtitle: "Did we get this right?",
                symbol: "exclamationmark.triangle.fill",
                tint: SVTheme.amber,
                prominence: .strong
            ))
        case .fallback:
            return AnyView(confidenceBanner(
                title: "Structured offline — AI refinement will update when connected.",
                subtitle: nil,
                symbol: "wifi.exclamationmark",
                tint: SVTheme.amber,
                prominence: .subtle
            ))
        }
    }

    private func confidenceBanner(
        title: String,
        subtitle: String?,
        symbol: String,
        tint: Color,
        prominence: BannerProminence
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(SVTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(prominence == .strong ? tint.opacity(0.14) : tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(prominence == .strong ? 0.35 : 0.2), lineWidth: 1)
        )
    }

    private var approvedActionItemsStatusText: String {
        let total = editableActionItems.count
        let approved = approvedActionItemIds.count
        if total == 0 {
            return "No action items"
        }
        if approved == total {
            return "All \(total) action items approved"
        }
        return "\(approved) of \(total) approved"
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
            task: TranscriptProcessor.polishActionTask(task),
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
    let showsWarningIndicator: Bool
    let emphasizeWarning: Bool
    let showsOfflineEstimateBadge: Bool
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
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.content)
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .lineSpacing(2)

                        if showsWarningIndicator {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(SVTheme.amber)
                        }
                    }

                    HStack(spacing: 6) {
                        CategoryPill(info: CategoryDisplayInfo(from: item.category))
                        UrgencyBadge(urgency: item.urgency)
                        if showsOfflineEstimateBadge {
                            Text("Estimated (offline)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(SVTheme.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(SVTheme.iconBackground)
                                .clipShape(.rect(cornerRadius: 6))
                        }
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
        .background(emphasizeWarning && showsWarningIndicator ? SVTheme.amber.opacity(0.08) : SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(emphasizeWarning && showsWarningIndicator ? SVTheme.amber.opacity(0.45) : SVTheme.surfaceBorder, lineWidth: 1)
        )
    }
}

struct EditableActionItemRow: View {
    @Binding var item: EditableActionItem
    let isApproved: Bool
    let showsWarningIndicator: Bool
    let emphasizeWarning: Bool
    var hideAssignee: Bool = false
    let onApprove: () -> Void
    let onUnapprove: () -> Void
    let onAssign: () -> Void
    let onDelete: () -> Void
    @State private var isEditing: Bool = false
    @State private var showSuggestion: Bool = true
    @State private var showUrgencyMenu: Bool = false

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

    private var confidenceLabel: String? {
        if showsWarningIndicator {
            return "Needs review"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if showsWarningIndicator {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(SVTheme.amber)
                }
                if let confidenceLabel {
                    Text(confidenceLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(SVTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if isEditing {
                TextField("Action item...", text: $item.task, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(SVTheme.textPrimary)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(SVTheme.surfaceSecondary)
                    .clipShape(.rect(cornerRadius: 10))
                    .onSubmit { isEditing = false }
            } else {
                Text(item.task)
                    .font(.body)
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

            HStack(spacing: 10) {
                Button {
                    showUrgencyMenu = true
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(SVTheme.urgencyColor(item.urgency))
                            .frame(width: 8, height: 8)
                        Text(item.urgency.rawValue)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(SVTheme.urgencyColor(item.urgency))
                    .background(SVTheme.urgencyColor(item.urgency).opacity(0.1))
                    .clipShape(.rect(cornerRadius: 9))
                }
                .confirmationDialog("Select Urgency", isPresented: $showUrgencyMenu, titleVisibility: .visible) {
                    ForEach(UrgencyLevel.allCases) { level in
                        Button(level.rawValue) {
                            item.urgency = level
                        }
                    }
                }

                if !hideAssignee {
                    Button {
                        onAssign()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.assignee != nil ? "person.fill" : "person")
                                .font(.system(size: 11, weight: .medium))
                            Text(item.assignee ?? "Unassigned")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(item.assignee != nil ? SVTheme.accent : SVTheme.textTertiary)
                        .background(item.assignee != nil ? SVTheme.accent.opacity(0.1) : SVTheme.iconBackground)
                        .clipShape(.rect(cornerRadius: 9))
                    }
                }

                Spacer()

                Button {
                    if isApproved {
                        onUnapprove()
                    } else {
                        onApprove()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isApproved ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption.weight(.semibold))
                        Text(isApproved ? "Approved" : "Approve")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(isApproved ? .white : SVTheme.accent)
                    .background(isApproved ? SVTheme.accent : SVTheme.accent.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 9))
                }
                .sensoryFeedback(.success, trigger: isApproved)

                Menu {
                    Button {
                        isEditing.toggle()
                    } label: {
                        Label("Refine wording", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(emphasizeWarning && showsWarningIndicator ? SVTheme.amber.opacity(0.08) : Color.clear)
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
