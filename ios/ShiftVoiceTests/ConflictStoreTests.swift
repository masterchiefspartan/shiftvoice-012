import Foundation
import Testing
@testable import ShiftVoice

@MainActor
struct ConflictStoreTests {
    @Test func addConflictAppearsInActiveConflicts() {
        let store = makeStore(name: "AddActive")
        let conflict = makeConflict(noteId: "note-1", fieldName: "status", local: "Resolved", server: "Open")

        store.addConflict(conflict)

        #expect(store.activeConflicts.count == 1)
        #expect(store.activeConflicts.first?.id == conflict.id)
    }

    @Test func resolveConflictMovesOutOfActiveConflicts() {
        let store = makeStore(name: "ResolveActive")
        let conflict = makeConflict(noteId: "note-1", fieldName: "status", local: "Resolved", server: "Open")
        store.addConflict(conflict)

        store.resolveConflict(id: conflict.id, resolution: .keptServer, userId: "resolver")

        #expect(store.activeConflicts.isEmpty)
        let resolved = store.allConflicts.first(where: { $0.id == conflict.id })
        #expect(resolved?.state == .resolved)
        #expect(resolved?.resolutionAction == .keptServer)
        #expect(resolved?.resolvedAt != nil)
        #expect(resolved?.resolvedBy == "resolver")
    }

    @Test func dismissConflictMovesOutOfActiveConflicts() {
        let store = makeStore(name: "DismissActive")
        let conflict = makeConflict(noteId: "note-2", fieldName: "assigneeId", local: "u_local", server: "u_server")
        store.addConflict(conflict)

        store.dismissConflict(id: conflict.id, userId: "dismisser")

        #expect(store.activeConflicts.isEmpty)
        let dismissed = store.allConflicts.first(where: { $0.id == conflict.id })
        #expect(dismissed?.state == .dismissed)
        #expect(dismissed?.resolutionAction == .dismissed)
        #expect(dismissed?.resolvedAt != nil)
        #expect(dismissed?.resolvedBy == "dismisser")
    }

    @Test func persistAndReload_conflictsSurvive() {
        let directory = testDirectory(name: "PersistReload")
        let store = ConflictStore(baseDirectoryURL: directory)
        store.configure(userId: "user-1")

        let conflict = makeConflict(noteId: "note-3", fieldName: "priority", local: "Immediate", server: "FYI")
        store.addConflict(conflict)

        let reloaded = ConflictStore(baseDirectoryURL: directory)
        reloaded.configure(userId: "user-1")

        #expect(reloaded.allConflicts.count == 1)
        #expect(reloaded.allConflicts.first?.id == conflict.id)
        #expect(reloaded.activeConflicts.count == 1)
    }

    @Test func conflictsForNoteFiltersCorrectly() {
        let store = makeStore(name: "FilterByNote")
        store.addConflict(makeConflict(noteId: "note-a", fieldName: "status", local: "Resolved", server: "Open"))
        store.addConflict(makeConflict(noteId: "note-a", fieldName: "assigneeId", local: "u1", server: "u2"))
        store.addConflict(makeConflict(noteId: "note-b", fieldName: "priority", local: "Immediate", server: "FYI"))

        let noteAConflicts = store.conflictsForNote("note-a")
        let noteBConflicts = store.conflictsForNote("note-b")

        #expect(noteAConflicts.count == 2)
        #expect(noteBConflicts.count == 1)
        #expect(noteBConflicts.first?.fieldName == "priority")
    }

    @Test func duplicateConflictForSameFieldAndNote_updatesExistingWithoutDuplication() {
        let store = makeStore(name: "DuplicateUpdate")

        let initial = makeConflict(
            noteId: "note-dup",
            fieldName: "status",
            local: "Resolved",
            server: "Open",
            detectedAt: Date(timeIntervalSince1970: 100)
        )
        store.addConflict(initial)

        let refreshed = ConflictItem(
            noteId: "note-dup",
            fieldName: "status",
            localIntendedValue: "In Progress",
            serverCurrentValue: "Open",
            serverUpdatedBy: "server-user-2",
            serverUpdatedAt: Date(timeIntervalSince1970: 200),
            localEditStartedAt: Date(timeIntervalSince1970: 90),
            detectedAt: Date(timeIntervalSince1970: 210)
        )
        store.addConflict(refreshed)

        #expect(store.allConflicts.count == 1)
        let stored = store.allConflicts[0]
        #expect(stored.id == initial.id)
        #expect(stored.localIntendedValue == "In Progress")
        #expect(stored.serverUpdatedBy == "server-user-2")
        #expect(stored.serverUpdatedAt == Date(timeIntervalSince1970: 200))
    }

    private func makeStore(name: String) -> ConflictStore {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: name))
        store.configure(userId: "test-user")
        return store
    }

    private func makeConflict(
        noteId: String,
        fieldName: String,
        local: String,
        server: String,
        detectedAt: Date = Date()
    ) -> ConflictItem {
        ConflictItem(
            noteId: noteId,
            fieldName: fieldName,
            localIntendedValue: local,
            serverCurrentValue: server,
            serverUpdatedBy: "server-user",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date().addingTimeInterval(-60),
            detectedAt: detectedAt
        )
    }

    private func testDirectory(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShiftVoiceTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
