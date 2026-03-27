import Foundation
import Testing
@testable import ShiftVoice

@MainActor
struct ConflictResolutionTests {
    @Test func keptServerResolution_marksResolved_andDoesNotIssueWrite() async {
        let store = makeStore(name: "KeptServer")
        let writer = FakeConflictResolutionWriter()
        let coordinator = ConflictResolutionCoordinator(store: store, writer: writer)
        let conflict = makeConflict(fieldName: "status", local: "Resolved", server: "Open")
        store.addConflict(conflict)

        await coordinator.resolve(conflictId: conflict.id, resolution: .keptServer, userId: "user-1")

        let resolved = store.allConflicts.first(where: { $0.id == conflict.id })
        #expect(resolved?.state == .resolved)
        #expect(resolved?.resolutionAction == .keptServer)
        #expect(resolved?.resolvedAt != nil)
        #expect(resolved?.resolvedBy == "user-1")
        #expect(writer.calls.isEmpty)
        #expect(coordinator.noteConflictState[conflict.noteId] == "none")
    }

    @Test func appliedLocalResolution_issuesWrite_andMarksResolved() async {
        let store = makeStore(name: "AppliedLocal")
        let writer = FakeConflictResolutionWriter()
        let coordinator = ConflictResolutionCoordinator(store: store, writer: writer)
        let conflict = makeConflict(fieldName: "priority", local: "Immediate", server: "FYI")
        store.addConflict(conflict)

        await coordinator.resolve(conflictId: conflict.id, resolution: .appliedLocal, userId: "user-2")

        let resolved = store.allConflicts.first(where: { $0.id == conflict.id })
        #expect(resolved?.state == .resolved)
        #expect(resolved?.resolutionAction == .appliedLocal)
        #expect(resolved?.resolvedAt != nil)
        #expect(resolved?.resolvedBy == "user-2")
        #expect(writer.calls.count == 1)
        #expect(writer.calls.first?.noteId == conflict.noteId)
        #expect(writer.calls.first?.fieldName == conflict.fieldName)
        #expect(writer.calls.first?.value == conflict.localIntendedValue)
        #expect(coordinator.noteConflictState[conflict.noteId] == "none")
    }

    @Test func dismissedResolution_marksDismissed() async {
        let store = makeStore(name: "Dismissed")
        let writer = FakeConflictResolutionWriter()
        let coordinator = ConflictResolutionCoordinator(store: store, writer: writer)
        let conflict = makeConflict(fieldName: "assigneeId", local: "u_local", server: "u_server")
        store.addConflict(conflict)

        await coordinator.resolve(conflictId: conflict.id, resolution: .dismissed, userId: "user-3")

        let dismissed = store.allConflicts.first(where: { $0.id == conflict.id })
        #expect(dismissed?.state == .dismissed)
        #expect(dismissed?.resolutionAction == .dismissed)
        #expect(dismissed?.resolvedAt != nil)
        #expect(dismissed?.resolvedBy == "user-3")
        #expect(writer.calls.isEmpty)
        #expect(coordinator.noteConflictState[conflict.noteId] == "none")
    }

    private func makeStore(name: String) -> ConflictStore {
        let store = ConflictStore(baseDirectoryURL: testDirectory(name: name))
        store.configure(userId: "test-user")
        return store
    }

    private func makeConflict(fieldName: String, local: String, server: String) -> ConflictItem {
        ConflictItem(
            noteId: "note-1",
            fieldName: fieldName,
            localIntendedValue: local,
            serverCurrentValue: server,
            serverUpdatedBy: "server-user",
            serverUpdatedAt: Date(),
            localEditStartedAt: Date().addingTimeInterval(-120)
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

@MainActor
private final class ConflictResolutionCoordinator {
    private let store: ConflictStore
    private let writer: ConflictResolutionWriting
    private(set) var noteConflictState: [String: String] = [:]

    init(store: ConflictStore, writer: ConflictResolutionWriting) {
        self.store = store
        self.writer = writer
    }

    func resolve(conflictId: String, resolution: ConflictResolution, userId: String) async {
        guard let conflict = store.activeConflicts.first(where: { $0.id == conflictId }) else { return }

        switch resolution {
        case .keptServer:
            store.resolveConflict(id: conflict.id, resolution: .keptServer, userId: userId)
        case .appliedLocal:
            await writer.applyLocalUpdate(noteId: conflict.noteId, fieldName: conflict.fieldName, value: conflict.localIntendedValue)
            store.resolveConflict(id: conflict.id, resolution: .appliedLocal, userId: userId)
        case .dismissed:
            store.dismissConflict(id: conflict.id, userId: userId)
        }

        if store.activeConflicts.filter({ $0.noteId == conflict.noteId }).isEmpty {
            noteConflictState[conflict.noteId] = "none"
        }
    }
}

@MainActor
private protocol ConflictResolutionWriting {
    func applyLocalUpdate(noteId: String, fieldName: String, value: String) async
}

@MainActor
private final class FakeConflictResolutionWriter: ConflictResolutionWriting {
    nonisolated struct Call: Sendable {
        let noteId: String
        let fieldName: String
        let value: String
    }

    private(set) var calls: [Call] = []

    func applyLocalUpdate(noteId: String, fieldName: String, value: String) async {
        calls.append(Call(noteId: noteId, fieldName: fieldName, value: value))
    }
}
