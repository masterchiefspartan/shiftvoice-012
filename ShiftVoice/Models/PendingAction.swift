import Foundation

nonisolated struct PendingAction: Identifiable, Codable, Sendable {
    let id: String
    let type: ActionType
    let payload: String
    let createdAt: Date

    init(id: String = UUID().uuidString, type: ActionType, payload: String = "", createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.payload = payload
        self.createdAt = createdAt
    }

    nonisolated enum ActionType: String, Codable, Sendable {
        case syncNotes
        case sendInvite
        case updateProfile
    }
}
