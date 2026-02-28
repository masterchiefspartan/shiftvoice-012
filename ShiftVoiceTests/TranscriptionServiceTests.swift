import Testing
import Foundation
@testable import ShiftVoice

struct TranscriptionServiceTests {
    @Test func emptyRecordingFailureReasonsAreClassified() {
        #expect(TranscriptionFailureReason.emptyAudioFile.isEmptyRecording)
        #expect(TranscriptionFailureReason.noResult.isEmptyRecording)
        #expect(TranscriptionFailureReason.noAudioFile.isEmptyRecording == false)
        #expect(TranscriptionFailureReason.corruptAudioFile.isEmptyRecording == false)
        #expect(TranscriptionFailureReason.cloudFailed.isEmptyRecording == false)
    }

    @Test func validateAudioFileReturnsMissingForUnknownPath() {
        let service = TranscriptionService()
        let missingURL = URL(fileURLWithPath: "/tmp/shiftvoice-tests/does-not-exist-\(UUID().uuidString).m4a")

        let result = service.validateAudioFile(at: missingURL)

        switch result {
        case .missing:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateAudioFileReturnsEmptyForZeroByteFile() throws {
        let service = TranscriptionService()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("shiftvoice-empty-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let result = service.validateAudioFile(at: fileURL)

        switch result {
        case .empty:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateAudioFileReturnsCorruptForUnreadablePayload() throws {
        let service = TranscriptionService()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("shiftvoice-corrupt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let randomData = Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
        try randomData.write(to: fileURL)

        let result = service.validateAudioFile(at: fileURL)

        switch result {
        case .corrupt:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }
}
