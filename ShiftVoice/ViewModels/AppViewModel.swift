import SwiftUI
import AVFoundation

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
    var shiftNotes: [ShiftNote] = []
    var locations: [Location] = []
    var teamMembers: [TeamMember] = []
    var organization: Organization = MockDataService.organization
    var recurringIssues: [RecurringIssue] = []

    var selectedLocationId: String = ""
    var unacknowledgedCount: Int = 0

    var isProcessing: Bool = false
    var operationState: OperationState = .idle
    var saveError: String?
    var structuringWarning: String?
    var toastMessage: ToastMessage?
    var publishError: String?
    var pendingPublishNote: ShiftNote?
    var processingElapsed: TimeInterval = 0
    private var processingTimer: Task<Void, Never>?

    let networkMonitor = NetworkMonitor.shared
    var isOffline: Bool { !networkMonitor.isConnected }

    var pendingOfflineActions: [PendingAction] = []
    private var dirtyNoteIds: Set<String> = []

    var pendingOfflineCount: Int {
        pendingOfflineActions.count
    }

    var paginatedNotes: [ShiftNote] = []
    var paginationCursor: String? = nil
    var hasMoreNotes: Bool = true
    var isLoadingPage: Bool = false
    var totalNoteCount: Int = 0
    private let pageSize: Int = 20

    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()
    private let noteStructuring = NoteStructuringService.shared

    var isRecording: Bool { audioRecorder.isRecording }
    var recordingDuration: TimeInterval { audioRecorder.recordingDuration }
    var audioLevels: [CGFloat] { audioRecorder.audioLevels }

    private let persistence = PersistenceService.shared
    private let api = APIService.shared
    private var authenticatedUserId: String?
    private var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: String?

    var currentUserId: String {
        authenticatedUserId ?? ""
    }

    var currentUserName: String {
        guard let userId = authenticatedUserId else { return "" }
        return persistence.loadUserProfile(for: userId)?.name ?? ""
    }

    var currentUserInitials: String {
        guard let userId = authenticatedUserId else { return "" }
        return persistence.loadUserProfile(for: userId)?.initials ?? ""
    }

    var selectedLocation: Location? {
        locations.first { $0.id == selectedLocationId }
    }

    var organizationBusinessType: BusinessType {
        switch organization.industryType {
        case .restaurant: return .restaurant
        case .bar: return .barPub
        case .hotel: return .hotel
        case .cafe: return .cafe
        case .catering: return .other
        case .other: return .other
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
            if hour >= s.defaultStartHour {
                best = s
            }
        }
        return ShiftDisplayInfo(from: best)
    }

    var notesThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return shiftNotes.filter {
            $0.authorId == currentUserId &&
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }.count
    }

    var feedNotes: [ShiftNote] {
        if !paginatedNotes.isEmpty || totalNoteCount > 0 {
            return paginatedNotes
        }
        return shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    init() {}

    func setAuthenticatedUser(_ userId: String) {
        authenticatedUserId = userId
        loadData()
        syncFromBackend()
    }

    func clearAuthenticatedUser() {
        api.clearAuth()
        authenticatedUserId = nil
        shiftNotes = []
        locations = []
        teamMembers = []
        recurringIssues = []
        organization = MockDataService.organization
        selectedLocationId = ""
        unacknowledgedCount = 0
        lastSyncDate = nil
        syncError = nil
    }

    private func loadData() {
        guard let userId = authenticatedUserId else { return }

        if let appData = persistence.load(for: userId) {
            organization = appData.organization
            locations = appData.locations
            teamMembers = appData.teamMembers
            shiftNotes = appData.shiftNotes
            recurringIssues = appData.recurringIssues
            selectedLocationId = appData.selectedLocationId ?? appData.locations.first?.id ?? ""
        } else {
            locations = MockDataService.locations
            teamMembers = MockDataService.teamMembers
            organization = MockDataService.organization
            recurringIssues = MockDataService.recurringIssues
            shiftNotes = MockDataService.generateShiftNotes()
            selectedLocationId = locations.first?.id ?? ""
            persistData()
        }

        let savedQueue = persistence.loadPendingActions(for: userId)
        if !savedQueue.isEmpty {
            pendingOfflineActions = savedQueue
        }
        updateUnacknowledgedCount()
    }

    func persistData() {
        guard let userId = authenticatedUserId else { return }

        let appData = AppData(
            organization: organization,
            locations: locations,
            teamMembers: teamMembers,
            shiftNotes: shiftNotes,
            recurringIssues: recurringIssues,
            userProfile: persistence.loadUserProfile(for: userId),
            selectedLocationId: selectedLocationId
        )
        persistence.save(appData, for: userId)
        saveError = nil

        pushToBackend()
    }

    private func persistDataLocal() {
        guard let userId = authenticatedUserId else { return }
        let appData = AppData(
            organization: organization,
            locations: locations,
            teamMembers: teamMembers,
            shiftNotes: shiftNotes,
            recurringIssues: recurringIssues,
            userProfile: persistence.loadUserProfile(for: userId),
            selectedLocationId: selectedLocationId
        )
        persistence.save(appData, for: userId)
        saveError = nil
    }

    // MARK: - Backend Sync

    func setBackendAuth(token: String, userId: String) {
        api.setAuth(token: token, userId: userId)
    }

    func syncFromBackend(delta: Bool = false) {
        guard api.isConfigured, !isSyncing else { return }
        isSyncing = true
        syncError = nil

        let sincDate: Date? = delta ? lastSyncDate : nil

        Task {
            do {
                let response = try await api.pullData(updatedSince: sincDate)
                let isDelta = response.isDelta ?? false
                if response.hasData, let data = response.data {
                    if let orgDTO = data.organization {
                        organization = api.decodeOrganization(orgDTO)
                    }
                    if let locsDTO = data.locations {
                        if isDelta {
                            mergeLocations(locsDTO.map { api.decodeLocation($0) })
                        } else {
                            locations = locsDTO.map { api.decodeLocation($0) }
                        }
                    }
                    if let teamDTO = data.teamMembers {
                        if isDelta {
                            mergeTeamMembers(teamDTO.map { api.decodeTeamMember($0) })
                        } else {
                            teamMembers = teamDTO.map { api.decodeTeamMember($0) }
                        }
                    }
                    if let notesDTO = data.shiftNotes {
                        if isDelta {
                            mergeShiftNotes(notesDTO.map { api.decodeShiftNote($0) })
                        } else {
                            mergeShiftNotesFullReplace(notesDTO.map { api.decodeShiftNote($0) })
                        }
                    }
                    if let issuesDTO = data.recurringIssues {
                        if isDelta {
                            mergeRecurringIssues(issuesDTO.map { api.decodeRecurringIssue($0) })
                        } else {
                            recurringIssues = issuesDTO.map { api.decodeRecurringIssue($0) }
                        }
                    }
                    if let locId = data.selectedLocationId, !locId.isEmpty {
                        selectedLocationId = locId
                    } else if selectedLocationId.isEmpty {
                        selectedLocationId = locations.first?.id ?? ""
                    }
                    updateUnacknowledgedCount()
                    persistDataLocal()
                }
                lastSyncDate = Date()
                syncError = nil
            } catch {
                syncError = error.localizedDescription
                showToast("Sync failed: \(error.localizedDescription)", isError: true)
            }
            isSyncing = false
        }
    }

    private var pushDebounceTask: Task<Void, Never>?

    private func pushToBackend() {
        guard api.isConfigured, !isOffline else {
            if isOffline, let userId = authenticatedUserId {
                persistence.savePendingActions(pendingOfflineActions, for: userId)
            }
            return
        }
        guard let userId = authenticatedUserId else { return }

        pushDebounceTask?.cancel()
        pushDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let snapshot = self.buildCurrentAppData(userId: userId)
            self.persistence.saveSnapshot(snapshot, for: userId)

            let dirtyNotes = self.shiftNotes.filter { $0.isDirty }
            let pushNotes = dirtyNotes.isEmpty ? self.shiftNotes : dirtyNotes

            let pushData = AppData(
                organization: self.organization,
                locations: self.locations,
                teamMembers: self.teamMembers,
                shiftNotes: pushNotes,
                recurringIssues: self.recurringIssues,
                userProfile: self.persistence.loadUserProfile(for: userId),
                selectedLocationId: self.selectedLocationId
            )

            do {
                _ = try await self.api.pushData(appData: pushData)
                self.lastSyncDate = Date()
                self.syncError = nil
                self.clearDirtyFlags()
                self.persistence.clearSnapshot(for: userId)
            } catch {
                self.syncError = error.localizedDescription
                self.showToast("Failed to save to server", isError: true)
            }
        }
    }

    private func buildCurrentAppData(userId: String) -> AppData {
        AppData(
            organization: organization,
            locations: locations,
            teamMembers: teamMembers,
            shiftNotes: shiftNotes,
            recurringIssues: recurringIssues,
            userProfile: persistence.loadUserProfile(for: userId),
            selectedLocationId: selectedLocationId
        )
    }

    private func markNoteDirty(_ noteId: String) {
        dirtyNoteIds.insert(noteId)
        if let idx = shiftNotes.firstIndex(where: { $0.id == noteId }) {
            shiftNotes[idx].isDirty = true
            shiftNotes[idx].updatedAt = Date()
        }
    }

    private func clearDirtyFlags() {
        dirtyNoteIds.removeAll()
        for i in shiftNotes.indices {
            shiftNotes[i].isDirty = false
        }
    }

    func rollbackFromSnapshot() {
        guard let userId = authenticatedUserId,
              let snapshot = persistence.loadSnapshot(for: userId) else { return }
        organization = snapshot.organization
        locations = snapshot.locations
        teamMembers = snapshot.teamMembers
        shiftNotes = snapshot.shiftNotes
        recurringIssues = snapshot.recurringIssues
        selectedLocationId = snapshot.selectedLocationId ?? locations.first?.id ?? ""
        updateUnacknowledgedCount()
        persistence.clearSnapshot(for: userId)
        showToast("Changes rolled back due to sync failure", isError: true)
    }

    func forceSync() {
        guard !isSyncing else { return }
        pushToBackend()
        syncFromBackend()
    }

    func deltaSyncFromBackend() {
        syncFromBackend(delta: true)
    }

    // MARK: - Persistent Offline Queue

    func enqueuePendingAction(_ action: PendingAction) {
        pendingOfflineActions.append(action)
        if let userId = authenticatedUserId {
            persistence.savePendingActions(pendingOfflineActions, for: userId)
        }
    }

    func drainPendingQueue() {
        guard api.isConfigured, !isOffline, !pendingOfflineActions.isEmpty else { return }
        let actions = pendingOfflineActions
        pendingOfflineActions.removeAll()
        if let userId = authenticatedUserId {
            persistence.clearPendingActions(for: userId)
        }

        Task {
            for action in actions {
                do {
                    switch action.type {
                    case .syncNotes:
                        pushToBackend()
                    case .updateActionItemStatus:
                        let parts = action.payload.components(separatedBy: "|")
                        if parts.count == 3 {
                            _ = try await api.updateActionItemStatus(noteId: parts[0], actionItemId: parts[1], status: parts[2])
                        }
                    case .updateActionItemAssignee:
                        let parts = action.payload.components(separatedBy: "|")
                        if parts.count >= 2 {
                            let assignee = parts.count > 2 ? parts[2] : ""
                            _ = try await api.updateNote(noteId: parts[0], updates: ["actionItemId": parts[1], "assignee": assignee])
                        }
                    case .acknowledgeNote:
                        let parts = action.payload.components(separatedBy: "|")
                        if parts.count == 3 {
                            _ = try await api.acknowledgeNote(noteId: parts[0], userId: parts[1], userName: parts[2])
                        }
                    case .deleteNote:
                        _ = try await api.updateNote(noteId: action.payload, updates: ["deleted": true])
                    case .sendInvite, .updateProfile:
                        break
                    }
                } catch {
                    if action.retryCount < 3 {
                        enqueuePendingAction(action.withIncrementedRetry())
                    }
                }
            }
        }
    }

    // MARK: - Timestamp-Based Merge Helpers

    private func mergeLocations(_ incoming: [Location]) {
        for loc in incoming {
            if let idx = locations.firstIndex(where: { $0.id == loc.id }) {
                locations[idx] = loc
            } else {
                locations.append(loc)
            }
        }
    }

    private func mergeTeamMembers(_ incoming: [TeamMember]) {
        for member in incoming {
            if let idx = teamMembers.firstIndex(where: { $0.id == member.id }) {
                let local = teamMembers[idx]
                if member.updatedAt >= local.updatedAt {
                    teamMembers[idx] = member
                }
            } else {
                teamMembers.append(member)
            }
        }
    }

    private func mergeShiftNotesFullReplace(_ incoming: [ShiftNote]) {
        let localDirty = shiftNotes.filter { $0.isDirty }
        var merged = incoming
        for dirtyNote in localDirty {
            if let idx = merged.firstIndex(where: { $0.id == dirtyNote.id }) {
                let serverNote = merged[idx]
                merged[idx] = mergeNoteWithConflictDetection(local: dirtyNote, server: serverNote)
            } else {
                merged.append(dirtyNote)
            }
        }
        shiftNotes = merged.sorted { $0.createdAt > $1.createdAt }
    }

    private func mergeShiftNotes(_ incoming: [ShiftNote]) {
        for note in incoming {
            if let idx = shiftNotes.firstIndex(where: { $0.id == note.id }) {
                let local = shiftNotes[idx]
                if local.isDirty {
                    shiftNotes[idx] = mergeNoteWithConflictDetection(local: local, server: note)
                } else if note.updatedAt >= local.updatedAt {
                    shiftNotes[idx] = note
                }
            } else {
                shiftNotes.append(note)
            }
        }
        shiftNotes.sort { $0.createdAt > $1.createdAt }
    }

    func mergeNoteWithConflictDetection(local: ShiftNote, server: ShiftNote) -> ShiftNote {
        var result = local.updatedAt >= server.updatedAt ? local : server

        var mergedActionItems: [ActionItem] = []
        let localActions = Dictionary(uniqueKeysWithValues: local.actionItems.map { ($0.id, $0) })
        let serverActions = Dictionary(uniqueKeysWithValues: server.actionItems.map { ($0.id, $0) })

        let allIds = Set(localActions.keys).union(serverActions.keys)

        for id in allIds {
            if let localItem = localActions[id], let serverItem = serverActions[id] {
                let merged = mergeActionItemPerField(local: localItem, server: serverItem)
                mergedActionItems.append(merged)
            } else if let localItem = localActions[id] {
                mergedActionItems.append(localItem)
            } else if let serverItem = serverActions[id] {
                mergedActionItems.append(serverItem)
            }
        }

        result.actionItems = mergedActionItems

        let mergedAcks = mergeAcknowledgments(local: local.acknowledgments, server: server.acknowledgments)
        result.acknowledgments = mergedAcks

        return result
    }

    func mergeActionItemPerField(local: ActionItem, server: ActionItem) -> ActionItem {
        var merged = local
        var conflictParts: [String] = []

        if local.status != server.status {
            if server.statusUpdatedAt > local.statusUpdatedAt {
                merged.status = server.status
                merged.statusUpdatedAt = server.statusUpdatedAt
            } else if local.statusUpdatedAt == server.statusUpdatedAt && local.status != server.status {
                conflictParts.append("Status changed to '\(server.status.rawValue)' by another user")
            }
        }

        if local.assignee != server.assignee {
            if server.assigneeUpdatedAt > local.assigneeUpdatedAt {
                merged.assignee = server.assignee
                merged.assigneeUpdatedAt = server.assigneeUpdatedAt
            } else if local.assigneeUpdatedAt == server.assigneeUpdatedAt && local.assignee != server.assignee {
                let serverAssignee = server.assignee ?? "Unassigned"
                conflictParts.append("Assignee changed to '\(serverAssignee)' by another user")
            }
        }

        merged.updatedAt = max(local.updatedAt, server.updatedAt)

        if !conflictParts.isEmpty {
            merged.hasConflict = true
            merged.conflictDescription = conflictParts.joined(separator: "; ")
        }

        return merged
    }

    private func mergeAcknowledgments(local: [Acknowledgment], server: [Acknowledgment]) -> [Acknowledgment] {
        var merged = local
        let localIds = Set(local.map(\.id))
        for ack in server where !localIds.contains(ack.id) {
            merged.append(ack)
        }
        return merged.sorted { $0.timestamp < $1.timestamp }
    }

    private func mergeRecurringIssues(_ incoming: [RecurringIssue]) {
        for issue in incoming {
            if let idx = recurringIssues.firstIndex(where: { $0.id == issue.id }) {
                recurringIssues[idx] = issue
            } else {
                recurringIssues.append(issue)
            }
        }
    }

    func dismissConflict(noteId: String, actionItemId: String) {
        guard let noteIdx = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIdx = shiftNotes[noteIdx].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        shiftNotes[noteIdx].actionItems[itemIdx].hasConflict = false
        shiftNotes[noteIdx].actionItems[itemIdx].conflictDescription = nil
        persistDataLocal()
    }

    var conflictedActionItems: [(item: ActionItem, noteId: String)] {
        shiftNotes.flatMap { note in
            note.actionItems.filter { $0.hasConflict }.map { (item: $0, noteId: note.id) }
        }
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

    func applyOnboardingData(businessType: BusinessType, locationName: String, timezone: String, teamInvites: [TeamInvite]) {
        let industryType: IndustryType = switch businessType {
        case .restaurant: .restaurant
        case .barPub: .bar
        case .hotel: .hotel
        case .cafe: .cafe
        default: .other
        }

        organization = Organization(
            name: organization.name,
            ownerId: currentUserId,
            plan: organization.plan,
            industryType: industryType
        )

        let newLocation = Location(
            name: locationName,
            address: "",
            timezone: timezone,
            managerIds: [currentUserId]
        )
        locations = [newLocation]
        selectedLocationId = newLocation.id

        let userEmail: String = {
            guard let userId = authenticatedUserId else { return "" }
            return persistence.loadUserProfile(for: userId)?.email ?? ""
        }()

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

        persistData()
    }

    func updateUnacknowledgedCount() {
        unacknowledgedCount = shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .filter { !$0.acknowledgments.contains(where: { $0.userId == currentUserId }) }
            .count
    }

    func acknowledgeNote(_ noteId: String) {
        guard let index = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
        let ack = Acknowledgment(
            userId: currentUserId,
            userName: currentUserName
        )
        shiftNotes[index].acknowledgments.append(ack)
        markNoteDirty(noteId)
        updateUnacknowledgedCount()
        persistData()

        if api.isConfigured, !isOffline {
            Task {
                _ = try? await api.acknowledgeNote(noteId: noteId, userId: currentUserId, userName: currentUserName)
            }
        } else {
            enqueuePendingAction(PendingAction(type: .acknowledgeNote, payload: "\(noteId)|\(currentUserId)|\(currentUserName)"))
        }
    }

    func isNoteAcknowledged(_ note: ShiftNote) -> Bool {
        note.acknowledgments.contains { $0.userId == currentUserId }
    }

    func notesForLocation(_ locationId: String) -> [ShiftNote] {
        shiftNotes.filter { $0.locationId == locationId }
    }

    func requestRecordingPermissions() async -> Bool {
        let micGranted = await audioRecorder.requestPermission()
        let speechGranted = await transcriptionService.requestPermission()
        return micGranted && speechGranted
    }

    func startRecording() {
        audioRecorder.startRecording()
    }

    func stopRecording(selectedShift: ShiftDisplayInfo?) {
        let duration = audioRecorder.recordingDuration
        let audioURL = audioRecorder.currentAudioURL
        audioRecorder.stopRecording()
        isProcessing = true
        structuringWarning = nil
        processingElapsed = 0
        startProcessingTimer()

        Task {
            var transcript = ""
            if let audioURL {
                if let result = await transcriptionService.transcribeAudioFile(at: audioURL) {
                    transcript = result
                }
            }

            let shiftInfo = selectedShift ?? currentShiftDisplayInfo

            var summary: String
            var categorizedItems: [CategorizedItem]
            var actionItems: [ActionItem]
            var usedAI = false

            let businessType = organizationBusinessType.rawValue.lowercased()

            let aiResult = await withTaskGroup(of: Result<StructuringResult, StructuringError>?.self) { group -> Result<StructuringResult, StructuringError>? in
                group.addTask {
                    await self.noteStructuring.structureTranscript(
                        transcript,
                        businessType: businessType,
                        authToken: self.api.currentAuthToken,
                        userId: self.authenticatedUserId
                    )
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(30))
                    return nil
                }
                for await result in group {
                    if let result {
                        group.cancelAll()
                        return result
                    }
                }
                group.cancelAll()
                return .failure(.timeout)
            }

            switch aiResult {
            case .success(let result):
                summary = result.summary
                categorizedItems = result.categorizedItems
                actionItems = result.actionItems
                usedAI = true
                structuringWarning = result.warning
            case .failure(let error):
                summary = generateSummary(from: transcript)
                categorizedItems = generateCategories(from: transcript)
                actionItems = generateActionItems(from: categorizedItems)
                if !transcript.isEmpty {
                    structuringWarning = "AI structuring unavailable — structured locally. \(error.userMessage)"
                }
            case .none:
                summary = generateSummary(from: transcript)
                categorizedItems = generateCategories(from: transcript)
                actionItems = generateActionItems(from: categorizedItems)
                structuringWarning = "AI structuring timed out — structured locally."
            }

            pendingReviewData = PendingNoteReviewData(
                rawTranscript: transcript,
                audioDuration: duration,
                audioUrl: audioURL?.lastPathComponent,
                shiftInfo: shiftInfo,
                summary: summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems,
                usedAI: usedAI,
                structuringWarning: structuringWarning
            )
            stopProcessingTimer()
            isProcessing = false
        }
    }

    func cancelProcessing() {
        stopProcessingTimer()
        isProcessing = false
        pendingReviewData = nil
    }

    private func startProcessingTimer() {
        processingTimer?.cancel()
        processingTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                processingElapsed += 1
            }
        }
    }

    private func stopProcessingTimer() {
        processingTimer?.cancel()
        processingTimer = nil
    }

    func publishReviewedNote(_ note: ShiftNote) {
        var mutableNote = note
        mutableNote.updatedAt = Date()
        mutableNote.isDirty = true
        shiftNotes.insert(mutableNote, at: 0)
        dirtyNoteIds.insert(mutableNote.id)
        updateUnacknowledgedCount()
        publishError = nil
        pendingPublishNote = nil

        if isOffline {
            enqueuePendingAction(PendingAction(type: .syncNotes, payload: note.id))
            persistDataLocal()
            showToast("Saved offline — will sync when connected", isError: false)
        } else {
            persistData()
        }
        pendingReviewData = nil
    }

    func discardPendingNote() {
        pendingReviewData = nil
    }

    func updateActionItemAssignee(noteId: String, actionItemId: String, assignee: String?) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].assignee = assignee
        shiftNotes[noteIndex].actionItems[itemIndex].assigneeUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        markNoteDirty(noteId)
        persistData()
    }

    private func generateSummary(from transcript: String) -> String {
        guard !transcript.isEmpty else { return "Voice note recorded (no transcription available)." }
        let sentences = transcript.components(separatedBy: ". ")
        if sentences.count <= 2 { return transcript }
        return sentences.prefix(3).joined(separator: ". ") + "."
    }

    private func generateCategories(from transcript: String) -> [CategorizedItem] {
        guard !transcript.isEmpty else { return [] }
        let segments = splitTranscriptIntoSegments(transcript)
        var items: [CategorizedItem] = []

        let keywords: [(NoteCategory, String?, [String])] = [
            (.equipment, "cat_equip", ["broken", "repair", "fix", "malfunction", "not working", "equipment", "machine", "fryer", "oven", "grill"]),
            (.inventory, "cat_inv", ["out of", "running low", "restock", "order", "inventory", "supply", "supplies", "shortage"]),
            (.maintenance, "cat_maint", ["leak", "clean", "maintenance", "plumbing", "hvac", "light", "bulb"]),
            (.healthSafety, "cat_hs", ["safety", "hazard", "injury", "slip", "spill", "health", "sanitation"]),
            (.staffNote, "cat_staff", ["staff", "employee", "called out", "no show", "late", "schedule", "training"]),
            (.guestIssue, "cat_guest", ["guest", "customer", "complaint", "unhappy", "refund", "comped"]),
            (.eightySixed, "cat_86", ["86", "eighty-six", "ran out", "sold out", "unavailable"])
        ]

        for segment in segments {
            let lower = segment.lowercased()
            var matched = false
            for (category, templateId, words) in keywords {
                if words.contains(where: { lower.contains($0) }) {
                    items.append(CategorizedItem(
                        category: category,
                        categoryTemplateId: templateId,
                        content: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                        urgency: category == .healthSafety || category == .eightySixed ? .immediate : .nextShift
                    ))
                    matched = true
                    break
                }
            }
            if !matched {
                items.append(CategorizedItem(
                    category: .general,
                    categoryTemplateId: "cat_gen",
                    content: segment.trimmingCharacters(in: .whitespacesAndNewlines),
                    urgency: .fyi
                ))
            }
        }

        if items.isEmpty {
            items.append(CategorizedItem(
                category: .general,
                categoryTemplateId: "cat_gen",
                content: transcript,
                urgency: .fyi
            ))
        }

        return items
    }

    func splitTranscriptIntoSegments(_ transcript: String) -> [String] {
        let sentenceDelimiters = CharacterSet(charactersIn: ".!?")
        let rawSentences = transcript.components(separatedBy: sentenceDelimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 5 }

        let separators = [
            " also ", " and then ", " next ", " another thing ",
            " additionally ", " plus ", " on top of that ",
            " second ", " third ", " finally ", " lastly ",
            ", and ", " as well as ", " besides that ",
            " one more thing ", " other than that ", " apart from that ",
            " number one ", " number two ", " number three ",
            " first ", " then "
        ]

        var segments: [String] = []

        for sentence in rawSentences {
            let subSegments = recursiveSplit(sentence, separators: separators)
            segments.append(contentsOf: subSegments)
        }

        return segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 5 }
    }

    private func recursiveSplit(_ text: String, separators: [String]) -> [String] {
        let lower = text.lowercased()

        for sep in separators {
            guard let range = lower.range(of: sep) else { continue }
            let originalRange = text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.lowerBound))..<text.index(text.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))

            let before = String(text[text.startIndex..<originalRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(text[originalRange.upperBound..<text.endIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var results: [String] = []
            if before.count > 5 { results.append(before) }
            if after.count > 5 {
                results.append(contentsOf: recursiveSplit(after, separators: separators))
            }
            if !results.isEmpty { return results }
        }

        return [text]
    }

    func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        categorized.compactMap { item in
            let taskDescription: String
            switch item.category {
            case .equipment: taskDescription = "Check and address: \(item.content.prefix(80))"
            case .inventory: taskDescription = "Restock: \(item.content.prefix(80))"
            case .maintenance: taskDescription = "Fix: \(item.content.prefix(80))"
            case .healthSafety: taskDescription = "Resolve safety issue: \(item.content.prefix(80))"
            case .staffNote: taskDescription = "Follow up: \(item.content.prefix(80))"
            case .guestIssue: taskDescription = "Guest concern: \(item.content.prefix(80))"
            case .eightySixed: taskDescription = "86'd - restock: \(item.content.prefix(80))"
            case .reservation: taskDescription = "Reservation follow-up: \(item.content.prefix(80))"
            case .incident: taskDescription = "Incident follow-up: \(item.content.prefix(80))"
            case .general:
                guard item.urgency != .fyi else { return nil }
                taskDescription = "Review: \(item.content.prefix(80))"
            }
            return ActionItem(
                task: taskDescription,
                category: item.category,
                categoryTemplateId: item.categoryTemplateId,
                urgency: item.urgency
            )
        }
    }

    func filteredNotes(shiftFilter: ShiftType?) -> [ShiftNote] {
        let notes = feedNotes
        guard let filter = shiftFilter else { return notes }
        return notes.filter { $0.shiftType == filter }
    }

    func filteredNotes(shiftDisplayFilter: ShiftDisplayInfo?) -> [ShiftNote] {
        let notes = feedNotes
        guard let filter = shiftDisplayFilter else { return notes }
        return notes.filter { $0.shiftDisplayInfo.id == filter.id }
    }

    func locationStats(_ locationId: String) -> (noteCount: Int, unacknowledged: Int, highestUrgency: UrgencyLevel) {
        let notes = notesForLocation(locationId)
        let unack = notes.filter { !$0.acknowledgments.contains(where: { $0.userId == currentUserId }) }.count
        let highest = notes.compactMap { $0.highestUrgency }.min(by: { $0.sortOrder < $1.sortOrder }) ?? .fyi
        return (notes.count, unack, highest)
    }

    var allActionItems: [(item: ActionItem, noteId: String, authorName: String, locationId: String)] {
        shiftNotes.flatMap { note in
            note.actionItems.map { (item: $0, noteId: note.id, authorName: note.authorName, locationId: note.locationId) }
        }
    }

    var allActionItemsWithDate: [(item: ActionItem, noteId: String, authorName: String, locationId: String, createdAt: Date)] {
        shiftNotes.flatMap { note in
            note.actionItems.map { (item: $0, noteId: note.id, authorName: note.authorName, locationId: note.locationId, createdAt: note.createdAt) }
        }
    }

    func locationName(for locationId: String) -> String {
        locations.first { $0.id == locationId }?.name ?? "Unknown"
    }

    func updateActionItemStatus(noteId: String, actionItemId: String, newStatus: ActionItemStatus) {
        guard let noteIndex = shiftNotes.firstIndex(where: { $0.id == noteId }),
              let itemIndex = shiftNotes[noteIndex].actionItems.firstIndex(where: { $0.id == actionItemId }) else { return }
        let now = Date()
        shiftNotes[noteIndex].actionItems[itemIndex].status = newStatus
        shiftNotes[noteIndex].actionItems[itemIndex].statusUpdatedAt = now
        shiftNotes[noteIndex].actionItems[itemIndex].updatedAt = now
        markNoteDirty(noteId)
        persistData()

        if api.isConfigured, !isOffline {
            Task {
                _ = try? await api.updateActionItemStatus(noteId: noteId, actionItemId: actionItemId, status: newStatus.rawValue)
            }
        } else {
            enqueuePendingAction(PendingAction(type: .updateActionItemStatus, payload: "\(noteId)|\(actionItemId)|\(newStatus.rawValue)"))
        }
    }

    func resolveRecurringIssue(_ issueId: String) {
        guard let index = recurringIssues.firstIndex(where: { $0.id == issueId }) else { return }
        recurringIssues[index].status = .resolved
        persistData()
    }

    func acknowledgeRecurringIssue(_ issueId: String) {
        guard let index = recurringIssues.firstIndex(where: { $0.id == issueId }) else { return }
        recurringIssues[index].status = .acknowledged
        persistData()
    }

    func deleteNote(_ noteId: String) {
        shiftNotes.removeAll { $0.id == noteId }
        dirtyNoteIds.remove(noteId)
        updateUnacknowledgedCount()
        persistData()

        if isOffline {
            enqueuePendingAction(PendingAction(type: .deleteNote, payload: noteId))
        }
    }

    func addLocation(_ location: Location) {
        locations.append(location)
        persistData()
    }

    func removeLocation(_ locationId: String) {
        locations.removeAll { $0.id == locationId }
        shiftNotes.removeAll { $0.locationId == locationId }
        if selectedLocationId == locationId {
            selectedLocationId = locations.first?.id ?? ""
        }
        updateUnacknowledgedCount()
        persistData()
    }

    func addTeamMember(_ member: TeamMember) {
        teamMembers.append(member)
        persistData()
    }

    func removeTeamMember(_ memberId: String) {
        teamMembers.removeAll { $0.id == memberId }
        persistData()
    }

    func updateSelectedLocation(_ locationId: String) {
        selectedLocationId = locationId
        updateUnacknowledgedCount()
        persistData()
    }

    func resetAllData() {
        guard let userId = authenticatedUserId else { return }
        persistence.clearUserData(for: userId)
        locations = MockDataService.locations
        teamMembers = MockDataService.teamMembers
        organization = MockDataService.organization
        recurringIssues = MockDataService.recurringIssues
        shiftNotes = MockDataService.generateShiftNotes()
        selectedLocationId = locations.first?.id ?? ""
        updateUnacknowledgedCount()
        persistData()
    }

    func handleNetworkReconnect() {
        guard authenticatedUserId != nil else { return }
        if !pendingOfflineActions.isEmpty {
            showToast("Back online — syncing \(pendingOfflineActions.count) pending changes", isError: false)
            drainPendingQueue()
        }
        forceSync()
    }

    func retryPublish() {
        guard let note = pendingPublishNote else { return }
        publishError = nil
        publishReviewedNote(note)
    }

    var pendingReviewData: PendingNoteReviewData?
    var pendingNoteId: String?

    func handlePushNotificationTap(noteId: String) {
        pendingNoteId = noteId
    }

    // MARK: - Pagination

    func resetPagination() {
        paginatedNotes = []
        paginationCursor = nil
        hasMoreNotes = true
        totalNoteCount = 0
    }

    func loadFirstPage(shiftFilter: String? = nil) {
        guard api.isConfigured else { return }
        resetPagination()
        loadNextPage(shiftFilter: shiftFilter)
    }

    func loadNextPage(shiftFilter: String? = nil) {
        guard api.isConfigured, !isLoadingPage, hasMoreNotes else { return }
        isLoadingPage = true

        let locationId = selectedLocationId.isEmpty ? nil : selectedLocationId
        let cursor = paginationCursor

        Task {
            do {
                let response = try await api.fetchNotes(
                    locationId: locationId,
                    shiftFilter: shiftFilter,
                    cursor: cursor,
                    limit: pageSize
                )
                let decoded = response.notes.map { api.decodeShiftNote($0) }
                if cursor == nil {
                    paginatedNotes = decoded
                } else {
                    paginatedNotes.append(contentsOf: decoded)
                }
                totalNoteCount = response.totalCount
                hasMoreNotes = response.hasMore
                paginationCursor = response.nextCursor
            } catch {
                if cursor == nil {
                    paginatedNotes = shiftNotes
                        .filter { $0.locationId == selectedLocationId }
                        .sorted { $0.createdAt > $1.createdAt }
                    hasMoreNotes = false
                    totalNoteCount = paginatedNotes.count
                }
            }
            isLoadingPage = false
        }
    }

    func filteredPaginatedNotes(shiftDisplayFilter: ShiftDisplayInfo?) -> [ShiftNote] {
        guard let filter = shiftDisplayFilter else { return feedNotes }
        return feedNotes.filter { $0.shiftDisplayInfo.id == filter.id }
    }

    // MARK: - Test Helpers

    func testGenerateCategories(from transcript: String) -> [CategorizedItem] {
        generateCategories(from: transcript)
    }

    func testGenerateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        generateActionItems(from: categorized)
    }

    func testGenerateSummary(from transcript: String) -> String {
        generateSummary(from: transcript)
    }

    func testSplitTranscript(_ transcript: String) -> [String] {
        splitTranscriptIntoSegments(transcript)
    }
}
