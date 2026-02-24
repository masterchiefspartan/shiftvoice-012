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
    var organization: Organization = Organization(name: "", ownerId: "")
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
    var pendingOfflineCount: Int { 0 }

    var paginatedNotes: [ShiftNote] = []
    var paginationCursor: String? = nil
    var hasMoreNotes: Bool = false
    var isLoadingPage: Bool = false
    var totalNoteCount: Int = 0

    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()
    private let noteStructuring = NoteStructuringService.shared
    private let firestore = FirestoreService.shared
    private let api = APIService.shared

    var isRecording: Bool { audioRecorder.isRecording }
    var recordingDuration: TimeInterval { audioRecorder.recordingDuration }
    var audioLevels: [CGFloat] { audioRecorder.audioLevels }

    private(set) var userProfile: UserProfile?
    private var authenticatedUserId: String?
    private var organizationId: String?
    var lastSyncDate: Date?
    var syncError: String?

    var currentUserId: String { authenticatedUserId ?? "" }
    var currentUserName: String { userProfile?.name ?? "" }
    var currentUserInitials: String { userProfile?.initials ?? "" }

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

    var notesThisMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        return shiftNotes.filter {
            $0.authorId == currentUserId &&
            calendar.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }.count
    }

    var feedNotes: [ShiftNote] {
        shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    init() {}

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
            self.updateUnacknowledgedCount()
        }

        firestore.startTeamMembersListener(orgId) { [weak self] members in
            guard let self else { return }
            self.teamMembers = members
        }

        firestore.startShiftNotesListener(orgId) { [weak self] notes in
            guard let self else { return }
            self.shiftNotes = notes
            self.updateUnacknowledgedCount()
            self.lastSyncDate = Date()
        }

        firestore.startRecurringIssuesListener(orgId) { [weak self] issues in
            guard let self else { return }
            self.recurringIssues = issues
        }
    }

    // MARK: - Backend API Auth (for AI structuring)

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
        updateUnacknowledgedCount()
        publishError = nil
        pendingPublishNote = nil
        pendingReviewData = nil
        writeShiftNote(mutableNote)

        if isOffline {
            showToast("Saved offline — will sync when connected", isError: false)
        }
    }

    func deleteNote(_ noteId: String) {
        shiftNotes.removeAll { $0.id == noteId }
        updateUnacknowledgedCount()
        guard let orgId = organizationId else { return }
        firestore.deleteShiftNote(noteId, orgId: orgId)
    }

    func acknowledgeNote(_ noteId: String) {
        guard let index = shiftNotes.firstIndex(where: { $0.id == noteId }) else { return }
        let ack = Acknowledgment(userId: currentUserId, userName: currentUserName)
        shiftNotes[index].acknowledgments.append(ack)
        shiftNotes[index].updatedAt = Date()
        updateUnacknowledgedCount()
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

    var conflictedActionItems: [(item: ActionItem, noteId: String)] {
        shiftNotes.flatMap { note in
            note.actionItems.filter { $0.hasConflict }.map { (item: $0, noteId: note.id) }
        }
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
        updateUnacknowledgedCount()
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
        updateUnacknowledgedCount()
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
        unacknowledgedCount = shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .filter { !$0.acknowledgments.contains(where: { $0.userId == currentUserId }) }
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

    // MARK: - Pagination (data from Firestore listeners)

    func resetPagination() {
        paginatedNotes = []
        paginationCursor = nil
        hasMoreNotes = false
        totalNoteCount = 0
    }

    func loadFirstPage(shiftFilter: String? = nil) {}
    func loadNextPage(shiftFilter: String? = nil) {}

    func filteredPaginatedNotes(shiftDisplayFilter: ShiftDisplayInfo?) -> [ShiftNote] {
        guard let filter = shiftDisplayFilter else { return feedNotes }
        return feedNotes.filter { $0.shiftDisplayInfo.id == filter.id }
    }

    // MARK: - Push Notifications

    var pendingReviewData: PendingNoteReviewData?
    var pendingNoteId: String?

    func handlePushNotificationTap(noteId: String) {
        pendingNoteId = noteId
    }

    // MARK: - Recording

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

    func discardPendingNote() {
        pendingReviewData = nil
    }

    // MARK: - Display Helpers

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

    // MARK: - Note Processing

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

    // MARK: - Merge Helpers (kept for test compatibility)

    func mergeNoteWithConflictDetection(local: ShiftNote, server: ShiftNote) -> ShiftNote {
        return local.updatedAt >= server.updatedAt ? local : server
    }

    func mergeActionItemPerField(local: ActionItem, server: ActionItem) -> ActionItem {
        return local.updatedAt >= server.updatedAt ? local : server
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
