import Foundation

nonisolated struct FeatureFlagsSnapshot: Codable, Sendable {
    let conflictUIEnabled: Bool?
    let diagnosticsEnabled: Bool?
    let syncBannersEnabled: Bool?
    let structuringStrictValidationEnabled: Bool?
    let structuringGroundingChecksEnabled: Bool?
    let structuringPromptV2Enabled: Bool?
}

@Observable
@MainActor
final class FeatureFlagService {
    static let shared = FeatureFlagService()

    private let userDefaults: UserDefaults
    private let session: URLSession

    private let conflictUIOverrideKey: String = "feature_flags.override.conflict_ui_enabled"
    private let diagnosticsOverrideKey: String = "feature_flags.override.diagnostics_enabled"
    private let syncBannersOverrideKey: String = "feature_flags.override.sync_banners_enabled"
    private let remoteCacheDataKey: String = "feature_flags.remote.cache"
    private let remoteURLOverrideKey: String = "feature_flags.remote.url_override"
    private let structuringStrictValidationOverrideKey: String = "feature_flags.override.structuring_strict_validation_enabled"
    private let structuringGroundingChecksOverrideKey: String = "feature_flags.override.structuring_grounding_checks_enabled"
    private let structuringPromptV2OverrideKey: String = "feature_flags.override.structuring_prompt_v2_enabled"

    private var remoteSnapshot: FeatureFlagsSnapshot?

    var conflictUIEnabled: Bool {
        resolvedFlag(localOverrideForKey: conflictUIOverrideKey, remoteValue: remoteSnapshot?.conflictUIEnabled, defaultValue: true)
    }

    var diagnosticsEnabled: Bool {
        resolvedFlag(localOverrideForKey: diagnosticsOverrideKey, remoteValue: remoteSnapshot?.diagnosticsEnabled, defaultValue: true)
    }

    var syncBannersEnabled: Bool {
        resolvedFlag(localOverrideForKey: syncBannersOverrideKey, remoteValue: remoteSnapshot?.syncBannersEnabled, defaultValue: true)
    }

    var structuringStrictValidationEnabled: Bool {
        resolvedFlag(localOverrideForKey: structuringStrictValidationOverrideKey, remoteValue: remoteSnapshot?.structuringStrictValidationEnabled, defaultValue: false)
    }

    var structuringGroundingChecksEnabled: Bool {
        resolvedFlag(localOverrideForKey: structuringGroundingChecksOverrideKey, remoteValue: remoteSnapshot?.structuringGroundingChecksEnabled, defaultValue: false)
    }

    var structuringPromptV2Enabled: Bool {
        resolvedFlag(localOverrideForKey: structuringPromptV2OverrideKey, remoteValue: remoteSnapshot?.structuringPromptV2Enabled, defaultValue: false)
    }

    var conflictUIOverride: Bool? {
        get { overrideValue(forKey: conflictUIOverrideKey) }
        set { setOverride(newValue, forKey: conflictUIOverrideKey) }
    }

    var diagnosticsOverride: Bool? {
        get { overrideValue(forKey: diagnosticsOverrideKey) }
        set { setOverride(newValue, forKey: diagnosticsOverrideKey) }
    }

    var syncBannersOverride: Bool? {
        get { overrideValue(forKey: syncBannersOverrideKey) }
        set { setOverride(newValue, forKey: syncBannersOverrideKey) }
    }

    var structuringStrictValidationOverride: Bool? {
        get { overrideValue(forKey: structuringStrictValidationOverrideKey) }
        set { setOverride(newValue, forKey: structuringStrictValidationOverrideKey) }
    }

    var structuringGroundingChecksOverride: Bool? {
        get { overrideValue(forKey: structuringGroundingChecksOverrideKey) }
        set { setOverride(newValue, forKey: structuringGroundingChecksOverrideKey) }
    }

    var structuringPromptV2Override: Bool? {
        get { overrideValue(forKey: structuringPromptV2OverrideKey) }
        set { setOverride(newValue, forKey: structuringPromptV2OverrideKey) }
    }

    init(
        userDefaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) {
        self.userDefaults = userDefaults
        self.session = session
        loadCachedRemoteSnapshot()
    }

    func refreshRemoteFlags() async {
        guard let url = remoteConfigURL() else { return }
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return }
            let snapshot = try JSONDecoder().decode(FeatureFlagsSnapshot.self, from: data)
            remoteSnapshot = snapshot
            userDefaults.set(data, forKey: remoteCacheDataKey)
        } catch {
            return
        }
    }

    func setRemoteConfigURLOverride(_ urlString: String?) {
        let trimmed = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: remoteURLOverrideKey)
        } else {
            userDefaults.set(trimmed, forKey: remoteURLOverrideKey)
        }
    }

    func remoteConfigURLOverride() -> String {
        userDefaults.string(forKey: remoteURLOverrideKey) ?? ""
    }

    func clearAllOverrides() {
        userDefaults.removeObject(forKey: conflictUIOverrideKey)
        userDefaults.removeObject(forKey: diagnosticsOverrideKey)
        userDefaults.removeObject(forKey: syncBannersOverrideKey)
        userDefaults.removeObject(forKey: structuringStrictValidationOverrideKey)
        userDefaults.removeObject(forKey: structuringGroundingChecksOverrideKey)
        userDefaults.removeObject(forKey: structuringPromptV2OverrideKey)
    }

    private func resolvedFlag(localOverrideForKey key: String, remoteValue: Bool?, defaultValue: Bool) -> Bool {
        if let localOverride = overrideValue(forKey: key) {
            return localOverride
        }
        if let remoteValue {
            return remoteValue
        }
        return defaultValue
    }

    private func overrideValue(forKey key: String) -> Bool? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.bool(forKey: key)
    }

    private func setOverride(_ value: Bool?, forKey key: String) {
        if let value {
            userDefaults.set(value, forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func loadCachedRemoteSnapshot() {
        guard let data = userDefaults.data(forKey: remoteCacheDataKey) else { return }
        remoteSnapshot = try? JSONDecoder().decode(FeatureFlagsSnapshot.self, from: data)
    }

    private func remoteConfigURL() -> URL? {
        let override = userDefaults.string(forKey: remoteURLOverrideKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty, let url = URL(string: override) {
            return url
        }
        let base = Config.EXPO_PUBLIC_RORK_API_BASE_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        return URL(string: "\(base)/feature-flags")
    }
}
