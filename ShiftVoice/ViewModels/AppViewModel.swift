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

    let networkMonitor = NetworkMonitor.shared
    var isOffline: Bool { !networkMonitor.isConnected }

    var pendingOfflineActions: [PendingAction] = []

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
                            shiftNotes = notesDTO.map { api.decodeShiftNote($0) }
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

                    if let userId = authenticatedUserId {
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
                    }
                }
                lastSyncDate = Date()
                syncError = nil
            } catch {
                syncError = error.localizedDescription
            }
            isSyncing = false
        }
    }

    private func pushToBackend() {
        guard api.isConfigured, !isOffline else { return }
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

        Task {
            do {
                _ = try await api.pushData(appData: appData)
                lastSyncDate = Date()
                syncError = nil
            } catch {
                syncError = error.localizedDescription
            }
        }
    }

    func forceSync() {
        guard !isSyncing else { return }
        pushToBackend()
        syncFromBackend()
    }

    func deltaSyncFromBackend() {
        syncFromBackend(delta: true)
    }

    // MARK: - Delta Merge Helpers

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
                teamMembers[idx] = member
            } else {
                teamMembers.append(member)
            }
        }
    }

    private func mergeShiftNotes(_ incoming: [ShiftNote]) {
        for note in incoming {
            if let idx = shiftNotes.firstIndex(where: { $0.id == note.id }) {
                shiftNotes[idx] = note
            } else {
                shiftNotes.append(note)
            }
        }
        shiftNotes.sort { $0.createdAt > $1.createdAt }
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

    func dismissOperationState() {
        operationState = .idle
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
        updateUnacknowledgedCount()
        persistData()

        if api.isConfigured, !isOffline {
            Task {
                _ = try? await api.acknowledgeNote(noteId: noteId, userId: currentUserId, userName: currentUserName)
            }
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

            let businessType = organizationBusinessType.rawValue.lowercased()
            let aiResult = await noteStructuring.structureTranscript(
                transcript,
                businessType: businessType,
                authToken: api.currentAuthToken,
                userId: authenticatedUserId
            )

            if let ai = aiResult {
                summary = ai.summary
                categorizedItems = ai.categorizedItems
                actionItems = ai.actionItems
            } else {
                summary = generateSummary(from: transcript)
                categorizedItems = generateCategories(from: transcript)
                actionItems = generateActionItems(from: categorizedItems)
            }

            let newNote = ShiftNote(
                authorId: currentUserId,
                authorName: currentUserName,
                authorInitials: currentUserInitials,
                locationId: selectedLocationId,
                shiftType: currentShiftType,
                shiftTemplateId: shiftInfo.id,
                rawTranscript: transcript,
                audioUrl: audioURL?.lastPathComponent,
                audioDuration: duration,
                summary: summary,
                categorizedItems: categorizedItems,
                actionItems: actionItems
            )

            isProcessing = false
            shiftNotes.insert(newNote, at: 0)
            updateUnacknowledgedCount()
            persistData()
        }
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

    private func splitTranscriptIntoSegments(_ transcript: String) -> [String] {
        let separators = [" also ", " and then ", " next ", " another thing ", " additionally ", " plus ", " on top of that ", " second ", " third ", " finally ", " lastly "]
        var segments: [String] = []

        let sentences = transcript.components(separatedBy: ". ")
            .flatMap { $0.components(separatedBy: ", and ") }

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var didSplit = false
            for sep in separators {
                if trimmed.lowercased().contains(sep) {
                    let parts = trimmed.lowercased().range(of: sep).map { range -> [String] in
                        let before = String(trimmed[trimmed.startIndex..<range.lowerBound])
                        let after = String(trimmed[range.upperBound..<trimmed.endIndex])
                        return [before, after].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    }
                    if let parts, parts.count > 1 {
                        segments.append(contentsOf: parts)
                        didSplit = true
                        break
                    }
                }
            }
            if !didSplit {
                segments.append(trimmed)
            }
        }

        return segments.filter { $0.count > 5 }
    }

    private func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        categorized.compactMap { item in
            guard item.category != .general else { return nil }
            let taskDescription: String
            switch item.category {
            case .equipment: taskDescription = "Check and address: \(item.content.prefix(80))"
            case .inventory: taskDescription = "Restock: \(item.content.prefix(80))"
            case .maintenance: taskDescription = "Fix: \(item.content.prefix(80))"
            case .healthSafety: taskDescription = "Resolve safety issue: \(item.content.prefix(80))"
            case .staffNote: taskDescription = "Follow up: \(item.content.prefix(80))"
            case .guestIssue: taskDescription = "Guest concern: \(item.content.prefix(80))"
            case .eightySixed: taskDescription = "86'd - restock: \(item.content.prefix(80))"
            default: taskDescription = "Review: \(item.content.prefix(80))"
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
        shiftNotes[noteIndex].actionItems[itemIndex].status = newStatus
        persistData()

        if api.isConfigured, !isOffline {
            Task {
                _ = try? await api.updateActionItemStatus(noteId: noteId, actionItemId: actionItemId, status: newStatus.rawValue)
            }
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
        updateUnacknowledgedCount()
        persistData()
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
        forceSync()
    }

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
}
