import SwiftUI

struct ShiftFeedView: View {
    @Bindable var viewModel: AppViewModel
    @Binding var navPath: NavigationPath
    @State private var selectedShiftFilter: ShiftDisplayInfo? = nil
    @State private var showLocationPicker: Bool = false
    @State private var searchText: String = ""
    @State private var isSearchActive: Bool = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var showOnlyConflictedNotes: Bool = false
    @State private var selectedConflictNoteId: String?
    @State private var showConflictSheet: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPersonalScope: Bool {
        viewModel.feedScope == .personal
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 24) {
                    feedScopeToggle
                        .padding(.horizontal, 24)
                    if !isPersonalScope {
                        locationHeader
                            .padding(.horizontal, 24)
                    }
                    searchBar
                        .padding(.horizontal, 24)
                    if !isSearchActive && !isPersonalScope {
                        filterBar
                    }
                    if !isPersonalScope, viewModel.featureFlags.conflictUIEnabled, viewModel.hasActiveConflicts {
                        conflictSummaryBanner
                            .padding(.horizontal, 24)
                    }
                    notesList
                        .padding(.horizontal, 24)
                }
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(SVTheme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Feed")
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
            .sheet(isPresented: $showLocationPicker) {
                locationPickerSheet
            }
            .sheet(isPresented: $showConflictSheet) {
                if viewModel.featureFlags.conflictUIEnabled, let noteId = selectedConflictNoteId {
                    ConflictDetailView(noteId: noteId, viewModel: viewModel)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .presentationContentInteraction(.scrolls)
                }
            }
            .onAppear {
                let shiftFilterId = isPersonalScope ? nil : selectedShiftFilter?.id
                viewModel.loadFirstPage(shiftFilter: shiftFilterId)
            }
            .onChange(of: viewModel.selectedLocationId) { _, _ in
                let shiftFilterId = isPersonalScope ? nil : selectedShiftFilter?.id
                viewModel.loadFirstPage(shiftFilter: shiftFilterId)
            }
            .onChange(of: selectedShiftFilter) { _, newValue in
                let shiftFilterId = isPersonalScope ? nil : newValue?.id
                viewModel.loadFirstPage(shiftFilter: shiftFilterId)
            }
            .onChange(of: viewModel.feedScope) { _, newValue in
                let shiftFilterId = newValue == .personal ? nil : selectedShiftFilter?.id
                viewModel.loadFirstPage(shiftFilter: shiftFilterId)
            }
            .onChange(of: searchText) { _, newValue in
                searchDebounceTask?.cancel()
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    viewModel.searchQuery = ""
                    withAnimation(.easeOut(duration: 0.2)) { isSearchActive = false }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { isSearchActive = true }
                    searchDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        if !Task.isCancelled {
                            viewModel.searchQuery = trimmed
                        }
                    }
                }
            }
            .refreshable {
                viewModel.loadFirstPage(shiftFilter: isPersonalScope ? nil : selectedShiftFilter?.id)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(SVTheme.divider)
                    .frame(height: 1 / UIScreen.main.scale)
                    .padding(.top, -1)
            }
        }
    }

    private var feedScopeToggle: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.feedScope = .team
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                    Text("Team Feed")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(viewModel.feedScope == .team ? .white : SVTheme.textSecondary)
                .background(viewModel.feedScope == .team ? SVTheme.textPrimary : Color.clear)
                .clipShape(.rect(cornerRadius: 8))
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewModel.feedScope = .personal
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text("My Notes")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(viewModel.feedScope == .personal ? .white : SVTheme.textSecondary)
                .background(viewModel.feedScope == .personal ? Color.indigo : Color.clear)
                .clipShape(.rect(cornerRadius: 8))
            }
        }
        .padding(3)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
        .sensoryFeedback(.selection, trigger: viewModel.feedScope)
    }

    private var locationHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Text("Team Feed")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .tracking(-0.5)
                Spacer()
                if let syncError = viewModel.syncError {
                    Button {
                        viewModel.forceSync()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.caption2)
                            Text("Retry")
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(SVTheme.urgentRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(SVTheme.urgentRed.opacity(0.08))
                        .clipShape(.rect(cornerRadius: 6))
                    }
                } else if let lastSync = viewModel.lastSyncDate {
                    Text(lastSyncLabel(lastSync))
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textTertiary)
                        .padding(.top, 8)
                }
            }

            Button {
                showLocationPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(SVTheme.iconBackground)
                        .clipShape(.rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.selectedLocation?.name ?? "Select Location")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textPrimary)
                        Text(viewModel.selectedLocation?.address ?? "")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(16)
                .background(SVTheme.cardBackground)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                )
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(searchText.isEmpty ? SVTheme.textTertiary : SVTheme.textSecondary)

            TextField("Search notes, tasks, people…", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textPrimary)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.searchQuery = ""
                    withAnimation(.easeOut(duration: 0.2)) { isSearchActive = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSearchActive ? SVTheme.accent.opacity(0.3) : SVTheme.surfaceBorder, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isSearchActive)
    }

    private var availableShifts: [ShiftDisplayInfo] {
        let template = IndustrySeed.template(for: viewModel.organizationBusinessType)
        return template.defaultShifts.map { ShiftDisplayInfo(from: $0) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", isSelected: selectedShiftFilter == nil) {
                    withAnimation(.easeOut(duration: 0.2)) { selectedShiftFilter = nil }
                }
                ForEach(availableShifts) { shift in
                    FilterChip(
                        title: shift.name,
                        icon: shift.icon,
                        isSelected: selectedShiftFilter?.id == shift.id
                    ) {
                        withAnimation(.easeOut(duration: 0.2)) { selectedShiftFilter = shift }
                    }
                }
            }
        }
        .contentMargins(.horizontal, 24)
    }

    private var notesList: some View {
        Group {
            if isSearchActive {
                searchResultsList
            } else if viewModel.isInitialLoading {
                skeletonList
            } else {
                paginatedNotesList
            }
        }
    }

    private var paginatedNotesList: some View {
        let notes = filteredPaginatedNotes
        return Group {
            if notes.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes, id: \.id) { note in
                        NavigationLink(value: AppRoute.shiftNoteDetail(noteId: note.id)) {
                            ShiftNoteCardView(
                                note: note,
                                isAcknowledged: viewModel.isNoteAcknowledged(note),
                                activeConflictCount: viewModel.featureFlags.conflictUIEnabled ? viewModel.activeConflictsForNote(note.id).count : 0,
                                onTapConflictBadge: viewModel.featureFlags.conflictUIEnabled ? {
                                    selectedConflictNoteId = note.id
                                    showConflictSheet = true
                                } : nil
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if note.id == notes.last?.id && viewModel.hasMoreNotes {
                                viewModel.loadNextPage(shiftFilter: isPersonalScope ? nil : selectedShiftFilter?.id)
                            }
                        }

                        if note.id != notes.last?.id {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                        }
                    }

                    if viewModel.isLoadingPage {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading more…")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }

                    if !viewModel.hasMoreNotes && viewModel.totalNoteCount > 20 {
                        Text("All \(viewModel.totalNoteCount) notes loaded")
                            .font(.caption2)
                            .foregroundStyle(SVTheme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
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

    private var searchResultsList: some View {
        let results = viewModel.searchResults
        return Group {
            if results.isEmpty && !viewModel.searchQuery.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(SVTheme.textTertiary)
                    Text("No results")
                        .font(.headline)
                        .foregroundStyle(SVTheme.textSecondary)
                    Text("No notes for: \(viewModel.searchQuery)")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 48)
            } else if results.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(results.count >= 50 ? "50+ results" : "\(results.count) result\(results.count == 1 ? "" : "s")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textTertiary)

                    LazyVStack(spacing: 0) {
                        ForEach(results, id: \.id) { note in
                            NavigationLink(value: AppRoute.shiftNoteDetail(noteId: note.id)) {
                                ShiftNoteCardView(
                                    note: note,
                                    isAcknowledged: viewModel.isNoteAcknowledged(note),
                                    activeConflictCount: viewModel.featureFlags.conflictUIEnabled ? viewModel.activeConflictsForNote(note.id).count : 0,
                                    onTapConflictBadge: viewModel.featureFlags.conflictUIEnabled ? {
                                        selectedConflictNoteId = note.id
                                        showConflictSheet = true
                                    } : nil
                                )
                            }
                            .buttonStyle(.plain)

                            if note.id != results.last?.id {
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
        }
    }

    private var skeletonList: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { index in
                ShiftNoteSkeletonRow()
                if index < 4 {
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: isPersonalScope ? "lock.doc" : "tray")
                .font(.system(size: 36))
                .foregroundStyle(isPersonalScope ? Color.indigo.opacity(0.5) : SVTheme.textTertiary)
            Text(isPersonalScope ? "No private notes yet" : "No shift notes yet")
                .font(.headline)
                .foregroundStyle(SVTheme.textSecondary)
            Text(isPersonalScope ? "Your private notes will appear here. Tap the mic to capture your first thought." : "Tap the mic button to record your first shift note")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var filteredPaginatedNotes: [ShiftNote] {
        let notes = viewModel.paginatedNotes
        guard showOnlyConflictedNotes else { return notes }
        return notes.filter { !viewModel.activeConflictsForNote($0.id).isEmpty }
    }

    private var conflictSummaryBanner: some View {
        Button {
            showOnlyConflictedNotes.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)

                Text("\(viewModel.activeConflictCount) conflict\(viewModel.activeConflictCount == 1 ? "" : "s") need your attention")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SVTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text(showOnlyConflictedNotes ? "Showing" : "Show")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(12)
            .background(SVTheme.amber.opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SVTheme.amber.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(viewModel.activeConflictCount) conflicts need attention")
        .accessibilityHint(showOnlyConflictedNotes ? "Shows all notes" : "Filters notes to conflicted only")
    }

    private func lastSyncLabel(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Synced just now" }
        if interval < 3600 { return "Synced \(Int(interval / 60))m ago" }
        if interval < 86400 { return "Synced \(Int(interval / 3600))h ago" }
        return "Synced \(Int(interval / 86400))d ago"
    }

    private var locationPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(viewModel.locations) { location in
                    Button {
                        viewModel.updateSelectedLocation(location.id)
                        showLocationPicker = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin")
                                .font(.subheadline)
                                .foregroundStyle(SVTheme.textTertiary)
                                .frame(width: 36, height: 36)
                                .background(SVTheme.iconBackground)
                                .clipShape(.rect(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SVTheme.textPrimary)
                                Text(location.address)
                                    .font(.caption)
                                    .foregroundStyle(SVTheme.textTertiary)
                            }

                            Spacer()

                            if location.id == viewModel.selectedLocationId {
                                Image(systemName: "checkmark")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SVTheme.accent)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                    }

                    if location.id != viewModel.locations.last?.id {
                        Rectangle()
                            .fill(SVTheme.divider)
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.top, 8)
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showLocationPicker = false }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? SVTheme.textPrimary : SVTheme.surface)
            .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }
}

struct ShiftNoteSkeletonRow: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(shimmerColor)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerColor)
                    .frame(height: 13)
                    .frame(maxWidth: .infinity)

                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerColor)
                    .frame(height: 11)
                    .frame(maxWidth: 200)

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(shimmerColor)
                        .frame(width: 50, height: 9)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(shimmerColor)
                        .frame(width: 70, height: 9)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private var shimmerColor: Color {
        Color(.systemFill).opacity(0.6 + 0.4 * phase)
    }
}
