import SwiftUI

nonisolated enum OperationState: Sendable {
    case idle
    case loading
    case success(String)
    case failure(String)

    var isVisible: Bool {
        switch self {
        case .idle: return false
        case .loading, .success, .failure: return true
        }
    }
}

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

    var operationState: OperationState = .idle
    var saveError: String?
    var toastMessage: ToastMessage?
    var publishError: String?
    var pendingPublishNote: ShiftNote?
    var showPaywall: Bool = false

    let networkMonitor = NetworkMonitor.shared
    var isOffline: Bool { !networkMonitor.isConnected }
    var pendingOfflineCount: Int { 0 }

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

    // MARK: - Search
    var searchQuery: String = ""
    var searchResults: [ShiftNote] {
        guard !searchQuery.isEmpty else { return [] }
        let q = searchQuery.lowercased()
        return feedNotes.filter {
            $0.rawTranscript.lowercased().localizedStandardContains(q) ||
            $0.summary.lowercased().localizedStandardContains(q) ||
            $0.authorName.lowercased().localizedStandardContains(q) ||
            $0.actionItems.contains { $0.task.lowercased().localizedStandardContains(q) }
        }
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

    func filteredPaginatedNotes(shiftDisplayFilter: ShiftDisplayInfo?) -> [ShiftNote] {
        paginatedNotes
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

        Task { await loadUserData(userId) }
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
        isInitialLoading = true
    }

    private func loadUserData(_ userId: String) async {
        do {
            let (profile, orgId, locId) = try await firestore.fetchUserData(userId)
            if let profile { self.userProfile = profile }
            self.organizationId = orgId
            if let locId { self.selectedLocationId = locId }
            if let orgId { startListeners(orgId: orgId) }
        } catch {
            syncError = "Unable to load data: \(error.localizedDescription)"
            isInitialLoading = false
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

        firestore.startShiftNotesListener(orgId) { [weak self] notes in
            guard let self else { return }
            self.shiftNotes = notes
            self.isInitialLoading = false
            self.lastSyncDate = Date()
        }

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
        guard let orgId = organizationId else { return }
        do { try firestore.saveShiftNote(note, orgId: orgId) }
        catch { showToast("Failed to save note", isError: true) }
    }

    private func writeLocation(_ location: Location) {
        guard let orgId = organizationId else { return }
        do { try firestore.saveLocation(location, orgId: orgId) }
        catch { showToast("Failed to save location", isError: true) }
    }

    private func writeTeamMember(_ member: TeamMember) {
        guard let orgId = organizationId else { return }
        do { try firestore.saveTeamMember(member, orgId: orgId) }
        catch { showToast("Failed to save team member", isError: true) }
    }

    private func writeOrganization(_ org: Organization) {
        do { try firestore.saveOrganization(org) }
        catch { showToast("Failed to save organization", isError: true) }
    }

    private func writeRecurringIssue(_ issue: RecurringIssue) {
        guard let orgId = organizationId else { return }
        do { try firestore.saveRecurringIssue(issue, orgId: orgId) }
        catch { showToast("Failed to save issue", isError: true) }
    }

    // MARK: - Notes

    func publishReviewedNote(_ note: ShiftNote) {
        var mutableNote = note
        mutableNote.updatedAt = Date()
        shiftNotes.insert(mutableNote, at: 0)
        publishError = nil
        pendingPublishNote = nil
        recording.discardPendingNote()
        writeShiftNote(mutableNote)

        if isOffline {
            showToast("Saved offline — will sync when connected", isError: false)
        }
    }

    func deleteNote(_ noteId: String) {
        shiftNotes.removeAll { $0.id == noteId }
        guard let orgId = organizationId else { return }
        firestore.deleteShiftNote(noteId, orgId: orgId)
    }

    func acknowledgeNote(_ noteId: String) {
        guard let index = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
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
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].status = newStatus
        shiftNotes[noteIndex].actionItems[itemIndex].statusUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAt = now
        writeShiftNote(shiftNotes[noteIndex])
    }

    func updateActionItemAssignee(noteId: String, actionItemId: String, assignee: String?) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].assignee = assignee
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
        locations.append(location)
        writeLocation(location)
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
    }

    // MARK: - Team

    func addTeamMember(_ member: TeamMember) {
        teamMembers.append(member)
        writeTeamMember(member)
    }

    func removeTeamMember(_ memberId: String) {
        teamMembers.removeAll { $0.id == memberId }
        guard let orgId = organizationId else { return }
        firestore.deleteTeamMember(memberId, orgId: orgId)
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

    func updateUnacknowledgedCount() {
        let uid = currentUserId
        unacknowledgedCount = feedNotes
            .filter { !$0.acknowledgments.contains(where: { $0.userId == uid }) }
            .count
    }

    func dismissOperationState() {
        operationState = .idle
    }

    func showToast(_ message: String, isError: Bool = false) {
        toastMessage = ToastMessage(text: message, isError: isError)
    }

    func dismissToast() {
        toastMessage = nil
    }

    func handleNetworkReconnect() {}

    func forceSync() {
        showToast("Data syncs automatically via Firestore", isError: false)
    }

    func deltaSyncFromBackend() {}

    func resetAllData() {
        showToast("Data is managed in Firestore", isError: false)
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
