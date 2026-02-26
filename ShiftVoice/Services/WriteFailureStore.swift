import Foundation

@MainActor
final class WriteFailureStore {
    private let persistence: WriteFailurePersisting
    private let dedupeInterval: TimeInterval

    private(set) var lastWriteError: WriteFailure?
    var triggerReauthFlag: Bool = false

    init(
        persistence: WriteFailurePersisting = UserDefaultsWriteFailurePersistence(),
        dedupeInterval: TimeInterval = 30
    ) {
        self.persistence = persistence
        self.dedupeInterval = dedupeInterval
        self.lastWriteError = persistence.loadLastWriteFailure()
        self.triggerReauthFlag = lastWriteError?.category == .unauthenticated
    }

    func setFailure(_ failure: WriteFailure) {
        if shouldDedupe(with: failure) {
            return
        }

        lastWriteError = failure
        triggerReauthFlag = failure.category == .unauthenticated
        persistence.saveLastWriteFailure(failure)
    }

    func clearFailure() {
        lastWriteError = nil
        triggerReauthFlag = false
        persistence.clearLastWriteFailure()
    }

    var shouldPromptReauth: Bool {
        lastWriteError?.category == .unauthenticated
    }

    var shouldRecommendRetry: Bool {
        guard let category = lastWriteError?.category else { return false }
        return category == .unavailable || category == .resourceExhausted
    }

    private func shouldDedupe(with incoming: WriteFailure) -> Bool {
        guard let existing = lastWriteError else { return false }
        let sameSignature = existing.category == incoming.category
            && existing.operation == incoming.operation
            && existing.documentPath == incoming.documentPath
        guard sameSignature else { return false }
        return incoming.timestamp.timeIntervalSince(existing.timestamp) <= dedupeInterval
    }
}

protocol WriteFailurePersisting {
    func saveLastWriteFailure(_ failure: WriteFailure)
    func loadLastWriteFailure() -> WriteFailure?
    func clearLastWriteFailure()
}

nonisolated final class UserDefaultsWriteFailurePersistence: WriteFailurePersisting {
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "shiftvoice.last_write_failure"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func saveLastWriteFailure(_ failure: WriteFailure) {
        guard let data = try? encoder.encode(failure) else { return }
        userDefaults.set(data, forKey: storageKey)
    }

    func loadLastWriteFailure() -> WriteFailure? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try? decoder.decode(WriteFailure.self, from: data)
    }

    func clearLastWriteFailure() {
        userDefaults.removeObject(forKey: storageKey)
    }
}
