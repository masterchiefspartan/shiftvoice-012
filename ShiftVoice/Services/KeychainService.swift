import Foundation
import Security

nonisolated enum KeychainService: Sendable {
    private static let serviceName = "com.shiftvoice.auth"
    private static let sessionTokenKey = "sv_session_token"
    private static let sessionUserIdKey = "sv_session_user_id"
    private static let sessionExpiryKey = "sv_session_expiry"

    static func savePassword(_ password: String, for email: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pwd_\(email)",
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func loadPassword(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pwd_\(email)",
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pwd_\(email)",
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func updatePassword(_ newPassword: String, for email: String) -> Bool {
        deletePassword(for: email)
        return savePassword(newPassword, for: email)
    }

    // MARK: - Session Token

    static func saveSessionToken(_ token: String, userId: String, expiry: Date) -> Bool {
        let tokenSaved = saveSecureValue(token, forKey: sessionTokenKey)
        let userIdSaved = saveSecureValue(userId, forKey: sessionUserIdKey)
        let expirySaved = saveSecureValue(String(expiry.timeIntervalSince1970), forKey: sessionExpiryKey)
        return tokenSaved && userIdSaved && expirySaved
    }

    static func loadSessionToken() -> (token: String, userId: String, expiry: Date)? {
        guard let token = loadSecureValue(forKey: sessionTokenKey),
              let userId = loadSecureValue(forKey: sessionUserIdKey),
              let expiryString = loadSecureValue(forKey: sessionExpiryKey),
              let expiryInterval = TimeInterval(expiryString) else { return nil }
        let expiry = Date(timeIntervalSince1970: expiryInterval)
        guard expiry > Date() else {
            clearSessionToken()
            return nil
        }
        return (token, userId, expiry)
    }

    static func clearSessionToken() {
        deleteSecureValue(forKey: sessionTokenKey)
        deleteSecureValue(forKey: sessionUserIdKey)
        deleteSecureValue(forKey: sessionExpiryKey)
    }

    static func refreshSessionToken() -> String? {
        guard let existing = loadSessionToken() else { return nil }
        let newToken = generateToken()
        let newExpiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
        if saveSessionToken(newToken, userId: existing.userId, expiry: newExpiry) {
            return newToken
        }
        return nil
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Generic Secure Storage

    private static func saveSecureValue(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private static func loadSecureValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteSecureValue(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clearAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }
}
