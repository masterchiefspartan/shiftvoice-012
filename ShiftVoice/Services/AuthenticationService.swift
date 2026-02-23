import Foundation
import GoogleSignIn
import Security

nonisolated enum AuthMethod: String, Codable, Sendable {
    case google
    case email
}

@Observable
final class AuthenticationService {
    var currentUser: GIDGoogleUser?
    var isSignedIn: Bool = false
    var isLoading: Bool = true
    var errorMessage: String?

    private var authMethod: AuthMethod?
    private var emailUserProfile: UserProfile?

    var userName: String {
        if authMethod == .email {
            return emailUserProfile?.name ?? ""
        }
        return currentUser?.profile?.name ?? ""
    }

    var userEmail: String {
        if authMethod == .email {
            return emailUserProfile?.email ?? ""
        }
        return currentUser?.profile?.email ?? ""
    }

    var userInitials: String {
        let name = userName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var userProfileImageURL: URL? {
        if authMethod == .email { return nil }
        return currentUser?.profile?.imageURL(withDimension: 120)
    }

    init() {
        configureGoogleSignIn()
        restorePreviousSignIn()
    }

    private func configureGoogleSignIn() {
        let clientID = Config.GOOGLE_CLIENT_ID
        guard !clientID.isEmpty else { return }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }

    func restorePreviousSignIn() {
        isLoading = true

        if let savedMethod = UserDefaults.standard.string(forKey: "sv_auth_method"),
           let method = AuthMethod(rawValue: savedMethod) {
            authMethod = method

            if method == .email {
                if let profile = PersistenceService.shared.loadUserProfile() {
                    emailUserProfile = profile
                    isSignedIn = true
                }
                isLoading = false
                return
            }
        }

        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let user {
                        self.currentUser = user
                        self.isSignedIn = true
                        self.authMethod = .google
                        self.persistUserProfile()
                    }
                    self.isLoading = false
                }
            }
        } else {
            isLoading = false
        }
    }

    // MARK: - Google Sign In

    func signInWithGoogle() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to find root view controller"
            return
        }

        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        self.errorMessage = error.localizedDescription
                    }
                    return
                }
                guard let user = result?.user else { return }
                self.currentUser = user
                self.isSignedIn = true
                self.authMethod = .google
                UserDefaults.standard.set(AuthMethod.google.rawValue, forKey: "sv_auth_method")
                self.persistUserProfile()
            }
        }
    }

    // MARK: - Email/Password Sign In

    func signUpWithEmail(name: String, email: String, password: String) {
        errorMessage = nil

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please enter your name"
            return
        }
        guard isValidEmail(email) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        if KeychainHelper.loadPassword(for: trimmedEmail) != nil {
            errorMessage = "An account with this email already exists. Please sign in."
            return
        }

        guard KeychainHelper.savePassword(password, for: trimmedEmail) else {
            errorMessage = "Unable to create account. Please try again."
            return
        }

        let initials: String = {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }()

        let profile = UserProfile(
            id: UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            email: trimmedEmail,
            initials: initials,
            profileImageURL: nil
        )

        PersistenceService.shared.saveUserProfile(profile)
        emailUserProfile = profile
        isSignedIn = true
        authMethod = .email
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
    }

    func signInWithEmail(email: String, password: String) {
        errorMessage = nil

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard !password.isEmpty else {
            errorMessage = "Please enter your password"
            return
        }

        guard let storedPassword = KeychainHelper.loadPassword(for: trimmedEmail) else {
            errorMessage = "No account found with this email. Please sign up."
            return
        }

        guard storedPassword == password else {
            errorMessage = "Incorrect password. Please try again."
            return
        }

        if let profile = PersistenceService.shared.loadUserProfile(), profile.email == trimmedEmail {
            emailUserProfile = profile
        } else {
            let profile = UserProfile(
                id: UUID().uuidString,
                name: trimmedEmail.components(separatedBy: "@").first ?? "User",
                email: trimmedEmail,
                initials: String(trimmedEmail.prefix(2)).uppercased(),
                profileImageURL: nil
            )
            PersistenceService.shared.saveUserProfile(profile)
            emailUserProfile = profile
        }

        isSignedIn = true
        authMethod = .email
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
    }

    // MARK: - Sign Out

    func signOut() {
        if authMethod == .google {
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
        }
        emailUserProfile = nil
        isSignedIn = false
        authMethod = nil
        UserDefaults.standard.removeObject(forKey: "sv_auth_method")
    }

    // MARK: - Helpers

    private func persistUserProfile() {
        guard let user = currentUser, let profile = user.profile else { return }
        let initials: String = {
            let parts = profile.name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(profile.name.prefix(2)).uppercased()
        }()
        let userProfile = UserProfile(
            id: user.userID ?? UUID().uuidString,
            name: profile.name,
            email: profile.email,
            initials: initials,
            profileImageURL: profile.imageURL(withDimension: 120)?.absoluteString
        )
        PersistenceService.shared.saveUserProfile(userProfile)
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: regex) != nil
    }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
    static func savePassword(_ password: String, for email: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: email,
            kSecAttrService as String: "com.shiftvoice.auth"
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadPassword(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: email,
            kSecAttrService as String: "com.shiftvoice.auth",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
