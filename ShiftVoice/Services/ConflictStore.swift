import Foundation

@MainActor
final class ConflictStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseDirectoryURL: URL

    private var currentUserId: String?
    private var storageURL: URL {
        guard let currentUserId else {
            return baseDirectoryURL.appendingPathComponent("conflicts.json")
        }
        let userDirectory = baseDirectoryURL.appendingPathComponent("users/\(currentUserId)", isDirectory: true)
        if !fileManager.fileExists(atPath: userDirectory.path) {
            try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        }
        return userDirectory.appendingPathComponent("conflicts.json")
    }

    private(set) var allConflicts: [ConflictItem] = []

    var activeConflicts: [ConflictItem] {
        allConflicts.filter { $0.state == .detected }
    }

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        load()
    }

    func configure(userId: String) {
        currentUserId = userId
        load()
    }

    func clearCurrentUserContext() {
        currentUserId = nil
        allConflicts = []
    }

    func addConflict(_ conflict: ConflictItem) {
        if let existingIndex = allConflicts.firstIndex(where: {
            $0.noteId == conflict.noteId &&
            $0.fieldName == conflict.fieldName &&
            $0.state == .detected
        }) {
            let existing = allConflicts[existingIndex]
            allConflicts[existingIndex] = ConflictItem(
                id: existing.id,
                noteId: conflict.noteId,
                fieldName: conflict.fieldName,
                localIntendedValue: conflict.localIntendedValue,
                serverCurrentValue: conflict.serverCurrentValue,
                serverUpdatedBy: conflict.serverUpdatedBy,
                serverUpdatedAt: conflict.serverUpdatedAt,
                localEditStartedAt: conflict.localEditStartedAt,
                detectedAt: conflict.detectedAt,
                state: .detected
            )
        } else {
            allConflicts.append(conflict)
        }
        save()
    }

    func resolveConflict(id: String, resolution: ConflictResolution, userId: String) {
        guard let index = allConflicts.firstIndex(where: { $0.id == id }) else { return }
        allConflicts[index].state = .resolved
        allConflicts[index].resolvedAt = Date()
        allConflicts[index].resolvedBy = userId
        allConflicts[index].resolutionAction = resolution
        save()
    }

    func dismissConflict(id: String, userId: String) {
        guard let index = allConflicts.firstIndex(where: { $0.id == id }) else { return }
        allConflicts[index].state = .dismissed
        allConflicts[index].resolvedAt = Date()
        allConflicts[index].resolvedBy = userId
        allConflicts[index].resolutionAction = .dismissed
        save()
    }

    func conflictsForNote(_ noteId: String) -> [ConflictItem] {
        allConflicts.filter { $0.noteId == noteId }
    }

    func clearAllConflicts() {
        allConflicts = []
        save()
    }

    private func load() {
        let url = storageURL
        guard fileManager.fileExists(atPath: url.path) else {
            allConflicts = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            allConflicts = try decoder.decode([ConflictItem].self, from: data)
        } catch {
            allConflicts = []
        }
    }

    private func save() {
        let url = storageURL
        do {
            let data = try encoder.encode(allConflicts)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
