import Foundation
import FirebaseFirestore

final class FirestoreService {
    static let shared = FirestoreService()
    private let db = Firestore.firestore()
    private var activeListeners: [ListenerRegistration] = []

    // MARK: - User Profile

    func saveUserProfile(_ profile: UserProfile) {
        var data: [String: Any] = [
            "name": profile.name,
            "email": profile.email,
            "initials": profile.initials
        ]
        if let url = profile.profileImageURL {
            data["profileImageURL"] = url
        }
        db.collection("users").document(profile.id).setData(data, merge: true)
    }

    func fetchUserData(_ userId: String) async throws -> (profile: UserProfile?, organizationId: String?, selectedLocationId: String?) {
        let doc = try await db.collection("users").document(userId).getDocument()
        guard doc.exists, let data = doc.data() else { return (nil, nil, nil) }
        let profile = UserProfile(
            id: userId,
            name: data["name"] as? String ?? "",
            email: data["email"] as? String ?? "",
            initials: data["initials"] as? String ?? "",
            profileImageURL: data["profileImageURL"] as? String
        )
        return (profile, data["organizationId"] as? String, data["selectedLocationId"] as? String)
    }

    func updateUserPreferences(userId: String, organizationId: String? = nil, selectedLocationId: String? = nil) {
        var data: [String: Any] = [:]
        if let orgId = organizationId { data["organizationId"] = orgId }
        if let locId = selectedLocationId { data["selectedLocationId"] = locId }
        guard !data.isEmpty else { return }
        db.collection("users").document(userId).setData(data, merge: true)
    }

    // MARK: - Organization

    func saveOrganization(_ org: Organization) throws {
        try db.collection("organizations").document(org.id).setData(from: org)
    }

    func startOrganizationListener(_ orgId: String, onChange: @escaping (Organization?) -> Void) {
        let reg = db.collection("organizations").document(orgId).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else { onChange(nil); return }
            onChange(try? snapshot.data(as: Organization.self))
        }
        activeListeners.append(reg)
    }

    // MARK: - Locations

    func saveLocation(_ location: Location, orgId: String) throws {
        try db.collection("organizations").document(orgId).collection("locations").document(location.id).setData(from: location)
    }

    func deleteLocation(_ locationId: String, orgId: String) {
        db.collection("organizations").document(orgId).collection("locations").document(locationId).delete()
    }

    func startLocationsListener(_ orgId: String, onChange: @escaping ([Location]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("locations").addSnapshotListener { snapshot, _ in
            let items = snapshot?.documents.compactMap { try? $0.data(as: Location.self) } ?? []
            onChange(items)
        }
        activeListeners.append(reg)
    }

    // MARK: - Team Members

    func saveTeamMember(_ member: TeamMember, orgId: String) throws {
        try db.collection("organizations").document(orgId).collection("teamMembers").document(member.id).setData(from: member)
    }

    func deleteTeamMember(_ memberId: String, orgId: String) {
        db.collection("organizations").document(orgId).collection("teamMembers").document(memberId).delete()
    }

    func startTeamMembersListener(_ orgId: String, onChange: @escaping ([TeamMember]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("teamMembers").addSnapshotListener { snapshot, _ in
            let items = snapshot?.documents.compactMap { try? $0.data(as: TeamMember.self) } ?? []
            onChange(items)
        }
        activeListeners.append(reg)
    }

    // MARK: - Shift Notes

    func saveShiftNote(_ note: ShiftNote, orgId: String) throws {
        try db.collection("organizations").document(orgId).collection("shiftNotes").document(note.id).setData(from: note)
    }

    func deleteShiftNote(_ noteId: String, orgId: String) {
        db.collection("organizations").document(orgId).collection("shiftNotes").document(noteId).delete()
    }

    func startShiftNotesListener(_ orgId: String, onChange: @escaping ([ShiftNote]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("shiftNotes")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let items = snapshot?.documents.compactMap { try? $0.data(as: ShiftNote.self) } ?? []
                onChange(items)
            }
        activeListeners.append(reg)
    }

    // MARK: - Recurring Issues

    func saveRecurringIssue(_ issue: RecurringIssue, orgId: String) throws {
        try db.collection("organizations").document(orgId).collection("recurringIssues").document(issue.id).setData(from: issue)
    }

    func deleteRecurringIssue(_ issueId: String, orgId: String) {
        db.collection("organizations").document(orgId).collection("recurringIssues").document(issueId).delete()
    }

    func startRecurringIssuesListener(_ orgId: String, onChange: @escaping ([RecurringIssue]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("recurringIssues").addSnapshotListener { snapshot, _ in
            let items = snapshot?.documents.compactMap { try? $0.data(as: RecurringIssue.self) } ?? []
            onChange(items)
        }
        activeListeners.append(reg)
    }

    // MARK: - Batch Operations

    func deleteLocationNotes(locationId: String, orgId: String) async throws {
        let snapshot = try await db.collection("organizations").document(orgId).collection("shiftNotes")
            .whereField("locationId", isEqualTo: locationId).getDocuments()
        let batch = db.batch()
        for doc in snapshot.documents {
            batch.deleteDocument(doc.reference)
        }
        try await batch.commit()
    }

    func deleteUserData(_ userId: String) {
        db.collection("users").document(userId).delete()
    }

    // MARK: - Listener Management

    func stopAllListeners() {
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }
}
