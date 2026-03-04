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

    @Test func validateAudioFileReturnsMissingForUnknownPath() async {
        let service = TranscriptionService()
        let missingURL = URL(fileURLWithPath: "/tmp/shiftvoice-tests/does-not-exist-\(UUID().uuidString).m4a")

        let result = await service.validateAudioFile(at: missingURL)

        switch result {
        case .missing:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateAudioFileReturnsEmptyForZeroByteFile() async throws {
        let service = TranscriptionService()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("shiftvoice-empty-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        FileManager.default.createFile(atPath: fileURL.path, contents: Data())

        let result = await service.validateAudioFile(at: fileURL)

        switch result {
        case .empty:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateAudioFileReturnsCorruptForUnreadablePayload() async throws {
        let service = TranscriptionService()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("shiftvoice-corrupt-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let randomData = Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
        try randomData.write(to: fileURL)

        let result = await service.validateAudioFile(at: fileURL)

        switch result {
        case .corrupt:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateAudioFileRejectsUnsupportedExtension() async throws {
        let service = TranscriptionService()
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent("shiftvoice-unsupported-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data([0x00, 0x01, 0x02, 0x03]).write(to: fileURL)
        let result = await service.validateAudioFile(at: fileURL)

        switch result {
        case .unsupportedFormat:
            #expect(Bool(true))
        default:
            #expect(Bool(false))
        }
    }

    @Test func validateBeforeTranscriptionSurfacesUserMessageForMissingAudio() async {
        let service = TranscriptionService()
        let missingURL = URL(fileURLWithPath: "/tmp/shiftvoice-tests/missing-\(UUID().uuidString).m4a")

        let isValid = await service.validateBeforeTranscription(at: missingURL)

        #expect(isValid == false)
        #expect(service.failureReason == .noAudioFile)
        #expect(service.errorMessage == TranscriptionFailureReason.noAudioFile.userMessage)
    }

    @Test func whisperPromptBuilderIncludesIndustryTermsAndDeduplicatesCaseInsensitively() {
        let terms = ["Barbacks", "expo", "barbacks", "86'd", "  walk-in cooler  "]

        let prompt = WhisperPromptBuilder.build(from: terms)

        #expect(prompt.contains("Shift handoff transcription vocabulary:"))
        #expect(prompt.contains("Barbacks"))
        #expect(prompt.contains("expo"))
        #expect(prompt.contains("86'd"))
        #expect(prompt.contains("walk-in cooler"))
        #expect(prompt.components(separatedBy: "Barbacks").count == 2)
    }

    @Test func whisperPromptBuilderLimitsPromptLengthForWhisperWindow() {
        let terms = (1...200).map { "term\($0)" }

        let prompt = WhisperPromptBuilder.build(from: terms)

        #expect(prompt.count <= 700)
    }
}
