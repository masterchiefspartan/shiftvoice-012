import Foundation

nonisolated struct UserProfile: Codable, Sendable {
    let id: String
    let name: String
    let email: String
    let initials: String
    let profileImageURL: String?
}

nonisolated struct AppData: Codable, Sendable {
    var organization: Organization
    var locations: [Location]
    var teamMembers: [TeamMember]
    var shiftNotes: [ShiftNote]
    var recurringIssues: [RecurringIssue]
    var userProfile: UserProfile?
    var selectedLocationId: String?
    var businessType: String?
    var selectedCategoryTemplateIds: [String]?
    var selectedShiftTemplateIds: [String]?
}

final class PersistenceService {
    static let shared = PersistenceService()

    private let fileManager = FileManager.default

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - User-Scoped Directory

    private func userDirectory(for userId: String) -> URL {
        let dir = documentsURL.appendingPathComponent("users/\(userId)", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func appDataURL(for userId: String) -> URL {
        userDirectory(for: userId).appendingPathComponent("app_data.json")
    }

    private func userProfileURL(for userId: String) -> URL {
        userDirectory(for: userId).appendingPathComponent("profile.json")
    }

    private var emailMappingURL: URL {
        documentsURL.appendingPathComponent("email_user_map.json")
    }

    // MARK: - Legacy paths (for migration)

    private var legacyAppDataURL: URL {
        documentsURL.appendingPathComponent("shiftvoice_data.json")
    }

    private var legacyProfileURL: URL {
        documentsURL.appendingPathComponent("user_profile.json")
    }

    // MARK: - User-Scoped App Data

    func save(_ data: AppData, for userId: String) {
        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: appDataURL(for: userId), options: .atomic)
        } catch {
            print("PersistenceService save error: \(error)")
        }
    }

    func load(for userId: String) -> AppData? {
        let url = appDataURL(for: userId)
        guard fileManager.fileExists(atPath: url.path) else {
            return migrateLegacyData(to: userId)
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AppData.self, from: data)
        } catch {
            print("PersistenceService load error: \(error)")
            return nil
        }
    }

    // MARK: - User Profile (scoped)

    func saveUserProfile(_ profile: UserProfile, for userId: String) {
        do {
            let data = try encoder.encode(profile)
            try data.write(to: userProfileURL(for: userId), options: .atomic)
        } catch {
            print("PersistenceService saveUserProfile error: \(error)")
        }
    }

    func loadUserProfile(for userId: String) -> UserProfile? {
        let url = userProfileURL(for: userId)
        guard fileManager.fileExists(atPath: url.path) else {
            return migrateLegacyProfile(to: userId)
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            print("PersistenceService loadUserProfile error: \(error)")
            return nil
        }
    }

    // MARK: - Email → UserId Mapping

    func saveEmailToUserIdMapping(email: String, userId: String) {
        var map = loadEmailMap()
        map[email.lowercased()] = userId
        do {
            let data = try encoder.encode(map)
            try data.write(to: emailMappingURL, options: .atomic)
        } catch {
            print("PersistenceService saveEmailMapping error: \(error)")
        }
    }

    func loadUserIdForEmail(_ email: String) -> String? {
        let map = loadEmailMap()
        return map[email.lowercased()]
    }

    private func loadEmailMap() -> [String: String] {
        guard fileManager.fileExists(atPath: emailMappingURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: emailMappingURL)
            return try decoder.decode([String: String].self, from: data)
        } catch {
            return [:]
        }
    }

    // MARK: - Sync Snapshot (for rollback)

    private func snapshotURL(for userId: String) -> URL {
        userDirectory(for: userId).appendingPathComponent("sync_snapshot.json")
    }

    func saveSnapshot(_ data: AppData, for userId: String) {
        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: snapshotURL(for: userId), options: .atomic)
        } catch {
            print("PersistenceService saveSnapshot error: \(error)")
        }
    }

    func loadSnapshot(for userId: String) -> AppData? {
        let url = snapshotURL(for: userId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(AppData.self, from: data)
        } catch {
            return nil
        }
    }

    func clearSnapshot(for userId: String) {
        try? fileManager.removeItem(at: snapshotURL(for: userId))
    }

    // MARK: - Clear User Data

    func clearUserData(for userId: String) {
        let dir = userDirectory(for: userId)
        try? fileManager.removeItem(at: dir)
    }

    func clearAll() {
        try? fileManager.removeItem(at: legacyAppDataURL)
        try? fileManager.removeItem(at: legacyProfileURL)
        let usersDir = documentsURL.appendingPathComponent("users", isDirectory: true)
        try? fileManager.removeItem(at: usersDir)
        try? fileManager.removeItem(at: emailMappingURL)
    }

    func hasPersistedData(for userId: String) -> Bool {
        fileManager.fileExists(atPath: appDataURL(for: userId).path)
    }

    // MARK: - Legacy Migration

    private func migrateLegacyData(to userId: String) -> AppData? {
        guard fileManager.fileExists(atPath: legacyAppDataURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: legacyAppDataURL)
            let appData = try decoder.decode(AppData.self, from: data)
            save(appData, for: userId)
            try? fileManager.removeItem(at: legacyAppDataURL)
            return appData
        } catch {
            return nil
        }
    }

    private func migrateLegacyProfile(to userId: String) -> UserProfile? {
        guard fileManager.fileExists(atPath: legacyProfileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: legacyProfileURL)
            let profile = try decoder.decode(UserProfile.self, from: data)
            saveUserProfile(profile, for: userId)
            try? fileManager.removeItem(at: legacyProfileURL)
            return profile
        } catch {
            return nil
        }
    }

    // MARK: - Backward Compat (deprecated, used during migration)

    func saveUserProfile(_ profile: UserProfile) {
        saveUserProfile(profile, for: profile.id)
    }

    func loadUserProfile() -> UserProfile? {
        guard fileManager.fileExists(atPath: legacyProfileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: legacyProfileURL)
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            return nil
        }
    }
}
