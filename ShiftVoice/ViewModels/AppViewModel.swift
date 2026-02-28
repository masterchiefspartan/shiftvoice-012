import SwiftUI
import FirebaseAuth

@Observable
final class AppViewModel {
    var shiftNotes: [ShiftNote] = [] {
        didSet { invalidateCaches() }
    }
    var locations: [Location] = []
    var teamMembers: [TeamMember] = []
    private(set) var hasTeamMembersLoaded: Bool = false
    var organization: Organization = Organization(name: "", ownerId: "")
    var recurringIssues: [RecurringIssue] = []
    var isAssignedToMeFilterEnabled: Bool = false

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
    var paywallTriggerReason: PaywallTriggerReason = .unknown

    let networkMonitor = NetworkMonitor.shared
    var isOffline: Bool { !networkMonitor.isConnected }
    var isDataFromCache: Bool = true
    var hasPendingWrites: Bool = false
    var pendingNoteIds: Set<String> = []
    var lastSyncedFromServer: Date?
    var lastWriteError: SyncError?
    var syncState: SyncState = .onlineCache
    private var hasBlockingWriteFailure: Bool = false
    var pendingOfflineCount: Int { pendingNoteIds.count }
    var hasPendingSyncIndicators: Bool { hasPendingWrites || !pendingNoteIds.isEmpty }

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
    var isLoadingUserData: Bool = false
    var hasExistingOrganization: Bool = false

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
    private let persistence = PersistenceService.shared
    private let pendingOpsStore: PendingOpsStoreProtocol
    private let confirmationReconciler: PendingOpReconciling
    private let conflictStore: ConflictStore
    private let editBaselineStore: EditBaselineStore
    private let syncEventLogger: SyncEventLogger
    let featureFlags: FeatureFlagService
    private let conflictDetector: ConflictDetector
    private var recentlyClearedPendingNoteIds: Set<String> = []
    private var recentlyClearedPendingEdits: [String: PendingOp] = [:]

    var hasActiveConflicts: Bool { !conflictStore.activeConflicts.isEmpty }
    var activeConflictCount: Int { conflictStore.activeConflicts.count }
    var pendingDocIdsForDiagnostics: [String] { pendingOpsStore.all().map(\.docId).sorted() }
    var pendingOpsCountForDiagnostics: Int { pendingOpsStore.all().count }
    var recentSyncEventsForDiagnostics: [SyncEventRecord] { syncEventLogger.recentEvents(limit: 10) }
    var recentWriteFailuresForDiagnostics: [SyncEventRecord] { syncEventLogger.recentWriteFailures(limit: 5) }
    var writeFailureCountForDiagnostics: Int { syncEventLogger.writeFailureEventCount }

    func conflictsForNote(_ noteId: String) -> [ConflictItem] {
        conflictStore.conflictsForNote(noteId)
    }

    func activeConflictsForNote(_ noteId: String) -> [ConflictItem] {
        conflictStore.conflictsForNote(noteId).filter { $0.state == .detected }
    }

    private(set) var userProfile: UserProfile?
    private var authenticatedUserId: String?
    private var organizationId: String?
    var lastSyncDate: Date?
    var syncError: String?
    private var hasServerSnapshotSinceReconnect: Bool = false
    private var pendingSyncState: PendingSyncState = PendingSyncState()
    private var pendingReconciliationTask: Task<Void, Never>?
    private var networkReconnectObserver: NSObjectProtocol?
    private var networkStatusObserver: NSObjectProtocol?
    private var forcedSyncStateForDebug: SyncState?

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

    init(
        pendingOpsStore: PendingOpsStoreProtocol? = nil,
        confirmationReconciler: PendingOpReconciling? = nil,
        conflictStore: ConflictStore? = nil,
        editBaselineStore: EditBaselineStore? = nil
    ) {
        let resolvedPendingOpsStore = pendingOpsStore ?? PendingOpsStore(persistence: PersistenceService.shared)
        self.pendingOpsStore = resolvedPendingOpsStore
        self.confirmationReconciler = confirmationReconciler ?? ConfirmationReconciler(
            pendingOpsStore: resolvedPendingOpsStore,
            documentFetcher: FirestoreService.shared
        )
        self.conflictStore = conflictStore ?? ConflictStore()
        self.editBaselineStore = editBaselineStore ?? EditBaselineStore()
        self.syncEventLogger = .shared
        self.featureFlags = .shared
        self.conflictDetector = ConflictDetector(conflictStore: self.conflictStore, syncEventLogger: self.syncEventLogger)
        networkReconnectObserver = NotificationCenter.default.addObserver(
            forName: .networkReconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.handleReconnectTransition()
        }
        networkStatusObserver = NotificationCenter.default.addObserver(
            forName: .networkStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.updateSyncState()
        }
        updateSyncState()
    }

    func presentPaywall(reason: PaywallTriggerReason) {
        guard !showPaywall else { return }
        paywallTriggerReason = reason
        showPaywall = true
    }

    func dismissPaywall() {
        showPaywall = false
    }

    deinit {
        pendingReconciliationTask?.cancel()
        if let networkReconnectObserver {
            NotificationCenter.default.removeObserver(networkReconnectObserver)
        }
        if let networkStatusObserver {
            NotificationCenter.default.removeObserver(networkStatusObserver)
        }
    }

    // MARK: - Cache Invalidation

