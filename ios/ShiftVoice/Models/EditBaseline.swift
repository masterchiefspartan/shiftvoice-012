import Foundation

nonisolated struct EditBaseline: Codable, Equatable, Sendable {
    let noteId: String
    let capturedAt: Date
    let fields: [String: String]
    let updatedAtServer: Date

    init(
        noteId: String,
        capturedAt: Date = Date(),
        fields: [String: String],
        updatedAtServer: Date
    ) {
        self.noteId = noteId
        self.capturedAt = capturedAt
        self.fields = fields
        self.updatedAtServer = updatedAtServer
    }
}
