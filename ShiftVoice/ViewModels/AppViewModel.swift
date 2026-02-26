import SwiftUI

@Observable
final class AppViewModel {
    var shiftNotes: [ShiftNote] = [] {
        didSet { invalidateCaches() }
    }
    var locations: [Location] = []
    var teamMembers: [TeamMember] = []
    var organization: Organization = Organization(name: "", ownerId: "")
    var recurringIssues: [RecurringIssue] = []

    var selectedLocationId: String = "" {
        didSet {
            guard oldValue != selectedLocationId else { return }
            invalidateCaches()
            loadFirstPage(shiftFilter: nil)
        }
    }
    var unacknowledgedCount: Int = 0

    var saveError: String?
    var toastMessage: ToastMessage?
    var publishError: String?
    var pendingPublishNote: ShiftNote?
    var showPaywall: Bool = false

    let networkMonitor = NetworkMonitor.shared
    var isOffline: Bool { !networkMonitor.isConnected }
    var hasPendingWrites: Bool = false
    var pendingOfflineCount: Int { shiftNotes.filter(\.isDirty).count }
    var hasPendingSyncIndicators: Bool { hasPendingWrites || pendingOfflineCount > 0 }

    // MARK: - Cached Computed Properties
    private(set) var feedNotes: [ShiftNote] = []
    private(set) var allActionItemsWithDate: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)] = []
    private(set) var notesThisMonth: Int = 0
    private(set) var conflictedActionItemsCache: [(item: ActionItem, noteId: String)] = []

    // MARK: - Pagination
    var paginatedNotes: [ShiftNote] = []
    var paginationCursor: String? = nil
    var hasMoreNotes: Bool = false
    var isLoadingPage: Bool = false
    var totalNoteCount: Int = 0
    private var currentShiftFilter: String? = nil
    private let pageSize = 20

    // MARK: - Loading State
    var isInitialLoading: Bool = true

    // MARK: - Action Items Pagination
    private let actionPageSize = 30
    var paginatedActionItems: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)] = []
    var hasMoreActionItems: Bool = false
    var isLoadingActionPage: Bool = false
    private var currentActionPage: Int = 0

    // MARK: - Search
    private let maxSearchResults = 50
    var searchQuery: String = ""
    var searchResults: [ShiftNote] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        var results: [ShiftNote] = []
        for note in feedNotes {
            if results.count >= maxSearchResults { break }
            if note.rawTranscript.lowercased().localizedStandardContains(q) ||
               note.summary.lowercased().localizedStandardContains(q) ||
               note.authorName.lowercased().localizedStandardContains(q) ||
               note.actionItems.contains(where: { $0.task.lowercased().localizedStandardContains(q) }) {
                results.append(note)
            }
        }
        return results
    }

    let recording = RecordingViewModel()
    private let firestore = FirestoreService.shared
    private let api = APIService.shared

    private(set) var userProfile: UserProfile?
    private var authenticatedUserId: String?
    private var organizationId: String?
    var lastSyncDate: Date?
    var syncError: String?

    var currentUserId: String { authenticatedUserId ?? "" }
    var currentUserName: String { userProfile?.name ?? "" }
    var currentUserInitials: String { userProfile?.initials ?? "" }
    var backendAuthToken: String? { api.currentAuthToken }

    var selectedLocation: Location? {
        locations.first { $0.id == selectedLocationId }
    }

    var organizationBusinessType: BusinessType {
        switch organization.industryType {
        case .restaurant: return .restaurant
        case .bar: return .barPub
        case .hotel: return .hotel
        case .cafe: return .cafe
        case .catering, .other: return .other
        }
    }

    var availableShifts: [ShiftDisplayInfo] {
        let template = IndustrySeed.template(for: organizationBusinessType)
        return template.defaultShifts.map { ShiftDisplayInfo(from: $0) }
    }

    var availableRoles: [RoleDisplayInfo] {
        let template = IndustrySeed.template(for: organizationBusinessType)
        return template.defaultRoles.map { RoleDisplayInfo(from: $0) }
    }

    var currentShiftType: ShiftType {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 { return .opening }
        if hour >= 12 && hour < 17 { return .mid }
        return .closing
    }

    var currentShiftDisplayInfo: ShiftDisplayInfo {
        let hour = Calendar.current.component(.hour, from: Date())
        let shifts = availableShifts
        guard !shifts.isEmpty else { return ShiftDisplayInfo(from: currentShiftType) }
        let template = IndustrySeed.template(for: organizationBusinessType)
        let sorted = template.defaultShifts.sorted { $0.defaultStartHour < $1.defaultStartHour }
        var best = sorted.last!
        for s in sorted {
            if hour >= s.defaultStartHour { best = s }
        }
        return ShiftDisplayInfo(from: best)
    }

    var allActionItems: [(item: ActionItem, noteId: String, authorName: String, locationId: String)] {
        allActionItemsWithDate.map { (item: $0.item, noteId: $0.noteId, authorName: $0.authorName, locationId: $0.locationId) }
    }

    var conflictedActionItems: [(item: ActionItem, noteId: String)] {
        conflictedActionItemsCache
    }

    init() {}

    // MARK: - Cache Invalidation

    private func invalidateCaches() {
        let newFeedNotes = shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .sorted { $0.createdAt > $1.createdAt }
        feedNotes = newFeedNotes

        allActionItemsWithDate = shiftNotes.flatMap { note in
            note.actionItems.map { (
                item: $0,
                noteId: note.id,
                authorName: note.authorName,
                locationId: note.locationId,
                createdAt: note.createdAt
            ) }
        }

        conflictedActionItemsCache = shiftNotes.flatMap { note in
            note.actionItems.filter { $0.hasConflict }.map { (item: $0, noteId: note.id) }
        }

        let calendar = Calendar.current
        let now = Date()
        let uid = currentUserId
        notesThisMonth = shiftNotes.filter {
            $0.authorId == uid &&
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }.count

        unacknowledgedCount = newFeedNotes
            .filter { !$0.acknowledgments.contains(where: { $0.userId == uid }) }
            .count

        refreshPaginatedNotes()
    }

    // MARK: - Pagination

    private func filteredSource(for shiftFilter: String?) -> [ShiftNote] {
        guard let filter = shiftFilter else { return feedNotes }
        return feedNotes.filter { $0.shiftDisplayInfo.id == filter }
    }

    private func refreshPaginatedNotes() {
        let source = filteredSource(for: currentShiftFilter)
        let preserve = max(paginatedNotes.count, pageSize)
        paginatedNotes = Array(source.prefix(preserve))
        hasMoreNotes = source.count > preserve
        totalNoteCount = source.count
    }

    func resetPagination() {
        paginatedNotes = []
        paginationCursor = nil
        hasMoreNotes = false
        totalNoteCount = 0
        isLoadingPage = false
    }

    func loadFirstPage(shiftFilter: String? = nil) {
        currentShiftFilter = shiftFilter
        isLoadingPage = false
        let source = filteredSource(for: shiftFilter)
        paginatedNotes = Array(source.prefix(pageSize))
        hasMoreNotes = source.count > pageSize
        totalNoteCount = source.count
    }

    // MARK: - Action Items Pagination

    func loadFirstActionPage(filtered: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)]) {
        currentActionPage = 0
        let page = Array(filtered.prefix(actionPageSize))
        paginatedActionItems = page
        hasMoreActionItems = filtered.count > actionPageSize
    }

    func loadNextActionPage(filtered: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)]) {
        guard !isLoadingActionPage, hasMoreActionItems else { return }
        isLoadingActionPage = true
        currentActionPage += 1
        let start = currentActionPage * actionPageSize
        let nextBatch = Array(filtered.dropFirst(start).prefix(actionPageSize))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            paginatedActionItems.append(contentsOf: nextBatch)
            hasMoreActionItems = paginatedActionItems.count < filtered.count
            isLoadingActionPage = false
        }
    }

    func loadNextPage(shiftFilter: String? = nil) {
        guard !isLoadingPage, hasMoreNotes else { return }
        isLoadingPage = true
        currentShiftFilter = shiftFilter
        let source = filteredSource(for: shiftFilter)
        let nextBatch = Array(source.dropFirst(paginatedNotes.count).prefix(pageSize))
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            paginatedNotes.append(contentsOf: nextBatch)
            hasMoreNotes = paginatedNotes.count < source.count
            totalNoteCount = source.count
            isLoadingPage = false
        }
    }

    // MARK: - Auth Lifecycle

    func setAuthenticatedUser(_ userId: String, name: String = "", email: String = "") {
        authenticatedUserId = userId

        if !name.isEmpty {
            let parts = name.split(separator: " ")
            let initials = parts.count >= 2
                ? "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
                : String(name.prefix(2)).uppercased()
            userProfile = UserProfile(id: userId, name: name, email: email, initials: initials, profileImageURL: nil)
        }

        Task {
            await loadUserData(userId)
            await syncSubscriptionPlan()
        }
    }

    func clearAuthenticatedUser() {
        api.clearAuth()
        firestore.stopAllListeners()
        authenticatedUserId = nil
        organizationId = nil
        userProfile = nil
        shiftNotes = []
        locations = []
        teamMembers = []
        recurringIssues = []
        organization = Organization(name: "", ownerId: "")
        selectedLocationId = ""
        unacknowledgedCount = 0
        lastSyncDate = nil
        syncError = nil
        hasPendingWrites = false
        isInitialLoading = true
    }

    private func loadUserData(_ userId: String) async {
        do {
            let (profile, orgId, locId) = try await firestore.fetchUserData(userId)
            if let profile { self.userProfile = profile }
            self.organizationId = orgId
            if let locId { self.selectedLocationId = locId }
            syncError = nil
            if let orgId {
                startListeners(orgId: orgId)
            } else {
                loadDemoData()
            }
        } catch {
            syncError = "Could not load your data. Tap to retry."
            isInitialLoading = false
            loadDemoData()
        }
    }

    private func applyShiftNotesSnapshot(_ notes: [ShiftNote]) {
        shiftNotes = notes
        isInitialLoading = false
    }

    private func applyShiftNotesMetadata(hasPendingWrites: Bool, isFromCache: Bool) {
        self.hasPendingWrites = hasPendingWrites
        if !hasPendingWrites && !isFromCache {
            lastSyncDate = Date()
        }
    }

    private func startListeners(orgId: String) {
        firestore.stopAllListeners()

        firestore.startOrganizationListener(orgId) { [weak self] org in
            guard let self, let org else { return }
            self.organization = org
        }

        firestore.startLocationsListener(orgId) { [weak self] locations in
            guard let self else { return }
            self.locations = locations
            if self.selectedLocationId.isEmpty, let first = locations.first {
                self.selectedLocationId = first.id
            }
        }

        firestore.startTeamMembersListener(orgId) { [weak self] members in
            guard let self else { return }
            self.teamMembers = members
        }

        firestore.startShiftNotesListener(
            orgId,
            onChange: { [weak self] notes in
                guard let self else { return }
                self.applyShiftNotesSnapshot(notes)
            },
            onMetadataChange: { [weak self] hasPendingWrites, isFromCache in
                guard let self else { return }
                self.applyShiftNotesMetadata(hasPendingWrites: hasPendingWrites, isFromCache: isFromCache)
            }
        )

        firestore.startRecurringIssuesListener(orgId) { [weak self] issues in
            guard let self else { return }
            self.recurringIssues = issues
        }
    }

    // MARK: - Backend API Auth

    func setBackendAuth(token: String, userId: String) {
        api.setAuth(token: token, userId: userId)
    }

    // MARK: - Firestore Write Helpers

    private func writeShiftNote(_ note: ShiftNote) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }
        do {
            try firestore.saveShiftNote(note, orgId: orgId)
        } catch {
            showToast("Failed to save note", isError: true)
        }
    }

    private func writeLocation(_ location: Location) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }
        do {
            try firestore.saveLocation(location, orgId: orgId)
        } catch {
            showToast("Failed to save location", isError: true)
        }
    }

    private func writeTeamMember(_ member: TeamMember) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }
        do {
            try firestore.saveTeamMember(member, orgId: orgId)
        } catch {
            showToast("Failed to save team member", isError: true)
        }
    }

    private func writeOrganization(_ org: Organization) {
        do {
            try firestore.saveOrganization(org)
        } catch {
            showToast("Failed to save organization", isError: true)
        }
    }

    private func writeRecurringIssue(_ issue: RecurringIssue) {
        guard let orgId = organizationId else { return }
        do {
            try firestore.saveRecurringIssue(issue, orgId: orgId)
        } catch {
            showToast("Failed to save issue", isError: true)
        }
    }

    // MARK: - Notes

    func publishReviewedNote(_ note: ShiftNote) {
        let validation = InputValidator.validateShiftNote(
            summary: note.summary,
            rawTranscript: note.rawTranscript,
            locationId: note.locationId,
            authorId: note.authorId
        )
        guard validation.isValid else {
            let firstError = validation.errors.values.first ?? "Invalid note data"
            publishError = firstError
            pendingPublishNote = note
            return
        }

        var mutableNote = note
        mutableNote.updatedAt = Date()
        publishError = nil
        pendingPublishNote = nil
        recording.discardPendingNote()

        shiftNotes.insert(mutableNote, at: 0)

        writeShiftNote(mutableNote)

        if !isOffline {
            showToast("Shift note published", isError: false)
        }
    }

    func deleteNote(_ noteId: String) {
        let removedNotes = shiftNotes.filter { $0.id == noteId }
        shiftNotes.removeAll { $0.id == noteId }

        guard let orgId = organizationId else { return }
        firestore.deleteShiftNote(noteId, orgId: orgId)

        showToast("Note deleted", isError: false)
    }

    func acknowledgeNote(_ noteId: String) {
        guard let index = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
        guard !shiftNotes[index].acknowledgments.contains(where: { $0.userId == currentUserId }) else { return }
        let ack = Acknowledgment(userId: currentUserId, userName: currentUserName)
        shiftNotes[index].acknowledgments.append(ack)
        shiftNotes[index].updatedAt = Date()
        writeShiftNote(shiftNotes[index])
    }

    func isNoteAcknowledged(_ note: ShiftNote) -> Bool {
        note.acknowledgments.contains { $0.userId == currentUserId }
    }

    func notesForLocation(_ locationId: String) -> [ShiftNote] {
        shiftNotes.filter { $0.locationId == locationId }
    }

    // MARK: - Action Items

    func updateActionItemStatus(noteId: String, actionItemId: String, newStatus: ActionItemStatus) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let oldStatus = shiftNotes[noteIndex].actionItems[itemIndex].status
        guard oldStatus != newStatus else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].status = newStatus
        shiftNotes[noteIndex].actionItems[itemIndex].statusUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAt = now
        writeShiftNote(shiftNotes[noteIndex])
    }

    func updateActionItemAssignee(noteId: String, actionItemId: String, assignee: String?, assigneeId: String? = nil) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].assignee = assignee
        shiftNotes[noteIndex].actionItems[itemIndex].assigneeId = assigneeId
        shiftNotes[noteIndex].actionItems[itemIndex].assigneeUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAt = now
        writeShiftNote(shiftNotes[noteIndex])
    }

    func dismissConflict(noteId: String, actionItemId: String) {
        guard let noteIdx = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIdx = shiftNotes[noteIdx].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        shiftNotes[noteIdx].actionItems[itemIdx].hasConflict = false
        shiftNotes[noteIdx].actionItems[itemIdx].conflictDescription = nil
        writeShiftNote(shiftNotes[noteIdx])
    }

    // MARK: - Locations

    func addLocation(_ location: Location) {
        if let error = InputValidator.validateLocationName(location.name) {
            showToast(error, isError: true)
            return
        }
        locations.append(location)
        writeLocation(location)
        if !isOffline {
            showToast("Location added", isError: false)
        }
    }

    func removeLocation(_ locationId: String) {
        locations.removeAll { $0.id == locationId }
        shiftNotes.removeAll { $0.locationId == locationId }
        if selectedLocationId == locationId {
            selectedLocationId = locations.first?.id ?? ""
        }
        guard let orgId = organizationId else { return }
        firestore.deleteLocation(locationId, orgId: orgId)
        Task { try? await firestore.deleteLocationNotes(locationId: locationId, orgId: orgId) }
        showToast("Location removed", isError: false)
    }

    // MARK: - Team

    func addTeamMember(_ member: TeamMember) {
        if let error = InputValidator.validateName(member.name, fieldName: "Name") {
            showToast(error, isError: true)
            return
        }
        if let error = InputValidator.validateEmail(member.email) {
            showToast(error, isError: true)
            return
        }
        teamMembers.append(member)
        writeTeamMember(member)
        if !isOffline {
            showToast("Team member added", isError: false)
        }
    }

    func removeTeamMember(_ memberId: String) {
        teamMembers.removeAll { $0.id == memberId }
        guard let orgId = organizationId else { return }
        firestore.deleteTeamMember(memberId, orgId: orgId)
        showToast("Team member removed", isError: false)
    }

    // MARK: - Recurring Issues

    func resolveRecurringIssue(_ issueId: String) {
        guard let index = recurringIssues.firstIndex(where: { $0.id == issueId }) else { return }
        recurringIssues[index].status = .resolved
        writeRecurringIssue(recurringIssues[index])
    }

    func acknowledgeRecurringIssue(_ issueId: String) {
        guard let index = recurringIssues.firstIndex(where: { $0.id == issueId }) else { return }
        recurringIssues[index].status = .acknowledged
        writeRecurringIssue(recurringIssues[index])
    }

    // MARK: - Location Selection

    func updateSelectedLocation(_ locationId: String) {
        selectedLocationId = locationId
        guard let userId = authenticatedUserId else { return }
        firestore.updateUserPreferences(userId: userId, selectedLocationId: locationId)
    }

    // MARK: - Onboarding

    func applyOnboardingData(businessType: BusinessType, locationName: String, timezone: String, teamInvites: [TeamInvite]) {
        let industryType: IndustryType = switch businessType {
        case .restaurant: .restaurant
        case .barPub: .bar
        case .hotel: .hotel
        case .cafe: .cafe
        default: .other
        }

        let org = Organization(
            name: organization.name.isEmpty ? "My Organization" : organization.name,
            ownerId: currentUserId,
            plan: .free,
            industryType: industryType
        )
        organization = org
        organizationId = org.id

        let newLocation = Location(
            name: locationName,
            address: "",
            timezone: timezone,
            managerIds: [currentUserId]
        )
        locations = [newLocation]
        selectedLocationId = newLocation.id

        let userEmail = userProfile?.email ?? ""
        var members: [TeamMember] = [
            TeamMember(
                id: currentUserId,
                name: currentUserName,
                email: userEmail,
                role: .owner,
                roleTemplateId: "role_owner",
                locationIds: [newLocation.id]
            )
        ]

        for invite in teamInvites where !invite.email.isEmpty {
            let member = TeamMember(
                name: invite.email.components(separatedBy: "@").first ?? invite.email,
                email: invite.email,
                role: .manager,
                roleTemplateId: invite.roleTemplate.id,
                locationIds: [newLocation.id],
                inviteStatus: .pending
            )
            members.append(member)
        }

        teamMembers = members
        shiftNotes = []
        recurringIssues = []

        writeOrganization(org)
        writeLocation(newLocation)
        for member in members { writeTeamMember(member) }
        firestore.updateUserPreferences(
            userId: currentUserId,
            organizationId: org.id,
            selectedLocationId: newLocation.id
        )
        startListeners(orgId: org.id)
    }

    // MARK: - UI State

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = ToastMessage(text: message, isError: isError)
    }

    func dismissToast() {
        toastMessage = nil
    }

    func handleNetworkReconnect() {
        guard let orgId = organizationId else { return }
        showToast("Back online", isError: false)
        startListeners(orgId: orgId)
    }

    func forceSync() {
        guard let userId = authenticatedUserId else {
            showToast("Not signed in", isError: true)
            return
        }
        syncError = nil
        isInitialLoading = true
        Task {
            await loadUserData(userId)
        }
    }

    func syncSubscriptionPlan() async {
        let subscription = SubscriptionService.shared
        await subscription.refreshStatus()
        let newPlan = subscription.correspondingPlan
        guard organization.plan != newPlan, !organization.name.isEmpty else { return }
        organization = Organization(
            id: organization.id,
            name: organization.name,
            ownerId: organization.ownerId,
            plan: newPlan,
            industryType: organization.industryType
        )
        writeOrganization(organization)
    }

    func deltaSyncFromBackend() {}

    func resetAllData() {
        showToast("Data is managed in Firestore", isError: false)
    }

    func loadDemoData() {
        organization = MockDataService.organization
        organizationId = MockDataService.organization.id
        locations = MockDataService.locations
        teamMembers = MockDataService.teamMembers
        shiftNotes = MockDataService.generateShiftNotes()
        recurringIssues = MockDataService.recurringIssues
        if selectedLocationId.isEmpty, let first = locations.first {
            selectedLocationId = first.id
        }
        isInitialLoading = false
        hasPendingWrites = false
        lastSyncDate = Date()
        syncError = nil
        loadFirstPage(shiftFilter: nil)
    }

    func retryPublish() {
        guard let note = pendingPublishNote else { return }
        publishError = nil
        publishReviewedNote(note)
    }

    // MARK: - Push Notifications

    var pendingNoteId: String?

    func handlePushNotificationTap(noteId: String) {
        pendingNoteId = noteId
    }

    // MARK: - Display Helpers

    func filteredNotes(shiftFilter: ShiftType?) -> [ShiftNote] {
        guard let filter = shiftFilter else { return feedNotes }
        return feedNotes.filter { $0.shiftType == filter }
    }

    func filteredNotes(shiftDisplayFilter: ShiftDisplayInfo?) -> [ShiftNote] {
        guard let filter = shiftDisplayFilter else { return feedNotes }
        return feedNotes.filter { $0.shiftDisplayInfo.id == filter.id }
    }

    func locationStats(_ locationId: String) -> (noteCount: Int, unacknowledged: Int, highestUrgency: UrgencyLevel) {
        let notes = notesForLocation(locationId)
        let uid = currentUserId
        let unack = notes.filter { !$0.acknowledgments.contains(where: { $0.userId == uid }) }.count
        let highest = notes.compactMap { $0.highestUrgency }.min(by: { $0.sortOrder < $1.sortOrder }) ?? .fyi
        return (notes.count, unack, highest)
    }

    func allActionItemsWithDateForDisplay() -> [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)] {
        allActionItemsWithDate
    }

    func locationName(for locationId: String) -> String {
        locations.first { $0.id == locationId }?.name ?? "Unknown"
    }

    // MARK: - Merge Helpers (kept for test compatibility)

    func mergeNoteWithConflictDetection(local: ShiftNote, server: ShiftNote) -> ShiftNote {
        return local.updatedAt >= server.updatedAt ? local : server
    }

    func mergeActionItemPerField(local: ActionItem, server: ActionItem) -> ActionItem {
        return local.updatedAt >= server.updatedAt ? local : server
    }

    // MARK: - Test Helpers

    func testGenerateCategories(from transcript: String) -> [CategorizedItem] {
        TranscriptProcessor.generateCategories(from: transcript)
    }

    func testGenerateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        TranscriptProcessor.generateActionItems(from: categorized)
    }

    func testGenerateSummary(from transcript: String) -> String {
        TranscriptProcessor.generateSummary(from: transcript)
    }

    func testSplitTranscript(_ transcript: String) -> [String] {
        TranscriptProcessor.splitTranscriptIntoSegments(transcript)
    }

    func splitTranscriptIntoSegments(_ transcript: String) -> [String] {
        TranscriptProcessor.splitTranscriptIntoSegments(transcript)
    }

    func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        TranscriptProcessor.generateActionItems(from: categorized)
    }
}
