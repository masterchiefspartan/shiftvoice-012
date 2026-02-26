import Foundation
import Testing
@testable import ShiftVoice

struct ConflictStoreTests {
    @Test func conflictItemCreationAndStateTransitions() {
        let serverUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let localEditStartedAt = Date(timeIntervalSince1970: 1_699_999_000)
        var conflict = ConflictItem(
            noteId: "note-1",
            fieldName: "status",
            localIntendedValue: "Resolved",
            serverCurrentValue: "Open",
            serverUpdatedBy: "server-user",
            serverUpdatedAt: serverUpdatedAt,
            localEditStartedAt: localEditStartedAt
        )

        #expect(conflict.state == .detected)
        #expect(conflict.resolvedAt == nil)
        #expect(conflict.resolvedBy == nil)
        #expect(conflict.resolutionAction == nil)

        conflict.state = .resolved
        conflict.resolutionAction = .appliedLocal
        conflict.resolvedBy = "local-user"
        conflict.resolvedAt = Date(timeIntervalSince1970: 1_700_000_500)

        #expect(conflict.state == .resolved)
        #expect(conflict.resolutionAction == .appliedLocal)
        #expect(conflict.resolvedBy == "local-user")
        #expect(conflict.resolvedAt != nil)
    }

    @Test @MainActor func conflictStorePersistsAndReloadsFromDisk() {
        let directory = testDirectory(name: "ConflictStorePersistence")
        let store = ConflictStore(baseDirectoryURL: directory)
        store.configure(userId: "user-a")

        let conflict = ConflictItem(
            noteId: "note-1",
            fieldName: "assigneeId",
            localIntendedValue: "u_local",
            serverCurrentValue: "u_server",
            serverUpdatedBy: "u_server",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        store.addConflict(conflict)

        let reloaded = ConflictStore(baseDirectoryURL: directory)
        reloaded.configure(userId: "user-a")

        #expect(reloaded.allConflicts.count == 1)
        #expect(reloaded.allConflicts.first?.id == conflict.id)
        #expect(reloaded.activeConflicts.count == 1)
    }

    @Test @MainActor func resolveAndDismissMutationsUpdateState() {
        let directory = testDirectory(name: "ConflictStoreMutations")
        let store = ConflictStore(baseDirectoryURL: directory)
        store.configure(userId: "user-b")

        let first = ConflictItem(
            noteId: "note-1",
            fieldName: "priority",
            localIntendedValue: "High",
            serverCurrentValue: "Low",
            serverUpdatedBy: "u2",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        let second = ConflictItem(
            noteId: "note-2",
            fieldName: "status",
            localIntendedValue: "Resolved",
            serverCurrentValue: "In Progress",
            serverUpdatedBy: "u3",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        store.addConflict(first)
        store.addConflict(second)

        store.resolveConflict(id: first.id, resolution: .keptServer, userId: "resolver")
        store.dismissConflict(id: second.id, userId: "dismisser")

        let resolved = store.allConflicts.first { $0.id == first.id }
        let dismissed = store.allConflicts.first { $0.id == second.id }

        #expect(resolved?.state == .resolved)
        #expect(resolved?.resolutionAction == .keptServer)
        #expect(resolved?.resolvedBy == "resolver")
        #expect(resolved?.resolvedAt != nil)

        #expect(dismissed?.state == .dismissed)
        #expect(dismissed?.resolutionAction == .dismissed)
        #expect(dismissed?.resolvedBy == "dismisser")
        #expect(dismissed?.resolvedAt != nil)

        #expect(store.activeConflicts.isEmpty)
    }

    @Test @MainActor func conflictsForNoteFiltersByNoteId() {
        let directory = testDirectory(name: "ConflictStoreNoteFilter")
        let store = ConflictStore(baseDirectoryURL: directory)
        store.configure(userId: "user-c")

        let noteAStatus = ConflictItem(
            noteId: "note-a",
            fieldName: "status",
            localIntendedValue: "Resolved",
            serverCurrentValue: "Open",
            serverUpdatedBy: "u1",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        let noteAAssignee = ConflictItem(
            noteId: "note-a",
            fieldName: "assigneeId",
            localIntendedValue: "u_local",
            serverCurrentValue: "u_server",
            serverUpdatedBy: "u2",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        let noteB = ConflictItem(
            noteId: "note-b",
            fieldName: "priority",
            localIntendedValue: "High",
            serverCurrentValue: "Low",
            serverUpdatedBy: "u3",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date()
        )

        store.addConflict(noteAStatus)
        store.addConflict(noteAAssignee)
        store.addConflict(noteB)

        let noteAConflicts = store.conflictsForNote("note-a")
        let noteBConflicts = store.conflictsForNote("note-b")

        #expect(noteAConflicts.count == 2)
        #expect(noteBConflicts.count == 1)
        #expect(noteBConflicts.first?.fieldName == "priority")
    }

    @MainActor
    private func testDirectory(name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShiftVoiceTests")
            .appendingPathComponent(name)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
