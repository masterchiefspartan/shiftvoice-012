import Foundation

nonisolated struct PendingAction: Identifiable, Codable, Sendable {
    let id: String
    let type: ActionType
    let payload: String
    let createdAt: Date
    let retryCount: Int

    init(id: String = UUID().uuidString, type: ActionType, payload: String = "", createdAt: Date = Date(), retryCount: Int = 0) {
        self.id = id
        self.type = type
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
    }

    func withIncrementedRetry() -> PendingAction {
        PendingAction(id: id, type: type, payload: payload, createdAt: createdAt, retryCount: retryCount + 1)
    }

    nonisolated enum ActionType: String, Codable, Sendable {
        case syncNotes
        case sendInvite
        case updateProfile
        case updateActionItemStatus
        case updateActionItemAssignee
        case acknowledgeNote
        case deleteNote
    }
}
