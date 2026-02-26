import Foundation

nonisolated enum SyncState: String, Codable, Sendable {
    case offline
    case onlineCache = "online_cache"
    case syncing
    case onlineFresh = "online_fresh"
    case error
}

nonisolated enum PendingNoteOperationType: String, Codable, Sendable {
    case create
    case edit
    case delete
}

nonisolated enum SyncError: Error, Codable, Sendable, Equatable {
    case permissionDenied
    case authExpired
    case invalidData
    case rejectedTransaction
    case networkFatal
    case unknown(code: Int, message: String)

    init(error: Error) {
        let nsError = error as NSError
        let code = nsError.code

        switch code {
        case 7:
            self = .permissionDenied
        case 16:
            self = .authExpired
        case 3:
            self = .invalidData
        case 10:
            self = .rejectedTransaction
        case 14:
            self = .networkFatal
        default:
            self = .unknown(code: code, message: nsError.localizedDescription)
        }
    }
}

nonisolated struct PendingNoteOperation: Codable, Sendable {
    let noteId: String
    let type: PendingNoteOperationType
    let expectedUpdatedAtClient: Date?
    let lastSeenUpdatedAtServer: Date?
    let recordedAt: Date

    init(
        noteId: String,
        type: PendingNoteOperationType,
        expectedUpdatedAtClient: Date? = nil,
        lastSeenUpdatedAtServer: Date? = nil,
        recordedAt: Date = Date()
    ) {
        self.noteId = noteId
        self.type = type
        self.expectedUpdatedAtClient = expectedUpdatedAtClient
        self.lastSeenUpdatedAtServer = lastSeenUpdatedAtServer
        self.recordedAt = recordedAt
    }
}

nonisolated struct PendingSyncState: Codable, Sendable {
    var pendingOperations: [String: PendingNoteOperation]
    var pendingDeletes: [String: PendingNoteOperation]
    var pendingNoteIds: Set<String>
    var noteLastSeenUpdatedAtServer: [String: Date]
    var noteEditBases: [String: Date]
    var conflictCandidateNoteIds: Set<String>

    init(
        pendingOperations: [String: PendingNoteOperation] = [:],
        pendingDeletes: [String: PendingNoteOperation] = [:],
        pendingNoteIds: Set<String> = [],
        noteLastSeenUpdatedAtServer: [String: Date] = [:],
        noteEditBases: [String: Date] = [:],
        conflictCandidateNoteIds: Set<String> = []
    ) {
        self.pendingOperations = pendingOperations
        self.pendingDeletes = pendingDeletes
        self.pendingNoteIds = pendingNoteIds
        self.noteLastSeenUpdatedAtServer = noteLastSeenUpdatedAtServer
        self.noteEditBases = noteEditBases
        self.conflictCandidateNoteIds = conflictCandidateNoteIds
    }
}

nonisolated struct SyncStateInput: Sendable {
    let isConnected: Bool
    let hasPendingWrites: Bool
    let hasServerSnapshotSinceReconnect: Bool
    let lastWriteError: SyncError?
}

nonisolated enum SyncStateReducer {
    static func reduce(_ input: SyncStateInput) -> SyncState {
        if !input.isConnected {
            return .offline
        }
        if input.lastWriteError != nil {
            return .error
        }
        if input.hasPendingWrites {
            return .syncing
        }
        if input.hasServerSnapshotSinceReconnect {
            return .onlineFresh
        }
        return .onlineCache
    }
}

nonisolated struct ShiftNotesListenerEvent: Sendable {
    let notes: [ShiftNote]
    let hasPendingWrites: Bool
    let isFromCache: Bool
    let documentIDs: Set<String>
}

nonisolated struct ShiftNoteDocumentEvent: Sendable {
    let noteId: String
    let note: ShiftNote?
    let exists: Bool
    let hasPendingWrites: Bool
    let isFromCache: Bool
}
