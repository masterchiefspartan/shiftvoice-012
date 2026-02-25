import SwiftUI

struct DashboardView: View {
    @Bindable var viewModel: AppViewModel
    @Binding var navPath: NavigationPath
    @State private var selectedUrgencyFilter: UrgencyLevel? = nil
    @State private var selectedStatusFilter: ActionItemStatus? = nil
    @State private var selectedLocationFilter: String? = nil
    @State private var selectedCategoryFilter: CategoryDisplayInfo? = nil
    @State private var selectedDateRange: DateRangeFilter = .all
    @State private var showRecurringIssues: Bool = false
    @State private var showFilterSheet: Bool = false

    private var activeFilterCount: Int {
        var count = 0
        if selectedUrgencyFilter != nil { count += 1 }
        if selectedStatusFilter != nil { count += 1 }
        if selectedLocationFilter != nil { count += 1 }
        if selectedCategoryFilter != nil { count += 1 }
        if selectedDateRange != .all { count += 1 }
        return count
    }

    private var filteredActions: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)] {
        viewModel.allActionItemsWithDate.filter { entry in
            if let urgency = selectedUrgencyFilter, entry.item.urgency != urgency { return false }
            if let status = selectedStatusFilter, entry.item.status != status { return false }
            if let locId = selectedLocationFilter, entry.locationId != locId { return false }
            if let cat = selectedCategoryFilter, entry.item.displayInfo.id != cat.id { return false }
            if selectedDateRange != .all {
                let cutoff = selectedDateRange.cutoffDate
                if entry.createdAt < cutoff { return false }
            }
            return true
        }
        .sorted { $0.item.urgency.sortOrder < $1.item.urgency.sortOrder }
    }

    private var openCount: Int {
        viewModel.allActionItemsWithDate.filter { $0.item.status == .open }.count
    }

    private var immediateCount: Int {
        viewModel.allActionItemsWithDate.filter { $0.item.urgency == .immediate && $0.item.status != .resolved }.count
    }

    private var inProgressCount: Int {
        viewModel.allActionItemsWithDate.filter { $0.item.status == .inProgress }.count
    }

    private var resolvedCount: Int {
        viewModel.allActionItemsWithDate.filter { $0.item.status == .resolved }.count
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = viewModel.currentUserName.split(separator: " ").first.map(String.init) ?? "there"
        if hour < 12 { return "Good morning, \(firstName)" }
        if hour < 17 { return "Good afternoon, \(firstName)" }
        return "Good evening, \(firstName)"
    }

    private var activeCategories: [CategoryDisplayInfo] {
        let infos = viewModel.allActionItemsWithDate.map(\.item.displayInfo)
        var seen = Set<String>()
        return infos.filter { seen.insert($0.id).inserted }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    statsStrip
                    filterSection
                    actionItemsList
                    recurringIssuesSection
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
                    Text("Actions")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: String.self) { noteId in
                ShiftNoteDetailView(noteId: noteId, viewModel: viewModel)
            }
            .sheet(isPresented: $showFilterSheet) {
                filterSheetContent
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(greeting)
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(SVTheme.textPrimary)
                .tracking(-0.5)

            let unresolvedTotal = openCount + inProgressCount + immediateCount
            if unresolvedTotal > 0 {
                Text("You have \(filteredActions.filter { $0.item.status != .resolved }.count) items that need your attention")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
            } else {
                Text("All caught up — nothing needs your attention")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.successGreen)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsStrip: some View {
        HStack(spacing: 0) {
            ActionStatCell(
                value: immediateCount,
                label: "URGENT",
                color: SVTheme.urgentRed,
                isSelected: selectedUrgencyFilter == .immediate
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedUrgencyFilter = selectedUrgencyFilter == .immediate ? nil : .immediate
                    selectedStatusFilter = nil
                }
            }

            Rectangle().fill(SVTheme.divider).frame(width: 1)

            ActionStatCell(
                value: openCount,
                label: "OPEN",
                color: SVTheme.amber,
                isSelected: selectedStatusFilter == .open
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedStatusFilter = selectedStatusFilter == .open ? nil : .open
                    selectedUrgencyFilter = nil
                }
            }

            Rectangle().fill(SVTheme.divider).frame(width: 1)

            ActionStatCell(
                value: inProgressCount,
                label: "IN PROGRESS",
                color: SVTheme.infoBlue,
                isSelected: selectedStatusFilter == .inProgress
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedStatusFilter = selectedStatusFilter == .inProgress ? nil : .inProgress
                    selectedUrgencyFilter = nil
                }
            }

            Rectangle().fill(SVTheme.divider).frame(width: 1)

            ActionStatCell(
                value: resolvedCount,
                label: "DONE",
                color: SVTheme.successGreen,
                isSelected: selectedStatusFilter == .resolved
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedStatusFilter = selectedStatusFilter == .resolved ? nil : .resolved
                    selectedUrgencyFilter = nil
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

    private var filterSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    showFilterSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.caption)
                        Text("Filters")
                            .font(.caption.weight(.medium))
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(SVTheme.accent)
                                .clipShape(Circle())
                        }
                    }
                    .foregroundStyle(activeFilterCount > 0 ? SVTheme.accent : SVTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(activeFilterCount > 0 ? SVTheme.accent.opacity(0.06) : SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(activeFilterCount > 0 ? SVTheme.accent.opacity(0.2) : SVTheme.surfaceBorder, lineWidth: 1)
                    )
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(DateRangeFilter.allCases) { range in
                            if range != .all {
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedDateRange = selectedDateRange == range ? .all : range
                                    }
                                } label: {
                                    Text(range.label)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(selectedDateRange == range ? .white : SVTheme.textSecondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedDateRange == range ? SVTheme.textPrimary : SVTheme.surface)
                                        .clipShape(.rect(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedDateRange == range ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, 0)
            }

            if !activeCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeCategories) { cat in
                            let isSelected = selectedCategoryFilter?.id == cat.id
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedCategoryFilter = isSelected ? nil : cat
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 9))
                                    Text(cat.name)
                                        .font(.caption2.weight(.medium))
                                }
                                .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? cat.color : SVTheme.surface)
                                .clipShape(.rect(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, 0)
            }

            if !activeLocationChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.locations) { location in
                            let isSelected = selectedLocationFilter == location.id
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    selectedLocationFilter = isSelected ? nil : location.id
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "mappin")
                                        .font(.system(size: 9))
                                    Text(location.name)
                                        .font(.caption2.weight(.medium))
                                }
                                .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSelected ? SVTheme.textPrimary : SVTheme.surface)
                                .clipShape(.rect(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, 0)
            }
        }
    }

    private var activeLocationChips: [Location] {
        viewModel.locations
    }

    private var actionItemsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(filteredActions.count) Action Items")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SVTheme.textSecondary)
                Spacer()
                if activeFilterCount > 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            clearAllFilters()
                        }
                    } label: {
                        Text("Clear all")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SVTheme.accent)
                    }
                }
            }

            if filteredActions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredActions.enumerated()), id: \.element.item.id) { index, entry in
                        NavigationLink(value: entry.noteId) {
                            ActionItemRow(
                                item: entry.item,
                                authorName: entry.authorName,
                                locationName: viewModel.locationName(for: entry.locationId),
                                noteId: entry.noteId,
                                onStatusChange: { newStatus in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        viewModel.updateActionItemStatus(
                                            noteId: entry.noteId,
                                            actionItemId: entry.item.id,
                                            newStatus: newStatus
                                        )
                                    }
                                },
                                onDismissConflict: entry.item.hasConflict ? {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        viewModel.dismissConflict(noteId: entry.noteId, actionItemId: entry.item.id)
                                    }
                                } : nil
                            )
                        }
                        .buttonStyle(.plain)

                        if index < filteredActions.count - 1 {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 52)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(SVTheme.textTertiary)
            Text("All clear")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SVTheme.textPrimary)
            Text("No action items match your filters")
                .font(.caption)
                .foregroundStyle(SVTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var recurringIssuesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    showRecurringIssues.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(SVTheme.iconBackground)
                        .clipShape(.rect(cornerRadius: 6))

                    Text("Recurring Issues")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)

                    let activeCount = viewModel.recurringIssues.filter { $0.status == .active }.count
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(SVTheme.urgentRed)
                            .clipShape(Circle())
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textTertiary)
                        .rotationEffect(.degrees(showRecurringIssues ? 90 : 0))
                }
                .padding(16)
                .background(SVTheme.cardBackground)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                )
            }

            if showRecurringIssues {
                if viewModel.recurringIssues.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 24))
                            .foregroundStyle(SVTheme.textTertiary)
                        Text("No recurring issues")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textSecondary)
                        Text("Issues mentioned across multiple shifts will appear here")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(SVTheme.cardBackground)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )
                    .transition(.opacity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.recurringIssues.enumerated()), id: \.element.id) { index, issue in
                            RecurringIssueRow(
                                issue: issue,
                                onAcknowledge: { viewModel.acknowledgeRecurringIssue(issue.id) },
                                onResolve: { viewModel.resolveRecurringIssue(issue.id) }
                            )

                            if index < viewModel.recurringIssues.count - 1 {
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
                    .transition(.opacity)
                }
            }
        }
    }

    private var filterSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    filterSheetSection(title: "URGENCY") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(UrgencyLevel.allCases) { level in
                                let isSelected = selectedUrgencyFilter == level
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedUrgencyFilter = isSelected ? nil : level
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(SVTheme.urgencyColor(level))
                                            .frame(width: 6, height: 6)
                                        Text(level.rawValue)
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(isSelected ? SVTheme.urgencyColor(level).opacity(0.08) : SVTheme.surface)
                                    .foregroundStyle(isSelected ? SVTheme.urgencyColor(level) : SVTheme.textSecondary)
                                    .clipShape(.rect(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(isSelected ? SVTheme.urgencyColor(level).opacity(0.3) : SVTheme.surfaceBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    filterSheetSection(title: "STATUS") {
                        HStack(spacing: 8) {
                            ForEach([ActionItemStatus.open, .inProgress, .resolved], id: \.rawValue) { status in
                                let isSelected = selectedStatusFilter == status
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedStatusFilter = isSelected ? nil : status
                                    }
                                } label: {
                                    Text(status.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? SVTheme.textPrimary : SVTheme.surface)
                                        .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }

                    filterSheetSection(title: "CATEGORY") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                            ForEach(activeCategories) { cat in
                                let isSelected = selectedCategoryFilter?.id == cat.id
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedCategoryFilter = isSelected ? nil : cat
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: cat.icon)
                                            .font(.caption2)
                                        Text(cat.name)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? cat.color.opacity(0.08) : SVTheme.surface)
                                    .foregroundStyle(isSelected ? cat.color : SVTheme.textSecondary)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isSelected ? cat.color.opacity(0.3) : SVTheme.surfaceBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    filterSheetSection(title: "LOCATION") {
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                                let isSelected = selectedLocationFilter == location.id
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedLocationFilter = isSelected ? nil : location.id
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin")
                                            .font(.subheadline)
                                            .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)
                                            .frame(width: 36, height: 36)
                                            .background(isSelected ? SVTheme.accent.opacity(0.06) : SVTheme.iconBackground)
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
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(SVTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }

                                if index < viewModel.locations.count - 1 {
                                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 64)
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

                    filterSheetSection(title: "TIME RANGE") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(DateRangeFilter.allCases) { range in
                                let isSelected = selectedDateRange == range
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedDateRange = range
                                    }
                                } label: {
                                    Text(range.label)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? SVTheme.textPrimary : SVTheme.surface)
                                        .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if activeFilterCount > 0 {
                        Button("Reset") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                clearAllFilters()
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.urgentRed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFilterSheet = false }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }

    private func filterSheetSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)
            content()
        }
    }

    private func clearAllFilters() {
        selectedUrgencyFilter = nil
        selectedStatusFilter = nil
        selectedLocationFilter = nil
        selectedCategoryFilter = nil
        selectedDateRange = .all
    }
}

