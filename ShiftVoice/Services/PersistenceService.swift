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

    private var appDataURL: URL {
        documentsURL.appendingPathComponent("shiftvoice_data.json")
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

    func save(_ data: AppData) {
        do {
            let jsonData = try encoder.encode(data)
            try jsonData.write(to: appDataURL, options: .atomic)
        } catch {
            print("PersistenceService save error: \(error)")
        }
    }

    func load() -> AppData? {
        guard fileManager.fileExists(atPath: appDataURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: appDataURL)
            return try decoder.decode(AppData.self, from: data)
        } catch {
            print("PersistenceService load error: \(error)")
            return nil
        }
    }

    func saveUserProfile(_ profile: UserProfile) {
        let url = documentsURL.appendingPathComponent("user_profile.json")
        do {
            let data = try encoder.encode(profile)
            try data.write(to: url, options: .atomic)
        } catch {
            print("PersistenceService saveUserProfile error: \(error)")
        }
    }

    func loadUserProfile() -> UserProfile? {
        let url = documentsURL.appendingPathComponent("user_profile.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(UserProfile.self, from: data)
        } catch {
            print("PersistenceService loadUserProfile error: \(error)")
            return nil
        }
    }

    func clearAll() {
        try? fileManager.removeItem(at: appDataURL)
        let profileURL = documentsURL.appendingPathComponent("user_profile.json")
        try? fileManager.removeItem(at: profileURL)
    }

    var hasPersistedData: Bool {
        fileManager.fileExists(atPath: appDataURL.path)
    }
}
