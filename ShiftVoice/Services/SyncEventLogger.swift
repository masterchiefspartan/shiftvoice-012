import Foundation

nonisolated enum SyncEventKind: String, Codable, Sendable {
    case stateTransition
    case pendingOpAdded
    case pendingOpConfirmed
    case pendingOpFailed
    case conflictDetected
    case conflictResolved
    case reconciliationStarted
    case reconciliationCompleted
    case listenerRestarted
    case writeFailure
}

nonisolated struct SyncEventRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let timestamp: Date
    let kind: SyncEventKind
    let message: String

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        kind: SyncEventKind,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.message = message
    }
}

@MainActor
final class SyncEventLogger {
    static let shared = SyncEventLogger()

    private let maxInMemoryEvents: Int
    private let maxPersistedEvents: Int
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    private var events: [SyncEventRecord] = []

    init(
        maxInMemoryEvents: Int = 200,
        maxPersistedEvents: Int = 50,
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.maxInMemoryEvents = maxInMemoryEvents
        self.maxPersistedEvents = maxPersistedEvents
        self.fileManager = fileManager

        let baseDirectory = baseDirectoryURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.storageURL = baseDirectory.appendingPathComponent("sync_events.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        loadPersistedEvents()
    }

    var eventCount: Int {
        events.count
    }

    var writeFailureEventCount: Int {
        events.filter { $0.kind == .writeFailure || $0.kind == .pendingOpFailed }.count
    }

    func recentEvents(limit: Int) -> [SyncEventRecord] {
        Array(events.suffix(limit).reversed())
    }

    func recentWriteFailures(limit: Int) -> [SyncEventRecord] {
        let failures = events.filter { $0.kind == .writeFailure || $0.kind == .pendingOpFailed }
        return Array(failures.suffix(limit).reversed())
    }

    func stateTransition(from: SyncState, to: SyncState) {
        log(.stateTransition, "Sync state \(from.rawValue) → \(to.rawValue)")
    }

    func pendingOpAdded(docId: String, type: PendingOpType) {
        log(.pendingOpAdded, "Pending \(type.rawValue) added for \(docId)")
    }

    func pendingOpConfirmed(docId: String, type: PendingOpType, durationSeconds: TimeInterval) {
        log(.pendingOpConfirmed, "Pending \(type.rawValue) confirmed for \(docId) in \(formatDuration(durationSeconds))")
    }

    func pendingOpFailed(docId: String, type: PendingOpType, error: String) {
        log(.pendingOpFailed, "Pending \(type.rawValue) failed for \(docId): \(error)")
    }

    func conflictDetected(noteId: String, field: String) {
        log(.conflictDetected, "Conflict detected for \(noteId) field \(field)")
    }

    func conflictResolved(noteId: String, field: String, resolution: ConflictResolution) {
        log(.conflictResolved, "Conflict resolved for \(noteId) field \(field) using \(resolution.rawValue)")
    }

    func reconciliationStarted(pendingCount: Int) {
        log(.reconciliationStarted, "Reconciliation started with \(pendingCount) pending ops")
    }

    func reconciliationCompleted(confirmedCount: Int, remainingCount: Int, durationSeconds: TimeInterval) {
        log(
            .reconciliationCompleted,
            "Reconciliation completed: confirmed \(confirmedCount), remaining \(remainingCount), duration \(formatDuration(durationSeconds))"
        )
    }

    func listenerRestarted(reason: String) {
        log(.listenerRestarted, "Listeners restarted: \(reason)")
    }

    func writeFailure(category: WriteErrorCategory, operation: WriteOperationType, docPath: String?) {
        let path = docPath ?? "multiple_documents"
        log(.writeFailure, "Write failure \(category.rawValue) during \(operation.rawValue) at \(path)")
    }

    private func log(_ kind: SyncEventKind, _ message: String) {
        events.append(SyncEventRecord(kind: kind, message: message))
        if events.count > maxInMemoryEvents {
            events.removeFirst(events.count - maxInMemoryEvents)
        }
        persistRecentEvents()
    }

    private func loadPersistedEvents() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            events = []
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            events = try decoder.decode([SyncEventRecord].self, from: data)
        } catch {
            events = []
        }
    }

    private func persistRecentEvents() {
        let recent = Array(events.suffix(maxPersistedEvents))
        let targetURL = storageURL
        let encoder = self.encoder

        Task.detached(priority: .utility) {
            do {
                let data = try encoder.encode(recent)
                try data.write(to: targetURL, options: .atomic)
            } catch {
                return
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.2fs", duration)
    }
}
