import Foundation
import Testing
@testable import ShiftVoice

struct EditBaselineStoreTests {
    @Test @MainActor func setGetAndClearBaseline() {
        let directory = testDirectory(name: "EditBaselineStoreSetGetClear")
        let store = EditBaselineStore(baseDirectoryURL: directory)
        store.configure(userId: "user-1")

        let serverDate = Date(timeIntervalSince1970: 1_700_100_000)
        let fields: [String: String] = [
            "status": "Open",
            "assigneeId": "u1",
            "priority": "Immediate"
        ]

        store.setBaseline(for: "note-1", fields: fields, serverTimestamp: serverDate)
        let baseline = store.getBaseline(for: "note-1")

        #expect(baseline?.noteId == "note-1")
        #expect(baseline?.fields == fields)
        #expect(baseline?.updatedAtServer == serverDate)

        store.clearBaseline(for: "note-1")
        #expect(store.getBaseline(for: "note-1") == nil)
    }

    @Test @MainActor func persistsBaselinesAcrossReload() {
        let directory = testDirectory(name: "EditBaselineStorePersistence")
        let store = EditBaselineStore(baseDirectoryURL: directory)
        store.configure(userId: "user-2")

        let serverDate = Date(timeIntervalSince1970: 1_700_200_000)
        store.setBaseline(
            for: "note-2",
            fields: ["status": "Open", "assigneeId": "", "priority": "FYI"],
            serverTimestamp: serverDate
        )

        let reloaded = EditBaselineStore(baseDirectoryURL: directory)
        reloaded.configure(userId: "user-2")

        #expect(reloaded.getBaseline(for: "note-2")?.updatedAtServer == serverDate)
        #expect(reloaded.getBaseline(for: "note-2")?.fields["status"] == "Open")
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
