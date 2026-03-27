import Foundation

nonisolated enum ConflictState: String, Codable, Sendable {
    case detected
    case resolved
    case dismissed
}

nonisolated enum ConflictResolution: String, Codable, Sendable {
    case keptServer
    case appliedLocal
    case dismissed
}

nonisolated struct ConflictItem: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let noteId: String
    let fieldName: String
    let localIntendedValue: String
    let serverCurrentValue: String
    let serverUpdatedBy: String
    let serverUpdatedAt: Date
    let localEditStartedAt: Date
    let detectedAt: Date
    var state: ConflictState
    var resolvedAt: Date?
    var resolvedBy: String?
    var resolutionAction: ConflictResolution?

    init(
        id: String = UUID().uuidString,
        noteId: String,
        fieldName: String,
        localIntendedValue: String,
        serverCurrentValue: String,
        serverUpdatedBy: String,
        serverUpdatedAt: Date,
        localEditStartedAt: Date,
        detectedAt: Date = Date(),
        state: ConflictState = .detected,
        resolvedAt: Date? = nil,
        resolvedBy: String? = nil,
        resolutionAction: ConflictResolution? = nil
    ) {
        self.id = id
        self.noteId = noteId
        self.fieldName = fieldName
        self.localIntendedValue = localIntendedValue
        self.serverCurrentValue = serverCurrentValue
        self.serverUpdatedBy = serverUpdatedBy
        self.serverUpdatedAt = serverUpdatedAt
        self.localEditStartedAt = localEditStartedAt
        self.detectedAt = detectedAt
        self.state = state
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
        self.resolutionAction = resolutionAction
    }
}
