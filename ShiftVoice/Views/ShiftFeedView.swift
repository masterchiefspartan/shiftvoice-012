import SwiftUI

struct ShiftFeedView: View {
    @Bindable var viewModel: AppViewModel
    @State private var selectedShiftFilter: ShiftDisplayInfo? = nil
    @State private var selectedNoteId: String? = nil
    @State private var showLocationPicker: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    locationHeader
                        .padding(.horizontal, 24)
                    filterBar
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
                    Text("Inbox")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: String.self) { noteId in
                if let note = viewModel.shiftNotes.first(where: { $0.id == noteId }) {
                    ShiftNoteDetailView(
                        note: note,
                        isAcknowledged: viewModel.isNoteAcknowledged(note),
                        onAcknowledge: { viewModel.acknowledgeNote(noteId) }
                    )
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                locationPickerSheet
            }
            .onAppear {
                viewModel.loadFirstPage(shiftFilter: selectedShiftFilter?.id)
            }
            .onChange(of: viewModel.selectedLocationId) { _, _ in
                viewModel.loadFirstPage(shiftFilter: selectedShiftFilter?.id)
            }
            .onChange(of: selectedShiftFilter) { _, newValue in
                viewModel.loadFirstPage(shiftFilter: newValue?.id)
            }
            .refreshable {
                viewModel.loadFirstPage(shiftFilter: selectedShiftFilter?.id)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle()
                    .fill(SVTheme.divider)
                    .frame(height: 1 / UIScreen.main.scale)
                    .padding(.top, -1)
            }
        }
    }

    private var locationHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Inbox")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(SVTheme.textPrimary)
                .tracking(-0.5)

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
        let notes = viewModel.filteredPaginatedNotes(shiftDisplayFilter: selectedShiftFilter)
        return Group {
            if notes.isEmpty && !viewModel.isLoadingPage {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundStyle(SVTheme.textTertiary)
                    Text("No shift notes yet")
                        .font(.headline)
                        .foregroundStyle(SVTheme.textSecondary)
                    Text("Tap the mic button to record your first shift note")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes, id: \.id) { note in
                        NavigationLink(value: note.id) {
                            ShiftNoteCardView(
                                note: note,
                                isAcknowledged: viewModel.isNoteAcknowledged(note)
                            )
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if note.id == notes.last?.id && viewModel.hasMoreNotes {
                                viewModel.loadNextPage(shiftFilter: selectedShiftFilter?.id)
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
                            Text("Loading more...")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
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

    private var locationPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ForEach(viewModel.locations) { location in
                    Button {
                        viewModel.selectedLocationId = location.id
                        viewModel.updateUnacknowledgedCount()
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
