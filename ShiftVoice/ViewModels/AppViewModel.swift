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

    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()

    var isRecording: Bool { audioRecorder.isRecording }
    var recordingDuration: TimeInterval { audioRecorder.recordingDuration }
    var audioLevels: [CGFloat] { audioRecorder.audioLevels }

    private let persistence = PersistenceService.shared
    private var authenticatedUserId: String?

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

    var feedNotes: [ShiftNote] {
        shiftNotes
            .filter { $0.locationId == selectedLocationId }
            .sorted { $0.createdAt > $1.createdAt }
    }

    init() {}

    func setAuthenticatedUser(_ userId: String) {
        authenticatedUserId = userId
        loadData()
    }

    func clearAuthenticatedUser() {
        authenticatedUserId = nil
        shiftNotes = []
        locations = []
        teamMembers = []
        recurringIssues = []
        organization = MockDataService.organization
        selectedLocationId = ""
        unacknowledgedCount = 0
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
            let summary = generateSummary(from: transcript)
            let categorizedItems = generateCategories(from: transcript)
            let actionItems = generateActionItems(from: categorizedItems)

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
        let lower = transcript.lowercased()
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

        for (category, templateId, words) in keywords {
            if words.contains(where: { lower.contains($0) }) {
                items.append(CategorizedItem(
                    category: category,
                    categoryTemplateId: templateId,
                    content: transcript,
                    urgency: category == .healthSafety || category == .eightySixed ? .immediate : .nextShift
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

    private func generateActionItems(from categorized: [CategorizedItem]) -> [ActionItem] {
        categorized.compactMap { item in
            guard item.category != .general else { return nil }
            let taskDescription: String
            switch item.category {
            case .equipment: taskDescription = "Check and address equipment issue"
            case .inventory: taskDescription = "Restock items mentioned in note"
            case .maintenance: taskDescription = "Address maintenance concern"
            case .healthSafety: taskDescription = "Review and resolve safety issue"
            case .staffNote: taskDescription = "Follow up on staffing note"
            case .guestIssue: taskDescription = "Follow up on guest concern"
            case .eightySixed: taskDescription = "Update 86'd items and restock"
            default: taskDescription = "Review and follow up"
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
}
