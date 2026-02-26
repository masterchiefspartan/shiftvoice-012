import Foundation
import FirebaseFirestore

@MainActor
final class FirestoreService: PendingOpsDocumentFetching {
    static let shared = FirestoreService()
    private lazy var db = Firestore.firestore()
    private lazy var writeFailureStore = WriteFailureStore()
    private lazy var writeClient: FirestoreWriteClient = DefaultFirestoreWriteClient(
        db: db,
        failureStore: writeFailureStore,
        restartListenersHook: { [weak self] in
            self?.stopAllListeners()
        }
    )
    private var activeListeners: [ListenerRegistration] = []

    var lastWriteFailure: WriteFailure? {
        writeFailureStore.lastWriteError
    }

    var shouldPromptReauth: Bool {
        writeFailureStore.shouldPromptReauth
    }

    var shouldRecommendRetry: Bool {
        writeFailureStore.shouldRecommendRetry
    }

    var triggerReauthFlag: Bool {
        writeFailureStore.triggerReauthFlag
    }

    func clearWriteFailure() {
        writeFailureStore.clearFailure()
    }

    func retryLastSafeWrite() async {
        guard let client = writeClient as? DefaultFirestoreWriteClient else { return }
        await client.retryLastSafeWrite()
    }

    func restartListenersFromWriteRecovery() {
        guard let client = writeClient as? DefaultFirestoreWriteClient else { return }
        client.restartListeners()
    }

    // MARK: - User Profile

    func saveUserProfile(_ profile: UserProfile) async throws {
        var data: [String: Any] = [
            "name": profile.name,
            "email": profile.email,
            "initials": profile.initials
        ]
        if let url = profile.profileImageURL {
            data["profileImageURL"] = url
        }
        try await writeClient.setData(
            data,
            to: db.collection("users").document(profile.id),
            merge: true
        )
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

    func updateUserPreferences(userId: String, organizationId: String? = nil, selectedLocationId: String? = nil) async throws {
        var data: [String: Any] = [:]
        if let orgId = organizationId { data["organizationId"] = orgId }
        if let locId = selectedLocationId { data["selectedLocationId"] = locId }
        guard !data.isEmpty else { return }
        try await writeClient.setData(
            data,
            to: db.collection("users").document(userId),
            merge: true
        )
    }

    // MARK: - Organization

    func saveOrganization(_ org: Organization) async throws {
        try await writeClient.setData(
            encodeEncodable(org),
            to: db.collection("organizations").document(org.id),
            merge: false
        )
    }

    func startOrganizationListener(_ orgId: String, onChange: @escaping (Organization?) -> Void) {
        let reg = db.collection("organizations").document(orgId).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else { onChange(nil); return }
            onChange(try? snapshot.data(as: Organization.self))
        }
        activeListeners.append(reg)
    }

    // MARK: - Locations

    func saveLocation(_ location: Location, orgId: String) async throws {
        try await writeClient.setData(
            encodeEncodable(location),
            to: db.collection("organizations").document(orgId).collection("locations").document(location.id),
            merge: false
        )
    }

    func deleteLocation(_ locationId: String, orgId: String) async throws {
        try await writeClient.delete(
            db.collection("organizations").document(orgId).collection("locations").document(locationId)
        )
    }

