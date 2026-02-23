import Foundation
import GoogleSignIn
import Security

nonisolated enum AuthMethod: String, Codable, Sendable {
    case google
    case email
}

nonisolated struct AuthSession: Codable, Sendable {
    let userId: String
    let token: String
    let authMethod: AuthMethod
    let createdAt: Date
    let expiresAt: Date

    var isExpired: Bool { expiresAt < Date() }
    var needsRefresh: Bool { expiresAt.timeIntervalSinceNow < 7 * 24 * 60 * 60 }
}

@Observable
final class AuthenticationService {
    var currentUser: GIDGoogleUser?
    var isSignedIn: Bool = false
    var isLoading: Bool = true
    var errorMessage: String?
    var showPasswordReset: Bool = false
    var passwordResetSuccess: Bool = false

    private var authMethod: AuthMethod?
    private var emailUserProfile: UserProfile?
    private(set) var currentUserId: String?

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

    // MARK: - Session Restore

    func restorePreviousSignIn() {
        isLoading = true

        if let session = KeychainService.loadSessionToken() {
            let savedMethod = UserDefaults.standard.string(forKey: "sv_auth_method")
            let method = savedMethod.flatMap { AuthMethod(rawValue: $0) }

            if method == .email {
                if let profile = PersistenceService.shared.loadUserProfile(for: session.userId) {
                    emailUserProfile = profile
                    currentUserId = session.userId
                    authMethod = .email
                    isSignedIn = true
                    refreshSessionIfNeeded()
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
                        let userId = user.userID ?? UUID().uuidString
                        self.currentUserId = userId
                        self.createSession(userId: userId, method: .google)
                        self.persistGoogleUserProfile()
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
                let userId = user.userID ?? UUID().uuidString
                self.currentUserId = userId
                self.isSignedIn = true
                self.authMethod = .google
                UserDefaults.standard.set(AuthMethod.google.rawValue, forKey: "sv_auth_method")
                self.createSession(userId: userId, method: .google)
                self.persistGoogleUserProfile()
            }
        }
    }

    // MARK: - Email/Password Sign Up

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
        guard isStrongPassword(password) else {
            errorMessage = "Password must be at least 8 characters with a letter and number"
            return
        }

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        if KeychainService.loadPassword(for: trimmedEmail) != nil {
            errorMessage = "An account with this email already exists. Please sign in."
            return
        }

        guard KeychainService.savePassword(password, for: trimmedEmail) else {
            errorMessage = "Unable to create account. Please try again."
            return
        }

        let userId = UUID().uuidString
        let initials: String = {
            let parts = name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }()

        let profile = UserProfile(
            id: userId,
            name: name.trimmingCharacters(in: .whitespaces),
            email: trimmedEmail,
            initials: initials,
            profileImageURL: nil
        )

        PersistenceService.shared.saveUserProfile(profile, for: userId)
        PersistenceService.shared.saveEmailToUserIdMapping(email: trimmedEmail, userId: userId)
        emailUserProfile = profile
        currentUserId = userId
        isSignedIn = true
        authMethod = .email
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
        createSession(userId: userId, method: .email)
    }

    // MARK: - Email/Password Sign In

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

        guard let storedPassword = KeychainService.loadPassword(for: trimmedEmail) else {
            errorMessage = "No account found with this email. Please sign up."
            return
        }

        guard storedPassword == password else {
            errorMessage = "Incorrect password. Please try again."
            return
        }

        let userId: String
        if let mappedId = PersistenceService.shared.loadUserIdForEmail(trimmedEmail) {
            userId = mappedId
        } else {
            userId = UUID().uuidString
            PersistenceService.shared.saveEmailToUserIdMapping(email: trimmedEmail, userId: userId)
        }

        if let profile = PersistenceService.shared.loadUserProfile(for: userId) {
            emailUserProfile = profile
        } else {
            let profile = UserProfile(
                id: userId,
                name: trimmedEmail.components(separatedBy: "@").first ?? "User",
                email: trimmedEmail,
                initials: String(trimmedEmail.prefix(2)).uppercased(),
                profileImageURL: nil
            )
            PersistenceService.shared.saveUserProfile(profile, for: userId)
            emailUserProfile = profile
        }

        currentUserId = userId
        isSignedIn = true
        authMethod = .email
        UserDefaults.standard.set(AuthMethod.email.rawValue, forKey: "sv_auth_method")
        createSession(userId: userId, method: .email)
    }

    // MARK: - Password Reset

    func resetPassword(email: String, newPassword: String, confirmPassword: String) {
        errorMessage = nil

        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        guard isValidEmail(trimmedEmail) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        guard KeychainService.loadPassword(for: trimmedEmail) != nil else {
            errorMessage = "No account found with this email."
            return
        }
        guard isStrongPassword(newPassword) else {
            errorMessage = "Password must be at least 8 characters with a letter and number"
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }

        guard KeychainService.updatePassword(newPassword, for: trimmedEmail) else {
            errorMessage = "Unable to reset password. Please try again."
            return
        }

        passwordResetSuccess = true
        showPasswordReset = false
    }

    // MARK: - Sign Out

    func signOut() {
        if authMethod == .google {
            GIDSignIn.sharedInstance.signOut()
            currentUser = nil
        }
        emailUserProfile = nil
        currentUserId = nil
        isSignedIn = false
        authMethod = nil
        KeychainService.clearSessionToken()
        UserDefaults.standard.removeObject(forKey: "sv_auth_method")
    }

    func deleteAccount() {
        let email = userEmail
        let userId = currentUserId

        signOut()

        if !email.isEmpty {
            KeychainService.deletePassword(for: email)
        }
        if let userId {
            PersistenceService.shared.clearUserData(for: userId)
        }
    }

    // MARK: - Session Management

    private func createSession(userId: String, method: AuthMethod) {
        let token = KeychainService.generateToken()
        let expiry = Date().addingTimeInterval(30 * 24 * 60 * 60)
        _ = KeychainService.saveSessionToken(token, userId: userId, expiry: expiry)
    }

    private func refreshSessionIfNeeded() {
        guard let session = KeychainService.loadSessionToken(),
              Date(timeIntervalSince1970: 0) < session.expiry else { return }

        let timeToExpiry = session.expiry.timeIntervalSinceNow
        if timeToExpiry < 7 * 24 * 60 * 60 {
            _ = KeychainService.refreshSessionToken()
        }
    }

    func validateSession() -> Bool {
        guard let session = KeychainService.loadSessionToken() else {
            if isSignedIn && authMethod == .email {
                signOut()
            }
            return false
        }
        refreshSessionIfNeeded()
        return session.expiry > Date()
    }

    // MARK: - Helpers

    private func persistGoogleUserProfile() {
        guard let user = currentUser, let profile = user.profile else { return }
        let userId = user.userID ?? UUID().uuidString
        let initials: String = {
            let parts = profile.name.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(profile.name.prefix(2)).uppercased()
        }()
        let userProfile = UserProfile(
            id: userId,
            name: profile.name,
            email: profile.email,
            initials: initials,
            profileImageURL: profile.imageURL(withDimension: 120)?.absoluteString
        )
        PersistenceService.shared.saveUserProfile(userProfile, for: userId)
    }

    func handleURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let regex = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return email.wholeMatch(of: regex) != nil
    }

    private func isStrongPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        let hasLetter = password.contains(where: \.isLetter)
        let hasNumber = password.contains(where: \.isNumber)
        return hasLetter && hasNumber
    }
}
