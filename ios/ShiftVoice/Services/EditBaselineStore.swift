import Foundation

@MainActor
final class EditBaselineStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseDirectoryURL: URL

    private var currentUserId: String?
    private var storageURL: URL {
        guard let currentUserId else {
            return baseDirectoryURL.appendingPathComponent("edit_baselines.json")
        }
        let userDirectory = baseDirectoryURL.appendingPathComponent("users/\(currentUserId)", isDirectory: true)
        if !fileManager.fileExists(atPath: userDirectory.path) {
            try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        }
        return userDirectory.appendingPathComponent("edit_baselines.json")
    }

    private(set) var baselines: [String: EditBaseline] = [:]

    init(
        fileManager: FileManager = .default,
        baseDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.baseDirectoryURL = baseDirectoryURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
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
        baselines = [:]
    }

    func setBaseline(for noteId: String, fields: [String: String], serverTimestamp: Date) {
        baselines[noteId] = EditBaseline(
            noteId: noteId,
            fields: fields,
            updatedAtServer: serverTimestamp
        )
        save()
    }

    func getBaseline(for noteId: String) -> EditBaseline? {
        baselines[noteId]
    }

    func clearBaseline(for noteId: String) {
        baselines.removeValue(forKey: noteId)
        save()
    }

    func clearAllBaselines() {
        baselines = [:]
        save()
    }

    private func load() {
        let url = storageURL
        guard fileManager.fileExists(atPath: url.path) else {
            baselines = [:]
            return
        }

        do {
            let data = try Data(contentsOf: url)
            baselines = try decoder.decode([String: EditBaseline].self, from: data)
        } catch {
            baselines = [:]
        }
    }

    private func save() {
        let url = storageURL
        do {
            let data = try encoder.encode(baselines)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}