nonisolated enum DateRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Time"
    case today = "Today"
    case thisWeek = "This Week"
    case last24h = "Last 24h"
    case last3Days = "Last 3 Days"

    var id: String { rawValue }
    var label: String { rawValue }

    var cutoffDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all: return .distantPast
        case .today: return cal.startOfDay(for: now)
        case .thisWeek: return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .last24h: return cal.date(byAdding: .hour, value: -24, to: now) ?? now
        case .last3Days: return cal.date(byAdding: .day, value: -3, to: now) ?? now
        }
    }
}

struct ActionStatCell: View {
    let value: Int
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(isSelected ? color : SVTheme.textPrimary)
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(SVTheme.textTertiary)
                    .tracking(0.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? color.opacity(0.06) : Color.clear)
        }
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let authorName: String
    let locationName: String
    let noteId: String
    let onStatusChange: (ActionItemStatus) -> Void
    var onDismissConflict: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.hasConflict, let desc = item.conflictDescription {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(SVTheme.amber)
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let dismiss = onDismissConflict {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(SVTheme.textTertiary)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(SVTheme.amber.opacity(0.08))
            }

        HStack(alignment: .top, spacing: 12) {
            Button {
                let next: ActionItemStatus = switch item.status {
                case .open: .inProgress
                case .inProgress: .resolved
                case .resolved: .open
                }
                onStatusChange(next)
            } label: {
                Image(systemName: statusIcon)
                    .font(.body)
                    .foregroundStyle(statusColor)
                    .frame(width: 28, height: 28)
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: item.status)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.task)
                    .font(.subheadline)
                    .foregroundStyle(item.status == .resolved ? SVTheme.textTertiary : SVTheme.textPrimary)
                    .strikethrough(item.status == .resolved, color: SVTheme.textTertiary)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SVTheme.urgencyColor(item.urgency))
                            .frame(width: 5, height: 5)
                        Text(item.urgency.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SVTheme.textTertiary)
                    }

                    Text("·")
                        .foregroundStyle(SVTheme.textTertiary)

                    Text(locationName)
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textTertiary)

                    Text("·")
                        .foregroundStyle(SVTheme.textTertiary)

                    Text(authorName)
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }

            Spacer(minLength: 4)

            Menu {
                Button { onStatusChange(.open) } label: {
                    Label("Open", systemImage: "circle")
                }
                Button { onStatusChange(.inProgress) } label: {
                    Label("In Progress", systemImage: "circle.dotted.and.circle")
                }
                Button { onStatusChange(.resolved) } label: {
                    Label("Resolved", systemImage: "checkmark.circle.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SVTheme.textTertiary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        }
    }

    private var statusIcon: String {
        switch item.status {
        case .open: return "circle"
        case .inProgress: return "circle.dotted.and.circle"
        case .resolved: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .open: return SVTheme.textTertiary
        case .inProgress: return SVTheme.infoBlue
        case .resolved: return SVTheme.successGreen
        }
    }
}

struct RecurringIssueRow: View {
    let issue: RecurringIssue
    let onAcknowledge: () -> Void
    let onResolve: () -> Void

    private var catInfo: CategoryDisplayInfo { issue.displayInfo }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: catInfo.icon)
                    .font(.caption)
                    .foregroundStyle(catInfo.color)
                    .frame(width: 28, height: 28)
                    .background(catInfo.color.opacity(0.08))
                    .clipShape(.rect(cornerRadius: 6))

                Text(issue.description)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("\(issue.mentionCount)x mentioned")
                        .font(.caption2)
                        .foregroundStyle(SVTheme.textTertiary)
                }

                Text("·")
                    .foregroundStyle(SVTheme.textTertiary)

                Text(issue.locationName)
                    .font(.caption2)
                    .foregroundStyle(SVTheme.textTertiary)

                Spacer()

                if issue.status == .active {
                    Button(action: onAcknowledge) {
                        Text("Ack")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(SVTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SVTheme.surface)
                            .clipShape(.rect(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                            )
                    }
                    Button(action: onResolve) {
                        Text("Resolve")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SVTheme.accent)
                            .clipShape(.rect(cornerRadius: 6))
                    }
                } else {
                    Text(issue.status.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor)
                }
            }
        }
        .padding(16)
    }

    private var statusColor: Color {
        switch issue.status {
        case .active: return SVTheme.urgentRed
        case .acknowledged: return SVTheme.amber
        case .resolved: return SVTheme.successGreen
        }
    }
}