    private func invalidateCaches() {
        let newFeedNotes = shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .sorted { $0.syncOrderingDate > $1.syncOrderingDate }
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
        isLoadingUserData = true
        hasExistingOrganization = false

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
        if let userId = authenticatedUserId {
            persistence.clearPendingSyncState(for: userId)
            pendingOpsStore.clearCurrentUser()
            conflictStore.clearCurrentUserContext()
            editBaselineStore.clearCurrentUserContext()
        }
        authenticatedUserId = nil
        organizationId = nil
        userProfile = nil
        shiftNotes = []
        locations = []
        teamMembers = []
        hasTeamMembersLoaded = false
        recurringIssues = []
        isAssignedToMeFilterEnabled = false
        organization = Organization(name: "", ownerId: "")
        selectedLocationId = ""
        unacknowledgedCount = 0
        lastSyncDate = nil
        lastSyncedFromServer = nil
        syncError = nil
        hasPendingWrites = false
        pendingNoteIds = []
        pendingSyncState = PendingSyncState()
        pendingOpsStore.clearCurrentUser()
        hasServerSnapshotSinceReconnect = false
        lastWriteError = nil
        isDataFromCache = true
        isInitialLoading = true
        isLoadingUserData = false
        hasExistingOrganization = false
        updateSyncState()
    }

    private func loadUserData(_ userId: String) async {
        defer { isLoadingUserData = false }
        do {
            if let persistedPending = persistence.loadPendingSyncState(for: userId) {
                pendingSyncState = persistedPending
                pendingNoteIds = persistedPending.pendingNoteIds
            }

            pendingOpsStore.configure(userId: userId)
            conflictStore.configure(userId: userId)
            editBaselineStore.configure(userId: userId)
            normalizePendingStateFromPersistence()

            let (profile, orgId, locId) = try await firestore.fetchUserData(userId)
            if let profile { self.userProfile = profile }
            self.organizationId = orgId
            hasExistingOrganization = orgId != nil
            if let locId { self.selectedLocationId = locId }
            syncError = nil
            if let orgId {
                startListeners(orgId: orgId)
            } else {
                loadDemoData()
            }
        } catch {
            hasExistingOrganization = false
            syncError = "Could not load your data. Tap to retry."
            isInitialLoading = false
            loadDemoData()
        }
    }

