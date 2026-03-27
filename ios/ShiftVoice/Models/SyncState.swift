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

nonisolated enum PendingOpType: String, Codable, Sendable {
    case upsert
    case delete
}

nonisolated struct PendingOp: Codable, Equatable, Sendable {
    let docId: String
    let type: PendingOpType
    let mutationId: String
    let createdAtClient: Date
    let intendedFields: [String: String]?
    var lastAttemptAt: Date?
    var attemptCount: Int

    init(
        docId: String,
        type: PendingOpType,
        mutationId: String,
        createdAtClient: Date = Date(),
        intendedFields: [String: String]? = nil,
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0
    ) {
        self.docId = docId
        self.type = type
        self.mutationId = mutationId
        self.createdAtClient = createdAtClient
        self.intendedFields = intendedFields
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
    }
}

nonisolated struct PendingOpsSnapshot: Codable, Equatable, Sendable {
    var pendingOps: [String: PendingOp]

    init(pendingOps: [String: PendingOp] = [:]) {
        self.pendingOps = pendingOps
    }
}

nonisolated struct PendingOpReconcileMismatch: Equatable, Sendable {
    let docId: String
    let expectedMutationId: String
    let serverMutationId: String?
}

nonisolated struct PendingOpReconcileResult: Sendable {
    let remainingOps: [PendingOp]
    let clearedDocIds: Set<String>
    let mismatchDocIds: Set<String>
    let mismatches: [PendingOpReconcileMismatch]
    let encounteredError: SyncError?
}

nonisolated struct PendingOpsSummary: Sendable {
    let pendingDocIds: Set<String>
    let pendingDeleteCount: Int
}

protocol PendingOpsPersisting: AnyObject {
    func savePendingOpsSnapshot(_ snapshot: PendingOpsSnapshot, for userId: String)
    func loadPendingOpsSnapshot(for userId: String) -> PendingOpsSnapshot?
    func clearPendingOpsSnapshot(for userId: String)
}

protocol PendingOpsStoreProtocol: AnyObject {
    var pendingOps: [String: PendingOp] { get }
    func configure(userId: String)
    func clearCurrentUser()
    func all() -> [PendingOp]
    func summary() -> PendingOpsSummary
    func upsert(_ operation: PendingOp)
    func remove(docId: String)
    func markAttempt(docId: String, at date: Date)
}

protocol PendingOpsDocumentFetching: AnyObject {
    func fetchShiftNoteServerState(noteId: String, orgId: String) async throws -> ShiftNoteServerState
}

protocol PendingOpReconciling: AnyObject {
    func reconcile(orgId: String) async -> PendingOpReconcileResult
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

nonisolated enum SnapshotFreshness: String, Codable, Sendable {
    case none
    case cache
    case server
}

nonisolated struct SyncStateInput: Sendable {
    let isConnected: Bool
    let snapshotFreshness: SnapshotFreshness
    let hasPendingWrites: Bool
    let hasServerSnapshotSinceReconnect: Bool
    let lastWriteError: SyncError?
    let pendingNoteCount: Int
    let pendingDeleteCount: Int

    var hasAnyPendingOperations: Bool {
        hasPendingWrites || pendingNoteCount > 0 || pendingDeleteCount > 0
    }

    init(
        isConnected: Bool,
        snapshotFreshness: SnapshotFreshness = .none,
        hasPendingWrites: Bool,
        hasServerSnapshotSinceReconnect: Bool,
        lastWriteError: SyncError?,
        pendingNoteCount: Int = 0,
        pendingDeleteCount: Int = 0
    ) {
        self.isConnected = isConnected
        self.snapshotFreshness = snapshotFreshness
        self.hasPendingWrites = hasPendingWrites
        self.hasServerSnapshotSinceReconnect = hasServerSnapshotSinceReconnect
        self.lastWriteError = lastWriteError
        self.pendingNoteCount = pendingNoteCount
        self.pendingDeleteCount = pendingDeleteCount
    }
}

nonisolated enum SyncStateReducer {
    static func reduce(_ input: SyncStateInput) -> SyncState {
        guard input.isConnected else {
            return .offline
        }

        if input.lastWriteError != nil {
            return .error
        }

        if input.hasAnyPendingOperations {
            return .syncing
        }

        if input.hasServerSnapshotSinceReconnect || input.snapshotFreshness == .server {
            return .onlineFresh
        }

        return .onlineCache
    }

    static func bannerCopy(for state: SyncState) -> String {
        switch state {
        case .offline:
            return "You're offline. Changes will sync when connection is restored."
        case .onlineCache:
            return "Connected. Waiting for fresh server data."
        case .syncing:
            return "Syncing changes…"
        case .onlineFresh:
            return "All changes synced."
        case .error:
            return "Sync failed. Resolve the error to continue syncing."
        }
    }

    static func canClaimAllChangesSynced(for input: SyncStateInput) -> Bool {
        reduce(input) == .onlineFresh
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