    func startLocationsListener(_ orgId: String, onChange: @escaping ([Location]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("locations").addSnapshotListener { snapshot, _ in
            let items = snapshot?.documents.compactMap { try? $0.data(as: Location.self) } ?? []
            onChange(items)
        }
        activeListeners.append(reg)
    }

    // MARK: - Team Members

    func saveTeamMember(_ member: TeamMember, orgId: String) async throws {
        try await writeClient.setData(
            encodeEncodable(member),
            to: db.collection("organizations").document(orgId).collection("teamMembers").document(member.id),
            merge: false
        )
    }

    func deleteTeamMember(_ memberId: String, orgId: String) async throws {
        try await writeClient.delete(
            db.collection("organizations").document(orgId).collection("teamMembers").document(memberId)
        )
    }

    func startTeamMembersListener(_ orgId: String, onChange: @escaping ([TeamMember]) -> Void) {
        let reg = db.collection("organizations").document(orgId).collection("teamMembers").addSnapshotListener { snapshot, _ in
            let items = snapshot?.documents.compactMap { try? $0.data(as: TeamMember.self) } ?? []
            onChange(items)
        }
        activeListeners.append(reg)
    }

    // MARK: - Shift Notes

    @discardableResult
    func saveShiftNote(
        _ note: ShiftNote,
        orgId: String,
        mutationId: String,
        updatedAtClient: Date,
        updatedByUserId: String,
        completion: ((Result<Void, SyncError>) -> Void)? = nil
    ) -> String {
        let reference = db.collection("organizations").document(orgId).collection("shiftNotes").document(note.id)
        var mutableNote = note
        mutableNote.lastClientMutationId = mutationId
        mutableNote.updatedAtClient = updatedAtClient

        let encoded = encodeShiftNote(mutableNote)
        var payload = encoded
        payload["lastClientMutationId"] = mutationId
        payload["updatedAtClient"] = Timestamp(date: updatedAtClient)
        payload["updatedAtServer"] = FieldValue.serverTimestamp()
        payload["updatedByUserId"] = updatedByUserId

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.writeClient.setData(payload, to: reference, merge: true)
                completion?(.success(()))
            } catch {
                completion?(.failure(SyncError(error: error)))
            }
        }

        return mutationId
    }

    @discardableResult
    func deleteShiftNote(
        _ noteId: String,
        orgId: String,
        mutationId: String,
        completion: ((Result<Void, SyncError>) -> Void)? = nil
    ) -> String {
        let docRef = db.collection("organizations").document(orgId).collection("shiftNotes").document(noteId)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.writeClient.delete(docRef)
                completion?(.success(()))
            } catch {
                completion?(.failure(SyncError(error: error)))
            }
        }
        return mutationId
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

    func fetchShiftNoteServerState(noteId: String, orgId: String) async throws -> ShiftNoteServerState {
        let snapshot = try await db.collection("organizations")
            .document(orgId)
            .collection("shiftNotes")
            .document(noteId)
            .getDocument(source: .server)

        guard snapshot.exists else {
            return ShiftNoteServerState(noteId: noteId, exists: false, note: nil, lastClientMutationId: nil)
        }

        let note = try? snapshot.data(as: ShiftNote.self)
        let lastClientMutationId = snapshot.data()?["lastClientMutationId"] as? String
        return ShiftNoteServerState(noteId: noteId, exists: true, note: note, lastClientMutationId: lastClientMutationId)
    }

    // MARK: - Recurring Issues

    func saveRecurringIssue(_ issue: RecurringIssue, orgId: String) async throws {
        try await writeClient.setData(
            encodeEncodable(issue),
            to: db.collection("organizations").document(orgId).collection("recurringIssues").document(issue.id),
            merge: false
        )
    }

    func deleteRecurringIssue(_ issueId: String, orgId: String) async throws {
        try await writeClient.delete(
            db.collection("organizations").document(orgId).collection("recurringIssues").document(issueId)
        )
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
        try await writeClient.commitBatch { batch in
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
        }
    }

    func deleteUserData(_ userId: String) async throws {
        try await writeClient.delete(db.collection("users").document(userId))
    }

    // MARK: - Listener Management

    func stopAllListeners() {
        activeListeners.forEach { $0.remove() }
        activeListeners.removeAll()
    }

    private func encodeShiftNote(_ note: ShiftNote) -> [String: Any] {
        encodeEncodable(note)
    }

    private func encodeEncodable<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}

nonisolated struct ShiftNoteServerState: Sendable {
    let noteId: String
    let exists: Bool
    let note: ShiftNote?
    let lastClientMutationId: String?
}
