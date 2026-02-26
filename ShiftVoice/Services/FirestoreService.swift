import Foundation
import FirebaseFirestore

@MainActor
final class FirestoreService {
    static let shared = FirestoreService()
    private lazy var db = Firestore.firestore()
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

    func saveShiftNote(
        _ note: ShiftNote,
        orgId: String,
        completion: ((Result<Void, SyncError>) -> Void)? = nil
    ) throws {
        try db.collection("organizations").document(orgId).collection("shiftNotes").document(note.id).setData(from: note) { error in
            if let error {
                completion?(.failure(SyncError(error: error)))
                return
            }
            completion?(.success(()))
        }
    }

    func deleteShiftNote(
        _ noteId: String,
        orgId: String,
        completion: ((Result<Void, SyncError>) -> Void)? = nil
    ) {
        db.collection("organizations").document(orgId).collection("shiftNotes").document(noteId).delete { error in
            if let error {
                completion?(.failure(SyncError(error: error)))
                return
            }
            completion?(.success(()))
        }
    }

    func startShiftNotesListener(
        _ orgId: String,
        onEvent: @escaping (ShiftNotesListenerEvent) -> Void,
        onDocumentEvent: @escaping (ShiftNoteDocumentEvent) -> Void,
        onError: @escaping (SyncError) -> Void
    ) {
        let options = SnapshotListenOptions()
            .withIncludeMetadataChanges(true)
        let collection = db.collection("organizations").document(orgId).collection("shiftNotes")

        let queryReg = collection
            .order(by: "createdAt", descending: true)
            .limit(to: 300)
            .addSnapshotListener(options: options) { snapshot, error in
                if let error {
                    onError(SyncError(error: error))
                    return
                }
                guard let snapshot else {
                    onEvent(
                        ShiftNotesListenerEvent(
                            notes: [],
                            hasPendingWrites: false,
                            isFromCache: true,
                            documentIDs: []
                        )
                    )
                    return
                }
                let items = snapshot.documents.compactMap { document -> ShiftNote? in
                    guard var note = try? document.data(as: ShiftNote.self) else { return nil }
                    note.isSynced = !document.metadata.hasPendingWrites
                    note.isDirty = document.metadata.hasPendingWrites
                    return note
                }
                onEvent(
                    ShiftNotesListenerEvent(
                        notes: items,
                        hasPendingWrites: snapshot.metadata.hasPendingWrites,
                        isFromCache: snapshot.metadata.isFromCache,
                        documentIDs: Set(snapshot.documents.map(\.documentID))
                    )
                )
            }

        let documentReg = collection
            .addSnapshotListener(options: options) { snapshot, error in
                if let error {
                    onError(SyncError(error: error))
                    return
                }
                guard let snapshot else { return }
                for change in snapshot.documentChanges {
                    let noteId = change.document.documentID
                    let note = try? change.document.data(as: ShiftNote.self)
                    onDocumentEvent(
                        ShiftNoteDocumentEvent(
                            noteId: noteId,
                            note: note,
                            exists: change.type != .removed,
                            hasPendingWrites: change.document.metadata.hasPendingWrites,
                            isFromCache: snapshot.metadata.isFromCache
                        )
                    )
                }
            }

        activeListeners.append(queryReg)
        activeListeners.append(documentReg)
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