    private func applyShiftNotesListenerEvent(_ event: ShiftNotesListenerEvent) {
        hasPendingWrites = event.hasPendingWrites
        isDataFromCache = event.isFromCache

        let isFirstServerSnapshotAfterReconnect = !event.isFromCache && !hasServerSnapshotSinceReconnect
        if !event.isFromCache {
            hasServerSnapshotSinceReconnect = true
            let now = Date()
            lastSyncedFromServer = now
            lastSyncDate = now
        }

        let reconciledNotes = event.notes.map { note in
            var mutableNote = note
            if !event.isFromCache {
                mutableNote.updatedAtServer = note.updatedAt
                pendingSyncState.noteLastSeenUpdatedAtServer[note.id] = note.updatedAt
            } else if let knownServerDate = pendingSyncState.noteLastSeenUpdatedAtServer[note.id] {
                mutableNote.updatedAtServer = knownServerDate
            }
            if mutableNote.updatedAtClient == nil {
                mutableNote.updatedAtClient = mutableNote.updatedAt
            }
            return mutableNote
        }

        shiftNotes = reconciledNotes
        reconcilePendingState(using: event)
        isInitialLoading = false
        persistPendingSyncState()
        updateSyncState()

        if isFirstServerSnapshotAfterReconnect {
            schedulePendingReconciliation(reason: "server_snapshot")
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
            self.hasTeamMembersLoaded = true
        }

        firestore.startShiftNotesListener(
            orgId,
            onEvent: { [weak self] event in
                guard let self else { return }
                self.applyShiftNotesListenerEvent(event)
            },
            onDocumentEvent: { [weak self] event in
                guard let self else { return }
                self.handleShiftNoteDocumentEvent(event)
            },
            onError: { [weak self] error in
                guard let self else { return }
                self.lastWriteError = error
                self.syncError = self.userFacingSyncError(error)
                self.updateSyncState()
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

    private func writeShiftNote(_ note: ShiftNote, operation: PendingNoteOperationType) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }

        let mutationId = UUID().uuidString
        let now = Date()
        trackPendingOperation(note: note, type: operation, mutationId: mutationId)

        do {
            _ = firestore.saveShiftNote(
                note,
                orgId: orgId,
                mutationId: mutationId,
                updatedAtClient: now,
                updatedByUserId: currentUserId
            ) { [weak self] result in
                guard let self else { return }
                if case .failure(let fallbackError) = result {
                    self.consumeWriteFailureFromStore(fallback: fallbackError)
                    self.updateSyncState()
                }
            }
        }
    }

    private func writeLocation(_ location: Location) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }
        Task {
            do {
                try await firestore.saveLocation(location, orgId: orgId)
            } catch {
                showToast("Failed to save location", isError: true)
            }
        }
    }

    private func writeTeamMember(_ member: TeamMember) {
        guard let orgId = organizationId else {
            showToast("No organization found — please complete setup", isError: true)
            return
        }
        Task {
            do {
                try await firestore.saveTeamMember(member, orgId: orgId)
            } catch {
                showToast("Failed to save team member", isError: true)
            }
        }
    }

    private func writeOrganization(_ org: Organization) {
        Task {
            do {
                try await firestore.saveOrganization(org)
            } catch {
                showToast("Failed to save organization", isError: true)
            }
        }
    }

    private func writeRecurringIssue(_ issue: RecurringIssue) {
        guard let orgId = organizationId else { return }
        Task {
            do {
                try await firestore.saveRecurringIssue(issue, orgId: orgId)
            } catch {
                showToast("Failed to save issue", isError: true)
            }
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
        mutableNote.updatedAtClient = mutableNote.updatedAt
        mutableNote.updatedAtServer = pendingSyncState.noteLastSeenUpdatedAtServer[mutableNote.id]
        publishError = nil
        pendingPublishNote = nil
        recording.discardPendingNote()

        shiftNotes.insert(mutableNote, at: 0)

        writeShiftNote(mutableNote, operation: .create)

        if !isOffline {
            showToast("Shift note published", isError: false)
        }
    }

    func deleteNote(_ noteId: String) {
        guard let removedNote = shiftNotes.first(where: { $0.id == noteId }) else { return }
        shiftNotes.removeAll { $0.id == noteId }

        guard let orgId = organizationId else { return }
        let mutationId = UUID().uuidString
        trackDeleteTombstone(noteId: noteId, lastSeenUpdatedAtServer: removedNote.updatedAtServer, mutationId: mutationId)
        _ = firestore.deleteShiftNote(noteId, orgId: orgId, mutationId: mutationId) { [weak self] result in
            guard let self else { return }
            if case .failure(let fallbackError) = result {
                self.consumeWriteFailureFromStore(fallback: fallbackError)
                self.updateSyncState()
            }
        }

        showToast("Note deleted", isError: false)
    }

    func acknowledgeNote(_ noteId: String) {
        guard let index = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
        guard !shiftNotes[index].acknowledgments.contains(where: { $0.userId == currentUserId }) else { return }
        let ack = Acknowledgment(userId: currentUserId, userName: currentUserName)
        let now = Date()
        shiftNotes[index].acknowledgments.append(ack)
        shiftNotes[index].updatedAt = now
        shiftNotes[index].updatedAtClient = now
        writeShiftNote(shiftNotes[index], operation: .edit)
    }

    func isNoteAcknowledged(_ note: ShiftNote) -> Bool {
        note.acknowledgments.contains { $0.userId == currentUserId }
    }

    func notesForLocation(_ locationId: String) -> [ShiftNote] {
        shiftNotes.filter { $0.locationId == locationId }
    }

    // MARK: - Action Items

    func updateActionItemStatus(noteId: String, actionItemId: String, newStatus: ActionItemStatus) {
        beginEditingNote(noteId)
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let oldStatus = shiftNotes[noteIndex].actionItems[itemIndex].status
        guard oldStatus != newStatus else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].status = newStatus
        shiftNotes[noteIndex].actionItems[itemIndex].statusUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAtClient = now
        writeShiftNote(shiftNotes[noteIndex], operation: .edit)
    }

    func updateActionItemAssignee(noteId: String, actionItemId: String, assignee: String?, assigneeId: String? = nil) {
        beginEditingNote(noteId)
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].assignee = assignee
        shiftNotes[noteIndex].actionItems[itemIndex].assigneeId = assigneeId
        shiftNotes[noteIndex].actionItems[itemIndex].assigneeUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAtClient = now
        writeShiftNote(shiftNotes[noteIndex], operation: .edit)
    }

    func appendItemsToNote(noteId: String, categorizedItems: [CategorizedItem], actionItems: [ActionItem]) {
        beginEditingNote(noteId)
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
        let now = Date()
        var mutableNote = shiftNotes[noteIndex]
        var existingCategories = mutableNote.categorizedItems
        existingCategories.append(contentsOf: categorizedItems)
        var existingActions = mutableNote.actionItems
        existingActions.append(contentsOf: actionItems)
        mutableNote = ShiftNote(
            id: mutableNote.id,
            authorId: mutableNote.authorId,
            authorName: mutableNote.authorName,
            authorInitials: mutableNote.authorInitials,
            locationId: mutableNote.locationId,
            shiftType: mutableNote.shiftType,
            shiftTemplateId: mutableNote.shiftTemplateId,
            rawTranscript: mutableNote.rawTranscript,
            audioUrl: mutableNote.audioUrl,
            audioDuration: mutableNote.audioDuration,
            summary: mutableNote.summary,
            categorizedItems: existingCategories,
            actionItems: existingActions,
            photoUrls: mutableNote.photoUrls,
            acknowledgments: mutableNote.acknowledgments,
            voiceReplies: mutableNote.voiceReplies,
            createdAt: mutableNote.createdAt,
            updatedAt: now,
            updatedAtClient: now,
            updatedAtServer: mutableNote.updatedAtServer,
            updatedByUserId: currentUserId,
            isSynced: false,
            isDirty: true
        )
        shiftNotes[noteIndex] = mutableNote
        writeShiftNote(mutableNote, operation: .edit)
        showToast("\(categorizedItems.count) item\(categorizedItems.count == 1 ? "" : "s") added", isError: false)
    }

    func dismissConflict(noteId: String, actionItemId: String) {
        guard let noteIdx = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIdx = shiftNotes[noteIdx].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        shiftNotes[noteIdx].actionItems[itemIdx].hasConflict = false
        shiftNotes[noteIdx].actionItems[itemIdx].conflictDescription = nil
        let now = Date()
        shiftNotes[noteIdx].updatedAt = now
        shiftNotes[noteIdx].updatedAtClient = now
        writeShiftNote(shiftNotes[noteIdx], operation: .edit)
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
        Task {
            do {
                try await firestore.deleteLocation(locationId, orgId: orgId)
                try await firestore.deleteLocationNotes(locationId: locationId, orgId: orgId)
            } catch {
                showToast("Failed to remove location", isError: true)
            }
        }
        showToast("Location removed", isError: false)
    }

    func updateLocation(_ location: Location) {
        if let error = InputValidator.validateLocationName(location.name) {
            showToast(error, isError: true)
            return
        }
        guard let index = locations.firstIndex(where: { $0.id == location.id }) else { return }
        locations[index] = location
        writeLocation(location)
        showToast("Location updated", isError: false)
    }

    var canAddMoreLocations: Bool {
        locations.count < organization.plan.maxLocations
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
        guard memberId != organization.ownerId else {
            showToast("Cannot remove the organization owner", isError: true)
            return
        }
        guard let removedMember = teamMembers.first(where: { $0.id == memberId }) else { return }
        teamMembers.removeAll { $0.id == memberId }
        guard let orgId = organizationId else { return }
        Task {
            do {
                try await firestore.deleteTeamMember(memberId, orgId: orgId)
                showToast("Team member removed", isError: false)
            } catch {
                teamMembers.append(removedMember)
                showToast("Failed to remove team member", isError: true)
            }
        }
    }

    func updateTeamMember(_ member: TeamMember) {
        if let error = InputValidator.validateName(member.name, fieldName: "Name") {
            showToast(error, isError: true)
            return
        }
        if let error = InputValidator.validateEmail(member.email) {
            showToast(error, isError: true)
            return
        }
        guard let index = teamMembers.firstIndex(where: { $0.id == member.id }) else { return }
        teamMembers[index] = member
        writeTeamMember(member)
        showToast("Team member updated", isError: false)
    }

    var resolvedUserRole: ManagerRole? {
        guard hasTeamMembersLoaded else { return nil }
        return teamMembers.first(where: { $0.id == currentUserId })?.role
    }

    var currentUserRole: ManagerRole {
        resolvedUserRole ?? .owner
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
        Task {
            try? await firestore.updateUserPreferences(userId: userId, selectedLocationId: locationId)
        }
    }

    // MARK: - Onboarding

    func applyOnboardingData(businessType: BusinessType, locationName: String, timezone: String, teamInvites: [TeamInvite]) {
        guard organizationId == nil else { return }

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
        hasTeamMembersLoaded = true
        shiftNotes = []
        recurringIssues = []

        writeOrganization(org)
        writeLocation(newLocation)
        for member in members { writeTeamMember(member) }
        Task {
            try? await firestore.updateUserPreferences(
                userId: currentUserId,
                organizationId: org.id,
                selectedLocationId: newLocation.id
            )
        }
        startListeners(orgId: org.id)
    }

    private func updateSyncState() {
        let oldState = syncState
        refreshWriteFailureState()

        let snapshotFreshness: SnapshotFreshness
        if hasServerSnapshotSinceReconnect {
            snapshotFreshness = .server
        } else if isDataFromCache {
            snapshotFreshness = .cache
        } else {
            snapshotFreshness = .none
        }

        if let forcedSyncStateForDebug {
            syncState = forcedSyncStateForDebug
        } else {
            syncState = SyncStateReducer.reduce(
                SyncStateInput(
                    isConnected: networkMonitor.isConnected,
                    snapshotFreshness: snapshotFreshness,
                    hasPendingWrites: hasPendingWrites,
                    hasServerSnapshotSinceReconnect: hasServerSnapshotSinceReconnect,
                    lastWriteError: lastWriteError,
                    pendingNoteCount: pendingNoteIds.count,
                    pendingDeleteCount: pendingOpsStore.summary().pendingDeleteCount
                )
            )
        }

        if oldState != syncState {
            syncEventLogger.stateTransition(from: oldState, to: syncState)
        }
    }

    private func persistPendingSyncState() {
        pendingSyncState.pendingNoteIds = pendingNoteIds
        guard let userId = authenticatedUserId else { return }
        persistence.savePendingSyncState(pendingSyncState, for: userId)
    }

    private func handleReconnectTransition() {
        hasServerSnapshotSinceReconnect = false
        lastSyncedFromServer = nil
        lastWriteError = nil
        syncError = nil
        pendingReconciliationTask?.cancel()
        updateSyncState()

        if networkMonitor.isConnected {
            schedulePendingReconciliation(reason: "reconnect")
        }
    }

    private func trackPendingOperation(note: ShiftNote, type: PendingNoteOperationType, mutationId: String) {
        let operation = PendingNoteOperation(
            noteId: note.id,
            type: type,
            expectedUpdatedAtClient: note.updatedAtClient ?? note.updatedAt,
            lastSeenUpdatedAtServer: pendingSyncState.noteLastSeenUpdatedAtServer[note.id]
        )
        pendingSyncState.pendingOperations[note.id] = operation

        let intendedFields: [String: String]? = type == .edit ? collaborativeFields(from: note) : nil
        let pendingOp = PendingOp(
            docId: note.id,
            type: .upsert,
            mutationId: mutationId,
            intendedFields: intendedFields
        )
        pendingOpsStore.upsert(pendingOp)
        syncEventLogger.pendingOpAdded(docId: note.id, type: .upsert)
        pendingNoteIds.insert(note.id)

        if type == .edit,
           editBaselineStore.getBaseline(for: note.id) == nil,
           let baseServerDate = pendingSyncState.noteLastSeenUpdatedAtServer[note.id] {
            pendingSyncState.noteEditBases[note.id] = baseServerDate
            editBaselineStore.setBaseline(
                for: note.id,
                fields: collaborativeFields(from: note),
                serverTimestamp: baseServerDate
            )
        }

        persistPendingSyncState()
        updateSyncState()
    }

    private func trackDeleteTombstone(noteId: String, lastSeenUpdatedAtServer: Date?, mutationId: String) {
        let tombstone = PendingNoteOperation(
            noteId: noteId,
            type: .delete,
            expectedUpdatedAtClient: nil,
            lastSeenUpdatedAtServer: lastSeenUpdatedAtServer
        )
        pendingSyncState.pendingDeletes[noteId] = tombstone
        let pendingOp = PendingOp(docId: noteId, type: .delete, mutationId: mutationId)
        pendingOpsStore.upsert(pendingOp)
        syncEventLogger.pendingOpAdded(docId: noteId, type: .delete)
        pendingNoteIds.insert(noteId)
        persistPendingSyncState()
        updateSyncState()
    }

    private func clearPendingOperation(noteId: String) {
        let pendingOp = pendingOpsStore.pendingOps[noteId]
        pendingSyncState.pendingOperations.removeValue(forKey: noteId)
        pendingSyncState.pendingDeletes.removeValue(forKey: noteId)
        pendingSyncState.noteEditBases.removeValue(forKey: noteId)
        pendingOpsStore.remove(docId: noteId)
        pendingNoteIds.remove(noteId)

        if let pendingOp {
            syncEventLogger.pendingOpConfirmed(
                docId: noteId,
                type: pendingOp.type,
                durationSeconds: Date().timeIntervalSince(pendingOp.createdAtClient)
            )
        }

        let hasDetectedConflict = conflictStore.activeConflicts.contains { $0.noteId == noteId }
        if !hasDetectedConflict {
            editBaselineStore.clearBaseline(for: noteId)
        }

        persistPendingSyncState()
        updateSyncState()
    }

    private func normalizePendingStateFromPersistence() {
        let operationIDs = Set(pendingSyncState.pendingOperations.keys)
        let deleteIDs = Set(pendingSyncState.pendingDeletes.keys)
        let persistedPendingIDs = pendingOpsStore.summary().pendingDocIds
        pendingNoteIds = operationIDs.union(deleteIDs).union(persistedPendingIDs)
        pendingSyncState.pendingNoteIds = pendingNoteIds
        persistPendingSyncState()

        if networkMonitor.isConnected && !pendingNoteIds.isEmpty {
            schedulePendingReconciliation(reason: "launch")
        }
    }

    private func schedulePendingReconciliation(reason: String) {
        guard networkMonitor.isConnected else { return }
        guard organizationId != nil else { return }
        guard !pendingOpsStore.all().isEmpty || !pendingNoteIds.isEmpty else { return }

        pendingReconciliationTask?.cancel()
        pendingReconciliationTask = Task { [weak self] in
            guard let self else { return }
            await self.reconcilePendingOperationsWithServer(reason: reason)
        }
    }

    private func evaluateConflictsForServerNote(_ note: ShiftNote, isFromCache: Bool) {
        guard !isFromCache else { return }

        let noteId = note.id
        let hasPendingEdit = pendingSyncState.pendingOperations[noteId]?.type == .edit
        let wasJustCleared = recentlyClearedPendingNoteIds.contains(noteId)
        guard hasPendingEdit || wasJustCleared || editBaselineStore.getBaseline(for: noteId) != nil else { return }

        let pendingEdit = pendingOpsStore.pendingOps[noteId] ?? recentlyClearedPendingEdits[noteId]
        let baseline = editBaselineStore.getBaseline(for: noteId)
        let conflicts = conflictDetector.evaluateSnapshot(
            serverNote: note,
            localPendingEdit: pendingEdit,
            editBaseline: baseline,
            isFromCache: isFromCache
        )

        guard !conflicts.isEmpty else {
            if pendingSyncState.pendingOperations[noteId] == nil {
                editBaselineStore.clearBaseline(for: noteId)
            }
            return
        }

        for conflict in conflicts {
            conflictStore.addConflict(conflict)
        }

        Task {
            guard let orgId = organizationId else { return }
            try? await firestore.markNoteConflictDetected(
                noteId: noteId,
                orgId: orgId,
                summary: conflicts.map(\.fieldName).joined(separator: ",")
            )
        }
    }

    private func reconcileOperationFromObservedServerNote(_ note: ShiftNote) {
        let noteId = note.id
        pendingSyncState.noteLastSeenUpdatedAtServer[noteId] = note.updatedAt

        if let baseDate = pendingSyncState.noteEditBases[noteId],
           let operation = pendingSyncState.pendingOperations[noteId],
           operation.type == .edit,
           note.updatedAt > baseDate {
            pendingSyncState.conflictCandidateNoteIds.insert(noteId)
        }

        guard let operation = pendingSyncState.pendingOperations[noteId] else { return }

        switch operation.type {
        case .create:
            clearPendingOperation(noteId: noteId)
        case .edit:
            if let expectedDate = operation.expectedUpdatedAtClient {
                if note.updatedAt >= expectedDate {
                    clearPendingOperation(noteId: noteId)
                }
            } else {
                clearPendingOperation(noteId: noteId)
            }
        case .delete:
            break
        }
    }

    private func reconcilePendingOperationsWithServer(reason: String) async {
        guard networkMonitor.isConnected else { return }
        guard let orgId = organizationId else { return }

        let pendingOpsBeforeReconcile = pendingOpsStore.pendingOps
        let result = await confirmationReconciler.reconcile(orgId: orgId)

        if let encounteredError = result.encounteredError {
            lastWriteError = encounteredError
            syncError = userFacingSyncError(encounteredError)
            if encounteredError == .authExpired {
                await triggerReauthenticationForSyncFailure()
            }
            updateSyncState()
            _ = reason
            return
        }

        recentlyClearedPendingNoteIds.formUnion(result.clearedDocIds)
        for noteId in result.clearedDocIds {
            if let pendingOp = pendingOpsBeforeReconcile[noteId], pendingOp.type == .upsert {
                recentlyClearedPendingEdits[noteId] = pendingOp
            }
        }

        for noteId in result.clearedDocIds {
            pendingSyncState.pendingOperations.removeValue(forKey: noteId)
            pendingSyncState.pendingDeletes.removeValue(forKey: noteId)
            pendingSyncState.noteEditBases.removeValue(forKey: noteId)
        }

        let summary = pendingOpsStore.summary()
        pendingNoteIds = summary.pendingDocIds
        pendingSyncState.pendingNoteIds = pendingNoteIds

        if !result.mismatchDocIds.isEmpty {
            pendingSyncState.conflictCandidateNoteIds.formUnion(result.mismatchDocIds)
        }

        persistPendingSyncState()
        updateSyncState()
        _ = reason
    }

    private func reconcilePendingState(using event: ShiftNotesListenerEvent) {
        guard !event.isFromCache else { return }

        for note in shiftNotes {
            evaluateConflictsForServerNote(note, isFromCache: event.isFromCache)
            reconcileOperationFromObservedServerNote(note)
        }

        for noteId in Array(pendingSyncState.pendingDeletes.keys) where event.documentIDs.contains(noteId) {
            clearPendingOperation(noteId: noteId)
        }

        pendingNoteIds.formUnion(pendingOpsStore.summary().pendingDocIds)
        pendingSyncState.pendingNoteIds = pendingNoteIds
        persistPendingSyncState()
        updateSyncState()
        recentlyClearedPendingNoteIds.removeAll()
        recentlyClearedPendingEdits.removeAll()
    }

    private func handleShiftNoteDocumentEvent(_ event: ShiftNoteDocumentEvent) {
        guard !event.isFromCache else { return }

        if event.exists, let note = event.note {
            evaluateConflictsForServerNote(note, isFromCache: event.isFromCache)
            reconcileOperationFromObservedServerNote(note)
            if pendingSyncState.pendingOperations[event.noteId] != nil || pendingSyncState.pendingDeletes[event.noteId] != nil {
                clearPendingOperation(noteId: event.noteId)
            }
        } else if pendingSyncState.pendingDeletes[event.noteId] != nil {
            clearPendingOperation(noteId: event.noteId)
        }

        pendingNoteIds.formUnion(pendingOpsStore.summary().pendingDocIds)
        pendingSyncState.pendingNoteIds = pendingNoteIds
        persistPendingSyncState()
        updateSyncState()
        recentlyClearedPendingNoteIds.remove(event.noteId)
        recentlyClearedPendingEdits.removeValue(forKey: event.noteId)
    }

    private func consumeWriteFailureFromStore(fallback: SyncError) {
        if let failure = firestore.lastWriteFailure {
            if shouldPromoteToBlockingError(category: failure.category) {
                let mapped = mapWriteFailureToSyncError(failure)
                lastWriteError = mapped
                syncError = userFacingSyncError(mapped)
                hasBlockingWriteFailure = true
            } else {
                syncError = failure.message ?? userFacingSyncError(fallback)
            }
            if firestore.triggerReauthFlag {
                Task { [weak self] in
                    await self?.triggerReauthenticationForSyncFailure()
                }
            }
            return
        }

        lastWriteError = fallback
        syncError = userFacingSyncError(fallback)
    }

    private func refreshWriteFailureState() {
        guard let failure = firestore.lastWriteFailure else {
            if hasBlockingWriteFailure {
                lastWriteError = nil
                syncError = nil
                hasBlockingWriteFailure = false
            }
            return
        }

        if shouldPromoteToBlockingError(category: failure.category) {
            let mapped = mapWriteFailureToSyncError(failure)
            lastWriteError = mapped
            syncError = userFacingSyncError(mapped)
            hasBlockingWriteFailure = true
        } else if hasBlockingWriteFailure {
            lastWriteError = nil
            syncError = nil
            hasBlockingWriteFailure = false
        }

        if firestore.triggerReauthFlag {
            Task { [weak self] in
                await self?.triggerReauthenticationForSyncFailure()
            }
        }
    }

    private func shouldPromoteToBlockingError(category: WriteErrorCategory) -> Bool {
        category == .unauthenticated
            || category == .permissionDenied
            || category == .failedPrecondition
            || category == .invalidArgument
    }

    private func mapWriteFailureToSyncError(_ failure: WriteFailure) -> SyncError {
        switch failure.category {
        case .permissionDenied:
            return .permissionDenied
        case .unauthenticated:
            return .authExpired
        case .invalidArgument:
            return .invalidData
        case .failedPrecondition:
            return .rejectedTransaction
        case .resourceExhausted, .unavailable, .notFound, .unknown:
            return .unknown(code: failure.underlyingCode ?? -1, message: failure.message ?? "Unknown write error")
        }
    }

    func restartListenersAfterWriteFailure() {
        guard let orgId = organizationId else { return }
        syncEventLogger.listenerRestarted(reason: "write_failure_recovery")
        firestore.restartListenersFromWriteRecovery()
        hasServerSnapshotSinceReconnect = false
        startListeners(orgId: orgId)
    }

    func retryLastSafeWrite() {
        Task {
            await firestore.retryLastSafeWrite()
        }
    }

    private func userFacingSyncError(_ error: SyncError) -> String {
        switch error {
        case .permissionDenied:
            return "You don’t have permission to sync this change."
        case .authExpired:
            return "Your session expired. Please sign in again."
        case .invalidData:
            return "This note has invalid data and could not sync."
        case .rejectedTransaction:
            return "This change was rejected. Please retry."
        case .networkFatal:
            return "Network unavailable while syncing."
        case .unknown:
            return "Sync failed. Please retry."
        }
    }

    func forceSyncListenerRestart() {
        guard let orgId = organizationId else { return }
        syncEventLogger.listenerRestarted(reason: "manual_settings_restart")
        firestore.stopAllListeners()
        hasServerSnapshotSinceReconnect = false
        updateSyncState()
        startListeners(orgId: orgId)
    }

    func forceReconciliationFromDiagnostics() {
        schedulePendingReconciliation(reason: "manual_force_reconciliation")
    }

    func triggerReauthenticationForSyncFailure() async {
        guard case .authExpired = lastWriteError else { return }
        guard let user = Auth.auth().currentUser else { return }
        _ = try? await user.getIDToken(forcingRefresh: true)
    }

    func retryPendingNoteWrites() {
        let pendingOperations = pendingSyncState.pendingOperations.values
        for operation in pendingOperations {
            guard let note = shiftNotes.first(where: { $0.id == operation.noteId }) else { continue }
            writeShiftNote(note, operation: operation.type)
        }

        for deleteOperation in pendingSyncState.pendingDeletes.values {
            guard let orgId = organizationId else { continue }
            let mutationId = UUID().uuidString
            _ = firestore.deleteShiftNote(deleteOperation.noteId, orgId: orgId, mutationId: mutationId) { [weak self] result in
                guard let self else { return }
                if case .failure(let fallbackError) = result {
                    self.consumeWriteFailureFromStore(fallback: fallbackError)
                    self.updateSyncState()
                }
            }
        }
    }

    func beginEditingNote(_ noteId: String) {
        guard let note = shiftNotes.first(where: { $0.id == noteId }) else { return }
        guard let serverDate = pendingSyncState.noteLastSeenUpdatedAtServer[noteId] ?? note.updatedAtServer else { return }

        pendingSyncState.noteEditBases[noteId] = serverDate
        editBaselineStore.setBaseline(
            for: noteId,
            fields: collaborativeFields(from: note),
            serverTimestamp: serverDate
        )
        persistPendingSyncState()
    }

    func resolveConflict(id: String, resolution: ConflictResolution) {
        guard let conflict = conflictStore.activeConflicts.first(where: { $0.id == id }) else { return }

        syncEventLogger.conflictResolved(noteId: conflict.noteId, field: conflict.fieldName, resolution: resolution)

        switch resolution {
        case .keptServer:
            conflictStore.resolveConflict(id: id, resolution: .keptServer, userId: currentUserId)
            clearConflictStateIfNoActiveConflicts(noteId: conflict.noteId)
        case .appliedLocal:
            applyLocalConflictUpdate(conflict)
            conflictStore.resolveConflict(id: id, resolution: .appliedLocal, userId: currentUserId)
            clearConflictStateIfNoActiveConflicts(noteId: conflict.noteId)
        case .dismissed:
            dismissConflict(id: id)
        }
    }

    func dismissConflict(id: String) {
        guard let conflict = conflictStore.activeConflicts.first(where: { $0.id == id }) else { return }
        syncEventLogger.conflictResolved(noteId: conflict.noteId, field: conflict.fieldName, resolution: .dismissed)
        conflictStore.dismissConflict(id: id, userId: currentUserId)
        clearConflictStateIfNoActiveConflicts(noteId: conflict.noteId)
    }

    private func applyLocalConflictUpdate(_ conflict: ConflictItem) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == conflict.noteId }) else { return }
        guard let actionItemIndex = shiftNotes[noteIndex].actionItems.indices.max(by: {
            shiftNotes[noteIndex].actionItems[$0].updatedAt < shiftNotes[noteIndex].actionItems[$1].updatedAt
        }) else { return }

        let actionItemId = shiftNotes[noteIndex].actionItems[actionItemIndex].id

        switch conflict.fieldName {
        case "status":
            guard let status = ActionItemStatus(rawValue: conflict.localIntendedValue) else { return }
            updateActionItemStatus(noteId: conflict.noteId, actionItemId: actionItemId, newStatus: status)
        case "assigneeId":
            let assigneeId = conflict.localIntendedValue.isEmpty ? nil : conflict.localIntendedValue
            let assigneeName = teamMembers.first(where: { $0.id == assigneeId })?.name
            updateActionItemAssignee(noteId: conflict.noteId, actionItemId: actionItemId, assignee: assigneeName, assigneeId: assigneeId)
        case "priority":
            guard let urgency = UrgencyLevel(rawValue: conflict.localIntendedValue) else { return }
            updateActionItemPriority(noteId: conflict.noteId, actionItemId: actionItemId, newUrgency: urgency)
        default:
            return
        }
    }

    private func updateActionItemPriority(noteId: String, actionItemId: String, newUrgency: UrgencyLevel) {
        beginEditingNote(noteId)
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }

        let existingItem = shiftNotes[noteIndex].actionItems[itemIndex]
        guard existingItem.urgency != newUrgency else { return }

        let now = Date()
        let updatedItem = ActionItem(
            id: existingItem.id,
            task: existingItem.task,
            category: existingItem.category,
            categoryTemplateId: existingItem.categoryTemplateId,
            urgency: newUrgency,
            status: existingItem.status,
            assignee: existingItem.assignee,
            assigneeId: existingItem.assigneeId,
            updatedAt: now,
            statusUpdatedAt: existingItem.statusUpdatedAt,
            statusUpdatedAtServer: existingItem.statusUpdatedAtServer,
            statusUpdatedByUserId: existingItem.statusUpdatedByUserId,
            assigneeUpdatedAt: existingItem.assigneeUpdatedAt,
            assigneeUpdatedAtServer: existingItem.assigneeUpdatedAtServer,
            assigneeUpdatedByUserId: existingItem.assigneeUpdatedByUserId,
            hasConflict: existingItem.hasConflict,
            conflictDescription: existingItem.conflictDescription
        )

        shiftNotes[noteIndex].actionItems[itemIndex] = updatedItem
        shiftNotes[noteIndex].updatedAt = now
        shiftNotes[noteIndex].updatedAtClient = now
        writeShiftNote(shiftNotes[noteIndex], operation: .edit)
    }

    private func clearConflictStateIfNoActiveConflicts(noteId: String) {
        guard activeConflictsForNote(noteId).isEmpty else { return }
        guard let orgId = organizationId else { return }
        Task {
            try? await firestore.clearNoteConflictState(noteId: noteId, orgId: orgId)
        }
    }

    private func collaborativeFields(from note: ShiftNote) -> [String: String] {
        let prioritizedActionItem = note.actionItems.max(by: { $0.updatedAt < $1.updatedAt })
        return [
            "status": prioritizedActionItem?.status.rawValue ?? "",
            "assigneeId": prioritizedActionItem?.assigneeId ?? "",
            "priority": prioritizedActionItem?.urgency.rawValue ?? ""
        ]
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
        handleReconnectTransition()
        showToast("Back online", isError: false)
        startListeners(orgId: orgId)
        schedulePendingReconciliation(reason: "manual_reconnect")
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

    func syncStateLabel() -> String {
        switch syncState {
        case .offline:
            return "Offline"
        case .onlineCache:
            return "Online (Cache)"
        case .syncing:
            return "Syncing"
        case .onlineFresh:
            return "Synced"
        case .error:
            return "Error"
        }
    }

    func setForcedSyncStateForDebug(_ state: SyncState?) {
        forcedSyncStateForDebug = state
        updateSyncState()
    }

    func resetSyncDataForDebug() {
        pendingReconciliationTask?.cancel()
        pendingSyncState = PendingSyncState()
        pendingNoteIds = []
        recentlyClearedPendingNoteIds = []
        recentlyClearedPendingEdits = [:]
        hasPendingWrites = false
        hasServerSnapshotSinceReconnect = false
        lastWriteError = nil
        syncError = nil

        if let userId = authenticatedUserId {
            persistence.clearPendingSyncState(for: userId)
            pendingOpsStore.clearCurrentUser()
            pendingOpsStore.configure(userId: userId)
            conflictStore.clearAllConflicts()
            editBaselineStore.clearAllBaselines()
        } else {
            pendingOpsStore.clearCurrentUser()
            conflictStore.clearCurrentUserContext()
            editBaselineStore.clearCurrentUserContext()
        }

        updateSyncState()
        showToast("Sync debug data reset", isError: false)
    }

    func diagnosticsReport() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let generated = formatter.string(from: Date())
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let lastServerSync = lastSyncedFromServer.map { formatter.string(from: $0) } ?? "Never"
        let pendingDocIds = pendingDocIdsForDiagnostics
        let pendingSummary = pendingDocIds.isEmpty ? "none" : pendingDocIds.joined(separator: ",")

        var lines: [String] = []
        lines.append("---")
        lines.append("ShiftVoice Sync Diagnostics")
        lines.append("Generated: \(generated)")
        lines.append("App Version: \(appVersion) (\(buildNumber))")
        lines.append("SyncState: \(syncState.rawValue)")
        lines.append("Pending Ops: \(pendingOpsCountForDiagnostics) (\(pendingSummary))")
        lines.append("Active Conflicts: \(activeConflictCount)")
        lines.append("Last Server Sync: \(lastServerSync)")
        lines.append("Write Errors: \(writeFailureCountForDiagnostics)")
        lines.append("Recent Events:")

        for event in recentSyncEventsForDiagnostics {
            lines.append("[\(formatter.string(from: event.timestamp))] \(event.message)")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
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
        hasTeamMembersLoaded = true
        shiftNotes = MockDataService.generateShiftNotes()
        recurringIssues = MockDataService.recurringIssues
        if selectedLocationId.isEmpty, let first = locations.first {
            selectedLocationId = first.id
        }
        isInitialLoading = false
        hasPendingWrites = false
        pendingNoteIds = []
        lastSyncDate = Date()
        lastSyncedFromServer = Date()
        hasServerSnapshotSinceReconnect = true
        lastWriteError = nil
        syncError = nil
        updateSyncState()
        loadFirstPage(shiftFilter: nil)
    }

    func retryPublish() {
        guard let note = pendingPublishNote else { return }
        publishError = nil
        publishReviewedNote(note)
    }

    // MARK: - Push Notifications

    var pendingNoteId: String?
    private let reviewFlowLogger = ReviewFlowLogger.shared
    var recentReviewFlowEventsForDiagnostics: [ReviewFlowEventRecord] { reviewFlowLogger.recentEvents(limit: 20) }
    var reviewFlowDropOffCountForDiagnostics: Int { reviewFlowLogger.dropOffEventCount }

    func trackReviewFlowEvent(_ event: ReviewFlowEvent) {
        reviewFlowLogger.log(event)
    }

    func completeReviewSession(noteId: String) {
        pendingNoteId = noteId
    }

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
